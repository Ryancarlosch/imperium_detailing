import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dashboard tem menu hamburguer e privacidade', () {
    final source = File('lib/screens/dashboard_page.dart').readAsStringSync();

    expect(source, contains('dashboard-hamburguer-explicito-v2'));
    expect(source, contains('drawer: _DashboardMenuV2('));
    expect(source, contains('dashboard-privacidade-v2'));
    expect(source, contains('dashboard-olho-topo-v2'));
    expect(source, contains('dashboard-graficos-ocultos-v2'));
    expect(source, contains("'Fluxo de caixa'"));
    expect(source, contains("'Movimentações'"));
    expect(source, contains("'DRE'"));
  });
}
