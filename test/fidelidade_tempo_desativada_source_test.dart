import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fidelidade por tempo esta bloqueada', () {
    final repo = File(
      'lib/repositories/fidelidade_repository.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/custo_servicos_page.dart',
    ).readAsStringSync();
    expect(repo, contains('kFidelidadeTempoTemporariamenteDesativada = true'));
    expect(repo, contains('fidelidade-tempo-avaliacao-bloqueada-v1'));
    expect(tela, contains('fidelidade-tempo-ui-bloqueada-v1'));
  });
}
