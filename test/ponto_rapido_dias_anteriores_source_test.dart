import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ponto rápido de dias anteriores usa jornada programada', () {
    final source = File(
      'lib/screens/ponto_funcionarios_page.dart',
    ).readAsStringSync();

    expect(source, contains('ponto-rapido-dia-anterior-v1'));
    expect(source, contains('ponto-rapido-card-v1'));
    expect(source, contains('_repository.listarJornada()'));
    expect(source, contains('_repository.buscarRegistro('));
    expect(source, contains('_repository.salvarRegistro('));
    expect(source, contains("situacao: 'Trabalhado'"));
    expect(source, contains("lastDate: ontem"));
    expect(source, contains('Ponto rápido conforme jornada programada'));
  });
}
