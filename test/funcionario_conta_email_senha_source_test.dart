import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conta cloud da empresa aceita somente admin ou proprietario', () {
    final source = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains("papel != 'admin' && papel != 'proprietario'"));
    expect(source, contains('Funcionários continuam como'));
  });

  test('tela de funcionarios usa usuarios internos e permissoes', () {
    final source = File(
      'lib/screens/funcionarios_acesso_nuvem_page.dart',
    ).readAsStringSync();

    expect(source, contains('Funcionários ficam dentro da empresa'));
    expect(source, contains('Gerenciar usuários e permissões'));
    expect(source, contains('UsuariosPermissoesPage'));
    expect(source, isNot(contains('FuncionarioContaService')));
    expect(source, isNot(contains('prepararAcessoAdmin')));
    expect(
      source,
      isNot(contains('Cada funcionário usa o próprio e-mail e senha')),
    );
  });
}
