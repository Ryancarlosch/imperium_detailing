import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gestao Web V2 consulta estoque e financeiro Cloud', () {
    final source = File(
      'lib/services/web_cloud_gestao_service.dart',
    ).readAsStringSync();

    expect(source, contains("imperium_estoque_itens"));
    expect(source, contains("imperium_estoque_alertas"));
    expect(source, contains("imperium_financeiro_contas"));
    expect(source, contains("imperium_financeiro_movimentos"));
    expect(source, contains("imperium_financeiro_pagamentos_os"));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('Nova OS Web cria apenas OS aberta e itens remotos', () {
    final source = File(
      'lib/services/web_cloud_gestao_service.dart',
    ).readAsStringSync();

    expect(source, contains("status': 'Aberta'"));
    expect(source, contains("from('imperium_ordens_servico')"));
    expect(source, contains("from('imperium_ordem_servico_itens')"));
    expect(source, contains('valor_total'));
    expect(source, contains('status_pagamento'));
    expect(source, isNot(contains("status': 'Finalizada'")));
  });

  test('Paginas Web V2 incluem Nova OS Estoque Financeiro', () {
    final source = File('lib/web/web_gestao_pages.dart').readAsStringSync();

    expect(source, contains('class WebNovaOrdemPage'));
    expect(source, contains('class WebEstoquePage'));
    expect(source, contains('class WebFinanceiroPage'));
    expect(source, contains('Criar OS aberta'));
    expect(source, contains('Estoque Cloud'));
    expect(source, contains('Financeiro Cloud'));
  });

  test('Shell Web navega para modulos V2 atuais', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains("import 'web_gestao_pages.dart';"));
    expect(source, contains("import 'web_estoque_gestao_page.dart';"));
    expect(source, contains("import 'web_financeiro_lancamentos_page.dart';"));
    expect(source, contains("'Nova OS'"));
    expect(source, contains("'Estoque'"));
    expect(source, contains("'Financeiro'"));
    expect(source, contains('WebNovaOrdemPage'));
    expect(source, contains('WebEstoqueGestaoPage'));
    expect(source, contains('WebFinanceiroLancamentosPage'));
  });

  test('Android e schema permanecem preservados', () {
    final main = File('lib/main.dart').readAsStringSync();
    final db = File('lib/database/app_database.dart').readAsStringSync();

    expect(
      main,
      contains('OperacionalSyncService.instance.prepararTenantInicial'),
    );
    expect(db, contains('static const int schemaVersion = 33;'));
  });
}
