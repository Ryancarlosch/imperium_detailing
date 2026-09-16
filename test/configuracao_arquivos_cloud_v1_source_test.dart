import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Logo e assinatura usam Storage privado com conflito e tenant', () {
    final service = File(
      'lib/services/configuracao_arquivos_cloud_service.dart',
    ).readAsStringSync();
    final gate = File('lib/widgets/licenca_gate.dart').readAsStringSync();
    final realtime = File(
      'lib/services/operacional_realtime_service.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/20260917001000_configuracao_arquivos_storage_v1.sql',
    ).readAsStringSync();

    for (final marker in <String>[
      'imperium-configuracoes-arquivos',
      'imperium_configuracao_arquivos',
      'imperium_sync_configuracao_arquivos',
      'imperium_sync_configuracao_arquivos_conflitos',
      "tipo: 'logo'",
      "tipo: 'assinatura_empresa'",
      'resolverUsandoNuvem',
      'resolverUsandoLocal',
      'uploadBinary',
      'download(storagePath)',
      'sha256',
      "eq('atualizado_em'",
    ]) {
      expect(service, contains(marker));
    }

    expect(gate, contains('ConfiguracaoArquivosCloudService.instance'));
    expect(gate, contains('_configArquivos.sincronizar(empresaId)'));
    expect(realtime, contains("registrar('imperium_configuracao_arquivos')"));

    expect(sql, contains('private.imperium_eh_admin_empresa'));
    expect(sql, contains("public.imperium_configuracao_arquivos"));
    expect(sql, contains('alter publication supabase_realtime'));
    expect(sql, contains('10485760'));
  });
}
