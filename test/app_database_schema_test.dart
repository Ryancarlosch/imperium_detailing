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
      'imperium_database_schema_v27_test_',
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

  group('AppDatabase - criação do banco versão 27', () {
    test('cria banco atual com integridade e foreign keys válidas', () async {
      final database = await AppDatabase.instance.database;

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(AppDatabase.schemaVersion, 27);

      final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.single.values.single, 1);

      final integridade = await database.rawQuery('PRAGMA integrity_check');
      expect(integridade.single.values.single, 'ok');

      final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
      expect(violacoes, isEmpty);
    });

    test('cria tabelas essenciais incluindo automação de cartão v27', () async {
      final database = await AppDatabase.instance.database;
      final resultado = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
      ''');

      final tabelas = resultado
          .map((item) => item['name']?.toString())
          .whereType<String>()
          .toSet();

      expect(
        tabelas,
        containsAll(<String>{
          'clientes',
          'veiculos',
          'agendamentos',
          'movimentos_financeiros',
          'ordens_servico',
          'ordem_servico_revisoes',
          'ordem_servico_ajustes_financeiros',
          'ordem_servico_pagamentos',
          'itens_estoque',
          'estoque_lotes',
          'financeiro_plano_contas',
          'financeiro_contas',
          'financeiro_transferencias',
          'fornecedores',
          'financeiro_custos_fixos',
          'financeiro_colaboradores_custo',
          'financeiro_os_mao_obra',
          'financeiro_regras_taxa',
          'financeiro_metas',
        }),
      );
    });

    test('cria estrutura financeira completa nas movimentações', () async {
      final database = await AppDatabase.instance.database;
      final colunas = await _obterColunas(database, 'movimentos_financeiros');

      expect(
        colunas,
        containsAll(<String>{
          'id',
          'tipo',
          'descricao',
          'valor',
          'forma_pagamento',
          'data',
          'cliente_id',
          'agendamento_id',
          'ordem_servico_id',
          'pagamento_id',
          'plano_conta_id',
          'conta_id',
          'fornecedor_id',
          'transferencia_id',
          'natureza',
          'origem',
          'status',
          'data_competencia',
          'data_vencimento',
          'data_pagamento',
          'numero_documento',
          'observacoes',
          'impacta_dre',
        }),
      );

      final indices = await _obterIndices(database, 'movimentos_financeiros');
      expect(indices, contains('idx_movimentos_plano_conta_id'));
      expect(indices, contains('idx_movimentos_conta_id'));
      expect(indices, contains('idx_movimentos_fornecedor_id'));
      expect(indices, contains('idx_movimentos_status_vencimento'));
      expect(indices, contains('idx_movimentos_competencia'));
    });

    test('cria plano de contas padrão e conta caixa sem duplicar', () async {
      final database = await AppDatabase.instance.database;

      final plano = await database.query('financeiro_plano_contas');
      expect(plano.length, greaterThanOrEqualTo(30));

      final codigos = plano.map((item) => item['codigo']).toSet();
      expect(codigos, contains('1.01.01'));
      expect(codigos, contains('2.02.01'));
      expect(codigos, contains('2.04.01'));
      expect(codigos, contains('9.01'));
      expect(codigos, contains('1.02.02'));
      expect(codigos, contains('1.02.03'));
      expect(codigos, contains('2.04.12'));
      expect(codigos, contains('9.06'));

      final produtosConsumidos = await database.query(
        'financeiro_plano_contas',
        columns: ['nome', 'natureza'],
        where: 'codigo = ?',
        whereArgs: ['2.03.01'],
        limit: 1,
      );
      expect(produtosConsumidos, hasLength(1));
      expect(
        produtosConsumidos.single['nome'],
        'Produtos consumidos em serviços',
      );

      final caixa = await database.query(
        'financeiro_contas',
        where: 'nome = ?',
        whereArgs: ['Caixa / Dinheiro'],
      );
      expect(caixa, hasLength(1));
      expect(caixa.single['tipo'], 'Dinheiro');
      expect((caixa.single['saldo_inicial'] as num).toDouble(), 0);
    });

    test('cria estrutura de custos fixos e mão de obra da v25', () async {
      final database = await AppDatabase.instance.database;

      final custosFixos = await _obterColunas(
        database,
        'financeiro_custos_fixos',
      );
      expect(
        custosFixos,
        containsAll(<String>{
          'nome',
          'valor_mensal',
          'dia_vencimento',
          'plano_conta_id',
          'ativo',
        }),
      );

      final colaboradores = await _obterColunas(
        database,
        'financeiro_colaboradores_custo',
      );
      expect(
        colaboradores,
        containsAll(<String>{
          'nome',
          'remuneracao_mensal',
          'encargos_mensais',
          'outros_custos_mensais',
          'horas_produtivas_mes',
          'ativo',
        }),
      );

      final maoObraOs = await _obterColunas(database, 'financeiro_os_mao_obra');
      expect(
        maoObraOs,
        containsAll(<String>{
          'ordem_servico_id',
          'colaborador_custo_id',
          'horas',
          'custo_hora_snapshot',
          'custo_total',
          'ativo',
        }),
      );
    });

    test(
      'cria regras de cartão, repasse automático e metas financeiras',
      () async {
        final database = await AppDatabase.instance.database;

        final regras = await _obterColunas(database, 'financeiro_regras_taxa');
        expect(
          regras,
          containsAll(<String>{
            'nome',
            'forma_pagamento',
            'parcelas',
            'conta_id',
            'taxa_percentual',
            'taxa_fixa',
            'prazo_recebimento_dias',
            'repassar_cliente',
            'ativo',
          }),
        );

        final metas = await _obterColunas(database, 'financeiro_metas');
        expect(
          metas,
          containsAll(<String>{
            'ano',
            'mes',
            'tipo',
            'plano_conta_id',
            'valor_meta',
            'ativo',
          }),
        );
      },
    );

    test('preserva estrutura de pagamentos e ajustes da v23', () async {
      final database = await AppDatabase.instance.database;
      final colunasOrdem = await _obterColunas(database, 'ordens_servico');
      expect(
        colunasOrdem,
        containsAll(<String>{
          'status_pagamento',
          'valor_recebido',
          'desconto_negociacao',
          'acrescimo_negociacao',
          'juros_parcelamento',
        }),
      );

      final colunasPagamentos = await _obterColunas(
        database,
        'ordem_servico_pagamentos',
      );
      expect(
        colunasPagamentos,
        containsAll(<String>{
          'taxa_percentual',
          'taxa_operacao',
          'valor_liquido',
          'regra_taxa_id',
          'parcelas_taxa',
          'comprovante_caminho',
        }),
      );

      final ajustes = await _obterColunas(
        database,
        'ordem_servico_ajustes_financeiros',
      );
      expect(
        ajustes,
        containsAll(<String>{
          'tipo',
          'valor',
          'motivo',
          'status',
          'origem',
          'regra_taxa_id',
          'pagamento_id',
        }),
      );
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
