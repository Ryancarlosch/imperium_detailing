import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Atalhos do dashboard abrem modulo sem Scaffold intermediario', () {
    final source = File(
      'lib/web/web_dashboard_gerencial_page.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> _abrirModulo'));
    expect(source, contains('settings: RouteSettings(name: titulo)'));
    expect(source, contains('builder: (context) => pagina'));
    expect(source, isNot(contains('body: pagina')));
    expect(source, isNot(contains('appBar: AppBar(title: Text(titulo)')));
  });
}
