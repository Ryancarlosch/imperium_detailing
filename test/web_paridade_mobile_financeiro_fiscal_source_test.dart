import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web fiscal esta conectado ao workspace e usa XML cloud', () {
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final fiscal = File('lib/web/web_fiscal_page.dart').readAsStringSync();
    final service = File('lib/services/web_fiscal_service.dart').readAsStringSync();

    expect(shell, contains("import 'web_fiscal_page.dart';"));
    expect(shell, contains('25 => WebFiscalPage('));
    expect(shell, contains("titulo: 'Notas fiscais'"));
    expect(fiscal, contains("allowedExtensions: const ['xml']"));
    expect(fiscal, contains('WebFiscalService.instance'));
    expect(service, contains('imperium_fiscal_notas_entrada'));
  });

  test('Gestao financeira web cobre rotinas administrativas do mobile', () {
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final page = File(
      'lib/web/web_financeiro_administracao_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_financeiro_administracao_service.dart',
    ).readAsStringSync();

    expect(shell, contains('26 => WebFinanceiroAdministracaoPage('));
    for (final marker in [
      'Fornecedores',
      'Regras da maquininha',
      'Custos fixos',
      'Metas financeiras',
      'Plano de contas',
      'Custos de mão de obra',
      'Previsto x realizado',
      'Transferir',
    ]) {
      expect(page, contains(marker));
    }

    for (final tabela in [
      'imperium_financeiro_fornecedores',
      'imperium_financeiro_regras_taxa',
      'imperium_financeiro_custos_fixos',
      'imperium_financeiro_metas',
      'imperium_financeiro_plano_contas',
      'imperium_precificacao_colaboradores_custo',
    ]) {
      expect(service, contains(tabela));
    }

    expect(service, contains("'imperium_financeiro_transferir_web'"));
  });

  test('Transferencia web e atomica, invoker e nao impacta DRE', () {
    final sql = File(
      'supabase/migrations/20260919185308_financeiro_web_transferencia_atomica.sql',
    ).readAsStringSync();

    expect(sql, contains('security invoker'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('grant execute on function'));
    expect(sql, contains("'Saída'"));
    expect(sql, contains("'Entrada'"));
    expect(sql, contains("'Transferência'"));
    expect(sql, contains('impacta_dre'));
    expect(sql, contains('false'));
    expect(sql, isNot(contains('security definer')));
  });

  test('Dashboard oferece atalhos para fiscal e gestao financeira', () {
    final dashboard = File(
      'lib/web/web_dashboard_gerencial_page.dart',
    ).readAsStringSync();

    expect(dashboard, contains("titulo: 'Gestão financeira'"));
    expect(dashboard, contains('widget.onNavigate?.call(26)'));
    expect(dashboard, contains("titulo: 'Notas fiscais'"));
    expect(dashboard, contains('widget.onNavigate?.call(25)'));
  });
}
