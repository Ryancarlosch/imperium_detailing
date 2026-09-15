import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('servico de funcionario usa Edge Function autenticada', () {
    final source = File(
      'lib/services/funcionario_conta_service.dart',
    ).readAsStringSync();

    expect(source, contains("functions.invoke("));
    expect(source, contains("'imperium-funcionario-conta'"));
    expect(source, contains("'Authorization': 'Bearer \${session.accessToken}'"));
    expect(source, contains("'enviar_email': true"));
    expect(source, isNot(contains("'password'")));
    expect(source, isNot(contains("'senha'")));
  });

  test('tela do administrador libera funcionario por email e senha', () {
    final source = File(
      'lib/screens/funcionarios_acesso_nuvem_page.dart',
    ).readAsStringSync();

    expect(source, contains('FuncionarioContaService.instance'));
    expect(source, contains('_contaService.prepararAcessoAdmin'));
    expect(source, contains('Liberar acesso'));
    expect(source, contains('definir a própria senha'));
    expect(source, contains('Cada funcionário usa o próprio e-mail e senha'));
    expect(source, isNot(contains('usará no Magic Link')));
    expect(source, isNot(contains('O PIN continua local de cada celular')));
  });
}
