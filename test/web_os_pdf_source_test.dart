import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF Web da OS usa bytes e nao depende de dart:io', () async {
    final service = await File(
      'lib/services/web_os_pdf_service.dart',
    ).readAsString();
    final pagina = await File(
      'lib/web/web_os_arquivos_page.dart',
    ).readAsString();

    expect(service, contains("import 'dart:typed_data';"));
    expect(service, isNot(contains("import 'dart:io';")));
    expect(service, contains('class WebOsPdfService'));
    expect(service, contains('WebOsArquivosService.instance'));
    expect(service, contains('_arquivosService.baixar(arquivo)'));
    expect(service, contains('pw.MemoryImage(imagem.bytes)'));
    expect(service, contains('pw.Document()'));
    expect(service, contains('Printing.sharePdf('));
    expect(service, contains("filename: 'ordem_servico_\$identificador.pdf'"));

    expect(pagina, contains("import '../services/web_os_pdf_service.dart';"));
    expect(pagina, contains('WebOsPdfService.instance'));
    expect(pagina, contains('Future<void> _baixarPdf()'));
    expect(pagina, contains("tooltip: 'Baixar PDF da OS'"));
    expect(pagina, contains('onPressed: _baixarPdf'));
    expect(pagina, contains('Icons.picture_as_pdf_outlined'));
  });
}
