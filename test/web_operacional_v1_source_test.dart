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

  test('Entrypoint abre shell multiempresa', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('ImperiumWebApp'));
    expect(source, contains('signInWithPassword'));
    expect(source, contains('EmpresaCloudService.instance'));
    expect(source, contains('WebOperacionalShell'));
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
