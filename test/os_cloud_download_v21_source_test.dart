import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imperium_detailing/services/os_cloud_download_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('OS remota nova e importada localmente', () async {
    final fixture = await _Fixture.create(orders: [_ordem('os-1')]);

    await fixture.service.sincronizarDownloadNovos('empresa-a');

    expect(await fixture.db.query('ordens_servico'), hasLength(1));
    expect(
      await fixture.db.query('imperium_sync_ordens_servico'),
      hasLength(1),
    );
    await fixture.close();
  });

  test('segundo download nao duplica OS nem altera seu ID', () async {
    final fixture = await _Fixture.create(orders: [_ordem('os-1')]);

    await fixture.service.sincronizarDownloadNovos('empresa-a');
    final primeira = await fixture.db.query('ordens_servico');
    await fixture.service.sincronizarDownloadNovos('empresa-a');
    final segunda = await fixture.db.query('ordens_servico');

    expect(segunda, hasLength(1));
    expect(segunda.single['id'], primeira.single['id']);
    await fixture.close();
  });

  test('itens remotos sao importados uma unica vez', () async {
    final fixture = await _Fixture.create(
      orders: [_ordem('os-1')],
      items: [_item('item-1', 'os-1')],
    );

    await fixture.service.sincronizarDownloadNovos('empresa-a');
    await fixture.service.sincronizarDownloadNovos('empresa-a');

    expect(await fixture.db.query('ordem_servico_itens'), hasLength(1));
    expect(
      await fixture.db.query('imperium_sync_ordem_servico_itens'),
      hasLength(1),
    );
    await fixture.close();
  });

  test(
    'OS sem mapa do cliente fica pendente e pode ser tentada novamente',
    () async {
      final fixture = await _Fixture.create(
        orders: [_ordem('os-1', clienteId: 'cliente-pendente')],
        mapCliente: false,
      );

      await fixture.service.sincronizarDownloadNovos('empresa-a');
      expect(await fixture.db.query('ordens_servico'), isEmpty);

      await fixture.db.insert('clientes', {'id': 2});
      await fixture.db.insert('imperium_sync_clientes', {
        'empresa_id': 'empresa-a',
        'local_id': 2,
        'remoto_id': 'cliente-pendente',
      });
      await fixture.service.sincronizarDownloadNovos('empresa-a');

      expect(await fixture.db.query('ordens_servico'), hasLength(1));
      await fixture.close();
    },
  );

  test('OS remota excluida nao e importada', () async {
    final fixture = await _Fixture.create(
      orders: [_ordem('os-1', excluidoEm: '2026-09-05T10:00:00Z')],
    );

    await fixture.service.sincronizarDownloadNovos('empresa-a');

    expect(await fixture.db.query('ordens_servico'), isEmpty);
    await fixture.close();
  });

  test('empresa A nunca importa OS no contexto da empresa B', () async {
    final fixture = await _Fixture.create(orders: [_ordem('os-a')]);

    await fixture.service.sincronizarDownloadNovos('empresa-b');

    expect(await fixture.db.query('ordens_servico'), isEmpty);
    expect(fixture.requestedTenants, ['empresa-b', 'empresa-b']);
    await fixture.close();
  });

  test('OS ja mapeada nao e sobrescrita', () async {
    final fixture = await _Fixture.create(
      orders: [_ordem('os-1', numero: 'REMOTE')],
      localOrder: {'id': 7, 'numero': 'LOCAL'},
      mapOrder: {'local_id': 7, 'remoto_id': 'os-1'},
    );

    await fixture.service.sincronizarDownloadNovos('empresa-a');

    final local = await fixture.db.query('ordens_servico', where: 'id = 7');
    expect(local.single['numero'], 'LOCAL');
    expect(local.single['id'], 7);
    await fixture.close();
  });

  test(
    'download nao toca financeiro, estoque, pagamentos ou produtos',
    () async {
      final fixture = await _Fixture.create(
        orders: [_ordem('os-1')],
        withProtectedRows: true,
      );
      final antes = await fixture.protectedCounts();

      await fixture.service.sincronizarDownloadNovos('empresa-a');

      expect(await fixture.protectedCounts(), antes);
      await fixture.close();
    },
  );

  test('contrato textual preserva os limites da V2.1', () {
    final service = File(
      'lib/services/os_cloud_download_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(service, contains('sincronizarDownloadNovos'));
    expect(service, contains(".from('imperium_ordens_servico')"));
    expect(service, contains(".from('imperium_ordem_servico_itens')"));
    expect(service, contains(".eq('empresa_id', empresaId)"));
    expect(service, contains("remoto['excluido_em']"));
    expect(service, contains('imperium_sync_ordens_servico'));
    expect(service, contains('imperium_sync_ordem_servico_itens'));
    expect(service, contains('imperium_sync_clientes'));
    expect(service, contains('imperium_sync_veiculos'));
    expect(service, contains('imperium_sync_agendamentos'));
    expect(service, contains('database.transaction'));
    expect(service, contains('if (mapa != null) return'));
    expect(service, isNot(contains(".from('ordem_servico_pagamentos')")));
    expect(
      service,
      isNot(contains(".from('imperium_ordem_servico_produtos')")),
    );
    expect(service, isNot(contains(".from('estoque')")));
    expect(service, isNot(contains(".from('movimentos_financeiros')")));
    expect(service, isNot(contains('assinatura_cliente')));

    final agendamentos = sync.indexOf('await _baixarAgendamentos(empresaId)');
    final osDownload = sync.indexOf(
      'OsCloudDownloadService.instance.sincronizarDownloadNovos',
    );
    expect(agendamentos, greaterThanOrEqualTo(0));
    expect(osDownload, greaterThan(agendamentos));
  });
}

Map<String, dynamic> _ordem(
  String id, {
  String clienteId = 'cliente-1',
  String numero = 'OS-001',
  String? excluidoEm,
}) {
  return {
    'id': id,
    'empresa_id': 'empresa-a',
    'cliente_id': clienteId,
    'veiculo_id': null,
    'agendamento_id': null,
    'numero': numero,
    'status': 'Aberta',
    'data_abertura': '2026-09-05',
    'data_inicio': null,
    'data_finalizacao': null,
    'hora_entrada': null,
    'hora_saida': null,
    'funcionario_responsavel': '',
    'observacoes': '',
    'valor_total': 100,
    'desconto': 0,
    'forma_pagamento': null,
    'quilometragem_entrada': '',
    'combustivel_entrada': '',
    'revisada_em': null,
    'motivo_ultima_revisao': '',
    'quantidade_revisoes': 0,
    'assinatura_desatualizada': false,
    'status_pagamento': 'Pendente',
    'valor_recebido': 0,
    'vencimento_pagamento': null,
    'pagamento_atualizado_em': null,
    'desconto_negociacao': 0,
    'acrescimo_negociacao': 0,
    'juros_parcelamento': 0,
    'excluido_em': excluidoEm,
    'atualizado_em': '2026-09-05T10:00:00Z',
  };
}

Map<String, dynamic> _item(String id, String ordemId) {
  return {
    'id': id,
    'empresa_id': 'empresa-a',
    'ordem_servico_id': ordemId,
    'servico': 'Lavagem',
    'descricao': 'Completa',
    'quantidade': 1,
    'valor_unitario': 100,
    'concluido': false,
    'ordem': 0,
    'excluido_em': null,
    'atualizado_em': '2026-09-05T10:00:00Z',
  };
}

class _Fixture {
  _Fixture(this.db, this.service, this.requestedTenants);

  final Database db;
  final OsCloudDownloadService service;
  final List<String> requestedTenants;

  static Future<_Fixture> create({
    List<Map<String, dynamic>> orders = const [],
    List<Map<String, dynamic>> items = const [],
    bool mapCliente = true,
    Map<String, dynamic>? localOrder,
    Map<String, dynamic>? mapOrder,
    bool withProtectedRows = false,
  }) async {
    final db = await openDatabase(inMemoryDatabasePath);
    await _createSchema(db);
    final requestedTenants = <String>[];
    await db.insert('clientes', {'id': 1});
    if (mapCliente) {
      await db.insert('imperium_sync_clientes', {
        'empresa_id': 'empresa-a',
        'local_id': 1,
        'remoto_id': 'cliente-1',
      });
    }
    if (localOrder != null) {
      await db.insert('ordens_servico', {
        'id': localOrder['id'],
        'cliente_id': 1,
        'numero': localOrder['numero'],
        'status': 'Aberta',
        'data_abertura': '2026-09-01',
      });
    }
    if (mapOrder != null) {
      await db.insert('imperium_sync_ordens_servico', {
        'empresa_id': 'empresa-a',
        'local_id': mapOrder['local_id'],
        'remoto_id': mapOrder['remoto_id'],
      });
    }
    if (withProtectedRows) {
      await db.insert('movimentos_financeiros', {'id': 1});
      await db.insert('itens_estoque', {'id': 1});
      await db.insert('ordem_servico_pagamentos', {'id': 1});
      await db.insert('ordem_servico_produtos', {'id': 1});
    }

    final service = OsCloudDownloadService.forTesting(
      database: db,
      ordensFetcher: (empresaId) async {
        requestedTenants.add(empresaId);
        return orders.where((item) => item['empresa_id'] == empresaId).toList();
      },
      itensFetcher: (empresaId) async {
        requestedTenants.add(empresaId);
        return items.where((item) => item['empresa_id'] == empresaId).toList();
      },
    );
    return _Fixture(db, service, requestedTenants);
  }

  Future<Map<String, int>> protectedCounts() async {
    return {
      'movimentos':
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM movimentos_financeiros'),
          ) ??
          0,
      'estoque':
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM itens_estoque'),
          ) ??
          0,
      'pagamentos':
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM ordem_servico_pagamentos'),
          ) ??
          0,
      'produtos':
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM ordem_servico_produtos'),
          ) ??
          0,
    };
  }

  Future<void> close() => db.close();
}

Future<void> _createSchema(Database db) async {
  await db.execute('CREATE TABLE clientes (id INTEGER PRIMARY KEY)');
  await db.execute('CREATE TABLE veiculos (id INTEGER PRIMARY KEY)');
  await db.execute('CREATE TABLE agendamentos (id INTEGER PRIMARY KEY)');
  await db.execute('''
    CREATE TABLE ordens_servico (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      agendamento_id INTEGER,
      cliente_id INTEGER NOT NULL,
      veiculo_id INTEGER,
      numero TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Aberta',
      data_abertura TEXT NOT NULL,
      data_inicio TEXT,
      data_finalizacao TEXT,
      hora_entrada TEXT,
      hora_saida TEXT,
      funcionario_responsavel TEXT NOT NULL DEFAULT '',
      observacoes TEXT NOT NULL DEFAULT '',
      valor_total REAL NOT NULL DEFAULT 0,
      desconto REAL NOT NULL DEFAULT 0,
      forma_pagamento TEXT,
      quilometragem_entrada TEXT NOT NULL DEFAULT '',
      combustivel_entrada TEXT NOT NULL DEFAULT '',
      revisada_em TEXT,
      motivo_ultima_revisao TEXT NOT NULL DEFAULT '',
      quantidade_revisoes INTEGER NOT NULL DEFAULT 0,
      assinatura_desatualizada INTEGER NOT NULL DEFAULT 0,
      status_pagamento TEXT NOT NULL DEFAULT 'Pendente',
      valor_recebido REAL NOT NULL DEFAULT 0,
      vencimento_pagamento TEXT,
      pagamento_atualizado_em TEXT,
      desconto_negociacao REAL NOT NULL DEFAULT 0,
      acrescimo_negociacao REAL NOT NULL DEFAULT 0,
      juros_parcelamento REAL NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE ordem_servico_itens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ordem_servico_id INTEGER NOT NULL,
      servico TEXT NOT NULL,
      descricao TEXT NOT NULL DEFAULT '',
      quantidade REAL NOT NULL DEFAULT 1,
      valor_unitario REAL NOT NULL DEFAULT 0,
      concluido INTEGER NOT NULL DEFAULT 0,
      ordem INTEGER NOT NULL DEFAULT 0
    )
  ''');
  for (final tabela in [
    'imperium_sync_clientes',
    'imperium_sync_veiculos',
    'imperium_sync_agendamentos',
    'imperium_sync_ordens_servico',
    'imperium_sync_ordem_servico_itens',
  ]) {
    await db.execute('''
      CREATE TABLE $tabela (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT
      )
    ''');
  }
  await db.execute(
    'CREATE TABLE movimentos_financeiros (id INTEGER PRIMARY KEY)',
  );
  await db.execute('CREATE TABLE itens_estoque (id INTEGER PRIMARY KEY)');
  await db.execute(
    'CREATE TABLE ordem_servico_pagamentos (id INTEGER PRIMARY KEY)',
  );
  await db.execute(
    'CREATE TABLE ordem_servico_produtos (id INTEGER PRIMARY KEY)',
  );
}
