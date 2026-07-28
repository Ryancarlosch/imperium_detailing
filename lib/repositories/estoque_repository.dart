import '../database/app_database.dart';
import '../models/item_estoque.dart';

class EstoqueRepository {
  final AppDatabase _appDatabase =
      AppDatabase.instance;

  Future<int> inserirItem(
    ItemEstoque item,
  ) async {
    final database =
        await _appDatabase.database;

    final dados = item.toMap();
    dados.remove('id');

    return database.insert(
      'itens_estoque',
      dados,
    );
  }

  Future<List<ItemEstoque>> listarItens() async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'itens_estoque',
      orderBy: 'nome ASC',
    );

    return resultado
        .map(ItemEstoque.fromMap)
        .toList();
  }

  Future<ItemEstoque?> buscarItemPorId(
    int id,
  ) async {
    final database =
        await _appDatabase.database;

    final resultado = await database.query(
      'itens_estoque',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ItemEstoque.fromMap(
      resultado.first,
    );
  }

  Future<int> atualizarItem(
    ItemEstoque item,
  ) async {
    if (item.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um item sem ID.',
      );
    }

    final database =
        await _appDatabase.database;

    final dados = item.toMap();
    dados.remove('id');

    return database.update(
      'itens_estoque',
      dados,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> atualizarQuantidade(
    int id,
    double quantidade,
  ) async {
    final database =
        await _appDatabase.database;

    return database.update(
      'itens_estoque',
      {
        'quantidade': quantidade,
        'atualizado_em':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirItem(int id) async {
    final database =
        await _appDatabase.database;

    return database.delete(
      'itens_estoque',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
