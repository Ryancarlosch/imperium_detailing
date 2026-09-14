import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OS Cloud V3 protege OS e itens mapeados', () {
    final source = File(
      'lib/services/os_cloud_v3_service.dart',
    ).readAsStringSync();

    expect(source, contains('imperium_sync_os_conflitos'));
    expect(source, contains('prepararUpload'));
    expect(source, contains('sincronizarDepoisDoDownload'));
    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
    expect(source, contains('exclusao_remota_os'));
  });

  test('Upload V1 usa CAS para OS itens e exclusoes', () {
    final source = File(
      'lib/services/os_cloud_upload_service.dart',
    ).readAsStringSync();

    expect(source, contains('calcularHashOrdemServico'));
    expect(source, contains('calcularHashOrdemServicoItem'));
    expect(source, contains("eq('atualizado_em', esperado)"));
    expect(source, contains('A OS mudou na nuvem antes do upload'));
    expect(source, contains('O item da OS mudou na nuvem antes do upload'));
    expect(source, contains('O registro remoto mudou antes da exclusão'));
  });

  test('Motor executa guard V3 antes do upload e reconcilia depois', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    final inicio = source.indexOf('Future<void> _syncOrdensServico');
    final fim = source.indexOf('Future<void> _syncArquivosOs', inicio);

    expect(inicio, greaterThanOrEqualTo(0));
    expect(fim, greaterThan(inicio));

    final bloco = source.substring(inicio, fim);

    final guard = bloco.indexOf('OsCloudV3Service.instance.prepararUpload');
    final upload = bloco.indexOf(
      'OsCloudUploadService.instance.sincronizarUpload',
    );
    final download = bloco.indexOf(
      'OsCloudDownloadService.instance.sincronizarDownloadNovos',
    );
    final depois = bloco.indexOf(
      'OsCloudV3Service.instance.sincronizarDepoisDoDownload',
    );

    expect(guard, greaterThanOrEqualTo(0));
    expect(upload, greaterThan(guard));
    expect(download, greaterThan(upload));
    expect(depois, greaterThan(download));
    expect(bloco, contains('SyncMotorBloqueadoException'));
  });

  test('Web usa RPC atomica e bloqueia finalizacao no contrato', () {
    final service = File(
      'lib/services/web_os_v3_service.dart',
    ).readAsStringSync();

    final page = File('lib/web/web_ordens_v3_page.dart').readAsStringSync();

    final sql = File(
      'supabase/migrations/'
      '20260913143000_os_cloud_v3_edicao_web_atomica.sql',
    ).readAsStringSync();

    // Contrato estrutural, sem depender de quebra de linha do dart format
    // ou de texto exibido ao usuario.
    expect(service, contains('client.rpc('));
    expect(service, contains("'imperium_os_web_editar_v3'"));
    expect(service, contains("'p_itens_base'"));
    expect(service, contains("'p_os_atualizado_em'"));

    expect(service, contains("status != 'Aberta'"));
    expect(service, contains("status != 'Em andamento'"));
    expect(page, contains("status != 'Aberta'"));
    expect(page, contains("status != 'Em andamento'"));

    final sqlLower = sql.toLowerCase();
    expect(sqlLower, contains('for update'));
    expect(sql, contains("errcode = '40001'"));
    expect(sql, contains("v_status not in ('Aberta', 'Em andamento')"));
    expect(sqlLower, contains('security invoker'));
  });

  test('Central Android expoe conflitos da OS', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('OsCloudV3Service'));
    expect(source, contains('_conflitosOrdensServico'));
    expect(source, contains('_ordensServicoCloudCard'));
    expect(source, contains('_resolverOsCloud'));
  });

  test('schema local continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
