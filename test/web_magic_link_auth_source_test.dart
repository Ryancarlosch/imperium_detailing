import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web reutiliza o mesmo login email senha do aplicativo', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final auth = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(web, contains("import 'screens/login_email_senha_page.dart';"));
    expect(web, contains('LoginEmailSenhaPage(onLogin: _aoEntrar)'));
    expect(web, contains('CloudSessionService'));
    expect(login, contains('entrarComEmailSenha'));
    expect(login, contains("labelText: 'E-mail da empresa'"));
    expect(login, contains("labelText: 'Senha'"));
    expect(auth, contains('signInWithPassword'));

    expect(web, isNot(contains('signInWithOtp')));
    expect(login, isNot(contains('signInWithOtp')));
    expect(web, isNot(contains('Magic Link')));
    expect(web, isNot(contains("import 'dart:io';")));
  });

  test('Web usa a mesma sessao segura e workspace administrativo', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();
    final empresaCloud = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
    ).readAsStringSync();
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();

    expect(source, contains('_cloudSession.prepararSessao()'));
    expect(source, contains('_cloudSession.prepararSessao(empresaId: destino)'));
    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('WebWorkspaceShell'));
    expect(cloudSession, contains("client.rpc('imperium_resgatar_convite')"));
    expect(
      empresaCloud,
      contains("papel != 'admin' && papel != 'proprietario'"),
    );
    expect(workspace, contains('WebOperacionalShell'));
    expect(shell, contains('WebDashboardGerencialPage'));
    expect(shell, contains('WebPontoPage'));
    expect(shell, contains("titulo: 'Ponto e funcionários'"));
  });
}
