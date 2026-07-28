import '../database/app_database.dart';
import '../models/veiculo.dart';

class VeiculoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<int> inserirVeiculo(Veiculo veiculo) async {
    final database = await _appDatabase.database;

    final dados = veiculo.toMap();
    dados.remove('id');

    return database.insert(
      'veiculos',
      dados,
    );
  }

  Future<List<Veiculo>> listarVeiculos() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'veiculos',
      orderBy: 'marca ASC, modelo ASC',
    );

    return resultado
        .map((mapa) => Veiculo.fromMap(mapa))
        .toList();
  }

  Future<List<Map<String, dynamic>>>
      listarVeiculosComCliente() async {
    final database = await _appDatabase.database;

    return database.rawQuery(
      '''
      SELECT
        v.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone
      FROM veiculos v
      INNER JOIN clientes c
        ON c.id = v.cliente_id
      ORDER BY v.marca ASC, v.modelo ASC
      ''',
    );
  }

  Future<Veiculo?> buscarVeiculoPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'veiculos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Veiculo.fromMap(resultado.first);
  }

  Future<Map<String, dynamic>?>
      buscarVeiculoComClientePorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        v.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        c.email AS cliente_email
      FROM veiculos v
      INNER JOIN clientes c
        ON c.id = v.cliente_id
      WHERE v.id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (resultado.isEmpty) {
      return null;
    }

    return resultado.first;
  }

  Future<List<Veiculo>> listarVeiculosDoCliente(
    int clienteId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'veiculos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'marca ASC, modelo ASC',
    );

    return resultado
        .map((mapa) => Veiculo.fromMap(mapa))
        .toList();
  }

  Future<int> atualizarVeiculo(Veiculo veiculo) async {
    if (veiculo.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um veículo sem ID.',
      );
    }

    final database = await _appDatabase.database;

    final dados = veiculo.toMap();
    dados.remove('id');

    return database.update(
      'veiculos',
      dados,
      where: 'id = ?',
      whereArgs: [veiculo.id],
    );
  }

  Future<int> excluirVeiculo(int id) async {
    final database = await _appDatabase.database;

    return database.delete(
      'veiculos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
