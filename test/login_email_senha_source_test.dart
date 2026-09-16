import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Login principal usa email e senha da empresa na Web e no app', () {
    final main = File('lib/main.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final auth = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(main, contains('LoginEmailSenhaPage'));
    expect(login, contains('Acesse sua empresa com o mesmo e-mail e senha'));
    expect(login, contains("labelText: 'E-mail da empresa'"));
    expect(login, contains('Começar 30 dias grátis'));
    expect(login, contains('Funcionários ficam cadastrados dentro da empresa'));
    expect(auth, contains('signInWithPassword'));
    expect(auth, contains('criarContaComEmailSenha'));
    expect(auth, contains('signUp'));
  });

  test('Primeiro acesso cria conta gratis sem magic link ou PIN', () {
    final source = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();

    expect(source, contains('Criar conta grátis'));
    expect(source, contains('Teste o Imperium grátis por 30 dias'));
    expect(source, contains('CloudSessionService'));
    expect(source, contains('criarContaComEmailSenha'));
    expect(source, contains('entrarComEmailSenha'));
    expect(source, contains("labelText: 'Seu e-mail'"));
    expect(source, contains('Confirme o e-mail'));
    expect(source, contains('30 dias grátis'));
    expect(source, contains('Não é necessária autorização prévia'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
    expect(source, isNot(contains('Criar PIN')));
  });

  test('Conta na nuvem nao oferece segundo login por magic link', () {
    final source = File(
      'lib/screens/supabase_conta_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Enviar Magic Link')));
    expect(source, contains('login principal do Imperium com e-mail e senha'));
    expect(source, contains('Plano e assinatura'));
    expect(source, contains("client.rpc('imperium_autocadastro_empresa')"));
  });
}
