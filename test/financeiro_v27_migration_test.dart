import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_financeiro_v27_migration_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDown(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  test('migra v26 para v27 preservando regras e ajustes existentes', () async {
    final legado = await databaseFactory.openDatabase(
      caminhoBanco,
      options: OpenDatabaseOptions(
        version: 26,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE financeiro_contas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nome TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ordens_servico (
              id INTEGER PRIMARY KEY AUTOINCREMENT
            )
          ''');
          await database.execute('''
            CREATE TABLE financeiro_regras_taxa (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nome TEXT NOT NULL,
              forma_pagamento TEXT NOT NULL,
              parcelas INTEGER NOT NULL DEFAULT 1,
              conta_id INTEGER,
              taxa_percentual REAL NOT NULL DEFAULT 0,
              taxa_fixa REAL NOT NULL DEFAULT 0,
              prazo_recebimento_dias INTEGER NOT NULL DEFAULT 0,
              prioridade INTEGER NOT NULL DEFAULT 0,
              observacoes TEXT NOT NULL DEFAULT '',
              ativo INTEGER NOT NULL DEFAULT 1,
              criado_em TEXT NOT NULL,
              atualizado_em TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ordem_servico_pagamentos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ordem_servico_id INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ordem_servico_ajustes_financeiros (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ordem_servico_id INTEGER NOT NULL,
              tipo TEXT NOT NULL,
              valor REAL NOT NULL,
              motivo TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'Ativo',
              criado_em TEXT NOT NULL,
              cancelado_em TEXT,
              motivo_cancelamento TEXT NOT NULL DEFAULT ''
            )
          ''');

          await database.insert('financeiro_regras_taxa', {
            'id': 10,
            'nome': 'Crédito 2x legado',
            'forma_pagamento': 'Cartão de crédito',
            'parcelas': 2,
            'taxa_percentual': 3.5,
            'taxa_fixa': 0,
            'prazo_recebimento_dias': 30,
            'prioridade': 0,
            'observacoes': '',
            'ativo': 1,
            'criado_em': '2026-08-01',
            'atualizado_em': '2026-08-01',
          });
          await database.insert('ordens_servico', {'id': 20});
          await database.insert('ordem_servico_ajustes_financeiros', {
            'id': 30,
            'ordem_servico_id': 20,
            'tipo': 'Acréscimo',
            'valor': 10,
            'motivo': 'Ajuste legado',
            'status': 'Ativo',
            'criado_em': '2026-08-01',
            'motivo_cancelamento': '',
          });
        },
      ),
    );
    await legado.close();

    final database = await AppDatabase.instance.database;
    expect(await database.getVersion(), 29);

    final regra = (await database.query(
      'financeiro_regras_taxa',
      where: 'id = ?',
      whereArgs: [10],
    )).single;
    expect(regra['nome'], 'Crédito 2x legado');
    expect(regra['repassar_cliente'], 0);

    final ajuste = (await database.query(
      'ordem_servico_ajustes_financeiros',
      where: 'id = ?',
      whereArgs: [30],
    )).single;
    expect(ajuste['motivo'], 'Ajuste legado');
    expect(ajuste['origem'], 'Manual');
    expect(ajuste['regra_taxa_id'], isNull);
    expect(ajuste['pagamento_id'], isNull);

    final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
    expect(violacoes, isEmpty);
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
