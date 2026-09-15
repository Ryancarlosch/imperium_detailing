import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cadastro Web de produto usa origem e entrada inicial transacional', () {
    final service = File(
      'lib/services/web_estoque_produtos_service.dart',
    ).readAsStringSync();

    expect(service, contains('imperium_estoque_criar_item_web'));
    expect(service, contains('WebOrigemService.instance.proxima()'));
    expect(service, contains("'p_quantidade_inicial': quantidadeNormalizada"));
    expect(service, contains("'p_valor_total_pago': valorTotalPago"));
  });

  test('Edicao Web de produto usa CAS e nao escreve saldo diretamente', () {
    final service = File(
      'lib/services/web_estoque_produtos_service.dart',
    ).readAsStringSync();

    expect(service, contains('imperium_estoque_atualizar_item_web'));
    expect(service, contains("'p_atualizado_em': atualizadoEm"));
    expect(service, isNot(contains("'quantidade': quantidade")));
  });

  test('Migration protege CAS reservas e OS ativas', () {
    final migration = File(
      'supabase/migrations/'
      '20260915150000_estoque_web_produtos_cas.sql',
    ).readAsStringSync();

    expect(migration, contains('imperium_estoque_criar_item_web'));
    expect(migration, contains('imperium_estoque_atualizar_item_web'));
    expect(migration, contains("errcode = '40001'"));
    expect(migration, contains('imperium_estoque_reservas_os'));
    expect(migration, contains('imperium_ordem_servico_produtos'));
    expect(migration, contains('imperium_estoque_movimentar_web'));
  });

  test('Estoque Web separa movimentacao e cadastro de produtos', () {
    final page = File(
      'lib/web/web_estoque_gestao_page.dart',
    ).readAsStringSync();

    expect(page, contains('WebEstoqueMovimentacoesPage'));
    expect(page, contains('WebEstoqueProdutosPage'));
    expect(page, contains('Saldo e movimentações'));
    expect(page, contains('Cadastro de produtos'));
  });

  test('Menu Web abre a gestao completa de estoque', () {
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();

    expect(shell, contains("import 'web_estoque_gestao_page.dart';"));
    expect(shell, contains('8 => WebEstoqueGestaoPage('));
  });
}
