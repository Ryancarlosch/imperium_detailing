import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relatórios web usam cloud e contrato monetário único da OS', () {
    final service = File(
      'lib/services/web_cloud_relatorios_service.dart',
    ).readAsStringSync();
    final page = File('lib/web/web_relatorios_page.dart').readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
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

    expect(workspace, contains("import 'web_relatorios_page.dart';"));
    expect(workspace, contains('Relatórios gerenciais'));
    expect(workspace, contains('WebRelatoriosPage'));
  });
}
