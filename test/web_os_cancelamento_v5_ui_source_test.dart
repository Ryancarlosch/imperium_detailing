import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lista Web expoe cancelamento V5 apenas para OS editavel', () {
    final source = File('lib/web/web_ordens_v3_page.dart').readAsStringSync();

    expect(source, contains('web_os_cancelamento_v5_service.dart'));
    expect(source, contains('WebOsCancelamentoV5Service.instance'));
    expect(source, contains('Future<void> _cancelar'));
    expect(source, contains("status != 'Aberta' && status != 'Em andamento'"));
    expect(source, contains('OS finalizada exige estorno/correção.'));
    expect(source, contains('Motivo do cancelamento *'));
    expect(source, contains('Confirmar cancelamento'));
    expect(source, contains('liberadas e o'));
    expect(source, contains('editavel ? () => _cancelar(os) : null'));
    expect(source, contains('_cancelamento.cancelar'));
    expect(source, contains('Cancelar OS com transação segura'));
  });
}
