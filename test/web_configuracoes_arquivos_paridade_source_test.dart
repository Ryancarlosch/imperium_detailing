import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Configurações Web gerenciam logo e assinatura no Storage oficial', () {
    final page = File(
      'lib/web/web_configuracoes_empresa_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_configuracao_arquivo_service.dart',
    ).readAsStringSync();

    for (final marker in [
      'Logo e assinatura',
      'Enviar logo',
      'Assinatura da empresa',
      'Desenhar',
      'Importar imagem',
      'Storage privado da empresa',
    ]) {
      expect(page, contains(marker));
    }

    expect(service, contains('imperium-configuracoes-arquivos'));
    expect(service, contains('imperium_configuracao_arquivos'));
    expect(service, contains('uploadBinary'));
    expect(service, contains('sha256.convert(bytes)'));
    expect(service, contains("onConflict: 'empresa_id,tipo'"));
    expect(service, contains("'logo'"));
    expect(service, contains("'assinatura_empresa'"));
  });

  test('Sync de arquivos usa implementação IO apenas fora do Web', () {
    final facade = File(
      'lib/services/configuracao_arquivos_cloud_service.dart',
    ).readAsStringSync();
    final io = File(
      'lib/services/configuracao_arquivos_cloud_service_io.dart',
    ).readAsStringSync();
    final stub = File(
      'lib/services/configuracao_arquivos_cloud_service_stub.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(facade, contains("if (dart.library.io)"));
    expect(facade, contains('configuracao_arquivos_cloud_service_io.dart'));
    expect(io, contains("import 'dart:io';"));
    expect(io, contains('resolverUsandoLocal'));
    expect(io, contains('resolverUsandoNuvem'));
    expect(io, contains('SHA-256'));
    expect(stub, isNot(contains("import 'dart:io';")));
    expect(stub, contains('gerenciado_diretamente_pelo_storage'));

    expect(
      motor,
      contains("import 'configuracao_arquivos_cloud_service.dart';"),
    );
    expect(
      motor,
      contains('ConfiguracaoArquivosCloudService.instance.sincronizar'),
    );
    expect(
      motor,
      contains('Conflitos pendentes em logo/assinatura da empresa.'),
    );
  });

  test('Diagnóstico textual reconhece identidade no Cloud', () {
    final service = File(
      'lib/services/configuracao_cloud_service.dart',
    ).readAsStringSync();

    expect(service, contains('arquivos_identidade_no_cloud'));
    expect(service, isNot(contains('arquivos_locais_fora_do_cloud')));
    expect(service, contains('backup_local_fora_do_cloud'));
  });
}
