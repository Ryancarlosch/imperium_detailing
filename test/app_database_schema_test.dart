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
      'imperium_database_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('AppDatabase - criação do banco versão 21', () {
    test('cria o banco com a versão atual e integridade válida', () async {
      final database = await AppDatabase.instance.database;

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(AppDatabase.schemaVersion, 21);

      final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.single.values.single, 1);

      final integridade = await database.rawQuery('PRAGMA integrity_check');
      expect(integridade.single.values.single, 'ok');

      final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
      expect(violacoes, isEmpty);
    });

    test('cria todas as tabelas essenciais', () async {
      final database = await AppDatabase.instance.database;

      final resultado = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
      ''');

      final tabelasCriadas = resultado
          .map((item) => item['name']?.toString())
          .whereType<String>()
          .toSet();

      const tabelasEsperadas = <String>{
        'clientes',
        'veiculos',
        'agendamentos',
        'fotos_servico',
        'movimentos_financeiros',
        'orcamentos',
        'orcamento_itens',
        'ordens_servico',
        'ordem_servico_revisoes',
        'ordem_servico_itens',
        'ordem_servico_checklist',
        'ordem_servico_fotos',
        'ordem_servico_produtos',
        'configuracoes',
        'itens_estoque',
        'estoque_lotes',
        'movimentacoes_estoque',
        'configuracoes_estoque',
        'servicos_catalogo',
        'servico_produtos',
        'servicos_relacionados',
        'servico_categorias',
        'ordem_servico_produto_lotes',
      };

      expect(tabelasCriadas, containsAll(tabelasEsperadas));
    });

    test('cria o arquivamento de clientes com valores padrão', () async {
      final database = await AppDatabase.instance.database;
      final colunas = await _obterColunas(database, 'clientes');

      expect(
        colunas,
        containsAll(<String>{
          'id',
          'nome',
          'telefone',
          'email',
          'endereco',
          'observacoes',
          'ativo',
          'arquivado_em',
        }),
      );

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente de teste',
      });

      final cliente = await database.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
        limit: 1,
      );

      expect(cliente, hasLength(1));
      expect(cliente.single['ativo'], 1);
      expect(cliente.single['arquivado_em'], isNull);

      final indices = await _obterIndices(database, 'clientes');
      expect(indices, contains('idx_clientes_ativo_nome'));
    });

    test('cria metadados e tabela de revisões da OS', () async {
      final database = await AppDatabase.instance.database;

      final colunasOrdem = await _obterColunas(database, 'ordens_servico');

      expect(
        colunasOrdem,
        containsAll(<String>{
          'revisada_em',
          'motivo_ultima_revisao',
          'quantidade_revisoes',
          'assinatura_desatualizada',
        }),
      );

      final colunasRevisao = await _obterColunas(
        database,
        'ordem_servico_revisoes',
      );

      expect(
        colunasRevisao,
        containsAll(<String>{
          'id',
          'ordem_servico_id',
          'numero_revisao',
          'tipo',
          'motivo',
          'dados_anteriores_json',
          'dados_novos_json',
          'criado_em',
        }),
      );

      final indices = await _obterIndices(database, 'ordem_servico_revisoes');

      expect(indices, contains('idx_os_revisoes_ordem_servico_id'));
      expect(indices, contains('idx_os_revisoes_criado_em'));
    });

    test('cria as configurações padrão do aplicativo e do estoque', () async {
      final database = await AppDatabase.instance.database;

      final configuracoes = await database.query(
        'configuracoes',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );

      expect(configuracoes, hasLength(1));
      expect(configuracoes.single['nome_aplicativo'], 'Imperium Detailing');
      expect(configuracoes.single['tema'], 'escuro');

      final configuracoesEstoque = await database.query(
        'configuracoes_estoque',
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );

      expect(configuracoesEstoque, hasLength(1));
      expect(configuracoesEstoque.single['controlar_estoque'], 1);
      expect(configuracoesEstoque.single['baixa_automatica'], 1);
    });
  });
}

Future<Set<String>> _obterColunas(Database database, String tabela) async {
  final resultado = await database.rawQuery('PRAGMA table_info($tabela)');

  return resultado
      .map((item) => item['name']?.toString())
      .whereType<String>()
      .toSet();
}

Future<Set<String>> _obterIndices(Database database, String tabela) async {
  final resultado = await database.rawQuery('PRAGMA index_list($tabela)');

  return resultado
      .map((item) => item['name']?.toString())
      .whereType<String>()
      .toSet();
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
