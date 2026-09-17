import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('financeiro web expoe correcao e devolucao somente para pagamento pago', () {
    final card = File(
      'lib/widgets/web_financeiro_pagamentos_card.dart',
    ).readAsStringSync();
    final page = File(
      'lib/web/web_financeiro_lancamentos_page.dart',
    ).readAsStringSync();

    expect(card, contains('listarPagamentosOs()'));
    expect(card, contains('WebFinanceiroEstornoService.instance'));
    expect(card, contains('WebFinanceiroEstornoModo.correcao'));
    expect(card, contains('WebFinanceiroEstornoModo.devolucao'));
    expect(card, contains('Correção de lançamento'));
    expect(card, contains('Devolução ao cliente'));
    expect(card, contains("status == 'Pago'"));
    expect(card, contains('_estorno.estornar('));
    expect(card, contains('Somente pagamentos confirmados'));

    expect(
      page,
      contains("import '../widgets/web_financeiro_pagamentos_card.dart';"),
    );
    expect(
      page,
      contains('WebFinanceiroPagamentosCard(onChanged: _recarregar)'),
    );
  });
}
