import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('otimizacao financeira v1 preserva regras e marcadores', () {
    final home = File('lib/screens/financeiro_page.dart').readAsStringSync();
    final lancamento = File(
      'lib/screens/lancamento_financeiro_page.dart',
    ).readAsStringSync();
    final transferencia = File(
      'lib/screens/transferencia_financeira_page.dart',
    ).readAsStringSync();
    final movimentos = File(
      'lib/screens/movimentacoes_financeiras_page.dart',
    ).readAsStringSync();
    final fluxo = File('lib/screens/fluxo_caixa_page.dart').readAsStringSync();
    final conta = File(
      'lib/repositories/conta_financeira_repository.dart',
    ).readAsStringSync();
    final fluxoRepo = File(
      'lib/repositories/fluxo_caixa_repository.dart',
    ).readAsStringSync();
    final banco = File('lib/database/app_database.dart').readAsStringSync();

    expect(home, contains('financeiro-home-limpo-v1'));
    expect(home, contains('financeiro-privacidade-v1'));
    expect(home, contains('financeiro-kpis-semantica-v1'));
    expect(home, contains('financeiro-acoes-rapidas-v1'));
    expect(home, contains('financeiro-gestao-expansivel-v1'));

    expect(lancamento, contains('financeiro-lancamento-unificado-v1'));
    expect(lancamento, contains('financeiro-lancamento-modo-v1'));
    expect(lancamento, contains('financeiro-lancamento-detalhes-v1'));
    expect(transferencia, contains('financeiro-transferencia-rapida-v1'));
    expect(movimentos, contains('financeiro-movimentacoes-compactas-v1'));
    expect(fluxo, contains('fluxo-caixa-ui-limpa-v1'));

    expect(conta, contains('financeiro-saldo-snapshot-v1'));
    expect(conta, contains('financeiro-extrato-snapshot-v1'));
    expect(conta, contains('financeiro-conciliacao-snapshot-v1'));
    expect(conta, contains('conciliacao-remocao-segura-v1'));

    expect(fluxoRepo, contains('fluxo-saldo-snapshot-v1'));
    expect(fluxoRepo, contains('fluxo-snapshot-resumo-v1'));
    expect(fluxoRepo, contains('fluxo-snapshot-diario-v1'));
    expect(fluxoRepo, contains('fluxo-snapshot-mensal-v1'));

    expect(banco, contains('financeiro-conciliacao-schema-v1'));
    expect(banco, contains('static const int schemaVersion = 33;'));

    final drePage = File('lib/screens/dre_page.dart').readAsStringSync();
    final dreServiceFile = File('lib/services/dre_pdf_service.dart');
    final dreService = dreServiceFile.existsSync()
        ? dreServiceFile.readAsStringSync()
        : '';
    expect(
      drePage.contains('dre-pdf-ui-v1') ||
          drePage.contains('dre-pdf-appbar-v1') ||
          dreService.contains('dre-pdf-detalhado-v1'),
      isTrue,
    );
  });
}
