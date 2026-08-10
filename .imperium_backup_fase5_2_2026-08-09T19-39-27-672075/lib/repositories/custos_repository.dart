import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/colaborador_custo.dart';
import '../models/custo_fixo.dart';

class CustosRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<List<CustoFixo>> listarCustosFixos({
    bool incluirInativos = false,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_custos_fixos',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC, id ASC',
    );
    return resultado
        .map((item) => CustoFixo.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> salvarCustoFixo(CustoFixo custo) async {
    final nome = custo.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do custo fixo.');
    }
    if (custo.valorMensal < 0) {
      throw ArgumentError('O valor mensal não pode ser negativo.');
    }
    if (custo.diaVencimento != null &&
        (custo.diaVencimento! < 1 || custo.diaVencimento! > 31)) {
      throw ArgumentError('O dia de vencimento deve ficar entre 1 e 31.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    final mapa = custo.toMap(incluirId: false)
      ..['nome'] = nome
      ..['atualizado_em'] = agora;

    if (mapa['plano_conta_id'] == null) {
      mapa['plano_conta_id'] = await _planoContaAutomaticoCustoFixo(
        database,
        nome,
      );
    }

    if (custo.id == null) {
      mapa['criado_em'] = agora;
      return database.insert(
        'financeiro_custos_fixos',
        mapa,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await database.update(
      'financeiro_custos_fixos',
      mapa,
      where: 'id = ?',
      whereArgs: [custo.id],
    );
    return custo.id!;
  }

  Future<void> arquivarCustoFixo(int id) async {
    final database = await _appDatabase.database;
    await database.update(
      'financeiro_custos_fixos',
      {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ColaboradorCusto>> listarColaboradores({
    bool incluirInativos = false,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_colaboradores_custo',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC, id ASC',
    );
    return resultado
        .map(
          (item) => ColaboradorCusto.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<int> salvarColaborador(ColaboradorCusto colaborador) async {
    final nome = colaborador.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do colaborador.');
    }
    if (colaborador.remuneracaoMensal < 0 ||
        colaborador.encargosMensais < 0 ||
        colaborador.outrosCustosMensais < 0) {
      throw ArgumentError('Os valores de custo não podem ser negativos.');
    }
    if (colaborador.horasProdutivasMes <= 0) {
      throw ArgumentError('Informe as horas produtivas mensais.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    final mapa = colaborador.toMap(incluirId: false)
      ..['nome'] = nome
      ..['funcao'] = colaborador.funcao.trim()
      ..['atualizado_em'] = agora;

    if (colaborador.id == null) {
      mapa['criado_em'] = agora;
      return database.insert(
        'financeiro_colaboradores_custo',
        mapa,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await database.update(
      'financeiro_colaboradores_custo',
      mapa,
      where: 'id = ?',
      whereArgs: [colaborador.id],
    );
    return colaborador.id!;
  }

  Future<void> arquivarColaborador(int id) async {
    final database = await _appDatabase.database;
    await database.update(
      'financeiro_colaboradores_custo',
      {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> registrarPagamentoColaborador({
    required int colaboradorId,
    required double valor,
    required int contaId,
    required DateTime dataPagamento,
    String formaPagamento = 'Pix',
    String observacoes = '',
  }) async {
    if (valor <= 0) {
      throw ArgumentError('Informe um valor de pagamento maior que zero.');
    }

    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final colaboradores = await transaction.query(
        'financeiro_colaboradores_custo',
        columns: ['id', 'nome'],
        where: 'id = ? AND ativo = 1',
        whereArgs: [colaboradorId],
        limit: 1,
      );
      if (colaboradores.isEmpty) {
        throw StateError('Funcionário não encontrado ou inativo.');
      }

      final contas = await transaction.query(
        'financeiro_contas',
        columns: ['id', 'ativo'],
        where: 'id = ?',
        whereArgs: [contaId],
        limit: 1,
      );
      if (contas.isEmpty || _int(contas.first['ativo']) != 1) {
        throw StateError('A conta financeira selecionada não está ativa.');
      }

      final planos = await transaction.query(
        'financeiro_plano_contas',
        columns: ['id', 'natureza', 'grupo_dre', 'ativo'],
        where: 'codigo = ?',
        whereArgs: ['2.01.01'],
        limit: 1,
      );
      if (planos.isEmpty || _int(planos.first['ativo']) != 1) {
        throw StateError(
          'A categoria Folha de pagamento não está disponível no plano de contas.',
        );
      }

      final nome = (colaboradores.first['nome'] ?? 'Funcionário')
          .toString()
          .trim();
      final plano = planos.first;
      final dataIso = dataPagamento.toIso8601String();
      final forma = formaPagamento.trim().isEmpty
          ? 'Não informado'
          : formaPagamento.trim();
      final grupoDre = (plano['grupo_dre'] ?? '').toString();

      return transaction.insert(
        'movimentos_financeiros',
        {
          'tipo': 'Saída',
          'descricao': 'Pagamento $nome - ${_dataCurta(dataPagamento)}',
          'valor': valor,
          'forma_pagamento': forma,
          'data': dataIso,
          'cliente_id': null,
          'agendamento_id': null,
          'ordem_servico_id': null,
          'pagamento_id': null,
          'plano_conta_id': _int(plano['id']),
          'conta_id': contaId,
          'fornecedor_id': null,
          'transferencia_id': null,
          'natureza': (plano['natureza'] ?? 'Mão de obra').toString(),
          'origem': 'Manual',
          'status': 'Realizado',
          'data_competencia': dataIso,
          'data_vencimento': null,
          'data_pagamento': dataIso,
          'numero_documento': 'FUNC-$colaboradorId',
          'observacoes': observacoes.trim(),
          'impacta_dre': grupoDre == 'Não DRE' ? 0 : 1,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<List<Map<String, dynamic>>> listarPagamentosColaboradores({
    int? colaboradorId,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    final database = await _appDatabase.database;
    final filtros = <String>[
      "LOWER(m.tipo) IN ('saída', 'saida')",
      "m.numero_documento LIKE 'FUNC-%'",
      "m.status != 'Cancelado'",
    ];
    final argumentos = <Object?>[];

    if (colaboradorId != null) {
      filtros.add('m.numero_documento = ?');
      argumentos.add('FUNC-$colaboradorId');
    }

    if (inicio != null && fim != null) {
      filtros.add(
        'date(COALESCE(m.data_pagamento, m.data)) '
        'BETWEEN date(?) AND date(?)',
      );
      argumentos.addAll([_dataBanco(inicio), _dataBanco(fim)]);
    }

    return database.rawQuery(
      '''
      SELECT
        m.*,
        fc.nome AS conta_nome,
        pc.nome AS plano_nome,
        CAST(
          SUBSTR(m.numero_documento, LENGTH('FUNC-') + 1) AS INTEGER
        ) AS colaborador_id,
        COALESCE(
          (
            SELECT c.nome
            FROM financeiro_colaboradores_custo c
            WHERE c.id = CAST(
              SUBSTR(m.numero_documento, LENGTH('FUNC-') + 1) AS INTEGER
            )
            LIMIT 1
          ),
          'Funcionário'
        ) AS colaborador_nome
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_contas fc ON fc.id = m.conta_id
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE ${filtros.join(' AND ')}
      ORDER BY
        datetime(COALESCE(m.data_pagamento, m.data)) DESC,
        m.id DESC
      ''',
      argumentos,
    );
  }

  Future<void> excluirPagamentoColaborador(int movimentoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'movimentos_financeiros',
      columns: [
        'id',
        'origem',
        'numero_documento',
        'pagamento_id',
        'ordem_servico_id',
        'transferencia_id',
      ],
      where: 'id = ?',
      whereArgs: [movimentoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Pagamento não encontrado.');
    }

    final movimento = resultado.first;
    final documento = (movimento['numero_documento'] ?? '').toString();
    final origem = (movimento['origem'] ?? '').toString();

    if (!documento.startsWith('FUNC-') ||
        origem != 'Manual' ||
        movimento['pagamento_id'] != null ||
        movimento['ordem_servico_id'] != null ||
        movimento['transferencia_id'] != null) {
      throw StateError(
        'Este lançamento não pode ser excluído pela área de funcionários.',
      );
    }

    await database.delete(
      'movimentos_financeiros',
      where: 'id = ?',
      whereArgs: [movimentoId],
    );
  }

  static String _dataCurta(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString().padLeft(4, '0');
    return '$dia/$mes/$ano';
  }

  static String _dataBanco(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  Future<Map<String, double>> obterResumoEstruturaCustos() async {
    final database = await _appDatabase.database;

    final fixos = await database.rawQuery('''
      SELECT COALESCE(SUM(valor_mensal), 0) AS total
      FROM financeiro_custos_fixos
      WHERE ativo = 1
    ''');

    final maoObra = await database.rawQuery('''
      SELECT
        COALESCE(SUM(
          remuneracao_mensal + encargos_mensais + outros_custos_mensais
        ), 0) AS custo_mensal,
        COALESCE(SUM(horas_produtivas_mes), 0) AS horas_produtivas
      FROM financeiro_colaboradores_custo
      WHERE ativo = 1
    ''');

    final custoFixoMensal = _double(fixos.first['total']);
    final custoMaoObraMensal = _double(maoObra.first['custo_mensal']);
    final horasProdutivas = _double(maoObra.first['horas_produtivas']);
    final custoMaoObraHora = horasProdutivas > 0
        ? custoMaoObraMensal / horasProdutivas
        : 0.0;
    final custoFixoHora = horasProdutivas > 0
        ? custoFixoMensal / horasProdutivas
        : 0.0;

    return {
      'custo_fixo_mensal': custoFixoMensal,
      'custo_mao_obra_mensal': custoMaoObraMensal,
      'horas_produtivas': horasProdutivas,
      'custo_mao_obra_hora': custoMaoObraHora,
      'custo_fixo_hora': custoFixoHora,
      'custo_estrutura_hora': custoMaoObraHora + custoFixoHora,
    };
  }

  Future<List<Map<String, dynamic>>> listarCustosEstimadosServicos({
    double? custoMaoObraHora,
  }) async {
    final database = await _appDatabase.database;
    final resumo = await obterResumoEstruturaCustos();
    final custoMaoObraHoraEfetivo =
        custoMaoObraHora ?? resumo['custo_mao_obra_hora'] ?? 0;
    final custoFixoHora = resumo['custo_fixo_hora'] ?? 0;

    final resultado = await database.rawQuery('''
      SELECT
        s.id,
        s.nome,
        s.categoria,
        s.preco_padrao,
        s.preco_minimo,
        s.preco_maximo,
        s.duracao_minutos,
        COALESCE(SUM(
          sp.quantidade_padrao *
          CASE
            WHEN COALESCE(e.custo_unitario_calculado, 0) > 0
              THEN e.custo_unitario_calculado
            ELSE COALESCE(e.custo_unitario, 0)
          END
        ), 0) AS custo_produtos_estimado
      FROM servicos_catalogo s
      LEFT JOIN servico_produtos sp ON sp.servico_id = s.id
      LEFT JOIN itens_estoque e ON e.id = sp.item_estoque_id
      WHERE s.ativo = 1
      GROUP BY s.id
      ORDER BY s.nome COLLATE NOCASE ASC
    ''');

    return resultado.map((item) {
      final mapa = Map<String, dynamic>.from(item);
      final minutos = _double(mapa['duracao_minutos']);
      final horas = minutos / 60;
      final produtos = _double(mapa['custo_produtos_estimado']);
      final maoObra = horas * custoMaoObraHoraEfetivo;
      final fixo = horas * custoFixoHora;
      final custoTotal = produtos + maoObra + fixo;
      final preco = _double(mapa['preco_padrao']);
      final resultadoEstimado = preco - custoTotal;
      final margem = preco > 0 ? (resultadoEstimado / preco) * 100 : 0.0;

      double precoParaMargem(double margemPercentual) {
        final margemDecimal = margemPercentual / 100;
        if (custoTotal <= 0 || margemDecimal >= 1) {
          return custoTotal;
        }
        return custoTotal / (1 - margemDecimal);
      }

      mapa['horas_estimadas'] = horas;
      mapa['custo_mao_obra_hora_usado'] = custoMaoObraHoraEfetivo;
      mapa['custo_mao_obra_estimado'] = maoObra;
      mapa['custo_fixo_rateado_estimado'] = fixo;
      mapa['custo_total_estimado'] = custoTotal;
      mapa['preco_equilibrio'] = custoTotal;
      mapa['resultado_estimado'] = resultadoEstimado;
      mapa['margem_estimada'] = margem;
      mapa['preco_sugerido_margem_20'] = precoParaMargem(20);
      mapa['preco_sugerido_margem_30'] = precoParaMargem(30);
      mapa['preco_sugerido_margem_40'] = precoParaMargem(40);
      return mapa;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listarResultadoOrdens() async {
    final database = await _appDatabase.database;
    final resumo = await obterResumoEstruturaCustos();
    final custoFixoHora = resumo['custo_fixo_hora'] ?? 0;

    final resultado = await database.rawQuery('''
      SELECT
        os.id,
        os.numero,
        os.data_finalizacao,
        os.valor_total,
        os.desconto,
        os.desconto_negociacao,
        os.acrescimo_negociacao,
        os.juros_parcelamento,
        os.valor_recebido,
        os.status_pagamento,
        os.funcionario_responsavel,
        c.nome AS cliente_nome,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
        COALESCE((
          SELECT SUM(p.custo_total_no_momento)
          FROM ordem_servico_produtos p
          WHERE p.ordem_servico_id = os.id
        ), 0) AS custo_produtos,
        COALESCE((
          SELECT SUM(pag.taxa_operacao)
          FROM ordem_servico_pagamentos pag
          WHERE pag.ordem_servico_id = os.id
            AND (
              pag.status = 'Pago'
              OR (
                pag.status = 'Estornado'
                AND EXISTS (
                  SELECT 1
                  FROM movimentos_financeiros devolucao
                  WHERE devolucao.pagamento_id = pag.id
                    AND devolucao.status = 'Realizado'
                    AND LOWER(COALESCE(devolucao.origem, '')) =
                        'devolução ao cliente'
                )
              )
            )
        ), 0) AS taxas_pagamento,
        COALESCE((
          SELECT SUM(mo.custo_total)
          FROM financeiro_os_mao_obra mo
          WHERE mo.ordem_servico_id = os.id
            AND mo.ativo = 1
        ), 0) AS custo_mao_obra,
        COALESCE((
          SELECT SUM(mo.horas)
          FROM financeiro_os_mao_obra mo
          WHERE mo.ordem_servico_id = os.id
            AND mo.ativo = 1
        ), 0) AS horas_mao_obra
      FROM ordens_servico os
      INNER JOIN clientes c ON c.id = os.cliente_id
      LEFT JOIN veiculos v ON v.id = os.veiculo_id
      WHERE os.status = 'Finalizada'
      ORDER BY COALESCE(os.data_finalizacao, os.data_abertura) DESC, os.id DESC
    ''');

    return resultado.map((item) {
      final mapa = Map<String, dynamic>.from(item);
      final valorNegociado = _valorNegociado(mapa);
      final produtos = _double(mapa['custo_produtos']);
      final taxas = _double(mapa['taxas_pagamento']);
      final maoObra = _double(mapa['custo_mao_obra']);
      final horas = _double(mapa['horas_mao_obra']);
      final rateioFixo = horas * custoFixoHora;

      final custoComercial = produtos + taxas;
      final resultadoComercial = valorNegociado - custoComercial;
      final margemComercial = valorNegociado > 0
          ? (resultadoComercial / valorNegociado) * 100
          : 0.0;

      final custoGerencial = custoComercial + maoObra + rateioFixo;
      final resultadoGerencial = valorNegociado - custoGerencial;
      final margemGerencial = valorNegociado > 0
          ? (resultadoGerencial / valorNegociado) * 100
          : 0.0;

      mapa['valor_negociado'] = valorNegociado;
      mapa['custo_comercial'] = custoComercial;
      mapa['resultado_comercial'] = resultadoComercial;
      mapa['margem_comercial'] = margemComercial;
      mapa['rateio_custo_fixo'] = rateioFixo;
      mapa['custo_gerencial_total'] = custoGerencial;
      mapa['resultado_gerencial_estimado'] = resultadoGerencial;
      mapa['margem_gerencial_estimada'] = margemGerencial;

      // Compatibilidade com telas/testes existentes.
      mapa['custo_total'] = custoGerencial;
      mapa['resultado_os'] = resultadoGerencial;
      mapa['margem_os'] = margemGerencial;
      return mapa;
    }).toList();
  }

  Future<Map<String, dynamic>?> obterResultadoOrdem(int ordemServicoId) async {
    final ordens = await listarResultadoOrdens();
    for (final ordem in ordens) {
      if (_int(ordem['id']) == ordemServicoId) {
        final mapa = Map<String, dynamic>.from(ordem);
        mapa['mao_obra_lancamentos'] = await listarMaoObraOrdem(ordemServicoId);
        return mapa;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listarMaoObraOrdem(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;
    return database.rawQuery(
      '''
      SELECT
        mo.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_os_mao_obra mo
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = mo.colaborador_custo_id
      WHERE mo.ordem_servico_id = ?
        AND mo.ativo = 1
      ORDER BY mo.data ASC, mo.id ASC
      ''',
      [ordemServicoId],
    );
  }

  Future<int> registrarMaoObraOrdem({
    required int ordemServicoId,
    int? colaboradorId,
    required double horas,
    double? custoHoraManual,
    String descricao = '',
    String observacoes = '',
    DateTime? data,
  }) async {
    if (horas <= 0) {
      throw ArgumentError('Informe uma quantidade de horas maior que zero.');
    }

    final database = await _appDatabase.database;
    double custoHora = custoHoraManual ?? 0;
    String descricaoFinal = descricao.trim();

    if (colaboradorId != null) {
      final resultado = await database.query(
        'financeiro_colaboradores_custo',
        where: 'id = ? AND ativo = 1',
        whereArgs: [colaboradorId],
        limit: 1,
      );
      if (resultado.isEmpty) {
        throw StateError('Colaborador de custo não encontrado.');
      }
      final colaborador = ColaboradorCusto.fromMap(
        Map<String, dynamic>.from(resultado.first),
      );
      custoHora = colaborador.custoHoraProdutiva;
      if (descricaoFinal.isEmpty) {
        descricaoFinal = colaborador.nome;
      }
    }

    if (custoHora < 0) {
      throw ArgumentError('O custo por hora não pode ser negativo.');
    }

    final ordem = await database.query(
      'ordens_servico',
      columns: ['id', 'status'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );
    if (ordem.isEmpty) {
      throw StateError('Ordem de Serviço não encontrada.');
    }
    if ((ordem.first['status'] ?? '').toString() != 'Finalizada') {
      throw StateError(
        'A mão de obra de resultado deve ser vinculada a uma OS finalizada.',
      );
    }

    final agora = DateTime.now().toIso8601String();
    return database.insert('financeiro_os_mao_obra', {
      'ordem_servico_id': ordemServicoId,
      'colaborador_custo_id': colaboradorId,
      'descricao': descricaoFinal,
      'horas': horas,
      'custo_hora_snapshot': custoHora,
      'custo_total': horas * custoHora,
      'data': (data ?? DateTime.now()).toIso8601String(),
      'observacoes': observacoes.trim(),
      'ativo': 1,
      'cancelado_em': null,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Registra automaticamente o custo do responsável ao finalizar a OS.
  ///
  /// O custo/hora é congelado em snapshot, portanto alterações futuras no
  /// salário do funcionário não mudam o resultado histórico da OS.
  Future<int?> registrarMaoObraAutomaticaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String colaboradorNome,
    required DateTime entrada,
    required DateTime saida,
  }) async {
    final nome = colaboradorNome.trim();
    if (nome.isEmpty || !saida.isAfter(entrada)) {
      return null;
    }

    final minutos = saida.difference(entrada).inMinutes;
    if (minutos <= 0) {
      return null;
    }

    final existente = await transaction.query(
      'financeiro_os_mao_obra',
      columns: ['id'],
      where: 'ordem_servico_id = ? AND ativo = 1',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    // Evita duplicidade em OS que já possua mão de obra registrada.
    if (existente.isNotEmpty) {
      return _int(existente.first['id']);
    }

    final colaboradores = await transaction.rawQuery(
      '''
      SELECT *
      FROM financeiro_colaboradores_custo
      WHERE LOWER(TRIM(nome)) = LOWER(TRIM(?))
      ORDER BY ativo DESC, id ASC
      LIMIT 1
      ''',
      [nome],
    );

    // Compatibilidade com OS antigas que tinham responsável digitado livre.
    if (colaboradores.isEmpty) {
      return null;
    }

    final colaborador = ColaboradorCusto.fromMap(
      Map<String, dynamic>.from(colaboradores.first),
    );

    final horas = minutos / 60.0;
    final custoHora = colaborador.custoHoraProdutiva;
    final agora = DateTime.now().toIso8601String();

    return transaction.insert(
      'financeiro_os_mao_obra',
      {
        'ordem_servico_id': ordemServicoId,
        'colaborador_custo_id': colaborador.id,
        'descricao': colaborador.nome,
        'horas': horas,
        'custo_hora_snapshot': custoHora,
        'custo_total': horas * custoHora,
        'data': saida.toIso8601String(),
        'observacoes':
            'Gerado automaticamente pela entrada e saída da Ordem de Serviço.',
        'ativo': 1,
        'cancelado_em': null,
        'criado_em': agora,
        'atualizado_em': agora,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int?> recalcularMaoObraAutomaticaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String colaboradorNome,
    required DateTime entrada,
    required DateTime saida,
  }) async {
    await transaction.delete(
      'financeiro_os_mao_obra',
      where: '''
        ordem_servico_id = ?
        AND observacoes =
          'Gerado automaticamente pela entrada e saída da Ordem de Serviço.'
      ''',
      whereArgs: [ordemServicoId],
    );

    return registrarMaoObraAutomaticaComTransacao(
      transaction,
      ordemServicoId: ordemServicoId,
      colaboradorNome: colaboradorNome,
      entrada: entrada,
      saida: saida,
    );
  }

  Future<int?> _planoContaAutomaticoCustoFixo(
    Database database,
    String nome,
  ) async {
    final texto = nome.toLowerCase().trim();

    String? codigo;
    if (texto.contains('aluguel')) {
      codigo = '2.04.01';
    } else if (texto.contains('energia') ||
        texto.contains('internet') ||
        texto.contains('água') ||
        texto.contains('agua') ||
        texto.contains('telefone')) {
      codigo = '2.04.13';
    } else if (texto.contains('contador') ||
        texto.contains('contabilidade')) {
      codigo = '2.04.05';
    } else if (texto.contains('imposto') || texto.contains('tribut')) {
      codigo = '2.04.06';
    } else if (texto.contains('combust') || texto.contains('veículo') ||
        texto.contains('veiculo')) {
      codigo = '2.04.07';
    } else if (texto.contains('manutenção') ||
        texto.contains('manutencao')) {
      codigo = '2.04.08';
    } else if (texto.contains('marketing') ||
        texto.contains('anúncio') ||
        texto.contains('anuncio')) {
      codigo = '2.04.09';
    } else if (texto.contains('software') ||
        texto.contains('assinatura') ||
        texto.contains('sistema')) {
      codigo = '2.04.10';
    }

    if (codigo == null) {
      return null;
    }

    final resultado = await database.query(
      'financeiro_plano_contas',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );

    return resultado.isEmpty ? null : _int(resultado.first['id']);
  }

  Future<void> cancelarMaoObraOrdem(int id) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    await database.update(
      'financeiro_os_mao_obra',
      {'ativo': 0, 'cancelado_em': agora, 'atualizado_em': agora},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  double _valorNegociado(Map<String, dynamic> ordem) {
    final base = _double(ordem['valor_total']) - _double(ordem['desconto']);
    final negociado =
        base -
        _double(ordem['desconto_negociacao']) +
        _double(ordem['acrescimo_negociacao']) +
        _double(ordem['juros_parcelamento']);
    return negociado < 0 ? 0 : negociado;
  }

  static int? _int(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double _double(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
