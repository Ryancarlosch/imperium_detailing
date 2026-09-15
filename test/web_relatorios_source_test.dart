import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relatórios web usam cloud e contrato monetário único da OS', () {
    final service = File(
      'lib/services/web_cloud_relatorios_service.dart',
    ).readAsStringSync();
    final page = File('lib/web/web_relatorios_page.dart').readAsStringSync();
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final dashboard = File(
      'lib/web/web_dashboard_gerencial_page.dart',
    ).readAsStringSync();

    expect(service, contains('WebCloudDreService.instance.calcular'));
    expect(service, contains('WebDreRegime.competencia'));
    expect(service, contains('WebDreRegime.caixa'));
    expect(service, contains("from('imperium_ordens_servico')"));
    expect(service, contains('OrdemServicoValor.valorNegociadoDeMapa'));
    expect(service, contains(".eq('empresa_id', empresaId)"));
    expect(service, contains(".isFilter('excluido_em', null)"));

    expect(page, contains('class WebRelatoriosPage'));
    expect(page, contains('showDateRangePicker'));
    expect(page, contains('Vendas líquidas'));
    expect(page, contains('Competência × caixa'));
    expect(page, contains('Desempenho por executor'));

    expect(shell, contains("import 'web_relatorios_page.dart';"));
    expect(shell, contains("titulo: 'Relatórios'"));
    expect(shell, contains('WebRelatoriosPage'));
    expect(dashboard, contains("titulo: 'Relatórios'"));
  });
}
