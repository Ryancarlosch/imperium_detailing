import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/meta_financeira.dart';

class MetaFinanceiraRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<List<MetaFinanceira>> listarMes(int ano, int mes) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_metas',
      where: 'ano = ? AND mes = ? AND ativo = 1',
      whereArgs: [ano, mes],
      orderBy: 'tipo ASC, id ASC',
    );
    return resultado
        .map((item) => MetaFinanceira.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, double>> obterResumoMes(int ano, int mes) async {
    final metas = await listarMes(ano, mes);
    final resumo = <String, double>{'Receita': 0, 'Despesa': 0, 'Resultado': 0};
    for (final meta in metas.where((item) => item.planoContaId == null)) {
      resumo[meta.tipo] = meta.valorMeta;
    }
    return resumo;
  }

  Future<int> salvarMetaGeral({
    required int ano,
    required int mes,
    required String tipo,
    required double valor,
    String observacoes = '',
  }) async {
    if (ano < 2000 || ano > 2200) {
      throw ArgumentError('Ano inválido.');
    }
    if (mes < 1 || mes > 12) {
      throw ArgumentError('Mês inválido.');
    }
    if (!const {'Receita', 'Despesa', 'Resultado'}.contains(tipo)) {
      throw ArgumentError('Tipo de meta inválido.');
    }
    if (valor < 0) {
      throw ArgumentError('O valor da meta não pode ser negativo.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    final existente = await database.query(
      'financeiro_metas',
      columns: ['id'],
      where:
          'ano = ? AND mes = ? AND tipo = ? AND plano_conta_id IS NULL AND ativo = 1',
      whereArgs: [ano, mes, tipo],
      orderBy: 'id DESC',
      limit: 1,
    );

    final mapa = <String, Object?>{
      'ano': ano,
      'mes': mes,
      'tipo': tipo,
      'plano_conta_id': null,
      'valor_meta': valor,
      'observacoes': observacoes.trim(),
      'ativo': 1,
      'atualizado_em': agora,
    };

    if (existente.isEmpty) {
      mapa['criado_em'] = agora;
      return database.insert(
        'financeiro_metas',
        mapa,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    final id = (existente.first['id'] as num).toInt();
    await database.update(
      'financeiro_metas',
      mapa,
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }
}
