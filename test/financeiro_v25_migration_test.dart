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
      'imperium_financeiro_v25_migration_',
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

  test(
    'migra da versão 24 para o schema atual preservando dados e custos',
    () async {
      final legado = await databaseFactory.openDatabase(
        caminhoBanco,
        options: OpenDatabaseOptions(
          version: 24,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (database, _) async {
            await database.execute('''
            CREATE TABLE clientes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nome TEXT NOT NULL
            )
          ''');

            await database.execute('''
            CREATE TABLE ordens_servico (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              cliente_id INTEGER NOT NULL,
              numero TEXT NOT NULL,
              status TEXT NOT NULL,
              data_abertura TEXT NOT NULL,
              FOREIGN KEY (cliente_id) REFERENCES clientes (id)
            )
          ''');

            await database.execute('''
            CREATE TABLE financeiro_plano_contas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              codigo TEXT NOT NULL UNIQUE,
              nome TEXT NOT NULL,
              tipo TEXT NOT NULL,
              natureza TEXT NOT NULL,
              grupo_dre TEXT NOT NULL DEFAULT 'Não DRE',
              parent_id INTEGER,
              ativo INTEGER NOT NULL DEFAULT 1,
              ordem INTEGER NOT NULL DEFAULT 0,
              criado_em TEXT NOT NULL,
              atualizado_em TEXT NOT NULL
            )
          ''');

            await database.insert('clientes', {
              'id': 1,
              'nome': 'Cliente preservado',
            });
            await database.insert('ordens_servico', {
              'id': 10,
              'cliente_id': 1,
              'numero': 'OS-V24-001',
              'status': 'Finalizada',
              'data_abertura': '2026-08-01',
            });
            await database.insert('financeiro_plano_contas', {
              'id': 20,
              'codigo': '2.04.01',
              'nome': 'Aluguel',
              'tipo': 'Saída',
              'natureza': 'Despesa fixa',
              'grupo_dre': 'Despesas Operacionais',
              'ativo': 1,
              'ordem': 1,
              'criado_em': '2026-08-01',
              'atualizado_em': '2026-08-01',
            });
          },
        ),
      );
      await legado.close();

      final database = await AppDatabase.instance.database;

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(AppDatabase.schemaVersion, 28);

      final cliente = await database.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [1],
      );
      expect(cliente, hasLength(1));
      expect(cliente.single['nome'], 'Cliente preservado');

      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [10],
      );
      expect(ordem, hasLength(1));
      expect(ordem.single['numero'], 'OS-V24-001');

      final tabelas = await database.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'table'
    ''');
      final nomes = tabelas.map((e) => e['name']).toSet();
      expect(nomes, contains('financeiro_custos_fixos'));
      expect(nomes, contains('financeiro_colaboradores_custo'));
      expect(nomes, contains('financeiro_os_mao_obra'));

      final custoId = await database.insert('financeiro_custos_fixos', {
        'nome': 'Aluguel',
        'valor_mensal': 1500,
        'categoria': 'Despesa fixa',
        'plano_conta_id': 20,
        'observacoes': '',
        'ativo': 1,
        'criado_em': '2026-08-08',
        'atualizado_em': '2026-08-08',
      });
      expect(custoId, greaterThan(0));

      final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
      expect(violacoes, isEmpty);
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
