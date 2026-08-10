import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/movimento_financeiro.dart';

class FinanceiroRepository {
  Future<int> inserirMovimento(MovimentoFinanceiro movimento) async {
    final database = await AppDatabase.instance.database;
    final preparado = await _prepararMovimento(database, movimento);

    return database.insert(
      'movimentos_financeiros',
      preparado.toMap(incluirId: false),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<MovimentoFinanceiro>> listarMovimentos() async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'movimentos_financeiros',
      orderBy:
      'COALESCE(data_pagamento, data_vencimento, data_competencia, data) DESC, id DESC',
    );

    return resultado
        .map(
          (item) =>
          MovimentoFinanceiro.fromMap(Map<String, dynamic>.from(item)),
    )
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarMovimentosComCliente({
    String? tipo,
    String? status,
    DateTime? dataInicial,
    DateTime? dataFinal,
  }) async {
    return listarMovimentosComDetalhes(
      tipo: tipo,
      status: status,
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );
  }

  Future<List<Map<String, dynamic>>> listarMovimentosComDetalhes({
    String? tipo,
    String? status,
    DateTime? dataInicial,
    DateTime? dataFinal,
  }) async {
    final database = await AppDatabase.instance.database;
    final filtros = <String>[];
    final argumentos = <Object?>[];

    final tipoLimpo = tipo?.trim() ?? '';
    if (tipoLimpo.isNotEmpty && tipoLimpo != 'Todos') {
      if (tipoLimpo.toLowerCase() == 'saída' ||
          tipoLimpo.toLowerCase() == 'saida') {
        filtros.add("LOWER(m.tipo) IN ('saída', 'saida')");
      } else {
        filtros.add('LOWER(m.tipo) = ?');
        argumentos.add(tipoLimpo.toLowerCase());
      }
    }

    final statusLimpo = status?.trim() ?? '';
    if (statusLimpo.isNotEmpty && statusLimpo != 'Todos') {
      if (statusLimpo == 'Atrasado') {
        filtros.add("m.status = 'Previsto'");
        filtros.add('date(m.data_vencimento) < date(?)');
        argumentos.add(_dataDia(DateTime.now()));
      } else {
        filtros.add('m.status = ?');
        argumentos.add(statusLimpo);
      }
    }

    if (dataInicial != null && dataFinal != null) {
      filtros.add('''
        date(COALESCE(
          m.data_pagamento,
          m.data_vencimento,
          m.data_competencia,
          m.data
        )) BETWEEN date(?) AND date(?)
      ''');
      argumentos.addAll([_dataDia(dataInicial), _dataDia(dataFinal)]);
    }

    final where = filtros.isEmpty ? '' : 'WHERE ${filtros.join(' AND ')}';

    return database.rawQuery('''
      SELECT
        m.*,
        c.nome AS cliente_nome,
        f.nome AS fornecedor_nome,
        fc.nome AS conta_nome,
        pc.codigo AS plano_codigo,
        pc.nome AS plano_nome,
        pc.grupo_dre AS plano_grupo_dre,
        CASE
          WHEN m.status = 'Previsto'
            AND m.data_vencimento IS NOT NULL
            AND date(m.data_vencimento) < date('now', 'localtime')
            THEN 'Atrasado'
          ELSE m.status
        END AS status_exibicao
      FROM movimentos_financeiros m
      LEFT JOIN clientes c ON c.id = m.cliente_id
      LEFT JOIN fornecedores f ON f.id = m.fornecedor_id
      LEFT JOIN financeiro_contas fc ON fc.id = m.conta_id
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      $where
      ORDER BY
        CASE
          WHEN m.status = 'Previsto'
            AND m.data_vencimento IS NOT NULL
            AND date(m.data_vencimento) < date('now', 'localtime') THEN 1
          WHEN m.status = 'Previsto' THEN 2
          WHEN m.status = 'Realizado' THEN 3
          ELSE 4
        END,
        COALESCE(m.data_vencimento, m.data_pagamento, m.data_competencia, m.data) DESC,
        m.id DESC
      ''', argumentos);
  }

  Future<List<MovimentoFinanceiro>> listarMovimentosPorPeriodo({
    required String dataInicial,
    required String dataFinal,
  }) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'movimentos_financeiros',
      where: '''
        date(COALESCE(data_pagamento, data_vencimento, data_competencia, data))
        BETWEEN date(?) AND date(?)
      ''',
      whereArgs: [dataInicial, dataFinal],
      orderBy: 'data DESC, id DESC',
    );

    return resultado
        .map(
          (item) =>
          MovimentoFinanceiro.fromMap(Map<String, dynamic>.from(item)),
    )
        .toList();
  }

  Future<MovimentoFinanceiro?> buscarMovimentoPorId(int id) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'movimentos_financeiros',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return MovimentoFinanceiro.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<int> atualizarMovimento(MovimentoFinanceiro movimento) async {
    if (movimento.id == null) {
      throw ArgumentError('Não foi possível atualizar o movimento sem ID.');
    }

    final database = await AppDatabase.instance.database;
    await _validarMovimentoManual(database, movimento.id!);
    final preparado = await _prepararMovimento(database, movimento);

    return database.update(
      'movimentos_financeiros',
      preparado.toMap(incluirId: false),
      where: 'id = ?',
      whereArgs: [movimento.id],
    );
  }

  Future<int> excluirMovimento(int id) async {
    final database = await AppDatabase.instance.database;
    await _validarMovimentoManual(database, id);

    return database.delete(
      'movimentos_financeiros',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarComoRealizado({
    required int id,
    DateTime? dataPagamento,
    int? contaId,
    String? formaPagamento,
  }) async {
    final database = await AppDatabase.instance.database;
    await _validarMovimentoManual(database, id);
    final pagamento = dataPagamento ?? DateTime.now();

    final atual = await database.query(
      'movimentos_financeiros',
      columns: ['conta_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final contaResolvida = contaId ??
        (atual.isEmpty ? null : _int(atual.first['conta_id']));

    if (contaResolvida == null) {
      throw StateError(
        'Selecione a conta/caixa antes de marcar o lançamento como realizado.',
      );
    }

    final conta = await database.query(
      'financeiro_contas',
      columns: ['id', 'ativo'],
      where: 'id = ?',
      whereArgs: [contaResolvida],
      limit: 1,
    );
    if (conta.isEmpty || _int(conta.first['ativo']) != 1) {
      throw StateError('A conta financeira selecionada não está ativa.');
    }

    final atualizacoes = <String, Object?>{
      'status': 'Realizado',
      'data_pagamento': pagamento.toIso8601String(),
      'data': pagamento.toIso8601String(),
      'conta_id': contaResolvida,
    };

    final forma = formaPagamento?.trim();
    if (forma != null && forma.isNotEmpty) {
      atualizacoes['forma_pagamento'] = forma;
    }

    await database.update(
      'movimentos_financeiros',
      atualizacoes,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cancelarMovimento(int id) async {
    final database = await AppDatabase.instance.database;
    await _validarMovimentoManual(database, id);
    await database.update(
      'movimentos_financeiros',
      {'status': 'Cancelado'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> registrarTransferencia({
    required int contaOrigemId,
    required int contaDestinoId,
    required double valor,
    required DateTime data,
    String descricao = 'Transferência entre contas',
    String observacoes = '',
  }) async {
    if (contaOrigemId == contaDestinoId) {
      throw ArgumentError('Selecione contas diferentes para a transferência.');
    }
    if (valor <= 0) {
      throw ArgumentError('O valor da transferência deve ser maior que zero.');
    }

    final database = await AppDatabase.instance.database;

    return database.transaction((transaction) async {
      await _validarContaAtiva(transaction, contaOrigemId);
      await _validarContaAtiva(transaction, contaDestinoId);

      final plano = await transaction.query(
        'financeiro_plano_contas',
        columns: ['id', 'natureza'],
        where: 'codigo = ?',
        whereArgs: ['9.01'],
        limit: 1,
      );
      final planoId = plano.isEmpty ? null : _int(plano.first['id']);
      final natureza = plano.isEmpty
          ? 'Transferência'
          : (plano.first['natureza'] ?? 'Transferência').toString();
      final agora = DateTime.now().toIso8601String();
      final dataIso = data.toIso8601String();

      final transferenciaId = await transaction
          .insert('financeiro_transferencias', {
        'conta_origem_id': contaOrigemId,
        'conta_destino_id': contaDestinoId,
        'valor': valor,
        'data': dataIso,
        'descricao': descricao.trim().isEmpty
            ? 'Transferência entre contas'
            : descricao.trim(),
        'observacoes': observacoes.trim(),
        'criado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final comum = <String, Object?>{
        'descricao': descricao.trim().isEmpty
            ? 'Transferência entre contas'
            : descricao.trim(),
        'valor': valor,
        'forma_pagamento': 'Transferência',
        'data': dataIso,
        'plano_conta_id': planoId,
        'transferencia_id': transferenciaId,
        'natureza': natureza,
        'origem': 'Transferência',
        'status': 'Realizado',
        'data_competencia': dataIso,
        'data_vencimento': null,
        'data_pagamento': dataIso,
        'numero_documento': '',
        'observacoes': observacoes.trim(),
        'impacta_dre': 0,
      };

      await transaction.insert('movimentos_financeiros', {
        ...comum,
        'tipo': 'Saída',
        'conta_id': contaOrigemId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await transaction.insert('movimentos_financeiros', {
        ...comum,
        'tipo': 'Entrada',
        'conta_id': contaDestinoId,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      return transferenciaId;
    });
  }

  /// Comparação orçamentária do período.
  ///
  /// Previsto:
  /// - lançamento ainda Previsto; ou
  /// - lançamento que nasceu com vencimento e depois foi Realizado.
  ///
  /// Realizado:
  /// - dinheiro efetivamente pago/recebido no período.
  ///
  /// Pagamentos de OS que foram Estornados são neutralizados na análise:
  /// a entrada original, a taxa e a saída de estorno continuam no histórico,
  /// mas não viram receita/despesa artificial nos indicadores.
  Future<Map<String, double>> obterPrevistoRealizado({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    final resultado = await database.rawQuery(
      '''
      WITH comparacao AS (
        SELECT
          LOWER(m.tipo) AS tipo,
          m.valor AS valor,
          1 AS previsto,
          0 AS realizado
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.status IN ('Previsto', 'Realizado')
          AND m.transferencia_id IS NULL
          AND COALESCE(m.impacta_dre, 1) = 1
          AND COALESCE(pc.grupo_dre, '') != 'Não DRE'
          AND (
            m.status = 'Previsto'
            OR (
              m.status = 'Realizado'
              AND m.data_vencimento IS NOT NULL
            )
          )
          AND date(COALESCE(
            m.data_vencimento,
            m.data_competencia,
            m.data
          )) BETWEEN date(?) AND date(?)
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos p
            WHERE p.id = m.pagamento_id
              AND p.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = p.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )

        UNION ALL

        SELECT
          LOWER(m.tipo) AS tipo,
          m.valor AS valor,
          0 AS previsto,
          1 AS realizado
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.status = 'Realizado'
          AND m.transferencia_id IS NULL
          AND COALESCE(m.impacta_dre, 1) = 1
          AND COALESCE(pc.grupo_dre, '') != 'Não DRE'
          AND date(COALESCE(
            m.data_pagamento,
            m.data
          )) BETWEEN date(?) AND date(?)
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos p
            WHERE p.id = m.pagamento_id
              AND p.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = p.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )
      )
      SELECT
        COALESCE(SUM(CASE
          WHEN previsto = 1 AND tipo = 'entrada'
          THEN valor ELSE 0 END), 0) AS entrada_prevista,
        COALESCE(SUM(CASE
          WHEN realizado = 1 AND tipo = 'entrada'
          THEN valor ELSE 0 END), 0) AS entrada_realizada,
        COALESCE(SUM(CASE
          WHEN previsto = 1 AND tipo IN ('saída', 'saida')
          THEN valor ELSE 0 END), 0) AS saida_prevista,
        COALESCE(SUM(CASE
          WHEN realizado = 1 AND tipo IN ('saída', 'saida')
          THEN valor ELSE 0 END), 0) AS saida_realizada
      FROM comparacao
      ''',
      [inicioDia, fimDia, inicioDia, fimDia],
    );

    final linha = resultado.first;
    final entradaPrevista = _double(linha['entrada_prevista']);
    final entradaRealizada = _double(linha['entrada_realizada']);
    final saidaPrevista = _double(linha['saida_prevista']);
    final saidaRealizada = _double(linha['saida_realizada']);

    return {
      'entrada_prevista': entradaPrevista,
      'entrada_realizada': entradaRealizada,
      'saida_prevista': saidaPrevista,
      'saida_realizada': saidaRealizada,
      'resultado_previsto': entradaPrevista - saidaPrevista,
      'resultado_realizado': entradaRealizada - saidaRealizada,
    };
  }

  Future<List<Map<String, dynamic>>> listarPrevistoRealizadoPorCategoria({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    return database.rawQuery(
      '''
      WITH comparacao AS (
        SELECT
          LOWER(m.tipo) AS tipo_normalizado,
          m.plano_conta_id,
          COALESCE(pc.codigo, '') AS codigo,
          COALESCE(pc.nome, 'Sem categoria') AS categoria,
          m.valor AS valor,
          1 AS previsto,
          0 AS realizado
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.status IN ('Previsto', 'Realizado')
          AND m.transferencia_id IS NULL
          AND COALESCE(m.impacta_dre, 1) = 1
          AND COALESCE(pc.grupo_dre, '') != 'Não DRE'
          AND (
            m.status = 'Previsto'
            OR (
              m.status = 'Realizado'
              AND m.data_vencimento IS NOT NULL
            )
          )
          AND date(COALESCE(
            m.data_vencimento,
            m.data_competencia,
            m.data
          )) BETWEEN date(?) AND date(?)
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos p
            WHERE p.id = m.pagamento_id
              AND p.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = p.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )

        UNION ALL

        SELECT
          LOWER(m.tipo) AS tipo_normalizado,
          m.plano_conta_id,
          COALESCE(pc.codigo, '') AS codigo,
          COALESCE(pc.nome, 'Sem categoria') AS categoria,
          m.valor AS valor,
          0 AS previsto,
          1 AS realizado
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
        WHERE m.status = 'Realizado'
          AND m.transferencia_id IS NULL
          AND COALESCE(m.impacta_dre, 1) = 1
          AND COALESCE(pc.grupo_dre, '') != 'Não DRE'
          AND date(COALESCE(
            m.data_pagamento,
            m.data
          )) BETWEEN date(?) AND date(?)
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos p
            WHERE p.id = m.pagamento_id
              AND p.status = 'Estornado'
              AND NOT EXISTS (
                SELECT 1
                FROM movimentos_financeiros devolucao
                WHERE devolucao.pagamento_id = p.id
                  AND devolucao.status = 'Realizado'
                  AND LOWER(COALESCE(devolucao.origem, '')) =
                      'devolução ao cliente'
              )
          )
      )
      SELECT
        CASE
          WHEN tipo_normalizado = 'entrada' THEN 'Entrada'
          ELSE 'Saída'
        END AS tipo,
        plano_conta_id,
        codigo,
        categoria,
        COALESCE(SUM(CASE WHEN previsto = 1 THEN valor ELSE 0 END), 0)
          AS previsto,
        COALESCE(SUM(CASE WHEN realizado = 1 THEN valor ELSE 0 END), 0)
          AS realizado
      FROM comparacao
      GROUP BY
        tipo_normalizado,
        plano_conta_id,
        codigo,
        categoria
      HAVING previsto > 0.000001 OR realizado > 0.000001
      ORDER BY
        CASE WHEN tipo_normalizado = 'entrada' THEN 1 ELSE 2 END,
        codigo COLLATE NOCASE ASC,
        categoria COLLATE NOCASE ASC
      ''',
      [inicioDia, fimDia, inicioDia, fimDia],
    );
  }

  Future<Map<String, double>> obterResumoFinanceiro({
    String? dataInicial,
    String? dataFinal,
  }) async {
    final database = await AppDatabase.instance.database;
    final filtros = <String>[
      "status = 'Realizado'",
      'transferencia_id IS NULL',
      '''
      NOT EXISTS (
        SELECT 1
        FROM ordem_servico_pagamentos p
        WHERE p.id = movimentos_financeiros.pagamento_id
          AND p.status = 'Estornado'
          AND NOT EXISTS (
            SELECT 1
            FROM movimentos_financeiros devolucao
            WHERE devolucao.pagamento_id = p.id
              AND devolucao.status = 'Realizado'
              AND LOWER(COALESCE(devolucao.origem, '')) =
                  'devolução ao cliente'
          )
      )
      ''',
    ];
    final argumentos = <Object?>[];

    if (dataInicial != null && dataFinal != null) {
      filtros.add(
        'date(COALESCE(data_pagamento, data)) BETWEEN date(?) AND date(?)',
      );
      argumentos.addAll([dataInicial, dataFinal]);
    }

    final resultado = await database.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN LOWER(tipo) = 'entrada' THEN valor ELSE 0 END), 0)
          AS entradas,
        COALESCE(SUM(CASE WHEN LOWER(tipo) IN ('saída', 'saida') THEN valor ELSE 0 END), 0)
          AS saidas
      FROM movimentos_financeiros
      WHERE ${filtros.join(' AND ')}
      ''', argumentos);

    final entradas = _double(resultado.first['entradas']);
    final saidas = _double(resultado.first['saidas']);
    return {'entradas': entradas, 'saidas': saidas, 'saldo': entradas - saidas};
  }

  Future<Map<String, double>> obterResumoOperacional({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) = 'entrada' THEN valor ELSE 0 END), 0)
          AS entradas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) IN ('saída', 'saida') THEN valor ELSE 0 END), 0)
          AS saidas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) = 'entrada' THEN valor ELSE 0 END), 0)
          AS entradas_previstas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) IN ('saída', 'saida') THEN valor ELSE 0 END), 0)
          AS saidas_previstas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto'
            AND LOWER(tipo) IN ('saída', 'saida')
            AND data_vencimento IS NOT NULL
            AND date(data_vencimento) < date('now', 'localtime')
          THEN valor ELSE 0 END), 0) AS vencido_pagar
      FROM movimentos_financeiros
      WHERE status != 'Cancelado'
        AND transferencia_id IS NULL
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos p
          WHERE p.id = movimentos_financeiros.pagamento_id
            AND p.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = p.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
        AND date(COALESCE(data_pagamento, data_vencimento, data_competencia, data))
          BETWEEN date(?) AND date(?)
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final mapa = resultado.first;
    final entradas = _double(mapa['entradas_realizadas']);
    final saidas = _double(mapa['saidas_realizadas']);
    return {
      'entradas_realizadas': entradas,
      'saidas_realizadas': saidas,
      'saldo_realizado': entradas - saidas,
      'entradas_previstas': _double(mapa['entradas_previstas']),
      'saidas_previstas': _double(mapa['saidas_previstas']),
      'vencido_pagar': _double(mapa['vencido_pagar']),
    };
  }

  Future<List<Map<String, dynamic>>> listarClientesAtivos() async {
    final database = await AppDatabase.instance.database;
    return database.query(
      'clientes',
      columns: ['id', 'nome'],
      where: 'ativo = 1',
      orderBy: 'nome COLLATE NOCASE ASC',
    );
  }

  Future<double> somarEntradas({String? dataInicial, String? dataFinal}) async {
    final resumo = await obterResumoFinanceiro(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );
    return resumo['entradas'] ?? 0;
  }

  Future<double> somarSaidas({String? dataInicial, String? dataFinal}) async {
    final resumo = await obterResumoFinanceiro(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );
    return resumo['saidas'] ?? 0;
  }

  Future<double> calcularSaldo({String? dataInicial, String? dataFinal}) async {
    final resumo = await obterResumoFinanceiro(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );
    return resumo['saldo'] ?? 0;
  }

  Future<bool> existeMovimentoDoAgendamento(int agendamentoId) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'movimentos_financeiros',
      columns: ['id'],
      where: 'agendamento_id = ?',
      whereArgs: [agendamentoId],
      limit: 1,
    );
    return resultado.isNotEmpty;
  }

  Future<MovimentoFinanceiro> _prepararMovimento(
      Database database,
      MovimentoFinanceiro movimento,
      ) async {
    if (movimento.valor <= 0) {
      throw ArgumentError('O valor deve ser maior que zero.');
    }

    final tipo = _normalizarTipo(movimento.tipo);
    if (movimento.descricao.trim().length < 3) {
      throw ArgumentError('Informe uma descrição com pelo menos 3 caracteres.');
    }

    int? planoContaId = movimento.planoContaId;
    String natureza = movimento.natureza;
    var impactaDre = movimento.impactaDre;

    if (planoContaId == null) {
      final codigo = tipo == 'Entrada' ? '1.99.01' : '2.99.01';
      final padrao = await database.query(
        'financeiro_plano_contas',
        columns: ['id', 'natureza', 'grupo_dre'],
        where: 'codigo = ?',
        whereArgs: [codigo],
        limit: 1,
      );
      if (padrao.isNotEmpty) {
        planoContaId = _int(padrao.first['id']);
        natureza = (padrao.first['natureza'] ?? natureza).toString();
        impactaDre = padrao.first['grupo_dre']?.toString() != 'Não DRE';
      }
    } else {
      final categoria = await database.query(
        'financeiro_plano_contas',
        columns: ['natureza', 'grupo_dre', 'ativo'],
        where: 'id = ?',
        whereArgs: [planoContaId],
        limit: 1,
      );
      if (categoria.isEmpty || _int(categoria.first['ativo']) != 1) {
        throw StateError('A categoria financeira selecionada não está ativa.');
      }
      natureza = (categoria.first['natureza'] ?? natureza).toString();
      impactaDre = categoria.first['grupo_dre']?.toString() != 'Não DRE';
    }

    final status =
    const {'Previsto', 'Realizado', 'Cancelado'}.contains(movimento.status)
        ? movimento.status
        : 'Realizado';

    // A tela exige conta/caixa para novos lançamentos realizados.
    // O repository, porém, mantém compatibilidade com dados e testes antigos
    // que podem possuir movimentos realizados sem conta vinculada.
    if (status == 'Realizado' && movimento.contaId != null) {
      final conta = await database.query(
        'financeiro_contas',
        columns: ['id', 'ativo'],
        where: 'id = ?',
        whereArgs: [movimento.contaId],
        limit: 1,
      );

      if (conta.isEmpty || _int(conta.first['ativo']) != 1) {
        throw StateError('A conta financeira selecionada não está ativa.');
      }
    }

    final competencia = movimento.dataCompetencia ?? movimento.data;
    final pagamento = status == 'Realizado'
        ? movimento.dataPagamento ?? movimento.data
        : movimento.dataPagamento;
    final dataBase = pagamento ?? movimento.dataVencimento ?? competencia;

    return movimento.copyWith(
      tipo: tipo,
      descricao: movimento.descricao.trim(),
      formaPagamento: movimento.formaPagamento.trim(),
      data: dataBase,
      planoContaId: planoContaId,
      natureza: natureza,
      origem: movimento.origem.trim().isEmpty
          ? 'Manual'
          : movimento.origem.trim(),
      status: status,
      dataCompetencia: competencia,
      dataPagamento: pagamento,
      numeroDocumento: movimento.numeroDocumento.trim(),
      observacoes: movimento.observacoes.trim(),
      impactaDre: impactaDre,
    );
  }

  Future<void> _validarMovimentoManual(Database database, int id) async {
    final resultado = await database.query(
      'movimentos_financeiros',
      columns: [
        'pagamento_id',
        'ordem_servico_id',
        'transferencia_id',
        'origem',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Movimentação financeira não encontrada.');
    }

    final item = resultado.first;
    final origem = (item['origem'] ?? 'Manual').toString();
    if (item['pagamento_id'] != null ||
        item['ordem_servico_id'] != null ||
        item['transferencia_id'] != null ||
        origem != 'Manual') {
      throw StateError(
        'Esta movimentação é automática e deve ser alterada no módulo de origem.',
      );
    }
  }

  Future<void> _validarContaAtiva(Transaction transaction, int contaId) async {
    final resultado = await transaction.query(
      'financeiro_contas',
      columns: ['id', 'ativo'],
      where: 'id = ?',
      whereArgs: [contaId],
      limit: 1,
    );

    if (resultado.isEmpty || _int(resultado.first['ativo']) != 1) {
      throw StateError('Conta financeira não encontrada ou inativa.');
    }
  }

  static String _normalizarTipo(String tipo) {
    final valor = tipo.trim().toLowerCase();
    if (valor == 'entrada') return 'Entrada';
    if (valor == 'saída' || valor == 'saida') return 'Saída';
    throw ArgumentError('Tipo de movimentação inválido.');
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
      valor?.toString().trim().replaceAll(',', '.') ?? '',
    ) ??
        0;
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }
}
