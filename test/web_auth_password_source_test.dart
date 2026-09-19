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
    expect(login, contains("label: 'E-mail'"));
    expect(login, contains("label: 'Senha'"));
    expect(login, contains('Acesse sua empresa com seu e-mail e senha'));
  });

  test('web centraliza a sessao no mesmo servico usado pelo mobile', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final mobile = File('lib/main.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();

    expect(web, contains('CloudSessionService.instance'));
    expect(mobile, contains('CloudSessionService.instance'));
    expect(login, contains('CloudSessionService.instance'));
    expect(web, contains('_cloudSession.prepararSessao()'));
    expect(web, contains('_cloudSession.prepararSessao(empresaId: destino)'));
    expect(login, contains('_cloudSession.prepararSessao'));
    expect(web, isNot(contains("from('empresa_usuarios')")));
    expect(web, isNot(contains("rpc('imperium_resgatar_convite')")));
  });

  test('web preserva redefinicao de senha no navegador', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('AuthChangeEvent.passwordRecovery'));
    expect(source, contains('definirNovaSenha'));
    expect(source, contains('Salvar nova senha'));
    expect(source, contains('Essa senha será a mesma no'));
    expect(source, contains('AppBranding.productName'));
    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
  });

  test(
    'primeiro acesso e autocadastro sao compartilhados entre web e mobile',
    () {
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
      expect(login, contains('Começar 30 dias grátis'));
      expect(firstAccess, contains('criarContaComEmailSenha'));
      expect(firstAccess, contains('entrarComEmailSenha'));
      expect(firstAccess, contains('Criar conta grátis'));
      expect(firstAccess, contains('30 dias grátis'));
      expect(cloudSession, contains("client.rpc('imperium_resgatar_convite')"));
      expect(
        cloudSession,
        contains("client.rpc('imperium_autocadastro_empresa')"),
      );
      expect(cloudSession, contains('prepararSessao'));
    },
  );

  test(
    'plano fica acessivel no web inclusive quando a licenca esta bloqueada',
    () {
      final web = File('lib/main_web.dart').readAsStringSync();
      final workspace = File(
        'lib/web/web_workspace_shell.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/web/web_operacional_shell.dart',
      ).readAsStringSync();
      final plano = File(
        'lib/screens/licenca_status_page.dart',
      ).readAsStringSync();

      expect(web, contains('Plano / renovar acesso'));
      expect(web, contains('LicencaStatusPage(empresaId: empresaId)'));
      expect(workspace, contains('WebOperacionalShell'));
      expect(shell, contains('Plano e assinatura'));
      expect(
        shell,
        contains('LicencaStatusPage(empresaId: widget.empresaAtualId)'),
      );
      expect(plano, contains('Plano do Imperium'));
      expect(plano, contains('Assinar antes do vencimento'));
      expect(plano, contains('InfinitePay'));
    },
  );

  test('funcionarios continuam internos a empresa', () {
    final loginSource = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();

    expect(loginSource, contains('EmpresaPrimeiroAcessoPage'));
    expect(loginSource, isNot(contains('FuncionarioPrimeiroAcessoPage')));
    expect(
      cloudSession,
      contains('Funcionários são cadastrados e gerenciados pelo administrador'),
    );
  });
}
