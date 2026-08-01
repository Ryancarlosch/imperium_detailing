import '../database/app_database.dart';
import '../models/movimento_financeiro.dart';

class FinanceiroRepository {
  Future<int> inserirMovimento(MovimentoFinanceiro movimento) async {
    final database = await AppDatabase.instance.database;

    return database.insert('movimentos_financeiros', movimento.toMap());
  }

  Future<List<MovimentoFinanceiro>> listarMovimentos() async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'movimentos_financeiros',
      orderBy: 'data DESC, id DESC',
    );

    return resultado.map((map) => MovimentoFinanceiro.fromMap(map)).toList();
  }

  Future<List<Map<String, dynamic>>> listarMovimentosComCliente() async {
    final database = await AppDatabase.instance.database;

    return database.rawQuery('''
      SELECT
        movimentos_financeiros.id,
        movimentos_financeiros.tipo,
        movimentos_financeiros.descricao,
        movimentos_financeiros.valor,
        movimentos_financeiros.forma_pagamento,
        movimentos_financeiros.data,
        movimentos_financeiros.cliente_id,
        movimentos_financeiros.agendamento_id,
        clientes.nome AS cliente_nome
      FROM movimentos_financeiros
      LEFT JOIN clientes
        ON clientes.id =
          movimentos_financeiros.cliente_id
      ORDER BY
        movimentos_financeiros.data DESC,
        movimentos_financeiros.id DESC
    ''');
  }

  Future<List<MovimentoFinanceiro>> listarMovimentosPorPeriodo({
    required String dataInicial,
    required String dataFinal,
  }) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'movimentos_financeiros',
      where: 'date(data) BETWEEN date(?) AND date(?)',
      whereArgs: [dataInicial, dataFinal],
      orderBy: 'data DESC, id DESC',
    );

    return resultado.map((map) => MovimentoFinanceiro.fromMap(map)).toList();
  }

  Future<MovimentoFinanceiro?> buscarMovimentoPorId(int id) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'movimentos_financeiros',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return MovimentoFinanceiro.fromMap(resultado.first);
  }

  Future<int> atualizarMovimento(MovimentoFinanceiro movimento) async {
    if (movimento.id == null) {
      throw Exception('Não foi possível atualizar o movimento sem ID.');
    }

    final database = await AppDatabase.instance.database;

    return database.update(
      'movimentos_financeiros',
      movimento.toMap(),
      where: 'id = ?',
      whereArgs: [movimento.id],
    );
  }

  Future<int> excluirMovimento(int id) async {
    final database = await AppDatabase.instance.database;

    return database.delete(
      'movimentos_financeiros',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> somarEntradas({String? dataInicial, String? dataFinal}) async {
    final database = await AppDatabase.instance.database;

    String consulta = '''
      SELECT
        COALESCE(SUM(valor), 0) AS total
      FROM movimentos_financeiros
      WHERE LOWER(tipo) = ?
    ''';

    final argumentos = <dynamic>['entrada'];

    if (dataInicial != null && dataFinal != null) {
      consulta += '''
        AND date(data) BETWEEN date(?) AND date(?)
      ''';

      argumentos.addAll([dataInicial, dataFinal]);
    }

    final resultado = await database.rawQuery(consulta, argumentos);

    if (resultado.isEmpty) {
      return 0;
    }

    final total = resultado.first['total'];
    if (total == null) {
      return 0;
    }

    return (total as num).toDouble();
  }

  Future<double> somarSaidas({String? dataInicial, String? dataFinal}) async {
    final database = await AppDatabase.instance.database;

    String consulta = '''
      SELECT
        COALESCE(SUM(valor), 0) AS total
      FROM movimentos_financeiros
      WHERE LOWER(tipo) IN (?, ?)
    ''';

    final argumentos = <dynamic>['saída', 'saida'];

    if (dataInicial != null && dataFinal != null) {
      consulta += '''
        AND date(data) BETWEEN date(?) AND date(?)
      ''';

      argumentos.addAll([dataInicial, dataFinal]);
    }

    final resultado = await database.rawQuery(consulta, argumentos);

    if (resultado.isEmpty) {
      return 0;
    }

    final total = resultado.first['total'];
    if (total == null) {
      return 0;
    }

    return (total as num).toDouble();
  }

  Future<double> calcularSaldo({String? dataInicial, String? dataFinal}) async {
    final entradas = await somarEntradas(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );

    final saidas = await somarSaidas(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );

    return entradas - saidas;
  }

  Future<Map<String, double>> obterResumoFinanceiro({
    String? dataInicial,
    String? dataFinal,
  }) async {
    final entradas = await somarEntradas(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );

    final saidas = await somarSaidas(
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );

    return {'entradas': entradas, 'saidas': saidas, 'saldo': entradas - saidas};
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
}
