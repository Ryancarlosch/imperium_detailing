import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OS Arquivos V1 cobre fotos checklist e assinatura', () {
    final source = File(
      'lib/services/os_arquivos_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('os-arquivos-cloud-v1'));
    expect(source, contains('ordem_servico_fotos'));
    expect(source, contains('ordem_servico_checklist'));
    expect(source, contains('assinatura_cliente'));
    expect(source, contains('imperium-os-arquivos'));
    expect(source, contains('uploadBinary'));
    expect(source, contains('TenantLocalStorageService.instance.pasta'));
  });

  test('Comprovante financeiro continua em bucket separado', () {
    final source = File(
      'lib/services/os_arquivos_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('imperium-financeiro-comprovantes'));
  });

  test('Sync operacional executa arquivos depois da OS', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    expect(compact, contains("modulo:'ordens_servico',prioridade:30"));
    expect(compact, contains("modulo:'arquivos_os',prioridade:40"));
    expect(
      compact,
      contains("dependencias:const<String>['ordens_servico']"),
    );
    expect(compact, contains('executar:()=>_syncArquivosOs(empresaId)'));

    final upload = compact.indexOf(
      'awaitOsArquivosCloudService.instance.sincronizarUpload(empresaId);',
    );
    final download = compact.indexOf(
      'awaitOsArquivosCloudService.instance.sincronizarDownload(empresaId);',
    );

    expect(upload, greaterThanOrEqualTo(0));
    expect(download, greaterThan(upload));
  });

  test('Migration cria bucket privado e RLS de fotos', () {
    final sql = File(
      'supabase/migrations/'
      '20260913030508_os_arquivos_storage_v1_complemento.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_ordem_servico_fotos'));
    expect(sql, contains('imperium-os-arquivos'));
    expect(sql, contains('20971520'));
    expect(sql, contains('imperium_os_arquivos_select'));
    expect(sql, contains("private.imperium_pode_modulo"));
    expect(sql, contains("'ordens_servico'"));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
