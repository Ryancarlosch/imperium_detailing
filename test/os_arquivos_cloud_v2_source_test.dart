import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OS Arquivos V2 protege checklist e assinatura', () {
    final source = File(
      'lib/services/os_arquivos_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('os-arquivos-cloud-v2'));
    expect(source, contains('imperium_sync_os_arquivos_conflitos'));
    expect(source, contains('_reconciliarChecklist'));
    expect(source, contains('_reconciliarAssinaturas'));
    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
  });

  test('Resolucao local usa CAS', () {
    final source = File(
      'lib/services/os_arquivos_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains("eq('atualizado_em', esperado)"));
    expect(source, contains('A nuvem mudou novamente'));
  });

  test('Sync guarda V1 antes de upload e download de arquivos', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    expect(
      compact,
      contains(
        'finalosArquivosPodePublicar='
        'awaitOsArquivosCloudV2Service.instance'
        '.prepararSincronizacao(empresaId);',
      ),
    );
    expect(
      compact,
      contains(
        'if(osArquivosPodePublicar){'
        'awaitOsArquivosCloudService.instance'
        '.sincronizarUpload(empresaId);}',
      ),
    );
    expect(
      compact,
      contains(
        'finalosArquivosPodeBaixar='
        'awaitOsArquivosCloudV2Service.instance'
        '.prepararSincronizacao(empresaId);',
      ),
    );
  });

  test('Central Cloud exibe e resolve conflitos de arquivos', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('Arquivos da OS'));
    expect(source, contains('_resolverArquivoOs'));
    expect(source, contains('OsArquivosCloudV2Service'));
    expect(source, contains('Usar nuvem'));
    expect(source, contains('Usar local'));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
