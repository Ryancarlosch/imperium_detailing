import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Central Gerencial reutiliza motores existentes e não cria banco paralelo',
    () {
      final source = File(
        'lib/repositories/central_gerencial_repository.dart',
      ).readAsStringSync();

      expect(source, contains('DashboardRepository'));
      expect(source, contains('DreRepository'));
      expect(source, contains('FinanceiroDashboardRepository'));
      expect(source, contains('PrecificacaoRepository'));
      expect(source, contains('CrmOperacaoRepository'));
      expect(source, contains('PontoRepository'));
      expect(source, isNot(contains('CREATE TABLE')));
      expect(source, isNot(contains('ALTER TABLE')));
    },
  );

  test('Central Gerencial mostra comparação, alertas, estoque e equipe', () {
    final source = File(
      'lib/screens/central_gerencial_page.dart',
    ).readAsStringSync();

    expect(source, contains('Visão executiva do negócio'));
    expect(source, contains('Alertas gerenciais'));
    expect(source, contains('Financeiro e estrutura'));
    expect(source, contains('Operação, estoque e equipe'));
    expect(source, contains('Serviços com maior receita'));
    expect(source, contains('Evolução mensal'));
  });

  test('Dashboard expõe a Central Gerencial no menu financeiro', () {
    final source = File('lib/screens/dashboard_page.dart').readAsStringSync();

    expect(source, contains("import 'central_gerencial_page.dart';"));
    expect(source, contains("'Central Gerencial'"));
    expect(source, contains('CentralGerencialPage'));
  });
}
