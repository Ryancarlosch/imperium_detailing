import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contas web respeitam empresa snapshot e movimentos realizados', () {
    final service = File(
      'lib/services/web_cloud_contas_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/web/web_contas_financeiras_page.dart',
    ).readAsStringSync();
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final dashboard = File(
      'lib/web/web_dashboard_gerencial_page.dart',
    ).readAsStringSync();

    expect(service, contains("from('imperium_financeiro_contas')"));
    expect(service, contains("from('imperium_financeiro_movimentos')"));
    expect(service, contains("from('imperium_financeiro_conciliacoes')"));
    expect(service, contains(".eq('empresa_id', empresaId)"));
    expect(service, contains(".eq('status', 'Realizado')"));
    expect(service, contains("conta['data_saldo_inicial']"));
    expect(service, contains('snapshotDepoisDoPeriodo'));
    expect(service, contains('obterComparativo'));

    expect(page, contains('class WebContasFinanceirasPage'));
    expect(page, contains('class WebExtratoContaPage'));
    expect(page, contains('Saldo consolidado'));
    expect(page, contains('Mês anterior × mês atual'));
    expect(page, contains('Extrato do mês'));
    expect(page, contains('Conciliações registradas'));

    expect(shell, contains("import 'web_contas_financeiras_page.dart';"));
    expect(shell, contains("titulo: 'Contas bancárias'"));
    expect(shell, contains('WebContasFinanceirasPage'));
    expect(dashboard, contains("titulo: 'Contas e caixa'"));
  });
}
