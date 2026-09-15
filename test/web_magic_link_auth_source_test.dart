import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web usa email e senha com Supabase Auth', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final auth = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(source, contains('entrarComEmailSenha'));
    expect(source, contains("labelText: 'E-mail'"));
    expect(source, contains("labelText: 'Senha'"));
    expect(source, contains('onAuthStateChange'));
    expect(source, contains("'imperium_resgatar_convite'"));
    expect(auth, contains('signInWithPassword'));

    expect(source, isNot(contains('signInWithOtp')));
    expect(source, isNot(contains('Magic Link')));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('Web mantem selecao segura de empresa e workspace administrativo', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final empresaCloud = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
    ).readAsStringSync();
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();

    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('atualValida'));
    expect(source, contains('trocarEmpresa'));
    expect(source, contains('WebWorkspaceShell'));
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
