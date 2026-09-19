import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Administracao Web usa acessos Cloud existentes sem chave privilegiada',
    () {
      final page = File(
        'lib/web/web_usuarios_acessos_page.dart',
      ).readAsStringSync();
      final service = File(
        'lib/services/funcionario_acesso_service.dart',
      ).readAsStringSync();

      for (final marker in [
        'class WebUsuariosAcessosPage',
        'listarAcessosAdmin',
        'prepararAcessoAdmin',
        'definirAtivoAdmin',
        'revogarDispositivosAdmin',
        'Usuários e acessos',
        'Dispositivos ativos',
        'Permissões',
      ]) {
        expect(page, contains(marker));
      }

      for (final rpc in [
        'imperium_funcionario_listar_acessos',
        'imperium_funcionario_preparar_acesso',
        'imperium_funcionario_definir_ativo',
        'imperium_funcionario_revogar_dispositivos',
      ]) {
        expect(service, contains(rpc));
      }

      expect(page, isNot(contains('service_role')));
      expect(page, isNot(contains('supabase.auth.admin')));
    },
  );

  test('Permissoes Web respeitam somente modulos Cloud homologados', () {
    final page = File(
      'lib/web/web_usuarios_acessos_page.dart',
    ).readAsStringSync();

    for (final modulo in [
      'ponto',
      'clientes',
      'crm',
      'agenda',
      'orcamentos',
      'ordens_servico',
      'estoque',
      'financeiro',
      'configuracoes',
    ]) {
      expect(page, contains("'$modulo'"));
    }

    final bloco =
        RegExp(
          r'static const _modulos = <String>\[([^\]]*)\]',
          dotAll: true,
        ).firstMatch(page)?.group(1) ??
        '';

    expect(bloco, isNot(contains("'precificacao'")));
  });

  test('Shell Web inclui usuarios e acessos dentro da Administracao', () {
    final shell = File('lib/web/web_operacional_shell.dart').readAsStringSync();

    expect(shell, contains("import 'web_usuarios_acessos_page.dart';"));
    expect(shell, contains("20 => 'Usuários e acessos'"));
    expect(shell, contains('20 => WebUsuariosAcessosPage('));
    expect(shell, contains('empresaId: widget.empresaAtualId'));
    expect(shell, contains("titulo: 'Administração'"));
    final administracao = RegExp(
      r"titulo: 'Administração',[\s\S]*?indices: const \{([^}]*)\}",
    ).firstMatch(shell)?.group(1);

    expect(administracao, isNotNull);
    expect(administracao, contains('17'));
    expect(administracao, contains('20'));
    expect(shell, contains("titulo: 'Usuários e acessos'"));
  });
}
