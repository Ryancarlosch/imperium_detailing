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
      'imperium_financeiro_v24_migration_test_',
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
    'migra da versão 23 para o schema atual preservando movimentos',
    () async {
      final legado = await databaseFactory.openDatabase(
        caminhoBanco,
        options: OpenDatabaseOptions(
          version: 23,
          onCreate: (database, _) async {
            await database.execute('''
            CREATE TABLE movimentos_financeiros (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              tipo TEXT NOT NULL,
              descricao TEXT NOT NULL,
              valor REAL NOT NULL DEFAULT 0,
              forma_pagamento TEXT,
              data TEXT NOT NULL,
              cliente_id INTEGER,
              agendamento_id INTEGER,
              ordem_servico_id INTEGER,
              pagamento_id INTEGER
            )
          ''');

            await database.insert('movimentos_financeiros', {
              'id': 1,
              'tipo': 'entrada',
              'descricao': 'Pagamento da OS OS-TESTE-23',
              'valor': 800,
              'forma_pagamento': 'Pix',
              'data': '2026-08-01T10:00:00.000',
              'ordem_servico_id': 10,
              'pagamento_id': 20,
            });

            await database.insert('movimentos_financeiros', {
              'id': 2,
              'tipo': 'saída',
              'descricao': 'Taxa da maquininha - OS OS-TESTE-23',
              'valor': 32,
              'forma_pagamento': 'Cartão de crédito',
              'data': '2026-08-01T10:00:00.000',
              'ordem_servico_id': 10,
              'pagamento_id': 20,
            });
          },
        ),
      );
      await legado.close();

      final database = await AppDatabase.instance.database;
      expect(await database.getVersion(), AppDatabase.schemaVersion);

      final colunas = await database.rawQuery(
        'PRAGMA table_info(movimentos_financeiros)',
      );
      final nomes = colunas
          .map((item) => item['name']?.toString())
          .whereType<String>()
          .toSet();
      expect(nomes, contains('plano_conta_id'));
      expect(nomes, contains('status'));
      expect(nomes, contains('data_competencia'));
      expect(nomes, contains('data_pagamento'));
      expect(nomes, contains('impacta_dre'));

      final movimentos = await database.query(
        'movimentos_financeiros',
        orderBy: 'id ASC',
      );
      expect(movimentos, hasLength(2));

      expect((movimentos[0]['valor'] as num).toDouble(), 800.0);
      expect(movimentos[0]['status'], 'Realizado');
      expect(movimentos[0]['origem'], 'Pagamento de OS');
      expect(movimentos[0]['data_competencia'], '2026-08-01T10:00:00.000');
      expect(movimentos[0]['data_pagamento'], '2026-08-01T10:00:00.000');

      expect((movimentos[1]['valor'] as num).toDouble(), 32.0);
      expect(movimentos[1]['origem'], 'Taxa de pagamento');
      expect(movimentos[1]['natureza'], 'Custo variável');

      final plano = await database.query('financeiro_plano_contas');
      expect(plano, isNotEmpty);
      final contas = await database.query('financeiro_contas');
      expect(contas, isNotEmpty);
      final fornecedores = await database.query('fornecedores');
      expect(fornecedores, isEmpty);
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
