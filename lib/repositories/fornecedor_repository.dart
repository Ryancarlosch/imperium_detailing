import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/fornecedor.dart';

class FornecedorRepository {
  Future<List<Fornecedor>> listar({bool incluirInativos = false}) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'fornecedores',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC',
    );

    return resultado
        .map((item) => Fornecedor.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> inserir(Fornecedor fornecedor) async {
    final nome = fornecedor.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do fornecedor.');
    }

    final database = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final dados = fornecedor
        .copyWith(nome: nome, ativo: true, criadoEm: agora, atualizadoEm: agora)
        .toMap(incluirId: false);

    return database.insert(
      'fornecedores',
      dados,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> atualizar(Fornecedor fornecedor) async {
    if (fornecedor.id == null) {
      throw ArgumentError('Fornecedor sem ID.');
    }

    final database = await AppDatabase.instance.database;
    final dados = fornecedor
        .copyWith(atualizadoEm: DateTime.now().toIso8601String())
        .toMap(incluirId: false);
    dados.remove('criado_em');

    await database.update(
      'fornecedores',
      dados,
      where: 'id = ?',
      whereArgs: [fornecedor.id],
    );
  }

  Future<void> alterarAtivo(int id, bool ativo) async {
    final database = await AppDatabase.instance.database;
    await database.update(
      'fornecedores',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
