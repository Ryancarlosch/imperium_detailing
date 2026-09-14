import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:imperium_detailing/services/os_cloud_upload_service.dart';
import 'package:imperium_detailing/services/os_cloud_v3_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> prepararBanco() async {
    final db = await openDatabase(inMemoryDatabasePath);

    await db.execute('''
      CREATE TABLE ordens_servico (
        id INTEGER PRIMARY KEY,
        agendamento_id INTEGER,
        cliente_id INTEGER NOT NULL,
        veiculo_id INTEGER,
        numero TEXT NOT NULL,
        status TEXT NOT NULL,
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
        id INTEGER PRIMARY KEY,
        ordem_servico_id INTEGER NOT NULL,
        servico TEXT NOT NULL,
        descricao TEXT NOT NULL DEFAULT '',
        quantidade REAL NOT NULL,
        valor_unitario REAL NOT NULL,
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
          remoto_atualizado_em TEXT,
          PRIMARY KEY (empresa_id, local_id),
          UNIQUE (empresa_id, remoto_id)
        )
      ''');
    }

    await db.insert('imperium_sync_clientes', {
      'empresa_id': 'empresa',
      'local_id': 10,
      'remoto_id': 'cliente-remoto',
    });

    await db.insert('ordens_servico', {
      'id': 1,
      'cliente_id': 10,
      'numero': 'OS-1',
      'status': 'Aberta',
      'data_abertura': '13/09/2026',
      'funcionario_responsavel': '',
      'observacoes': 'original',
      'valor_total': 100.0,
      'desconto': 0.0,
      'quilometragem_entrada': '',
      'combustivel_entrada': '',
      'motivo_ultima_revisao': '',
      'quantidade_revisoes': 0,
      'assinatura_desatualizada': 0,
      'status_pagamento': 'Pendente',
      'valor_recebido': 0.0,
      'desconto_negociacao': 0.0,
      'acrescimo_negociacao': 0.0,
      'juros_parcelamento': 0.0,
    });

    final local = (await db.query(
      'ordens_servico',
      where: 'id = ?',
      whereArgs: [1],
    )).first;

    final hash = OsCloudUploadService.instance.calcularHashOrdemServico(
      Map<String, Object?>.from(local),
    );

    await db.insert('imperium_sync_ordens_servico', {
      'empresa_id': 'empresa',
      'local_id': 1,
      'remoto_id': 'os-remota',
      'local_hash': hash,
      'remoto_atualizado_em': '2026-09-13T10:00:00Z',
    });

    return db;
  }

  Map<String, dynamic> remoto({
    String observacoes = 'nuvem',
    String atualizadoEm = '2026-09-13T11:00:00Z',
  }) {
    return <String, dynamic>{
      'id': 'os-remota',
      'cliente_id': 'cliente-remoto',
      'veiculo_id': null,
      'agendamento_id': null,
      'numero': 'OS-1',
      'status': 'Aberta',
      'data_abertura': '13/09/2026',
      'data_inicio': null,
      'data_finalizacao': null,
      'hora_entrada': null,
      'hora_saida': null,
      'funcionario_responsavel': '',
      'observacoes': observacoes,
      'valor_total': 100.0,
      'desconto': 0.0,
      'forma_pagamento': null,
      'quilometragem_entrada': '',
      'combustivel_entrada': '',
      'revisada_em': null,
      'motivo_ultima_revisao': '',
      'quantidade_revisoes': 0,
      'assinatura_desatualizada': false,
      'status_pagamento': 'Pendente',
      'valor_recebido': 0.0,
      'vencimento_pagamento': null,
      'pagamento_atualizado_em': null,
      'desconto_negociacao': 0.0,
      'acrescimo_negociacao': 0.0,
      'juros_parcelamento': 0.0,
      'excluido_em': null,
      'atualizado_em': atualizadoEm,
    };
  }

  test('nuvem muda sozinha e atualiza SQLite mapeado', () async {
    final db = await prepararBanco();

    final service = OsCloudV3Service.forTesting(
      database: db,
      ordemFetcher: (_, _) async => remoto(),
      itemFetcher: (_, _) async => null,
    );

    await service.sincronizarDepoisDoDownload('empresa');

    final local = (await db.query(
      'ordens_servico',
      where: 'id = ?',
      whereArgs: [1],
    )).single;

    expect(local['observacoes'], 'nuvem');

    final mapa = (await db.query(
      'imperium_sync_ordens_servico',
      where: 'local_id = ?',
      whereArgs: [1],
    )).single;

    expect(mapa['remoto_atualizado_em'], '2026-09-13T11:00:00Z');
    expect(
      await service.listarConflitosPendentes(empresaId: 'empresa'),
      isEmpty,
    );

    await db.close();
  });

  test('mudanca local e remota vira conflito e bloqueia upload', () async {
    final db = await prepararBanco();

    await db.update(
      'ordens_servico',
      {'observacoes': 'mudanca local'},
      where: 'id = ?',
      whereArgs: [1],
    );

    final service = OsCloudV3Service.forTesting(
      database: db,
      ordemFetcher: (_, _) async => remoto(observacoes: 'mudanca nuvem'),
      itemFetcher: (_, _) async => null,
    );

    final podePublicar = await service.prepararUpload('empresa');
    expect(podePublicar, isFalse);

    final conflitos = await service.listarConflitosPendentes(
      empresaId: 'empresa',
    );

    expect(conflitos, hasLength(1));
    expect(conflitos.first['entidade'], 'ordem');
    expect(conflitos.first['motivo'], 'alteracao_concorrente');

    await db.close();
  });
}
