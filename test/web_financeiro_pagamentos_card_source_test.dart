import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'card financeiro oferece correcao e devolucao apenas para pagamento pago',
    () {
      final card = File(
        'lib/widgets/web_financeiro_pagamentos_card.dart',
      ).readAsStringSync();
      final page = File(
        'lib/web/web_financeiro_lancamentos_page.dart',
      ).readAsStringSync();

      expect(card, contains('Pagamentos de OS'));
      expect(card, contains('Correção de lançamento'));
      expect(card, contains('Devolução ao cliente'));
      expect(card, contains('listarPagamentosOs'));
      expect(card, contains('WebFinanceiroEstornoService.instance'));
      expect(card, contains("status == 'Pago'"));
      expect(card, contains('Corrigir ou devolver pagamento'));
      expect(
        page,
        contains("import '../widgets/web_financeiro_pagamentos_card.dart';"),
      );
      expect(
        page,
        contains('WebFinanceiroPagamentosCard(onChanged: _recarregar)'),
      );
    },
  );
}
