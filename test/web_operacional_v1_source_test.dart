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
    expect(source, contains("imperium_ordens_servico"));
    expect(source, contains('OrdemServicoValor.valorNegociado'));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('Shell Web possui modulos operacionais', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    for (final marker in [
      'Dashboard',
      'Clientes',
      'Veículos',
      'Agenda',
      'Ordens de serviço',
      'Novo cliente',
      'Novo veículo',
      'Novo agendamento',
      'Faturamento do mês',
      'A receber em OS',
    ]) {
      expect(source, contains(marker));
    }
  });

  test('Entrypoint abre workspace premium multiempresa com Magic Link', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
    ).readAsStringSync();
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
    expect(dashboard, contains('Saldo consolidado'));
    expect(dashboard, contains('Vendas líquidas'));
    expect(dashboard, contains('A receber'));
    expect(dashboard, contains('Ticket médio'));
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
