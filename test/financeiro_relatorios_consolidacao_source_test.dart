import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relatórios financeiros possuem uma única tela oficial', () {
    final oficial = File('lib/screens/relatorios_financeiros_page.dart');
    final temporario = File(
      'lib/screens/relatorios_financeiros_page_corrigido.dart',
    );

    expect(oficial.existsSync(), isTrue);
    expect(temporario.existsSync(), isFalse);

    final fonte = oficial.readAsStringSync();
    expect(fonte, isNotEmpty);
  });
}
