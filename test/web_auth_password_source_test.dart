import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('servico de auth usa email senha e recuperacao do Supabase', () {
    final source = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(source, contains('signInWithPassword'));
    expect(source, contains('resetPasswordForEmail'));
    expect(source, contains('UserAttributes(password: senha)'));
    expect(source, contains('E-mail ou senha incorretos.'));
    expect(source, isNot(contains('signInWithOtp')));
  });

  test('web usa login por email senha e permite redefinir senha', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('entrarComEmailSenha'));
    expect(source, contains("'Criar senha' : 'Senha'"));
    expect(source, contains('mesmo e-mail e senha'));
    expect(source, contains('Esqueci minha senha'));
    expect(source, contains('AuthChangeEvent.passwordRecovery'));
    expect(source, contains('Salvar nova senha'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
  });

  test('web permite primeiro acesso da empresa', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('criarContaComEmailSenha'));
    expect(source, contains('Primeiro acesso da empresa'));
    expect(source, contains('Criar conta e ativar empresa'));
    expect(source, contains('e-mail informado na assinatura ou no convite'));
    expect(source, contains("labelText: 'E-mail da empresa'"));
  });

  test('mobile aponta para a nova tela de login da empresa', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final loginSource = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();

    expect(
      mainSource,
      contains("import 'screens/login_email_senha_page.dart';"),
    );
    expect(mainSource, contains('LoginEmailSenhaPage'));
    expect(loginSource, contains('entrarComEmailSenha'));
    expect(loginSource, contains('enviarRecuperacaoSenha'));
    expect(loginSource, contains("labelText: 'E-mail da empresa'"));
    expect(loginSource, contains("labelText: 'Senha'"));
    expect(loginSource, contains('Funcionários ficam cadastrados dentro da empresa'));
    expect(loginSource, isNot(contains('FuncionarioPrimeiroAcessoPage')));
  });
}
