import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backend cria primeira empresa com 30 dias apos confirmar email', () {
    final source = File(
      'supabase/migrations/20260916014700_autocadastro_empresa_30_dias_v1.sql',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'create or replace function public.imperium_autocadastro_empresa()',
      ),
    );
    expect(source, contains('security definer'));
    expect(source, contains("set search_path = ''"));
    expect(source, contains('email_confirmed_at'));
    expect(source, contains('confirmed_at'));
    expect(source, contains("'Teste 30 dias'"));
    expect(source, contains('current_date + 30'));
    expect(source, contains("'autocadastro_teste_30_dias'"));
    expect(source, contains('pg_advisory_xact_lock'));
    expect(
      source,
      contains(
        'grant execute on function public.imperium_autocadastro_empresa() to authenticated',
      ),
    );
    expect(
      source,
      contains(
        'revoke all on function public.imperium_autocadastro_empresa() from anon',
      ),
    );
  });

  test('convites comerciais antigos continuam compativeis', () {
    final source = File(
      'supabase/migrations/20260915201403_onboarding_comercial_email_senha_v1.sql',
    ).readAsStringSync();

    expect(
      source,
      contains('create or replace function public.imperium_resgatar_convite()'),
    );
    expect(source, contains('on conflict (empresa_id, user_id)'));
    expect(source, contains("onboarding_status = 'ativo'"));
  });

  test(
    'sessao tenta convite legado e depois autocadastro quando necessario',
    () {
      final cloudSession = File(
        'lib/services/cloud_session_service.dart',
      ).readAsStringSync();

      expect(cloudSession, contains("client.rpc('imperium_resgatar_convite')"));
      expect(
        cloudSession,
        contains("client.rpc('imperium_autocadastro_empresa')"),
      );
      expect(cloudSession, contains('listarEmpresasVinculadas'));
      expect(cloudSession, contains('30 dias grátis'));
    },
  );

  test('mobile oferece cadastro livre com confirmacao de email', () {
    final firstAccess = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();

    expect(firstAccess, contains('Criar conta grátis'));
    expect(firstAccess, contains('Teste o Imperium grátis por 30 dias'));
    expect(firstAccess, contains('Confirme o e-mail'));
    expect(firstAccess, contains('criarContaComEmailSenha'));
    expect(firstAccess, contains('entrarComEmailSenha'));
    expect(firstAccess, contains('prepararSessao'));
    expect(login, contains('Começar 30 dias grátis'));
    expect(login, contains('sem autorização prévia'));
  });

  test('web reutiliza o mesmo cadastro e sessao do mobile', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();

    expect(web, contains('LoginEmailSenhaPage(onLogin: _aoEntrar)'));
    expect(web, contains('CloudSessionService'));
    expect(web, contains('_cloudSession.prepararSessao()'));
    expect(login, contains('EmpresaPrimeiroAcessoPage'));
    expect(
      cloudSession,
      contains("client.rpc('imperium_autocadastro_empresa')"),
    );
  });
}
