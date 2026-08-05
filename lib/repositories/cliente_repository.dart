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
    return listarClientesAtivos();
  }

  Future<List<Cliente>> listarClientesAtivos() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'clientes',
      where: 'COALESCE(ativo, 1) = ?',
      whereArgs: [1],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado
        .map((mapa) => Cliente.fromMap(mapa))
        .toList();
  }

  Future<List<Cliente>> listarClientesArquivados() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'clientes',
      where: 'COALESCE(ativo, 1) = ?',
      whereArgs: [0],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado
        .map((mapa) => Cliente.fromMap(mapa))
        .toList();
  }

  Future<List<Cliente>> listarTodosClientes() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'clientes',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC',
    );

    return resultado
        .map((mapa) => Cliente.fromMap(mapa))
        .toList();
  }

  Future<Cliente?> buscarClientePorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'clientes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Cliente.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<int> contarVeiculosDoCliente(
      int clienteId,
      ) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM veiculos
      WHERE cliente_id = ?
      ''',
      [clienteId],
    );

    final valor = resultado.first['total'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(
      valor?.toString() ?? '',
    ) ??
        0;
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

  Future<int> arquivarCliente(int id) async {
    final database = await _appDatabase.database;

    return database.update(
      'clientes',
      {
        'ativo': 0,
        'arquivado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND COALESCE(ativo, 1) = ?',
      whereArgs: [id, 1],
    );
  }

  Future<int> reativarCliente(int id) async {
    final database = await _appDatabase.database;

    return database.update(
      'clientes',
      {
        'ativo': 1,
        'arquivado_em': null,
      },
      where: 'id = ? AND COALESCE(ativo, 1) = ?',
      whereArgs: [id, 0],
    );
  }

  Future<int> excluirCliente(int id) async {
    return arquivarCliente(id);
  }
}
