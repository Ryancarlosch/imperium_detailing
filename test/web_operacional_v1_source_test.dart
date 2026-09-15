import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web operacional usa Supabase online first', () {
    final source = File(
      'lib/services/web_cloud_operacional_service.dart',
    ).readAsStringSync();

    expect(source, contains("from('imperium_clientes')"));
    expect(source, contains("from('imperium_veiculos')"));
    expect(source, contains("from('imperium_agendamentos')"));
    expect(source, contains('imperium_ordens_servico'));
    expect(source, contains('OrdemServicoValor.valorNegociado'));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('Shell Web possui menu agrupado com todos os modulos', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    for (final marker in [
      'WebDashboardGerencialPage',
      'Icons.menu_rounded',
      'ExpansionTile',
      'Dashboard',
      'Operação',
      'Clientes',
      'Veículos',
      'Agenda',
      'Ordens de serviço',
      'Nova OS',
      'Financeiro',
      'Fluxo de caixa',
      'DRE',
      'Contas bancárias',
      'Relatórios',
      'Estoque',
      'Comercial',
      'CRM',
      'Orçamentos',
      'Precificação',
      'Equipe',
      'Ponto e funcionários',
      'Administração',
      'Central Cloud',
      'Novo cliente',
      'Novo veículo',
      'Novo agendamento',
    ]) {
      expect(source, contains(marker));
    }
  });

  test('Entrypoint abre workspace premium multiempresa com Magic Link', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
    ).readAsStringSync();
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final dashboard = File(
      'lib/web/web_dashboard_gerencial_page.dart',
    ).readAsStringSync();

    expect(source, contains('ImperiumWebApp'));
    expect(source, contains('signInWithOtp'));
    expect(source, contains('shouldCreateUser: false'));
    expect(source, isNot(contains('signInWithPassword')));
    expect(source, contains('EmpresaCloudService.instance'));
    expect(source, contains('WebWorkspaceShell'));

    expect(workspace, contains('WebDashboardGerencialPage'));
    expect(workspace, contains('WebOperacionalShell'));
    expect(workspace, contains('Sistema completo'));
    expect(workspace, contains("Text('Módulos')"));
    expect(workspace, contains('dashboard-premium-'));
    expect(workspace, contains('Trocar empresa'));

    expect(shell, contains('WebDashboardGerencialPage'));
    expect(shell, contains('Icons.menu_rounded'));
    expect(shell, contains('ExpansionTile'));
    expect(shell, isNot(contains('Sistema completo')));

    for (final marker in [
      'Dashboard executivo',
      'Saldo consolidado',
      'Vendas líquidas',
      'A receber',
      'Ticket médio',
      'Clientes ativos',
      'Veículos',
      'Acesso rápido',
      'Contas e caixa',
      'DRE gerencial',
      'Ponto e equipe',
      'Desempenho da equipe',
    ]) {
      expect(dashboard, contains(marker));
    }

    expect(source, isNot(contains('dashboard_page.dart')));
  });

  test('Android e schema nao foram alterados pelo lote', () {
    final main = File('lib/main.dart').readAsStringSync();
    final db = File('lib/database/app_database.dart').readAsStringSync();

    expect(
      main,
      contains('OperacionalSyncService.instance.prepararTenantInicial'),
    );
    expect(db, contains('static const int schemaVersion = 33;'));
  });
}
