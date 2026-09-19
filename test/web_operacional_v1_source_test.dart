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

  test('Sistema completo mantém módulos gerenciais dentro do workspace', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();
    final dre = File('lib/web/web_dre_page.dart').readAsStringSync();
    final contas = File(
      'lib/web/web_contas_financeiras_page.dart',
    ).readAsStringSync();
    final relatorios = File(
      'lib/web/web_relatorios_page.dart',
    ).readAsStringSync();

    expect(source, contains('isDrawerOpen == true'));
    expect(source, isNot(contains('_paginaRoteada')));
    expect(source, contains('10 => WebDrePage('));
    expect(source, contains('11 => WebContasFinanceirasPage('));
    expect(source, contains('12 => WebRelatoriosPage('));
    expect(source, contains('16 => WebPontoPage('));
    expect(source, contains('embedded: true'));
    expect(dre, contains('this.embedded = false'));
    expect(contas, contains('this.embedded = false'));
    expect(relatorios, contains('this.embedded = false'));
    expect(source, isNot(contains('fecharMenu && Navigator.canPop(context)')));
  });

  test(
    'Entrypoint abre workspace premium multiempresa com login compartilhado',
    () {
      final source = File('lib/main_web.dart').readAsStringSync();
      final login = File(
        'lib/screens/login_email_senha_page.dart',
      ).readAsStringSync();
      final auth = File(
        'lib/services/imperium_auth_service.dart',
      ).readAsStringSync();
      final workspace = File(
        'lib/web/web_workspace_shell.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/web/web_operacional_shell.dart',
      ).readAsStringSync();
      final dashboard = File(
        'lib/web/web_dashboard_gerencial_page.dart',
      ).readAsStringSync();

      expect(source, contains('ImperiumWebApp'));
      expect(source, contains('LoginEmailSenhaPage(onLogin: _aoEntrar)'));
      expect(source, contains('CloudSessionService.instance'));
      expect(source, isNot(contains('signInWithOtp')));
      expect(login, contains('entrarComEmailSenha'));
      expect(login, contains("label: 'Senha'"));
      expect(auth, contains('signInWithPassword'));
      expect(source, contains('EmpresaCloudService.instance'));
      expect(source, contains('WebWorkspaceShell'));

      expect(workspace, contains('WebOperacionalShell'));
      expect(workspace, contains("ValueKey('workspace-\$empresaAtualId')"));
      expect(workspace, isNot(contains('WebDashboardGerencialPage')));
      expect(workspace, isNot(contains('_abrirSistemaCompleto')));
      expect(workspace, isNot(contains('Abrir sistema completo')));

      expect(shell, contains('WebDashboardGerencialPage'));
      expect(shell, contains('Icons.menu_rounded'));
      expect(shell, contains('ExpansionTile'));
      expect(shell, isNot(contains('abrir-sistema-completo-marca')));

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
    },
  );

  test('Android e schema preservam base operacional', () {
    final main = File('lib/main.dart').readAsStringSync();
    final db = File('lib/database/app_database.dart').readAsStringSync();

    expect(
      main,
      contains('OperacionalSyncService.instance.prepararTenantInicial'),
    );
    expect(main, contains('LoginEmailSenhaPage'));
    expect(db, contains('static const int schemaVersion = 33;'));
  });
}
