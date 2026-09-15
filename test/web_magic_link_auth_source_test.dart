import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web usa Magic Link sem senha', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('signInWithOtp'));
    expect(source, contains('shouldCreateUser: false'));
    expect(source, contains('emailRedirectTo: _redirectUrl'));
    expect(source, contains('Uri.base.origin'));
    expect(source, contains('onAuthStateChange'));
    expect(source, contains("'imperium_resgatar_convite'"));

    expect(source, isNot(contains('signInWithPassword')));
    expect(source, isNot(contains("labelText: 'Senha'")));
    expect(source, isNot(contains('final senha = TextEditingController')));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('Web mantem selecao segura de empresa e workspace', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    final workspace = File(
      'lib/web/web_workspace_shell.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('empresaAtualValida'));
    expect(source, contains('trocarEmpresa'));
    expect(source, contains('WebWorkspaceShell'));
    expect(workspace, contains('WebOperacionalShell'));
    expect(shell, contains('WebDashboardGerencialPage'));
    expect(shell, contains('WebPontoPage'));
    expect(shell, contains("titulo: 'Ponto e funcionários'"));
  });
}
