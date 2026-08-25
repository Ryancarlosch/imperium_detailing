import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conciliação bancária possui remoção segura e confirmação final', () {
    final repository = File(
      'lib/repositories/conta_financeira_repository.dart',
    ).readAsStringSync();

    final tela = File('lib/screens/extrato_conta_page.dart').readAsStringSync();

    expect(repository, contains('conciliacao-remocao-segura-v1'));
    expect(repository, contains('removerConciliacaoConta'));
    expect(repository, contains("'Conciliação de conta'"));
    expect(repository, contains("'movimentos_financeiros'"));
    expect(repository, contains("'financeiro_conciliacoes_conta'"));

    expect(tela, contains('conciliacao-remover-ui-v1'));
    expect(tela, contains("tooltip: 'Remover conciliação'"));
    expect(tela, contains('conciliacao-confirmacao-final-v1'));
    expect(tela, contains('Voltar e revisar'));
    expect(tela, contains('verifique completamente'));
  });
}
