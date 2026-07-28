import '../database/app_database.dart';
import '../models/cliente.dart';

class ClienteRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<int> inserirCliente(Cliente cliente) async {
    final database = await _appDatabase.database;

    final dados = cliente.toMap();
    dados.remove('id');

    return database.insert(
      'clientes',
      dados,
    );
  }

  Future<List<Cliente>> listarClientes() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'clientes',
      orderBy: 'nome ASC',
    );

    return resultado
        .map((mapa) => Cliente.fromMap(mapa))
        .toList();
  }

  Future<int> atualizarCliente(Cliente cliente) async {
    if (cliente.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um cliente sem ID.',
      );
    }

    final database = await _appDatabase.database;

    final dados = cliente.toMap();
    dados.remove('id');

    return database.update(
      'clientes',
      dados,
      where: 'id = ?',
      whereArgs: [cliente.id],
    );
  }

  Future<int> excluirCliente(int id) async {
    final database = await _appDatabase.database;

    return database.delete(
      'clientes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}