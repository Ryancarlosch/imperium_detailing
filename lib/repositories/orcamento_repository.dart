import '../database/app_database.dart';
import '../models/orcamento.dart';

class OrcamentoRepository {
  final AppDatabase _appDatabase =
      AppDatabase.instance;

  Future<int> inserirOrcamento(
    Orcamento orcamento,
  ) async {
    final database =
        await _appDatabase.database;
    final dados = orcamento.toMap();
    dados.remove('id');

    return database.insert(
      'orcamentos',
      dados,
    );
  }

  Future<List<Map<String, dynamic>>>
      listarOrcamentosComDetalhes() async {
    final database =
        await _appDatabase.database;

    return database.rawQuery('''
      SELECT
        o.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa
      FROM orcamentos o
      INNER JOIN clientes c
        ON c.id = o.cliente_id
      LEFT JOIN veiculos v
        ON v.id = o.veiculo_id
      ORDER BY o.data_emissao DESC, o.id DESC
    ''');
  }

  Future<Map<String, dynamic>?>
      buscarOrcamentoComDetalhes(
    int id,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        o.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        c.email AS cliente_email,
        c.endereco AS cliente_endereco,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
        v.cor AS veiculo_cor,
        v.ano AS veiculo_ano
      FROM orcamentos o
      INNER JOIN clientes c
        ON c.id = o.cliente_id
      LEFT JOIN veiculos v
        ON v.id = o.veiculo_id
      WHERE o.id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (resultado.isEmpty) {
      return null;
    }

    return resultado.first;
  }

  Future<Orcamento?> buscarPorId(int id) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'orcamentos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Orcamento.fromMap(resultado.first);
  }

  Future<int> atualizarOrcamento(
    Orcamento orcamento,
  ) async {
    if (orcamento.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um orçamento sem ID.',
      );
    }

    final database =
        await _appDatabase.database;
    final dados = orcamento.toMap();
    dados.remove('id');

    return database.update(
      'orcamentos',
      dados,
      where: 'id = ?',
      whereArgs: [orcamento.id],
    );
  }

  Future<int> atualizarStatus(
    int id,
    String status,
  ) async {
    final database =
        await _appDatabase.database;

    return database.update(
      'orcamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirOrcamento(int id) async {
    final database =
        await _appDatabase.database;

    return database.delete(
      'orcamentos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
