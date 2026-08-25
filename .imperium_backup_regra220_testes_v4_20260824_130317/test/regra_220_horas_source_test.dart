import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('220 horas tem a mesma semantica no sistema', () {
    final regra = File(
      'lib/config/imperium_regras_negocio.dart',
    ).readAsStringSync();
    final ponto = File(
      'lib/repositories/ponto_repository.dart',
    ).readAsStringSync();
    final custos = File(
      'lib/repositories/custos_repository.dart',
    ).readAsStringSync();
    final prec = File(
      'lib/repositories/precificacao_repository.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/custo_servicos_page.dart',
    ).readAsStringSync();
    expect(regra, contains('horasMensaisPadrao = 220.0'));
    expect(ponto, contains('ponto-base-mensal-220-v2'));
    expect(custos, contains('custos-base-220-v2'));
    expect(prec, contains('precificacao-forcar-220-v2'));
    expect(tela, contains('precificacao-horas-220-readonly-v2'));
    expect(tela, isNot(contains('3 pessoas × 220h = 660h')));
  });
}
