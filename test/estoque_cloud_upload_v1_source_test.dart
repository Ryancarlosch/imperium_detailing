import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque Cloud V1 permanece upload-only e append-only', () {
    final service = File(
      'lib/services/estoque_cloud_upload_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(service, contains('estoque-cloud-upload-service-v1'));
    expect(service, contains('imperium_sync_estoque_itens'));
    expect(service, contains('imperium_sync_estoque_lotes'));
    expect(service, contains('imperium_sync_estoque_movimentacoes'));

    expect(service, contains("from('imperium_estoque_itens')"));
    expect(service, contains("from('imperium_estoque_lotes')"));
    expect(service, contains("from('imperium_estoque_movimentacoes')"));
    expect(service, contains('.insert(payload)'));

    expect(sync, contains("import 'estoque_cloud_upload_service.dart';"));
    expect(
      sync,
      contains(
        'await EstoqueCloudUploadService.instance.sincronizarUpload(empresaId);',
      ),
    );

    final osUpload = sync.indexOf(
      'await OsCloudUploadService.instance.sincronizarUpload(empresaId);',
    );
    final estoqueUpload = sync.indexOf(
      'await EstoqueCloudUploadService.instance.sincronizarUpload(empresaId);',
    );

    expect(osUpload, greaterThanOrEqualTo(0));
    expect(estoqueUpload, greaterThan(osUpload));
  });

  test('Migration do estoque protege tenant e movimentacoes imutaveis', () {
    final sql = File(
      'supabase/migrations/20260912023332_estoque_cloud_upload_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('public.imperium_estoque_itens'));
    expect(sql, contains('public.imperium_estoque_lotes'));
    expect(sql, contains('public.imperium_estoque_movimentacoes'));
    expect(
      sql,
      contains("private.imperium_pode_modulo(empresa_id, 'estoque')"),
    );
    expect(
      sql,
      contains('unique (empresa_id, origem_dispositivo, origem_local_id)'),
    );

    expect(sql, contains('imperium_estoque_mov_select'));
    expect(sql, contains('imperium_estoque_mov_insert'));
    expect(sql, isNot(contains('imperium_estoque_mov_update')));
    expect(sql, isNot(contains('imperium_estoque_mov_delete')));
  });

  test('SQLite continua v33 sem migration local', () {
    final database = File('lib/database/app_database.dart').readAsStringSync();

    expect(database, contains('static const int schemaVersion = 33;'));
  });
}
