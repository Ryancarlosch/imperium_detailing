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
    // No regime de caixa, o custo do produto acompanha o recebimento da OS.
    // Ex.: uma OS de R$ 1.000 com R$ 200 de produtos, recebida 40% neste mês,
    // reconhece R$ 80 de custo de produtos neste mês.
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
      recebimentos_periodo AS (
        SELECT
          m.ordem_servico_id,
          COALESCE(SUM(m.valor), 0) AS recebido_periodo
        FROM movimentos_financeiros m
        WHERE m.status = 'Realizado'
          AND m.transferencia_id IS NULL
          AND m.ordem_servico_id IS NOT NULL
          AND LOWER(m.tipo) = 'entrada'
          AND date(COALESCE(m.data_pagamento, m.data))
            BETWEEN date(?) AND date(?)
        GROUP BY m.ordem_servico_id
      )
      SELECT COALESCE(SUM(
        CASE
          WHEN c.valor_final_os <= 0 OR c.custo_produtos <= 0 THEN 0
          ELSE c.custo_produtos * MIN(
            r.recebido_periodo / c.valor_final_os,
            1.0
          )
        END
      ), 0) AS total
      FROM recebimentos_periodo r
      INNER JOIN custos_os c ON c.ordem_servico_id = r.ordem_servico_id
      ''',
      [inicioDia, fimDia],
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
