import '../database/app_database.dart';
import '../models/agendamento.dart';

class AgendamentoRepository {
  final AppDatabase _appDatabase =
      AppDatabase.instance;

  Future<int> inserirAgendamento(
    Agendamento agendamento,
  ) async {
    final database =
        await _appDatabase.database;

    final dados = agendamento.toMap();
    dados.remove('id');

    return database.insert(
      'agendamentos',
      dados,
    );
  }

  Future<List<Agendamento>>
      listarAgendamentos() async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      orderBy: 'data ASC, hora ASC',
    );

    return resultado
        .map(
          (mapa) =>
              Agendamento.fromMap(mapa),
        )
        .toList();
  }

  Future<Agendamento?>
      buscarAgendamentoPorId(
    int id,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Agendamento.fromMap(
      resultado.first,
    );
  }

  Future<List<Agendamento>>
      listarAgendamentosPorData(
    String data,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'data = ?',
      whereArgs: [data],
      orderBy: 'hora ASC',
    );

    return resultado
        .map(
          (mapa) =>
              Agendamento.fromMap(mapa),
        )
        .toList();
  }

  Future<List<Agendamento>>
      listarAgendamentosDoCliente(
    int clienteId,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado
        .map(
          (mapa) =>
              Agendamento.fromMap(mapa),
        )
        .toList();
  }

  Future<List<Agendamento>>
      listarAgendamentosDoVeiculo(
    int veiculoId,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado
        .map(
          (mapa) =>
              Agendamento.fromMap(mapa),
        )
        .toList();
  }

  Future<int> atualizarAgendamento(
    Agendamento agendamento,
  ) async {
    if (agendamento.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um '
        'agendamento sem ID.',
      );
    }

    final database =
        await _appDatabase.database;

    final dados = agendamento.toMap();
    dados.remove('id');

    return database.update(
      'agendamentos',
      dados,
      where: 'id = ?',
      whereArgs: [agendamento.id],
    );
  }

  Future<int> atualizarStatus(
    int id,
    String status,
  ) async {
    final database =
        await _appDatabase.database;

    return database.update(
      'agendamentos',
      {
        'status': status,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirAgendamento(
    int id,
  ) async {
    final database =
        await _appDatabase.database;

    return database.delete(
      'agendamentos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
