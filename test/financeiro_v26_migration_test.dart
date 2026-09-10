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
      'imperium_financeiro_v26_migration_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await AppDatabase.instance.fecharBanco();
    if (await databaseFactory.databaseExists(caminhoBanco)) {
      await databaseFactory.deleteDatabase(caminhoBanco);
    }
  });

  tearDown(() async {
    await AppDatabase.instance.fecharBanco();
    if (await databaseFactory.databaseExists(caminhoBanco)) {
      await databaseFactory.deleteDatabase(caminhoBanco);
    }
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  test(
    'migra da v25 até a versão atual preservando o fechamento v26',
    () async {
      final legado = await databaseFactory.openDatabase(
        caminhoBanco,
        options: OpenDatabaseOptions(
          version: 25,
          onCreate: (database, _) async {
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
            await database.execute('''
            CREATE TABLE ordem_servico_pagamentos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              ordem_servico_id INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'Pago',
              valor REAL NOT NULL DEFAULT 0,
              forma_pagamento TEXT NOT NULL DEFAULT '',
              data_pagamento TEXT,
              parcela_numero INTEGER,
              total_parcelas INTEGER,
              vencimento TEXT,
              comprovante_caminho TEXT,
              observacoes TEXT NOT NULL DEFAULT '',
              taxa_percentual REAL,
              taxa_operacao REAL NOT NULL DEFAULT 0,
              valor_liquido REAL NOT NULL DEFAULT 0,
              estornado_em TEXT,
              motivo_estorno TEXT NOT NULL DEFAULT '',
              criado_em TEXT NOT NULL,
              atualizado_em TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE movimentos_financeiros (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              plano_conta_id INTEGER,
              impacta_dre INTEGER NOT NULL DEFAULT 1
            )
          ''');
            await database.execute('''
            CREATE TABLE financeiro_contas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nome TEXT NOT NULL UNIQUE,
              tipo TEXT NOT NULL DEFAULT 'Conta bancária',
              instituicao TEXT NOT NULL DEFAULT '',
              saldo_inicial REAL NOT NULL DEFAULT 0,
              data_saldo_inicial TEXT,
              observacoes TEXT NOT NULL DEFAULT '',
              ativo INTEGER NOT NULL DEFAULT 1,
              criado_em TEXT NOT NULL,
              atualizado_em TEXT NOT NULL
            )
          ''');

            final agora = DateTime.now().toIso8601String();
            await database.insert('financeiro_plano_contas', {
              'id': 1,
              'codigo': '2.03.01',
              'nome': 'Produtos',
              'tipo': 'Saída',
              'natureza': 'Custo variável',
              'grupo_dre': 'Custos Variáveis',
              'parent_id': null,
              'ativo': 1,
              'ordem': 231,
              'criado_em': agora,
              'atualizado_em': agora,
            });
            await database.insert('ordem_servico_pagamentos', {
              'id': 10,
              'ordem_servico_id': 99,
              'status': 'Pago',
              'valor': 500,
              'forma_pagamento': 'Cartão de crédito',
              'taxa_operacao': 20,
              'valor_liquido': 480,
              'criado_em': agora,
              'atualizado_em': agora,
            });
            await database.insert('movimentos_financeiros', {
              'id': 20,
              'plano_conta_id': 1,
              'impacta_dre': 1,
            });
          },
        ),
      );
      await legado.close();

      final database = await AppDatabase.instance.database;
      expect(await database.getVersion(), AppDatabase.schemaVersion);

      final tabelas = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final nomes = tabelas.map((item) => item['name']).toSet();
      expect(nomes, contains('financeiro_regras_taxa'));
      expect(nomes, contains('financeiro_metas'));

      final colunas = await database.rawQuery(
        'PRAGMA table_info(ordem_servico_pagamentos)',
      );
      final nomesColunas = colunas.map((item) => item['name']).toSet();
      expect(nomesColunas, contains('regra_taxa_id'));
      expect(nomesColunas, contains('parcelas_taxa'));

      final pagamento = await database.query(
        'ordem_servico_pagamentos',
        where: 'id = ?',
        whereArgs: [10],
      );
      expect(pagamento, hasLength(1));
      expect((pagamento.single['valor'] as num).toDouble(), 500);
      expect((pagamento.single['parcelas_taxa'] as num).toInt(), 1);

      final produto = await database.query(
        'financeiro_plano_contas',
        where: 'codigo = ?',
        whereArgs: ['2.03.01'],
      );
      expect(produto.single['nome'], 'Produtos consumidos em serviços');

      final novosCodigos = await database.query(
        'financeiro_plano_contas',
        columns: ['codigo'],
        where: 'codigo IN (?, ?, ?, ?)',
        whereArgs: ['1.02.02', '1.02.03', '2.04.12', '9.06'],
      );
      expect(novosCodigos, hasLength(4));

      final colunasMovimentos = await database.rawQuery(
        'PRAGMA table_info(movimentos_financeiros)',
      );
      final nomesColunasMovimentos = colunasMovimentos
          .map((item) => item['name'])
          .toSet();
      expect(nomesColunasMovimentos, contains('origem'));
      expect(nomesColunasMovimentos, contains('status'));
      expect(nomesColunasMovimentos, contains('nota_fiscal_id'));
      expect(nomesColunasMovimentos, contains('parcela_numero'));
      expect(nomesColunasMovimentos, contains('total_parcelas'));

      final indicesMovimentos = await database.rawQuery(
        'PRAGMA index_list(movimentos_financeiros)',
      );
      final nomesIndicesMovimentos = indicesMovimentos
          .map((item) => item['name'])
          .toSet();
      expect(
        nomesIndicesMovimentos,
        contains('idx_movimentos_nota_fiscal_parcela_ativa'),
      );
    },
  );
}
