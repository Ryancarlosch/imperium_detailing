import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('servico de auth usa email e senha do Supabase', () {
    final source = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(source, contains('signInWithPassword'));
    expect(source, contains('E-mail ou senha incorretos.'));
    expect(source, isNot(contains('signInWithOtp')));
  });

  test('web usa login por email e senha', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('entrarComEmailSenha'));
    expect(source, contains("labelText: 'Senha'"));
    expect(source, contains('mesmo e-mail e senha'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
  });

  test('mobile aponta para a nova tela de login cloud', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final loginSource = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();

    expect(mainSource, contains("import 'screens/login_email_senha_page.dart';"));
    expect(mainSource, contains('LoginEmailSenhaPage'));
    expect(loginSource, contains('entrarComEmailSenha'));
    expect(loginSource, contains("labelText: 'E-mail'"));
    expect(loginSource, contains("labelText: 'Senha'"));
    expect(loginSource, contains('Funcionários são criados e administrados'));
  });
}
