import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration resgata assinatura por email de forma segura e idempotente', () {
    final source = File(
      'supabase/migrations/20260915201403_onboarding_comercial_email_senha_v1.sql',
    ).readAsStringSync();

    expect(
      source,
      contains('create or replace function public.imperium_resgatar_convite()'),
    );
    expect(source, contains('security definer'));
    expect(source, contains("set search_path = ''"));
    expect(source, contains('lower(trim(c.email)) = v_email'));
    expect(
      source,
      contains("lower(trim(c.papel)) in ('admin', 'proprietario')"),
    );
    expect(source, contains('on conflict (empresa_id, user_id)'));
    expect(source, contains("onboarding_status = 'ativo'"));
    expect(source, contains('aceito_por = v_uid'));
    expect(
      source,
      contains(
        'revoke all on function public.imperium_resgatar_convite() from anon',
      ),
    );
    expect(
      source,
      contains(
        'grant execute on function public.imperium_resgatar_convite() to authenticated',
      ),
    );
  });

  test('mobile ativa assinatura automaticamente depois da autenticacao', () {
    final firstAccess = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();
    final cloudSession = File(
      'lib/services/cloud_session_service.dart',
    ).readAsStringSync();

    expect(firstAccess, contains('E-mail da assinatura'));
    expect(firstAccess, contains('Criar senha e ativar assinatura'));
    expect(firstAccess, contains('vinculadas automaticamente'));
    expect(firstAccess, contains('criarContaComEmailSenha'));
    expect(firstAccess, contains('entrarComEmailSenha'));
    expect(firstAccess, contains('prepararSessao'));
    expect(cloudSession, contains("client.rpc('imperium_resgatar_convite')"));
    expect(cloudSession, contains('erroAtivacao'));
    expect(cloudSession, contains('listarEmpresasVinculadas'));
  });

  test('web usa o mesmo resgate automatico depois do login ou cadastro', () {
    final source = File('lib/main_web.dart').readAsStringSync();

    expect(source, contains('criarContaComEmailSenha'));
    expect(source, contains('entrarComEmailSenha'));
    expect(source, contains("c.rpc('imperium_resgatar_convite')"));
    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('mesmo e-mail e senha'));
  });
}
