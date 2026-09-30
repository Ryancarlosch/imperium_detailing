import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web expoe galeria a partir do historico do veiculo', () {
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final fotos = File('lib/web/web_fotos_page.dart').readAsStringSync();

    expect(shell, contains("label: const Text('Abrir galeria')"));
    expect(shell, contains('WebFotosPage('));
    expect(shell, contains('veiculoIdInicial:'));
    expect(fotos, contains('this.veiculoIdInicial'));
    expect(fotos, contains("e['veiculo_id']?.toString() != veiculoInicial"));
    expect(fotos, contains("ordem['veiculo_id']?.toString() != veiculoInicial"));
  });
}
