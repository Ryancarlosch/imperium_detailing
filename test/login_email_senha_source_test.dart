import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Login principal usa email e senha na Web e no app', () {
    final main = File('lib/main.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final auth = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(main, contains('LoginEmailSenhaPage'));
    expect(login, contains('Use o mesmo e-mail e senha'));
    expect(auth, contains('signInWithPassword'));
    expect(auth, contains('criarContaComEmailSenha'));
    expect(auth, contains('signUp'));
  });

  test('Primeiro acesso da empresa nao depende mais de magic link ou PIN', () {
    final source = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();

    expect(source, contains('Criar conta e ativar empresa'));
    expect(source, contains('CloudSessionService'));
    expect(source, contains('criarContaComEmailSenha'));
    expect(source, contains('entrarComEmailSenha'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
    expect(source, isNot(contains('Criar PIN')));
  });
}
