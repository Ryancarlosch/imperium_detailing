import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OS Cloud V1 continua upload-only e separada de Financeiro/Estoque', () {
    final service = File(
      'lib/services/os_cloud_upload_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/repositories/ordem_servico_repository.dart',
    ).readAsStringSync();

    expect(service, contains('os-cloud-upload-service-v1'));
    expect(service, contains('os-cloud-upload-mapas-v1'));
    expect(service, contains(".from('imperium_ordens_servico')"));
    expect(service, contains(".from('imperium_ordem_servico_itens')"));
    expect(
      service,
      contains("onConflict: 'empresa_id,origem_dispositivo,origem_local_id'"),
    );
    expect(service, contains("'__excluido__'"));

    expect(
      service,
      isNot(contains(".from('imperium_ordem_servico_pagamentos')")),
    );
    expect(
      service,
      isNot(contains(".from('imperium_ordem_servico_produtos')")),
    );
    expect(service, isNot(contains("local['assinatura_cliente']")));
    expect(service, isNot(contains('baixarOrdensServico')));

    expect(sync, contains('Future<void> _syncOrdensServico(String empresaId)'));
    expect(sync, contains('OsCloudUploadService.instance.sincronizarUpload'));
    expect(
      sync,
      contains('OsCloudDownloadService.instance.sincronizarDownloadNovos'),
    );
    expect(sync, contains('OsCloudV3Service.instance.sincronizarDepoisDoDownload'));
    expect(repo, contains('os-cloud-upload-trigger-v1'));
  });
}
