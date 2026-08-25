import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ponto rapido protege BuildContext antes do dialogo', () {
    final source = File(
      'lib/screens/ponto_funcionarios_page.dart',
    ).readAsStringSync();

    final marker = source.indexOf('ponto-rapido-context-mounted-v3');
    expect(marker, greaterThanOrEqualTo(0));

    final title = source.indexOf('Lançar ponto rápido?', marker);
    expect(title, greaterThan(marker));

    final trecho = source.substring(marker, title);

    expect(trecho, contains('if (!mounted)'));
    expect(trecho, contains('return;'));
    expect(trecho, contains('showDialog'));
  });
}
