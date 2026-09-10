import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/saude_sistema_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late SaudeSistemaRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp('imperium_saude_test_');
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    repository = SaudeSistemaRepository();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) {
      await pasta.delete(recursive: true);
    }
  });

  test(
    'diagnóstico local valida SQLite, schema e estruturas principais',
    () async {
      final resumo = await repository.diagnosticarLocal();

      expect(resumo.sqliteIntegro, isTrue);
      expect(resumo.versaoSchema, AppDatabase.schemaVersion);
      expect(resumo.violacoesForeignKey, 0);
      expect(resumo.criticos, 0);
      expect(resumo.contagens, contains('Clientes'));
      expect(resumo.coberturaSync.map((item) => item.entidade), contains('OS'));
      expect(resumo.gerarRelatorio(), contains('RELATÓRIO DE SAÚDE'));
    },
  );

  test(
    'detecta estoque negativo e movimento financeiro sem documento',
    () async {
      final database = await AppDatabase.instance.database;
      final agora = DateTime(2026, 9, 9, 18).toIso8601String();

      await database.insert('itens_estoque', {
        'nome': 'Produto inconsistente',
        'categoria': 'Teste',
        'quantidade': -2.0,
        'quantidade_minima': 0.0,
        'unidade': 'un',
        'valor_total_pago': 0.0,
        'quantidade_total': 0.0,
        'ean': '',
        'custo_unitario': 0.0,
        'custo_unitario_calculado': 0.0,
        'fornecedor': '',
        'observacoes': '',
        'ativo': 1,
        'atualizado_em': agora,
      });

      await database.insert('movimentos_financeiros', {
        'tipo': 'entrada',
        'descricao': 'Movimento legado sem documento',
        'valor': 100.0,
        'forma_pagamento': 'Pix',
        'data': agora,
        'natureza': 'Teste',
        'origem': 'Manual',
        'status': 'Realizado',
        'data_competencia': agora,
        'data_pagamento': agora,
        'numero_documento': '',
        'observacoes': '',
        'impacta_dre': 1,
      });

      final resumo = await repository.diagnosticarLocal();
      final chaves = resumo.itens.map((item) => item.chave).toSet();

      expect(chaves, contains('estoque_negativo'));
      expect(chaves, contains('movimento_sem_documento'));
      expect(resumo.criticos, greaterThanOrEqualTo(1));
    },
  );

  test('mede cobertura de sincronização e detecta múltiplos tenants', () async {
    var resumo = await repository.diagnosticarLocal();
    final database = await AppDatabase.instance.database;

    final cliente1 = await database.insert('clientes', {
      'nome': 'Cliente A',
      'telefone': '',
      'email': '',
      'endereco': '',
      'observacoes': '',
      'data_nascimento': null,
      'ativo': 1,
      'arquivado_em': null,
    });
    final cliente2 = await database.insert('clientes', {
      'nome': 'Cliente B',
      'telefone': '',
      'email': '',
      'endereco': '',
      'observacoes': '',
      'data_nascimento': null,
      'ativo': 1,
      'arquivado_em': null,
    });

    await database.insert('imperium_sync_clientes', {
      'empresa_id': 'empresa-a',
      'local_id': cliente1,
      'remoto_id': 'remoto-a',
      'local_hash': 'hash-a',
      'remoto_atualizado_em': null,
    });
    await database.insert('imperium_sync_clientes', {
      'empresa_id': 'empresa-b',
      'local_id': cliente2,
      'remoto_id': 'remoto-b',
      'local_hash': 'hash-b',
      'remoto_atualizado_em': null,
    });

    resumo = await repository.diagnosticarLocal();
    final clientes = resumo.coberturaSync.singleWhere(
      (item) => item.entidade == 'Clientes',
    );

    expect(clientes.locais, 2);
    expect(clientes.mapeados, 2);
    expect(resumo.tenantsMapeados, 2);
    expect(
      resumo.itens.map((item) => item.chave),
      contains('multiplos_tenants_local'),
    );
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
