import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

enum DreRegime { caixa, competencia }

class DreDetalhe {
  const DreDetalhe({
    required this.grupo,
    required this.codigo,
    required this.nome,
    required this.valor,
  });

  final String grupo;
  final String codigo;
  final String nome;
  final double valor;
}

class DreOrigemDetalhe {
  const DreOrigemDetalhe({
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.tipo,
    this.data,
    this.ordemServicoId,
    this.pagamentoId,
    this.movimentoId,
  });

  final String titulo;
  final String subtitulo;
  final double valor;
  final String tipo;
  final String? data;
  final int? ordemServicoId;
  final int? pagamentoId;
  final int? movimentoId;
}


class DreServicoResultado {
  const DreServicoResultado({
    required this.servico,
    required this.quantidade,
    required this.quantidadeOrdens,
    required this.faturamentoBruto,
    required this.descontos,
    required this.receitaLiquida,
    required this.custoProdutos,
    required this.taxasCartao,
    required this.resultadoComercial,
    required this.horasGerenciais,
    required this.custoMaoObraGerencial,
    required this.custoEstruturaRateada,
  });

  final String servico;
  final double quantidade;
  final int quantidadeOrdens;
  final double faturamentoBruto;
  final double descontos;
  final double receitaLiquida;
  final double custoProdutos;
  final double taxasCartao;
  final double resultadoComercial;
  final double horasGerenciais;
  final double custoMaoObraGerencial;
  final double custoEstruturaRateada;

  double get margemComercial {
    if (receitaLiquida.abs() <= 0.000001) {
      return 0;
    }
    return resultadoComercial / receitaLiquida * 100;
  }

  double get resultadoGerencialEstimado {
    return resultadoComercial -
        custoMaoObraGerencial -
        custoEstruturaRateada;
  }

  double get margemGerencial {
    if (receitaLiquida.abs() <= 0.000001) {
      return 0;
    }
    return resultadoGerencialEstimado / receitaLiquida * 100;
  }
}

class DreServicoOrdem {
  const DreServicoOrdem({
    required this.ordemServicoId,
    required this.numero,
    required this.cliente,
    required this.data,
    required this.quantidade,
    required this.faturamentoBruto,
    required this.descontos,
    required this.receitaLiquida,
    required this.custoProdutos,
    required this.taxasCartao,
    required this.resultadoComercial,
    required this.horasGerenciais,
    required this.custoMaoObraGerencial,
    required this.custoEstruturaRateada,
  });

  final int ordemServicoId;
  final String numero;
  final String cliente;
  final String? data;
  final double quantidade;
  final double faturamentoBruto;
  final double descontos;
  final double receitaLiquida;
  final double custoProdutos;
  final double taxasCartao;
  final double resultadoComercial;
  final double horasGerenciais;
  final double custoMaoObraGerencial;
  final double custoEstruturaRateada;

  double get margemComercial {
    if (receitaLiquida.abs() <= 0.000001) {
      return 0;
    }
    return resultadoComercial / receitaLiquida * 100;
  }

  double get resultadoGerencialEstimado {
    return resultadoComercial -
        custoMaoObraGerencial -
        custoEstruturaRateada;
  }

  double get margemGerencial {
    if (receitaLiquida.abs() <= 0.000001) {
      return 0;
    }
    return resultadoGerencialEstimado / receitaLiquida * 100;
  }
}

class DreResultado {
  const DreResultado({
    required this.regime,
    required this.inicio,
    required this.fim,
    required this.receitaBruta,
    required this.deducoes,
    required this.receitaLiquida,
    required this.custosVariaveis,
    required this.margemContribuicao,
    required this.despesasOperacionais,
    required this.resultadoFinanceiro,
    required this.outrasReceitas,
    required this.outrasDespesas,
    required this.resultadoGerencial,
    required this.custoProdutosConsumidos,
    required this.detalhes,
  });

  final DreRegime regime;
  final DateTime inicio;
  final DateTime fim;
  final double receitaBruta;
  final double deducoes;
  final double receitaLiquida;
  final double custosVariaveis;
  final double margemContribuicao;
  final double despesasOperacionais;
  final double resultadoFinanceiro;
  final double outrasReceitas;
  final double outrasDespesas;
  final double resultadoGerencial;
  final double custoProdutosConsumidos;
  final List<DreDetalhe> detalhes;

  double get margemPercentual {
    if (receitaLiquida.abs() <= 0.000001) {
      return 0;
    }
    return resultadoGerencial / receitaLiquida * 100;
  }
}

class DreRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<DreResultado> calcular({
    required DateTime inicio,
    required DateTime fim,
    DreRegime regime = DreRegime.competencia,
  }) async {
    final database = await _appDatabase.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    final detalhes = <DreDetalhe>[];
    final porGrupo = <String, double>{};

    final movimentos = await _carregarMovimentosClassificados(
      database: database,
      inicioDia: inicioDia,
      fimDia: fimDia,
      regime: regime,
    );

    for (final linha in movimentos) {
      _adicionarDetalhe(
        detalhes: detalhes,
        porGrupo: porGrupo,
        grupo: (linha['grupo_dre'] ?? '').toString(),
        codigo: (linha['codigo'] ?? '').toString(),
        nome: (linha['nome'] ?? 'Sem categoria').toString(),
        valor: _double(linha['total']),
      );
    }

    if (regime == DreRegime.competencia) {
      await _adicionarReceitaOrdensCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
        detalhes: detalhes,
        porGrupo: porGrupo,
      );

      await _adicionarTaxasCartaoCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
        detalhes: detalhes,
        porGrupo: porGrupo,
      );
    }

    final custoProdutos = regime == DreRegime.competencia
        ? await _custoProdutosCompetencia(
            database: database,
            inicioDia: inicioDia,
            fimDia: fimDia,
          )
        : await _custoProdutosCaixa(
            database: database,
            inicioDia: inicioDia,
            fimDia: fimDia,
          );

    if (custoProdutos > 0.000001) {
      _adicionarDetalhe(
        detalhes: detalhes,
        porGrupo: porGrupo,
        grupo: 'Custos Variáveis',
        codigo: regime == DreRegime.competencia
            ? 'FIFO'
            : 'FIFO-CAIXA',
        nome: regime == DreRegime.competencia
            ? 'Produtos consumidos nas OS (FIFO/snapshot)'
            : 'Produtos das OS proporcionais aos recebimentos',
        valor: custoProdutos,
      );
    }

    final receitaBruta = porGrupo['Receita Bruta'] ?? 0;
    final deducoes = porGrupo['Deduções'] ?? 0;
    final receitaLiquida = receitaBruta - deducoes;
    final custosVariaveis = porGrupo['Custos Variáveis'] ?? 0;
    final margemContribuicao = receitaLiquida - custosVariaveis;
    final despesasOperacionais = porGrupo['Despesas Operacionais'] ?? 0;
    final resultadoFinanceiro = porGrupo['Resultado Financeiro'] ?? 0;
    final outrasReceitas = porGrupo['Outras Receitas'] ?? 0;
    final outrasDespesas = porGrupo['Outras Despesas'] ?? 0;
    final resultadoGerencial =
        margemContribuicao -
        despesasOperacionais -
        resultadoFinanceiro +
        outrasReceitas -
        outrasDespesas;

    return DreResultado(
      regime: regime,
      inicio: inicio,
      fim: fim,
      receitaBruta: receitaBruta,
      deducoes: deducoes,
      receitaLiquida: receitaLiquida,
      custosVariaveis: custosVariaveis,
      margemContribuicao: margemContribuicao,
      despesasOperacionais: despesasOperacionais,
      resultadoFinanceiro: resultadoFinanceiro,
      outrasReceitas: outrasReceitas,
      outrasDespesas: outrasDespesas,
      resultadoGerencial: resultadoGerencial,
      custoProdutosConsumidos: custoProdutos,
      detalhes: detalhes,
    );
  }

  Future<List<Map<String, Object?>>> _carregarMovimentosClassificados({
    required Database database,
    required String inicioDia,
    required String fimDia,
    required DreRegime regime,
  }) {
    final dataExpressao = regime == DreRegime.caixa
        ? 'COALESCE(m.data_pagamento, m.data)'
        : 'COALESCE(m.data_competencia, m.data)';

    final filtroStatus = regime == DreRegime.caixa
        ? "m.status = 'Realizado'"
        : "m.status != 'Cancelado'";

    // Em competência, recebimentos, estornos e taxas ligados a pagamentos
    // não entram por esta consulta. A venda vem da OS e a taxa da maquininha
    // é reconhecida separadamente pela competência da OS.
    final excluirPagamentosCompetencia = regime == DreRegime.competencia
        ? '''
          AND m.pagamento_id IS NULL
          AND NOT (
            m.ordem_servico_id IS NOT NULL
            AND LOWER(m.tipo) = 'entrada'
          )
          '''
        : '';

    return database.rawQuery(
      '''
      SELECT
        COALESCE(pc.grupo_dre, 'Não DRE') AS grupo_dre,
        COALESCE(pc.codigo, '') AS codigo,
        COALESCE(pc.nome, m.natureza, 'Sem categoria') AS nome,
        LOWER(m.tipo) AS tipo,
        COALESCE(SUM(m.valor), 0) AS total
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE $filtroStatus
        AND COALESCE(m.impacta_dre, 1) = 1
        AND m.transferencia_id IS NULL
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos pcor
          WHERE pcor.id = m.pagamento_id
            AND pcor.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = pcor.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
        AND date($dataExpressao) BETWEEN date(?) AND date(?)
        AND COALESCE(pc.grupo_dre, 'Não DRE') != 'Não DRE'
        AND COALESCE(pc.codigo, '') != '2.03.01'
        $excluirPagamentosCompetencia
      GROUP BY pc.grupo_dre, pc.codigo, pc.nome, LOWER(m.tipo)
      ORDER BY pc.ordem ASC, pc.codigo ASC
      ''',
      [inicioDia, fimDia],
    );
  }

  Future<void> _adicionarReceitaOrdensCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
    required List<DreDetalhe> detalhes,
    required Map<String, double> porGrupo,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(
          COALESCE(valor_total, 0)
          + COALESCE(acrescimo_negociacao, 0)
          + COALESCE(juros_parcelamento, 0)
        ), 0) AS receita_bruta,
        COALESCE(SUM(
          COALESCE(desconto, 0)
          + COALESCE(desconto_negociacao, 0)
        ), 0) AS deducoes
      FROM ordens_servico
      WHERE status = 'Finalizada'
        AND date(COALESCE(data_finalizacao, data_abertura))
          BETWEEN date(?) AND date(?)
      ''',
      [inicioDia, fimDia],
    );

    final receitaOs = _double(resultado.first['receita_bruta']);
    final deducoesOs = _double(resultado.first['deducoes']);

    if (receitaOs > 0.000001) {
      detalhes.insert(
        0,
        DreDetalhe(
          grupo: 'Receita Bruta',
          codigo: 'OS',
          nome: 'Serviços finalizados no período',
          valor: receitaOs,
        ),
      );
      porGrupo['Receita Bruta'] =
          (porGrupo['Receita Bruta'] ?? 0) + receitaOs;
    }

    _adicionarDetalhe(
      detalhes: detalhes,
      porGrupo: porGrupo,
      grupo: 'Deduções',
      codigo: 'OS-DESC',
      nome: 'Descontos das Ordens de Serviço',
      valor: deducoesOs,
    );
  }

  Future<void> _adicionarTaxasCartaoCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
    required List<DreDetalhe> detalhes,
    required Map<String, double> porGrupo,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(m.valor), 0) AS total
      FROM movimentos_financeiros m
      INNER JOIN ordens_servico os ON os.id = m.ordem_servico_id
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE os.status = 'Finalizada'
        AND m.pagamento_id IS NOT NULL
        AND m.status = 'Realizado'
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos pcor
          WHERE pcor.id = m.pagamento_id
            AND pcor.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = pcor.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
        AND COALESCE(m.impacta_dre, 1) = 1
        AND m.transferencia_id IS NULL
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND (
          LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
          OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
        )
        AND COALESCE(pc.codigo, '2.02.01') = '2.02.01'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ''',
      [inicioDia, fimDia],
    );

    _adicionarDetalhe(
      detalhes: detalhes,
      porGrupo: porGrupo,
      grupo: 'Custos Variáveis',
      codigo: '2.02.01',
      nome: 'Taxas de cartão',
      valor: _double(resultado.first['total']),
    );
  }

  Future<double> _custoProdutosCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN COALESCE(p.custo_total_no_momento, 0) > 0
            THEN p.custo_total_no_momento
          ELSE COALESCE(p.quantidade, 0) *
            CASE
              WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                THEN p.custo_unitario_no_momento
              ELSE COALESCE(p.custo_unitario, 0)
            END
        END
      ), 0) AS total
      FROM ordem_servico_produtos p
      INNER JOIN ordens_servico os ON os.id = p.ordem_servico_id
      WHERE os.status = 'Finalizada'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ''',
      [inicioDia, fimDia],
    );

    return _double(resultado.first['total']);
  }

  Future<double> _custoProdutosCaixa({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    // No caixa, o custo dos produtos acompanha o avanço acumulado dos
    // recebimentos válidos da OS. Isso evita reconhecer o mesmo custo duas
    // vezes quando existe devolução real e o cliente paga novamente depois.
    // Correções de recebimento não entram porque seus movimentos são
    // cancelados; devoluções preservam a entrada histórica, como no Caixa.
    final resultado = await database.rawQuery(
      '''
      WITH custos_os AS (
        SELECT
          os.id AS ordem_servico_id,
          MAX(
            COALESCE(os.valor_total, 0)
            - COALESCE(os.desconto, 0)
            - COALESCE(os.desconto_negociacao, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0),
            0
          ) AS valor_final_os,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(p.custo_total_no_momento, 0) > 0
                THEN p.custo_total_no_momento
              ELSE COALESCE(p.quantidade, 0) *
                CASE
                  WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                    THEN p.custo_unitario_no_momento
                  ELSE COALESCE(p.custo_unitario, 0)
                END
            END
          ), 0) AS custo_produtos
        FROM ordens_servico os
        LEFT JOIN ordem_servico_produtos p ON p.ordem_servico_id = os.id
        WHERE os.status = 'Finalizada'
        GROUP BY os.id
      ),
      recebimentos_validos AS (
        SELECT
          m.ordem_servico_id,
          date(COALESCE(m.data_pagamento, m.data)) AS data_recebimento,
          m.valor
        FROM movimentos_financeiros m
        WHERE m.status = 'Realizado'
          AND m.transferencia_id IS NULL
          AND m.ordem_servico_id IS NOT NULL
          AND m.pagamento_id IS NOT NULL
          AND LOWER(m.tipo) = 'entrada'
          AND LOWER(COALESCE(m.origem, '')) = 'pagamento de os'
          AND date(COALESCE(m.data_pagamento, m.data)) <= date(?)
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos pcor
            WHERE pcor.id = m.pagamento_id
              AND pcor.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = pcor.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )
      ),
      acumulado_os AS (
        SELECT
          c.ordem_servico_id,
          c.valor_final_os,
          c.custo_produtos,
          COALESCE(SUM(CASE
            WHEN r.data_recebimento < date(?) THEN r.valor
            ELSE 0
          END), 0) AS recebido_antes,
          COALESCE(SUM(CASE
            WHEN r.data_recebimento <= date(?) THEN r.valor
            ELSE 0
          END), 0) AS recebido_ate_fim
        FROM custos_os c
        LEFT JOIN recebimentos_validos r
          ON r.ordem_servico_id = c.ordem_servico_id
        GROUP BY
          c.ordem_servico_id,
          c.valor_final_os,
          c.custo_produtos
      )
      SELECT COALESCE(SUM(
        CASE
          WHEN valor_final_os <= 0 OR custo_produtos <= 0 THEN 0
          ELSE custo_produtos * MAX(
            MIN(recebido_ate_fim / valor_final_os, 1.0)
            - MIN(recebido_antes / valor_final_os, 1.0),
            0
          )
        END
      ), 0) AS total
      FROM acumulado_os
      ''',
      [fimDia, inicioDia, fimDia],
    );

    return _double(resultado.first['total']);
  }

  void _adicionarDetalhe({
    required List<DreDetalhe> detalhes,
    required Map<String, double> porGrupo,
    required String grupo,
    required String codigo,
    required String nome,
    required double valor,
  }) {
    if (valor.abs() <= 0.000001) {
      return;
    }

    detalhes.add(
      DreDetalhe(
        grupo: grupo,
        codigo: codigo,
        nome: nome,
        valor: valor,
      ),
    );
    porGrupo[grupo] = (porGrupo[grupo] ?? 0) + valor;
  }


  Future<bool> _tabelaExiste(Database database, String nome) async {
    final resultado = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
      ''',
      [nome],
    );

    return resultado.isNotEmpty;
  }

  Future<double> _custoHoraEstruturaGerencial(Database database) async {
    var horasProdutivasMes = 160.0;
    var mesesMedia = 3;

    if (await _tabelaExiste(database, 'financeiro_precificacao_config')) {
      final config = await database.query(
        'financeiro_precificacao_config',
        columns: ['horas_produtivas_mes', 'meses_media'],
        where: 'id = 1',
        limit: 1,
      );

      if (config.isNotEmpty) {
        horasProdutivasMes = _double(
          config.first['horas_produtivas_mes'],
        );
        mesesMedia = (_int(config.first['meses_media']) ?? 3)
            .clamp(1, 12)
            .toInt();
      }
    }

    if (horasProdutivasMes <= 0) {
      horasProdutivasMes = 160;
    }

    final agora = DateTime.now();
    final primeiroMesAtual = DateTime(agora.year, agora.month, 1);
    final inicio = DateTime(
      primeiroMesAtual.year,
      primeiroMesAtual.month - mesesMedia,
      1,
    );
    final fim = primeiroMesAtual.subtract(const Duration(days: 1));

    final historico = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(m.valor), 0) AS total
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE m.status = 'Realizado'
        AND m.transferencia_id IS NULL
        AND COALESCE(m.impacta_dre, 1) = 1
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND date(COALESCE(m.data_pagamento, m.data))
          BETWEEN date(?) AND date(?)
        AND COALESCE(pc.grupo_dre, 'Não DRE') != 'Não DRE'
        AND COALESCE(pc.codigo, '') NOT LIKE '2.01%'
        AND COALESCE(pc.codigo, '') NOT IN ('2.02.01', '2.03.01')
        AND NOT (
          LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
          OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos pcor
          WHERE pcor.id = m.pagamento_id
            AND pcor.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = pcor.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final totalHistorico = _double(historico.first['total']);
    var mediaEstrutura = totalHistorico / mesesMedia;

    if (mediaEstrutura <= 0.000001 &&
        await _tabelaExiste(database, 'financeiro_custos_fixos')) {
      final fallback = await database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor_mensal), 0) AS total
        FROM financeiro_custos_fixos
        WHERE ativo = 1
        ''',
      );
      mediaEstrutura = _double(fallback.first['total']);
    }

    return mediaEstrutura / horasProdutivasMes;
  }

  Future<double> _custoHoraMaoObraGerencial(Database database) async {
    if (!await _tabelaExiste(database, 'financeiro_colaboradores_custo')) {
      return 0;
    }

    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(
          remuneracao_mensal +
          encargos_mensais +
          outros_custos_mensais
        ), 0) AS custo_total,
        COALESCE(SUM(horas_produtivas_mes), 0) AS horas_total
      FROM financeiro_colaboradores_custo
      WHERE ativo = 1
      ''',
    );

    final custoTotal = _double(resultado.first['custo_total']);
    final horasTotal = _double(resultado.first['horas_total']);

    if (horasTotal <= 0.000001) {
      return 0;
    }

    return custoTotal / horasTotal;
  }

  Future<Map<String, Map<String, double>>> _carregarGerencialPorServico({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final custoHoraEstrutura = await _custoHoraEstruturaGerencial(database);
    final custoHoraMaoObra = await _custoHoraMaoObraGerencial(database);

    final resultado = await database.rawQuery(
      '''
      WITH itens_os AS (
        SELECT
          item.ordem_servico_id,
          TRIM(item.servico) AS servico,
          COALESCE(SUM(item.quantidade), 0) AS quantidade,
          COALESCE(SUM(
            COALESCE(item.quantidade, 0) *
            COALESCE(item.valor_unitario, 0)
          ), 0) AS valor_item
        FROM ordem_servico_itens item
        WHERE TRIM(COALESCE(item.servico, '')) != ''
        GROUP BY item.ordem_servico_id, TRIM(item.servico)
      ),
      totais_itens_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(valor_item), 0) AS total_itens
        FROM itens_os
        GROUP BY ordem_servico_id
      ),
      mao_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(horas), 0) AS horas,
          COALESCE(SUM(custo_total), 0) AS custo_mao_obra
        FROM financeiro_os_mao_obra
        WHERE ativo = 1
          AND cancelado_em IS NULL
        GROUP BY ordem_servico_id
      )
      SELECT
        io.servico,
        COALESCE(SUM(
          COALESCE(mao.custo_mao_obra, 0) *
          CASE
            WHEN t.total_itens > 0
              THEN io.valor_item / t.total_itens
            ELSE 0
          END
        ), 0) AS custo_mao_obra,
        COALESCE(SUM(
          CASE
            WHEN COALESCE(mao.horas, 0) > 0
              THEN mao.horas *
                CASE
                  WHEN t.total_itens > 0
                    THEN io.valor_item / t.total_itens
                  ELSE 0
                END
            ELSE (
              COALESCE(
                (
                  SELECT sc.duracao_minutos
                  FROM servicos_catalogo sc
                  WHERE LOWER(TRIM(sc.nome)) = LOWER(TRIM(io.servico))
                  ORDER BY sc.ativo DESC, sc.id DESC
                  LIMIT 1
                ),
                60
              ) / 60.0
            ) * io.quantidade
          END
        ), 0) AS horas_gerenciais
      FROM itens_os io
      INNER JOIN totais_itens_os t
        ON t.ordem_servico_id = io.ordem_servico_id
      INNER JOIN ordens_servico os
        ON os.id = io.ordem_servico_id
      LEFT JOIN mao_os mao
        ON mao.ordem_servico_id = io.ordem_servico_id
      WHERE os.status = 'Finalizada'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
        AND t.total_itens > 0
      GROUP BY io.servico
      ''',
      [inicioDia, fimDia],
    );

    final mapa = <String, Map<String, double>>{};

    for (final linha in resultado) {
      final nome = (linha['servico'] ?? '').toString().trim();
      final horas = _double(linha['horas_gerenciais']);
      final maoObraRegistrada = _double(linha['custo_mao_obra']);
      final maoObra = maoObraRegistrada > 0.000001
          ? maoObraRegistrada
          : horas * custoHoraMaoObra;

      mapa[nome.toLowerCase()] = {
        'horas': horas,
        'mao_obra': maoObra,
        'estrutura': horas * custoHoraEstrutura,
      };
    }

    return mapa;
  }

  Future<Map<int, Map<String, double>>> _carregarGerencialPorOrdemServico({
    required Database database,
    required String servico,
    required String inicioDia,
    required String fimDia,
  }) async {
    final custoHoraEstrutura = await _custoHoraEstruturaGerencial(database);
    final custoHoraMaoObra = await _custoHoraMaoObraGerencial(database);

    final resultado = await database.rawQuery(
      '''
      WITH itens_os AS (
        SELECT
          item.ordem_servico_id,
          TRIM(item.servico) AS servico,
          COALESCE(SUM(item.quantidade), 0) AS quantidade,
          COALESCE(SUM(
            COALESCE(item.quantidade, 0) *
            COALESCE(item.valor_unitario, 0)
          ), 0) AS valor_item
        FROM ordem_servico_itens item
        WHERE TRIM(COALESCE(item.servico, '')) != ''
        GROUP BY item.ordem_servico_id, TRIM(item.servico)
      ),
      totais_itens_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(valor_item), 0) AS total_itens
        FROM itens_os
        GROUP BY ordem_servico_id
      ),
      mao_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(horas), 0) AS horas,
          COALESCE(SUM(custo_total), 0) AS custo_mao_obra
        FROM financeiro_os_mao_obra
        WHERE ativo = 1
          AND cancelado_em IS NULL
        GROUP BY ordem_servico_id
      )
      SELECT
        io.ordem_servico_id,
        COALESCE(mao.custo_mao_obra, 0) *
          CASE
            WHEN t.total_itens > 0
              THEN io.valor_item / t.total_itens
            ELSE 0
          END AS custo_mao_obra,
        CASE
          WHEN COALESCE(mao.horas, 0) > 0
            THEN mao.horas *
              CASE
                WHEN t.total_itens > 0
                  THEN io.valor_item / t.total_itens
                ELSE 0
              END
          ELSE (
            COALESCE(
              (
                SELECT sc.duracao_minutos
                FROM servicos_catalogo sc
                WHERE LOWER(TRIM(sc.nome)) = LOWER(TRIM(io.servico))
                ORDER BY sc.ativo DESC, sc.id DESC
                LIMIT 1
              ),
              60
            ) / 60.0
          ) * io.quantidade
        END AS horas_gerenciais
      FROM itens_os io
      INNER JOIN totais_itens_os t
        ON t.ordem_servico_id = io.ordem_servico_id
      INNER JOIN ordens_servico os
        ON os.id = io.ordem_servico_id
      LEFT JOIN mao_os mao
        ON mao.ordem_servico_id = io.ordem_servico_id
      WHERE os.status = 'Finalizada'
        AND t.total_itens > 0
        AND TRIM(io.servico) = ? COLLATE NOCASE
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ''',
      [servico.trim(), inicioDia, fimDia],
    );

    final mapa = <int, Map<String, double>>{};

    for (final linha in resultado) {
      final ordemId = _int(linha['ordem_servico_id']);
      if (ordemId == null) {
        continue;
      }

      final horas = _double(linha['horas_gerenciais']);
      final maoObraRegistrada = _double(linha['custo_mao_obra']);
      final maoObra = maoObraRegistrada > 0.000001
          ? maoObraRegistrada
          : horas * custoHoraMaoObra;

      mapa[ordemId] = {
        'horas': horas,
        'mao_obra': maoObra,
        'estrutura': horas * custoHoraEstrutura,
      };
    }

    return mapa;
  }

  Future<List<DreServicoResultado>> listarResultadoServicos({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    final resultado = await database.rawQuery(
      '''
      WITH itens_os AS (
        SELECT
          item.ordem_servico_id,
          TRIM(item.servico) AS servico,
          COALESCE(SUM(item.quantidade), 0) AS quantidade,
          COALESCE(SUM(
            COALESCE(item.quantidade, 0) *
            COALESCE(item.valor_unitario, 0)
          ), 0) AS valor_item
        FROM ordem_servico_itens item
        WHERE TRIM(COALESCE(item.servico, '')) != ''
        GROUP BY item.ordem_servico_id, TRIM(item.servico)
      ),
      totais_itens_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(valor_item), 0) AS total_itens
        FROM itens_os
        GROUP BY ordem_servico_id
      ),
      custos_os AS (
        SELECT
          p.ordem_servico_id,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(p.custo_total_no_momento, 0) > 0
                THEN p.custo_total_no_momento
              ELSE COALESCE(p.quantidade, 0) *
                CASE
                  WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                    THEN p.custo_unitario_no_momento
                  ELSE COALESCE(p.custo_unitario, 0)
                END
            END
          ), 0) AS custo_produtos
        FROM ordem_servico_produtos p
        GROUP BY p.ordem_servico_id
      ),
      taxas_os AS (
        SELECT
          m.ordem_servico_id,
          COALESCE(SUM(m.valor), 0) AS taxas_cartao
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.pagamento_id IS NOT NULL
          AND m.status = 'Realizado'
          AND COALESCE(m.impacta_dre, 1) = 1
          AND m.transferencia_id IS NULL
          AND LOWER(m.tipo) IN ('saída', 'saida')
          AND (
            LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
            OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
          )
          AND COALESCE(pc.codigo, '2.02.01') = '2.02.01'
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos pcor
            WHERE pcor.id = m.pagamento_id
              AND pcor.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = pcor.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )
        GROUP BY m.ordem_servico_id
      ),
      base AS (
        SELECT
          io.ordem_servico_id,
          io.servico,
          io.quantidade,
          io.valor_item,
          t.total_itens,
          CASE
            WHEN t.total_itens > 0
              THEN io.valor_item / t.total_itens
            ELSE 0
          END AS proporcao,
          (
            COALESCE(os.valor_total, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0)
          ) AS bruto_os,
          (
            COALESCE(os.desconto, 0)
            + COALESCE(os.desconto_negociacao, 0)
          ) AS descontos_os,
          COALESCE(c.custo_produtos, 0) AS custo_produtos_os,
          COALESCE(tx.taxas_cartao, 0) AS taxas_cartao_os
        FROM itens_os io
        INNER JOIN totais_itens_os t
          ON t.ordem_servico_id = io.ordem_servico_id
        INNER JOIN ordens_servico os
          ON os.id = io.ordem_servico_id
        LEFT JOIN custos_os c
          ON c.ordem_servico_id = io.ordem_servico_id
        LEFT JOIN taxas_os tx
          ON tx.ordem_servico_id = io.ordem_servico_id
        WHERE os.status = 'Finalizada'
          AND date(COALESCE(os.data_finalizacao, os.data_abertura))
            BETWEEN date(?) AND date(?)
      )
      SELECT
        servico,
        COALESCE(SUM(quantidade), 0) AS quantidade,
        COUNT(DISTINCT ordem_servico_id) AS quantidade_ordens,
        COALESCE(SUM(bruto_os * proporcao), 0) AS faturamento_bruto,
        COALESCE(SUM(descontos_os * proporcao), 0) AS descontos,
        COALESCE(SUM(
          (bruto_os - descontos_os) * proporcao
        ), 0) AS receita_liquida,
        COALESCE(SUM(custo_produtos_os * proporcao), 0) AS custo_produtos,
        COALESCE(SUM(taxas_cartao_os * proporcao), 0) AS taxas_cartao,
        COALESCE(SUM(
          (
            bruto_os
            - descontos_os
            - custo_produtos_os
            - taxas_cartao_os
          ) * proporcao
        ), 0) AS resultado_comercial
      FROM base
      WHERE proporcao > 0
      GROUP BY servico
      ORDER BY resultado_comercial DESC, receita_liquida DESC, servico ASC
      ''',
      [inicioDia, fimDia],
    );

    final gerencial = await _carregarGerencialPorServico(
      database: database,
      inicioDia: inicioDia,
      fimDia: fimDia,
    );

    final servicos = resultado.map((linha) {
      final nome = (linha['servico'] ?? 'Serviço').toString().trim();
      final custos = gerencial[nome.toLowerCase()] ?? const <String, double>{};

      return DreServicoResultado(
        servico: nome,
        quantidade: _double(linha['quantidade']),
        quantidadeOrdens: _int(linha['quantidade_ordens']) ?? 0,
        faturamentoBruto: _double(linha['faturamento_bruto']),
        descontos: _double(linha['descontos']),
        receitaLiquida: _double(linha['receita_liquida']),
        custoProdutos: _double(linha['custo_produtos']),
        taxasCartao: _double(linha['taxas_cartao']),
        resultadoComercial: _double(linha['resultado_comercial']),
        horasGerenciais: custos['horas'] ?? 0,
        custoMaoObraGerencial: custos['mao_obra'] ?? 0,
        custoEstruturaRateada: custos['estrutura'] ?? 0,
      );
    }).toList();

    servicos.sort((a, b) {
      final porResultado = b.resultadoGerencialEstimado.compareTo(
        a.resultadoGerencialEstimado,
      );
      if (porResultado != 0) {
        return porResultado;
      }

      final porReceita = b.receitaLiquida.compareTo(a.receitaLiquida);
      if (porReceita != 0) {
        return porReceita;
      }

      return a.servico.toLowerCase().compareTo(b.servico.toLowerCase());
    });

    return servicos;
  }

  Future<List<DreServicoOrdem>> listarOrdensServico({
    required String servico,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    final resultado = await database.rawQuery(
      '''
      WITH itens_os AS (
        SELECT
          item.ordem_servico_id,
          TRIM(item.servico) AS servico,
          COALESCE(SUM(item.quantidade), 0) AS quantidade,
          COALESCE(SUM(
            COALESCE(item.quantidade, 0) *
            COALESCE(item.valor_unitario, 0)
          ), 0) AS valor_item
        FROM ordem_servico_itens item
        WHERE TRIM(COALESCE(item.servico, '')) != ''
        GROUP BY item.ordem_servico_id, TRIM(item.servico)
      ),
      totais_itens_os AS (
        SELECT
          ordem_servico_id,
          COALESCE(SUM(valor_item), 0) AS total_itens
        FROM itens_os
        GROUP BY ordem_servico_id
      ),
      custos_os AS (
        SELECT
          p.ordem_servico_id,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(p.custo_total_no_momento, 0) > 0
                THEN p.custo_total_no_momento
              ELSE COALESCE(p.quantidade, 0) *
                CASE
                  WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                    THEN p.custo_unitario_no_momento
                  ELSE COALESCE(p.custo_unitario, 0)
                END
            END
          ), 0) AS custo_produtos
        FROM ordem_servico_produtos p
        GROUP BY p.ordem_servico_id
      ),
      taxas_os AS (
        SELECT
          m.ordem_servico_id,
          COALESCE(SUM(m.valor), 0) AS taxas_cartao
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.pagamento_id IS NOT NULL
          AND m.status = 'Realizado'
          AND COALESCE(m.impacta_dre, 1) = 1
          AND m.transferencia_id IS NULL
          AND LOWER(m.tipo) IN ('saída', 'saida')
          AND (
            LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
            OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
          )
          AND COALESCE(pc.codigo, '2.02.01') = '2.02.01'
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos pcor
            WHERE pcor.id = m.pagamento_id
              AND pcor.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = pcor.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )
        GROUP BY m.ordem_servico_id
      )
      SELECT
        os.id AS ordem_servico_id,
        COALESCE(os.numero, 'OS') AS numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        COALESCE(os.data_finalizacao, os.data_abertura) AS data_referencia,
        io.quantidade,
        (
          (
            COALESCE(os.valor_total, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0)
          ) * (io.valor_item / t.total_itens)
        ) AS faturamento_bruto,
        (
          (
            COALESCE(os.desconto, 0)
            + COALESCE(os.desconto_negociacao, 0)
          ) * (io.valor_item / t.total_itens)
        ) AS descontos,
        (
          (
            COALESCE(os.valor_total, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0)
            - COALESCE(os.desconto, 0)
            - COALESCE(os.desconto_negociacao, 0)
          ) * (io.valor_item / t.total_itens)
        ) AS receita_liquida,
        (
          COALESCE(custo.custo_produtos, 0) *
          (io.valor_item / t.total_itens)
        ) AS custo_produtos,
        (
          COALESCE(tx.taxas_cartao, 0) *
          (io.valor_item / t.total_itens)
        ) AS taxas_cartao,
        (
          (
            COALESCE(os.valor_total, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0)
            - COALESCE(os.desconto, 0)
            - COALESCE(os.desconto_negociacao, 0)
            - COALESCE(custo.custo_produtos, 0)
            - COALESCE(tx.taxas_cartao, 0)
          ) * (io.valor_item / t.total_itens)
        ) AS resultado_comercial
      FROM itens_os io
      INNER JOIN totais_itens_os t
        ON t.ordem_servico_id = io.ordem_servico_id
      INNER JOIN ordens_servico os
        ON os.id = io.ordem_servico_id
      LEFT JOIN clientes c
        ON c.id = os.cliente_id
      LEFT JOIN custos_os custo
        ON custo.ordem_servico_id = io.ordem_servico_id
      LEFT JOIN taxas_os tx
        ON tx.ordem_servico_id = io.ordem_servico_id
      WHERE os.status = 'Finalizada'
        AND t.total_itens > 0
        AND TRIM(io.servico) = ? COLLATE NOCASE
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ORDER BY
        date(COALESCE(os.data_finalizacao, os.data_abertura)) DESC,
        os.id DESC
      ''',
      [servico.trim(), inicioDia, fimDia],
    );

    final gerencial = await _carregarGerencialPorOrdemServico(
      database: database,
      servico: servico,
      inicioDia: inicioDia,
      fimDia: fimDia,
    );

    return resultado.map((linha) {
      final ordemId = _int(linha['ordem_servico_id']) ?? 0;
      final custos = gerencial[ordemId] ?? const <String, double>{};

      return DreServicoOrdem(
        ordemServicoId: ordemId,
        numero: (linha['numero'] ?? 'OS').toString().trim(),
        cliente: (linha['cliente_nome'] ?? '').toString().trim(),
        data: _textoNulo(linha['data_referencia']),
        quantidade: _double(linha['quantidade']),
        faturamentoBruto: _double(linha['faturamento_bruto']),
        descontos: _double(linha['descontos']),
        receitaLiquida: _double(linha['receita_liquida']),
        custoProdutos: _double(linha['custo_produtos']),
        taxasCartao: _double(linha['taxas_cartao']),
        resultadoComercial: _double(linha['resultado_comercial']),
        horasGerenciais: custos['horas'] ?? 0,
        custoMaoObraGerencial: custos['mao_obra'] ?? 0,
        custoEstruturaRateada: custos['estrutura'] ?? 0,
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> listarOrigens({
    required DreDetalhe detalhe,
    required DateTime inicio,
    required DateTime fim,
    required DreRegime regime,
  }) async {
    final database = await _appDatabase.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    if (regime == DreRegime.competencia && detalhe.codigo == 'OS') {
      return _origensReceitaOrdensCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
      );
    }

    if (regime == DreRegime.competencia && detalhe.codigo == 'OS-DESC') {
      return _origensDescontosOrdensCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
      );
    }

    if (regime == DreRegime.competencia &&
        detalhe.codigo == '2.02.01') {
      return _origensTaxasCartaoCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
      );
    }

    if (detalhe.codigo == 'FIFO') {
      return _origensProdutosCompetencia(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
      );
    }

    if (detalhe.codigo == 'FIFO-CAIXA') {
      return _origensProdutosCaixa(
        database: database,
        inicioDia: inicioDia,
        fimDia: fimDia,
      );
    }

    return _origensMovimentosFinanceiros(
      database: database,
      detalhe: detalhe,
      inicioDia: inicioDia,
      fimDia: fimDia,
      regime: regime,
    );
  }

  Future<List<DreOrigemDetalhe>> _origensReceitaOrdensCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        os.id AS ordem_servico_id,
        os.numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        COALESCE(os.data_finalizacao, os.data_abertura) AS data_referencia,
        (
          COALESCE(os.valor_total, 0)
          + COALESCE(os.acrescimo_negociacao, 0)
          + COALESCE(os.juros_parcelamento, 0)
        ) AS valor
      FROM ordens_servico os
      LEFT JOIN clientes c ON c.id = os.cliente_id
      WHERE os.status = 'Finalizada'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
        AND (
          COALESCE(os.valor_total, 0)
          + COALESCE(os.acrescimo_negociacao, 0)
          + COALESCE(os.juros_parcelamento, 0)
        ) > 0.000001
      ORDER BY
        date(COALESCE(os.data_finalizacao, os.data_abertura)) DESC,
        os.id DESC
      ''',
      [inicioDia, fimDia],
    );

    return resultado.map((linha) {
      final numero = (linha['numero'] ?? 'OS').toString().trim();
      final cliente = (linha['cliente_nome'] ?? '').toString().trim();

      return DreOrigemDetalhe(
        titulo: numero,
        subtitulo: cliente,
        valor: _double(linha['valor']),
        tipo: 'Ordem de Serviço',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> _origensDescontosOrdensCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        os.id AS ordem_servico_id,
        os.numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        COALESCE(os.data_finalizacao, os.data_abertura) AS data_referencia,
        (
          COALESCE(os.desconto, 0)
          + COALESCE(os.desconto_negociacao, 0)
        ) AS valor
      FROM ordens_servico os
      LEFT JOIN clientes c ON c.id = os.cliente_id
      WHERE os.status = 'Finalizada'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
        AND (
          COALESCE(os.desconto, 0)
          + COALESCE(os.desconto_negociacao, 0)
        ) > 0.000001
      ORDER BY
        date(COALESCE(os.data_finalizacao, os.data_abertura)) DESC,
        os.id DESC
      ''',
      [inicioDia, fimDia],
    );

    return resultado.map((linha) {
      final numero = (linha['numero'] ?? 'OS').toString().trim();
      final cliente = (linha['cliente_nome'] ?? '').toString().trim();

      return DreOrigemDetalhe(
        titulo: numero,
        subtitulo: cliente,
        valor: _double(linha['valor']),
        tipo: 'Desconto de OS',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> _origensTaxasCartaoCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        m.id AS movimento_id,
        m.ordem_servico_id,
        m.pagamento_id,
        os.numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        COALESCE(os.data_finalizacao, os.data_abertura) AS data_referencia,
        m.valor,
        COALESCE(m.forma_pagamento, '') AS forma_pagamento,
        p.parcela_numero,
        p.total_parcelas
      FROM movimentos_financeiros m
      INNER JOIN ordens_servico os ON os.id = m.ordem_servico_id
      LEFT JOIN clientes c ON c.id = os.cliente_id
      LEFT JOIN ordem_servico_pagamentos p ON p.id = m.pagamento_id
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE os.status = 'Finalizada'
        AND m.pagamento_id IS NOT NULL
        AND m.status = 'Realizado'
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos pcor
          WHERE pcor.id = m.pagamento_id
            AND pcor.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = pcor.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
        AND COALESCE(m.impacta_dre, 1) = 1
        AND m.transferencia_id IS NULL
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND (
          LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
          OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
        )
        AND COALESCE(pc.codigo, '2.02.01') = '2.02.01'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ORDER BY
        date(COALESCE(os.data_finalizacao, os.data_abertura)) DESC,
        m.id DESC
      ''',
      [inicioDia, fimDia],
    );

    return resultado.map((linha) {
      final numero = (linha['numero'] ?? 'OS').toString().trim();
      final cliente = (linha['cliente_nome'] ?? '').toString().trim();
      final forma = (linha['forma_pagamento'] ?? '').toString().trim();
      final parcela = _int(linha['parcela_numero']);
      final totalParcelas = _int(linha['total_parcelas']);

      final partes = <String>[
        if (cliente.isNotEmpty) cliente,
        if (forma.isNotEmpty) forma,
        if (parcela != null && totalParcelas != null)
          'Parcela $parcela/$totalParcelas',
      ];

      return DreOrigemDetalhe(
        titulo: 'Taxa • $numero',
        subtitulo: partes.join(' • '),
        valor: _double(linha['valor']),
        tipo: 'Taxa de cartão',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
        pagamentoId: _int(linha['pagamento_id']),
        movimentoId: _int(linha['movimento_id']),
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> _origensProdutosCompetencia({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        os.id AS ordem_servico_id,
        os.numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        COALESCE(os.data_finalizacao, os.data_abertura) AS data_referencia,
        COALESCE(p.produto_nome, 'Produto') AS produto_nome,
        COALESCE(p.quantidade, 0) AS quantidade,
        COALESCE(p.unidade, '') AS unidade,
        CASE
          WHEN COALESCE(p.custo_total_no_momento, 0) > 0
            THEN p.custo_total_no_momento
          ELSE COALESCE(p.quantidade, 0) *
            CASE
              WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                THEN p.custo_unitario_no_momento
              ELSE COALESCE(p.custo_unitario, 0)
            END
        END AS valor
      FROM ordem_servico_produtos p
      INNER JOIN ordens_servico os ON os.id = p.ordem_servico_id
      LEFT JOIN clientes c ON c.id = os.cliente_id
      WHERE os.status = 'Finalizada'
        AND date(COALESCE(os.data_finalizacao, os.data_abertura))
          BETWEEN date(?) AND date(?)
      ORDER BY
        date(COALESCE(os.data_finalizacao, os.data_abertura)) DESC,
        os.id DESC,
        p.id ASC
      ''',
      [inicioDia, fimDia],
    );

    return resultado
        .where((linha) => _double(linha['valor']) > 0.000001)
        .map((linha) {
      final numero = (linha['numero'] ?? 'OS').toString().trim();
      final cliente = (linha['cliente_nome'] ?? '').toString().trim();
      final quantidade = _double(linha['quantidade']);
      final unidade = (linha['unidade'] ?? '').toString().trim();
      final quantidadeTexto = _quantidadeTexto(quantidade);

      return DreOrigemDetalhe(
        titulo: (linha['produto_nome'] ?? 'Produto').toString(),
        subtitulo: [
          numero,
          if (cliente.isNotEmpty) cliente,
          '$quantidadeTexto${unidade.isEmpty ? '' : ' $unidade'}',
        ].join(' • '),
        valor: _double(linha['valor']),
        tipo: 'Produto consumido',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> _origensProdutosCaixa({
    required Database database,
    required String inicioDia,
    required String fimDia,
  }) async {
    final resultado = await database.rawQuery(
      '''
      WITH recebimentos_periodo AS (
        SELECT
          m.ordem_servico_id,
          COALESCE(SUM(m.valor), 0) AS recebido_periodo,
          MAX(COALESCE(m.data_pagamento, m.data)) AS ultima_data_recebimento
        FROM movimentos_financeiros m
        WHERE m.status = 'Realizado'
          AND m.transferencia_id IS NULL
          AND m.ordem_servico_id IS NOT NULL
          AND LOWER(m.tipo) = 'entrada'
          AND date(COALESCE(m.data_pagamento, m.data))
            BETWEEN date(?) AND date(?)
        GROUP BY m.ordem_servico_id
      )
      SELECT
        os.id AS ordem_servico_id,
        os.numero,
        COALESCE(c.nome, 'Cliente não informado') AS cliente_nome,
        r.ultima_data_recebimento AS data_referencia,
        COALESCE(p.produto_nome, 'Produto') AS produto_nome,
        COALESCE(p.quantidade, 0) AS quantidade,
        COALESCE(p.unidade, '') AS unidade,
        (
          CASE
            WHEN COALESCE(p.custo_total_no_momento, 0) > 0
              THEN p.custo_total_no_momento
            ELSE COALESCE(p.quantidade, 0) *
              CASE
                WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                  THEN p.custo_unitario_no_momento
                ELSE COALESCE(p.custo_unitario, 0)
              END
          END
        ) * MIN(
          r.recebido_periodo /
            MAX(
              COALESCE(os.valor_total, 0)
              - COALESCE(os.desconto, 0)
              - COALESCE(os.desconto_negociacao, 0)
              + COALESCE(os.acrescimo_negociacao, 0)
              + COALESCE(os.juros_parcelamento, 0),
              0.000001
            ),
          1.0
        ) AS valor
      FROM recebimentos_periodo r
      INNER JOIN ordens_servico os ON os.id = r.ordem_servico_id
      INNER JOIN ordem_servico_produtos p ON p.ordem_servico_id = os.id
      LEFT JOIN clientes c ON c.id = os.cliente_id
      WHERE os.status = 'Finalizada'
      ORDER BY date(r.ultima_data_recebimento) DESC, os.id DESC, p.id ASC
      ''',
      [inicioDia, fimDia],
    );

    return resultado
        .where((linha) => _double(linha['valor']) > 0.000001)
        .map((linha) {
      final numero = (linha['numero'] ?? 'OS').toString().trim();
      final cliente = (linha['cliente_nome'] ?? '').toString().trim();

      return DreOrigemDetalhe(
        titulo: (linha['produto_nome'] ?? 'Produto').toString(),
        subtitulo: [
          numero,
          if (cliente.isNotEmpty) cliente,
          'Custo proporcional ao recebido',
        ].join(' • '),
        valor: _double(linha['valor']),
        tipo: 'Produto proporcional ao caixa',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
      );
    }).toList();
  }

  Future<List<DreOrigemDetalhe>> _origensMovimentosFinanceiros({
    required Database database,
    required DreDetalhe detalhe,
    required String inicioDia,
    required String fimDia,
    required DreRegime regime,
  }) async {
    final dataExpressao = regime == DreRegime.caixa
        ? 'COALESCE(m.data_pagamento, m.data)'
        : 'COALESCE(m.data_competencia, m.data)';

    final filtroStatus = regime == DreRegime.caixa
        ? "m.status = 'Realizado'"
        : "m.status != 'Cancelado'";

    final excluirPagamentosCompetencia = regime == DreRegime.competencia
        ? '''
          AND m.pagamento_id IS NULL
          AND NOT (
            m.ordem_servico_id IS NOT NULL
            AND LOWER(m.tipo) = 'entrada'
          )
          '''
        : '';

    final resultado = await database.rawQuery(
      '''
      SELECT
        m.id AS movimento_id,
        m.ordem_servico_id,
        m.pagamento_id,
        m.descricao,
        m.valor,
        $dataExpressao AS data_referencia,
        COALESCE(m.origem, '') AS origem,
        COALESCE(m.forma_pagamento, '') AS forma_pagamento,
        COALESCE(m.numero_documento, '') AS numero_documento,
        COALESCE(m.observacoes, '') AS observacoes,
        COALESCE(os.numero, '') AS numero_os,
        COALESCE(fc.nome, '') AS conta_nome,
        COALESCE(f.nome, '') AS fornecedor_nome
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      LEFT JOIN ordens_servico os ON os.id = m.ordem_servico_id
      LEFT JOIN financeiro_contas fc ON fc.id = m.conta_id
      LEFT JOIN fornecedores f ON f.id = m.fornecedor_id
      WHERE $filtroStatus
        AND COALESCE(m.impacta_dre, 1) = 1
        AND m.transferencia_id IS NULL
        AND date($dataExpressao) BETWEEN date(?) AND date(?)
        AND COALESCE(pc.grupo_dre, 'Não DRE') = ?
        AND COALESCE(pc.codigo, '') = ?
        AND COALESCE(pc.grupo_dre, 'Não DRE') != 'Não DRE'
        AND COALESCE(pc.codigo, '') != '2.03.01'
        $excluirPagamentosCompetencia
      ORDER BY date($dataExpressao) DESC, m.id DESC
      ''',
      [inicioDia, fimDia, detalhe.grupo, detalhe.codigo],
    );

    return resultado.map((linha) {
      final origem = (linha['origem'] ?? '').toString().trim();
      final forma = (linha['forma_pagamento'] ?? '').toString().trim();
      final numeroOs = (linha['numero_os'] ?? '').toString().trim();
      final conta = (linha['conta_nome'] ?? '').toString().trim();
      final fornecedor = (linha['fornecedor_nome'] ?? '').toString().trim();
      final documento = (linha['numero_documento'] ?? '').toString().trim();

      final partes = <String>[
        if (origem.isNotEmpty) origem,
        if (numeroOs.isNotEmpty) numeroOs,
        if (fornecedor.isNotEmpty) fornecedor,
        if (conta.isNotEmpty) conta,
        if (forma.isNotEmpty) forma,
        if (documento.isNotEmpty) 'Doc. $documento',
      ];

      return DreOrigemDetalhe(
        titulo: (linha['descricao'] ?? detalhe.nome).toString(),
        subtitulo: partes.join(' • '),
        valor: _double(linha['valor']),
        tipo: 'Movimento financeiro',
        data: _textoNulo(linha['data_referencia']),
        ordemServicoId: _int(linha['ordem_servico_id']),
        pagamentoId: _int(linha['pagamento_id']),
        movimentoId: _int(linha['movimento_id']),
      );
    }).toList();
  }

  static int? _int(dynamic valor) {
    if (valor == null) {
      return null;
    }
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor.toString());
  }

  static String? _textoNulo(dynamic valor) {
    final texto = (valor ?? '').toString().trim();
    return texto.isEmpty ? null : texto;
  }

  static String _quantidadeTexto(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }

    return valor
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  Future<List<DreResultado>> evolucaoMensal({
    required int ano,
    DreRegime regime = DreRegime.competencia,
  }) async {
    final resultados = <DreResultado>[];
    for (var mes = 1; mes <= 12; mes++) {
      final inicio = DateTime(ano, mes, 1);
      final fim = DateTime(ano, mes + 1, 0, 23, 59, 59);
      resultados.add(await calcular(inicio: inicio, fim: fim, regime: regime));
    }
    return resultados;
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
