import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/conta_financeira.dart';

class ContaFinanceiraRepository {
  Future<List<ContaFinanceira>> listar({bool incluirInativas = false}) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.rawQuery('''
      SELECT
        c.*,
        c.saldo_inicial + COALESCE((
          SELECT SUM(
            CASE
              WHEN LOWER(m.tipo) = 'entrada' THEN m.valor
              WHEN LOWER(m.tipo) IN ('saída', 'saida') THEN -m.valor
              ELSE 0
            END
          )
          FROM movimentos_financeiros m
          WHERE m.conta_id = c.id
            AND m.status = 'Realizado'
        ), 0) AS saldo_atual
      FROM financeiro_contas c
      ${incluirInativas ? '' : 'WHERE c.ativo = 1'}
      ORDER BY c.ativo DESC, c.nome COLLATE NOCASE ASC
    ''');

    return resultado
        .map((item) => ContaFinanceira.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> inserir(ContaFinanceira conta) async {
    final nome = conta.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome da conta.');
    }

    final database = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final dados = conta
        .copyWith(nome: nome, criadoEm: agora, atualizadoEm: agora, ativo: true)
        .toMap(incluirId: false);

    return database.insert(
      'financeiro_contas',
      dados,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> atualizar(ContaFinanceira conta) async {
    if (conta.id == null) {
      throw ArgumentError('Conta financeira sem ID.');
    }

    final database = await AppDatabase.instance.database;
    final dados = conta
        .copyWith(atualizadoEm: DateTime.now().toIso8601String())
        .toMap(incluirId: false);
    dados.remove('criado_em');

    await database.update(
      'financeiro_contas',
      dados,
      where: 'id = ?',
      whereArgs: [conta.id],
    );
  }

  Future<void> alterarAtivo(int id, bool ativo) async {
    final database = await AppDatabase.instance.database;

    if (!ativo) {
      final previsto =
          Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*)
              FROM movimentos_financeiros
              WHERE conta_id = ? AND status = 'Previsto'
              ''',
              [id],
            ),
          ) ??
          0;
      if (previsto > 0) {
        throw StateError(
          'Esta conta possui lançamentos previstos. Resolva-os antes de desativar.',
        );
      }
    }

    await database.update(
      'financeiro_contas',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> obterExtratoMensal({
    required int contaId,
    required DateTime mes,
  }) async {
    final database = await AppDatabase.instance.database;
    final inicio = DateTime(mes.year, mes.month, 1);
    final fimExclusivo = DateTime(mes.year, mes.month + 1, 1);

    final conta = await database.query(
      'financeiro_contas',
      columns: [
        'id',
        'nome',
        'tipo',
        'instituicao',
        'saldo_inicial',
        'data_saldo_inicial',
        'ativo',
      ],
      where: 'id = ?',
      whereArgs: [contaId],
      limit: 1,
    );

    if (conta.isEmpty) {
      throw StateError('Conta financeira não encontrada.');
    }

    final anteriores = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN LOWER(tipo) = 'entrada' THEN valor
          WHEN LOWER(tipo) IN ('saída', 'saida') THEN -valor
          ELSE 0
        END
      ), 0) AS total
      FROM movimentos_financeiros
      WHERE conta_id = ?
        AND status = 'Realizado'
        AND date(COALESCE(data_pagamento, data)) < date(?)
      ''',
      [contaId, inicio.toIso8601String()],
    );

    final saldoBase = _double(conta.first['saldo_inicial']);
    final movimentoAnterior = _double(anteriores.first['total']);
    final saldoInicialMes = saldoBase + movimentoAnterior;

    final movimentos = await database.rawQuery(
      '''
      SELECT
        m.*,
        pc.codigo AS plano_codigo,
        pc.nome AS plano_nome,
        pc.grupo_dre AS plano_grupo_dre
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc
        ON pc.id = m.plano_conta_id
      WHERE m.conta_id = ?
        AND m.status = 'Realizado'
        AND date(COALESCE(m.data_pagamento, m.data)) >= date(?)
        AND date(COALESCE(m.data_pagamento, m.data)) < date(?)
      ORDER BY
        datetime(COALESCE(m.data_pagamento, m.data)) ASC,
        m.id ASC
      ''',
      [contaId, inicio.toIso8601String(), fimExclusivo.toIso8601String()],
    );

    var entradas = 0.0;
    var saidas = 0.0;
    for (final item in movimentos) {
      final tipo = (item['tipo'] ?? '').toString().trim().toLowerCase();
      final valor = _double(item['valor']);
      if (tipo == 'entrada') {
        entradas += valor;
      } else if (tipo == 'saída' || tipo == 'saida') {
        saidas += valor;
      }
    }

    return {
      'conta': Map<String, dynamic>.from(conta.first),
      'saldo_inicial_mes': saldoInicialMes,
      'entradas': entradas,
      'saidas': saidas,
      'saldo_final_mes': saldoInicialMes + entradas - saidas,
      'movimentos': movimentos
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    };
  }

  Future<void> _garantirTabelaConciliacoes(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_conciliacoes_conta (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conta_id INTEGER NOT NULL,
        data_conciliacao TEXT NOT NULL,
        saldo_calculado REAL NOT NULL DEFAULT 0,
        saldo_informado REAL NOT NULL DEFAULT 0,
        diferenca REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Conciliado',
        movimento_ajuste_id INTEGER,
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        FOREIGN KEY (conta_id)
          REFERENCES financeiro_contas (id)
          ON DELETE RESTRICT,
        FOREIGN KEY (movimento_ajuste_id)
          REFERENCES movimentos_financeiros (id)
          ON DELETE SET NULL,
        CHECK (status IN ('Conciliado', 'Divergente', 'Ajustado'))
      )
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_fin_conciliacoes_conta_data
      ON financeiro_conciliacoes_conta (conta_id, data_conciliacao)
    ''');
  }

  Future<double> _saldoCalculadoAte(
    DatabaseExecutor executor, {
    required int contaId,
    required DateTime data,
  }) async {
    final conta = await executor.query(
      'financeiro_contas',
      columns: ['id', 'saldo_inicial'],
      where: 'id = ?',
      whereArgs: [contaId],
      limit: 1,
    );

    if (conta.isEmpty) {
      throw StateError('Conta financeira não encontrada.');
    }

    final movimentos = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN LOWER(tipo) = 'entrada' THEN valor
          WHEN LOWER(tipo) IN ('saída', 'saida') THEN -valor
          ELSE 0
        END
      ), 0) AS total
      FROM movimentos_financeiros
      WHERE conta_id = ?
        AND status = 'Realizado'
        AND date(COALESCE(data_pagamento, data)) <= date(?)
      ''',
      [contaId, data.toIso8601String()],
    );

    return _double(conta.first['saldo_inicial']) +
        _double(movimentos.first['total']);
  }

  Future<double> obterSaldoCalculadoAte({
    required int contaId,
    required DateTime data,
  }) async {
    final database = await AppDatabase.instance.database;
    return _saldoCalculadoAte(database, contaId: contaId, data: data);
  }

  Future<List<Map<String, dynamic>>> listarConciliacoesMes({
    required int contaId,
    required DateTime mes,
  }) async {
    final database = await AppDatabase.instance.database;
    await _garantirTabelaConciliacoes(database);

    final inicio = DateTime(mes.year, mes.month, 1);
    final fimExclusivo = DateTime(mes.year, mes.month + 1, 1);

    final resultado = await database.rawQuery(
      '''
      SELECT
        c.*,
        m.descricao AS ajuste_descricao
      FROM financeiro_conciliacoes_conta c
      LEFT JOIN movimentos_financeiros m
        ON m.id = c.movimento_ajuste_id
      WHERE c.conta_id = ?
        AND date(c.data_conciliacao) >= date(?)
        AND date(c.data_conciliacao) < date(?)
      ORDER BY date(c.data_conciliacao) DESC, c.id DESC
      ''',
      [contaId, inicio.toIso8601String(), fimExclusivo.toIso8601String()],
    );

    return resultado.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  // conciliacao-remocao-segura-v1
  Future<void> removerConciliacaoConta({
    required int conciliacaoId,
    required int contaId,
  }) async {
    final database = await AppDatabase.instance.database;

    await database.transaction<void>((transaction) async {
      await _garantirTabelaConciliacoes(transaction);

      final conciliacoes = await transaction.query(
        'financeiro_conciliacoes_conta',
        columns: ['id', 'conta_id', 'status', 'movimento_ajuste_id'],
        where: 'id = ? AND conta_id = ?',
        whereArgs: [conciliacaoId, contaId],
        limit: 1,
      );

      if (conciliacoes.isEmpty) {
        throw StateError('Conciliação bancária não encontrada.');
      }

      final movimentoAjusteId = _int(conciliacoes.first['movimento_ajuste_id']);

      if (movimentoAjusteId != null) {
        final movimentos = await transaction.query(
          'movimentos_financeiros',
          columns: ['id', 'conta_id', 'origem', 'descricao'],
          where: 'id = ?',
          whereArgs: [movimentoAjusteId],
          limit: 1,
        );

        if (movimentos.isNotEmpty) {
          final movimento = movimentos.first;
          final movimentoContaId = _int(movimento['conta_id']);
          final origem = (movimento['origem'] ?? '').toString().trim();

          if (movimentoContaId != contaId || origem != 'Conciliação de conta') {
            throw StateError(
              'O ajuste vinculado não foi removido por segurança, pois '
              'não corresponde à conciliação desta conta.',
            );
          }

          final removidosMovimento = await transaction.delete(
            'movimentos_financeiros',
            where: 'id = ? AND conta_id = ?',
            whereArgs: [movimentoAjusteId, contaId],
          );

          if (removidosMovimento != 1) {
            throw StateError(
              'Não foi possível remover o ajuste financeiro da conciliação.',
            );
          }
        }
      }

      final removidosConciliacao = await transaction.delete(
        'financeiro_conciliacoes_conta',
        where: 'id = ? AND conta_id = ?',
        whereArgs: [conciliacaoId, contaId],
      );

      if (removidosConciliacao != 1) {
        throw StateError('Não foi possível remover a conciliação bancária.');
      }
    });
  }

  Future<int> registrarConciliacaoConta({
    required int contaId,
    required DateTime data,
    required double saldoInformado,
    required bool criarAjuste,
    String observacoes = '',
  }) async {
    final database = await AppDatabase.instance.database;

    return database.transaction<int>((transaction) async {
      await _garantirTabelaConciliacoes(transaction);

      final conta = await transaction.query(
        'financeiro_contas',
        columns: ['id', 'nome', 'ativo'],
        where: 'id = ?',
        whereArgs: [contaId],
        limit: 1,
      );

      if (conta.isEmpty) {
        throw StateError('Conta financeira não encontrada.');
      }

      final saldoCalculado = await _saldoCalculadoAte(
        transaction,
        contaId: contaId,
        data: data,
      );

      var diferenca = saldoInformado - saldoCalculado;
      if (diferenca.abs() < 0.005) diferenca = 0;

      int? movimentoAjusteId;
      var status = diferenca == 0 ? 'Conciliado' : 'Divergente';

      if (criarAjuste && diferenca != 0) {
        if (_int(conta.first['ativo']) != 1) {
          throw StateError(
            'Não é possível criar ajuste em uma conta financeira inativa.',
          );
        }

        final plano = await transaction.query(
          'financeiro_plano_contas',
          columns: ['id', 'natureza'],
          where: 'codigo = ?',
          whereArgs: ['9.05'],
          limit: 1,
        );

        if (plano.isEmpty) {
          throw StateError(
            'A categoria Correção de caixa (9.05) não foi encontrada.',
          );
        }

        final nomeConta = (conta.first['nome'] ?? 'Conta').toString().trim();
        final tipo = diferenca > 0 ? 'Entrada' : 'Saída';
        final valor = diferenca.abs();
        final dataIso = data.toIso8601String();

        movimentoAjusteId = await transaction.insert('movimentos_financeiros', {
          'tipo': tipo,
          'descricao': 'Ajuste de conciliação - $nomeConta',
          'valor': valor,
          'forma_pagamento': 'Ajuste',
          'data': dataIso,
          'cliente_id': null,
          'agendamento_id': null,
          'ordem_servico_id': null,
          'pagamento_id': null,
          'plano_conta_id': _int(plano.first['id']),
          'conta_id': contaId,
          'fornecedor_id': null,
          'transferencia_id': null,
          'natureza': (plano.first['natureza'] ?? 'Ajuste de caixa').toString(),
          'origem': 'Conciliação de conta',
          'status': 'Realizado',
          'data_competencia': dataIso,
          'data_vencimento': null,
          'data_pagamento': dataIso,
          'numero_documento': '',
          'observacoes': observacoes.trim().isEmpty
              ? 'Ajuste criado pela conciliação da conta.'
              : observacoes.trim(),
          'impacta_dre': 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        status = 'Ajustado';
      }

      return transaction.insert(
        'financeiro_conciliacoes_conta',
        {
          'conta_id': contaId,
          'data_conciliacao': data.toIso8601String(),
          'saldo_calculado': saldoCalculado,
          'saldo_informado': saldoInformado,
          'diferenca': diferenca,
          'status': status,
          'movimento_ajuste_id': movimentoAjusteId,
          'observacoes': observacoes.trim(),
          'criado_em': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
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
}
