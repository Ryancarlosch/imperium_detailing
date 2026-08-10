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
}
