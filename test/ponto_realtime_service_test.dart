import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Meu Ponto integra atualização Realtime com fallback seguro', () {
    final page = File('lib/screens/meu_ponto_page.dart').readAsStringSync();
    final service = File(
      'lib/services/ponto_realtime_service.dart',
    ).readAsStringSync();

    expect(page, contains('PontoRealtimeService.instance'));
    expect(page, contains('assinarColaborador'));
    expect(page, contains('unawaited(_realtime.cancelar())'));

    expect(service, contains("table: 'ponto_registros'"));
    expect(service, contains("column: 'colaborador_id'"));
    expect(service, contains('Duration(milliseconds: 400)'));
    expect(service, contains('empresaAtualId()'));
    expect(service, contains('remotoIdPorLocal('));
  });
}
