import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web gera e compartilha PDF da Ordem de Servico sem dart io', () {
    final service = File(
      'lib/services/web_os_pdf_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/web/web_ordens_v3_page.dart',
    ).readAsStringSync();

    expect(service, isNot(contains("import 'dart:io'")));
    expect(service, contains("import 'dart:typed_data'"));
    expect(service, contains('gerarPdf'));
    expect(service, contains('Printing.layoutPdf'));
    expect(service, contains('Printing.sharePdf'));
    expect(service, contains('WebOsArquivosService'));
    expect(service, contains('OrdemServicoValor.valorNegociado'));

    expect(page, contains("tooltip: 'PDF da Ordem de Serviço'"));
    expect(page, contains("'Visualizar PDF'"));
    expect(page, contains("'Compartilhar PDF'"));
    expect(page, contains('_pdf.visualizarPdf'));
    expect(page, contains('_pdf.compartilharPdf'));
  });

  test('PDF Web usa dados sincronizados e anexos privados da OS', () {
    final service = File(
      'lib/services/web_os_pdf_service.dart',
    ).readAsStringSync();
    final arquivos = File(
      'lib/services/web_os_arquivos_service.dart',
    ).readAsStringSync();

    expect(service, contains('carregarEdicao'));
    expect(service, contains('listarClientes'));
    expect(service, contains('listarVeiculos'));
    expect(service, contains('_carregarImagens'));
    expect(arquivos, contains("'imperium_ordem_servico_fotos'"));
    expect(arquivos, contains("'imperium_ordem_servico_checklist'"));
    expect(arquivos, contains("'imperium-os-arquivos'"));
    expect(arquivos, contains('.download(path)'));
  });
}
