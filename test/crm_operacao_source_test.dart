import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CRM V3 mantém envio assistido e lembrete local sem disparo automático',
    () {
      final page = File(
        'lib/screens/crm_operacao_page.dart',
      ).readAsStringSync();
      final notifications = File(
        'lib/services/notification_service.dart',
      ).readAsStringSync();

      expect(page, contains('WhatsAppService.enviarMensagemPersonalizada'));
      expect(
        page,
        contains('Abrir o WhatsApp não confirma que a mensagem foi enviada'),
      );
      expect(page, contains('nenhuma mensagem é disparada automaticamente'));
      expect(page, contains('Levar ao funil'));
      expect(notifications, contains('ativarLembreteDiarioCrm'));
      expect(notifications, contains("payload: 'crm:acoes'"));
      expect(notifications, contains('DateTimeComponents.time'));
    },
  );

  test('CRM principal expõe Central de relacionamento', () {
    final crm = File('lib/screens/crm_page.dart').readAsStringSync();
    expect(crm, contains("import 'crm_operacao_page.dart';"));
    expect(crm, contains('Central de relacionamento'));
    expect(crm, contains('CrmOperacaoPage'));
  });
}
