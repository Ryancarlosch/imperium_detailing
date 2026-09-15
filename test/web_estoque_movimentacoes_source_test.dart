import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque Web usa RPC transacional com origem idempotente', () {
    final source = File(
      'lib/services/web_estoque_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('imperium_estoque_movimentar_web'));
    expect(source, contains('WebOrigemService.instance.proxima()'));
    expect(source, contains("'p_origem_dispositivo': origem.dispositivoId"));
    expect(source, contains("'p_origem_local_id': origem.localId"));
    expect(source, contains("'SAIDA'"));
    expect(source, contains("'AJUSTE'"));
  });

  test('Tela de estoque Web exibe reservas FIFO e movimentacoes', () {
    final source = File(
      'lib/web/web_estoque_movimentacoes_page.dart',
    ).readAsStringSync();

    expect(source, contains('class WebEstoqueMovimentacoesPage'));
    expect(source, contains('Nova movimentação'));
    expect(source, contains('Reservado OS'));
    expect(source, contains('Disponível'));
    expect(source, contains('FIFO'));
    expect(source, contains('Movimentações recentes'));
  });

  test('Menu Web aponta Estoque para pagina transacional', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains("import 'web_estoque_gestao_page.dart';"));
    expect(source, contains('8 => WebEstoqueGestaoPage('));
  });

  test('Migration de estoque protege reserva e consome lotes FIFO', () {
    final source = File(
      'supabase/migrations/'
      '20260915144500_estoque_web_movimentacao_transacional.sql',
    ).readAsStringSync();

    expect(source, contains('imperium_estoque_movimentar_web'));
    expect(source, contains('imperium_estoque_reservas_os'));
    expect(source, contains('order by l.data_compra asc'));
    expect(source, contains("v_tipo not in ('ENTRADA', 'SAIDA', 'AJUSTE')"));
    expect(source, contains("origem_dispositivo = trim(p_origem_dispositivo)"));
    expect(source, contains('security definer'));
  });
}
