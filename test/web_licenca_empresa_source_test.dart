import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web valida a licença da empresa selecionada antes do workspace', () {
    final web = File('lib/main_web.dart').readAsStringSync();
    final service = File(
      'lib/services/licenca_empresa_cloud_service.dart',
    ).readAsStringSync();

    expect(web, contains('LicencaEmpresaCloudService'));
    expect(web, contains('_licencaService.consultar(atual)'));
    expect(web, contains('if (!licenca.acessoLiberado)'));
    expect(web, contains('_licencaBloqueadaTela'));
    expect(web, contains('Web e aplicativo usam a mesma licença da empresa.'));
    expect(service, contains("rpc(\n      'imperium_status_licenca_empresa'"));
    expect(service, contains("'p_empresa_id': id"));
    expect(service, contains('LicencaStatus.fromMap'));
  });

  test('RPC de licença por empresa exige vínculo administrativo autenticado', () {
    final migration = File(
      'supabase/migrations/20260915211400_licenca_por_empresa_login_web_mobile_v1.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'create or replace function public.imperium_status_licenca_empresa',
      ),
    );
    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('eu.user_id = (select auth.uid())'));
    expect(
      migration,
      contains("lower(trim(eu.papel)) in ('admin', 'proprietario')"),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.imperium_status_licenca_empresa(uuid) from anon',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.imperium_status_licenca_empresa(uuid) to authenticated',
      ),
    );
  });
}
