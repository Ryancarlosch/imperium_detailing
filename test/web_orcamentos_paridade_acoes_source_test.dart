import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web oferece PDF recibo WhatsApp e exclusao de orcamento', () {
    final page = File('lib/web/web_expansao_pages.dart').readAsStringSync();
    final pdf = File(
      'lib/services/web_orcamento_pdf_service.dart',
    ).readAsStringSync();

    expect(page, contains('Documento do orçamento'));
    expect(page, contains('Visualizar PDF'));
    expect(page, contains('Compartilhar orçamento'));
    expect(page, contains('Gerar e compartilhar recibo'));
    expect(page, contains('Enviar pelo WhatsApp'));
    expect(page, contains('Enviar orçamento'));
    expect(page, contains('Enviar aprovação'));
    expect(page, contains('Mensagem personalizada'));
    expect(page, contains('_service.excluirOrcamento'));

    expect(pdf, isNot(contains("import 'dart:io'")));
    expect(pdf, contains('Printing.layoutPdf'));
    expect(pdf, contains('Printing.sharePdf'));
    expect(pdf, contains('WebConfiguracaoEmpresaService'));
    expect(pdf, contains('WebConfiguracaoArquivoService'));
    expect(pdf, contains('termos_orcamento'));
    expect(pdf, contains('rodape_documentos'));
  });

  test('WhatsApp de orcamento usa o mesmo servico do Android', () {
    final page = File('lib/web/web_expansao_pages.dart').readAsStringSync();

    expect(page, contains('WhatsAppService.enviarOrcamento'));
    expect(page, contains('WhatsAppService.enviarAprovacaoOrcamento'));
    expect(page, contains('WhatsAppService.enviarMensagemPersonalizada'));
  });
}
