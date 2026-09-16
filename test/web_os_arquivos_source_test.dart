import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web visualiza arquivos da OS por bytes sem dart io na implementacao', () {
    final service = File(
      'lib/services/web_os_arquivos_service.dart',
    ).readAsStringSync();
    final page = File('lib/web/web_os_arquivos_page.dart').readAsStringSync();

    expect(service, contains("from('imperium_ordens_servico')"));
    expect(service, contains("from('imperium_ordem_servico_fotos')"));
    expect(service, contains("from('imperium_ordem_servico_checklist')"));
    expect(service, contains("storage.from(bucket).download(path)"));
    expect(service, contains("bucketPadrao = 'imperium-os-arquivos'"));
    expect(service, contains("'tipo': 'foto'"));
    expect(service, contains("'tipo': 'avaria'"));
    expect(service, contains("'tipo': 'assinatura'"));
    expect(service, isNot(contains("import 'dart:io'")));

    expect(page, contains('WebOsArquivosPage'));
    expect(page, contains('FutureBuilder<Uint8List>'));
    expect(page, contains('Image.memory'));
    expect(page, contains('InteractiveViewer'));
    expect(page, isNot(contains("import 'dart:io'")));
  });
}
