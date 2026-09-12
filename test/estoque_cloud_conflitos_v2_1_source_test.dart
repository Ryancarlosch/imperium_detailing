import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque Cloud V2.1 protege conflito concorrente', () {
    final conflito = File(
      'lib/services/estoque_cloud_conflito_service.dart',
    ).readAsStringSync();
    final upload = File(
      'lib/services/estoque_cloud_upload_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');

    expect(conflito, contains('estoque-cloud-conflitos-v2-1'));
    expect(conflito, contains('if (localMudou && remotoMudou)'));
    expect(conflito, contains('imperium_sync_estoque_conflitos'));

    expect(upload, contains("entidade: 'item'"));
    expect(upload, contains("entidade: 'lote'"));
    expect(upload, contains('_possuiConflitoPendente'));

    final reconciliar =
        RegExp(
          r'awaitEstoqueCloudConflitoService\.instance\.'
          r'reconciliarAntesDoUpload\(empresaId,?\);',
        ).firstMatch(sync)?.start ??
        -1;

    final publicar =
        RegExp(
          r'awaitEstoqueCloudUploadService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(sync)?.start ??
        -1;

    expect(reconciliar, greaterThanOrEqualTo(0));
    expect(publicar, greaterThan(reconciliar));
  });

  test('SQLite continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
