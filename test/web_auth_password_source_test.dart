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

  test('web e mobile usam a mesma tela de login da empresa', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final mobile = File('lib/main.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();

    expect(web, contains("import 'screens/login_email_senha_page.dart';"));
    expect(mobile, contains("import 'screens/login_email_senha_page.dart';"));
    expect(web, contains('LoginEmailSenhaPage(onLogin: _aoEntrar)'));
    expect(mobile, contains('LoginEmailSenhaPage(onLogin: _aoEntrar)'));
    expect(login, contains('entrarComEmailSenha'));
    expect(login, contains('enviarRecuperacaoSenha'));
    expect(login, contains("labelText: 'E-mail da empresa'"));
    expect(login, contains("labelText: 'Senha'"));
    expect(login, contains('mesmo e-mail e senha'));
  });

  test('web usa a mesma preparacao de sessao do mobile', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final mobile = File('lib/main.dart').readAsStringSync();

    expect(web, contains('CloudSessionService.instance'));
    expect(mobile, contains('CloudSessionService.instance'));
    expect(web, contains('_cloudSession.prepararSessao()'));
    expect(mobile, contains('_cloudSession.prepararSessao()'));
    expect(web, contains('_cloudSession.prepararSessao(empresaId: destino)'));
    expect(web, isNot(contains("from('empresa_usuarios')")));
    expect(web, isNot(contains("rpc('imperium_resgatar_convite')")));
  });

  test('web preserva redefinicao de senha no navegador', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('AuthChangeEvent.passwordRecovery'));
    expect(source, contains('definirNovaSenha'));
    expect(source, contains('Salvar nova senha'));
    expect(source, contains('mesma no Imperium Web e no aplicativo'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
  });

  test('primeiro acesso e ativacao sao compartilhados entre web e mobile', () {
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final firstAccess = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();

    expect(login, contains('EmpresaPrimeiroAcessoPage'));
    expect(login, contains('Criar ou ativar acesso da empresa'));
    expect(firstAccess, contains('criarContaComEmailSenha'));
    expect(firstAccess, contains('entrarComEmailSenha'));
    expect(firstAccess, contains('E-mail da assinatura'));
    expect(firstAccess, contains('Criar senha e ativar assinatura'));
    expect(cloudSession, contains("client.rpc('imperium_resgatar_convite')"));
    expect(cloudSession, contains('prepararSessao'));
  });

  test('funcionarios continuam internos a empresa', () {
    final loginSource = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();

    expect(
      loginSource,
      contains('Funcionários ficam cadastrados dentro da empresa'),
    );
    expect(loginSource, isNot(contains('FuncionarioPrimeiroAcessoPage')));
    expect(
      cloudSession,
      contains('Funcionários são cadastrados e gerenciados pelo administrador'),
    );
  });
}
