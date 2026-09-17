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

  test('Meu Ponto retoma Realtime ao voltar ao primeiro plano', () {
    final page = File('lib/screens/meu_ponto_page.dart').readAsStringSync();

    expect(page, contains('with WidgetsBindingObserver'));
    expect(page, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(page, contains('didChangeAppLifecycleState'));
    expect(page, contains('AppLifecycleState.resumed'));
    expect(page, contains('unawaited(_retomarSincronizacao())'));
    expect(page, contains('await _iniciarRealtime()'));
    expect(page, contains('await _carregar()'));
    expect(page, contains('WidgetsBinding.instance.removeObserver(this)'));
  });
}
