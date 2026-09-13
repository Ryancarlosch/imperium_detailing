import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppDatabase separa um arquivo SQLite por empresa', () {
    final appDatabase = File(
      'lib/database/app_database.dart',
    ).readAsStringSync();
    final platformIo = File(
      'lib/database/tenant_database_platform_io.dart',
    ).readAsStringSync();

    // O AppDatabase agora apenas orquestra a plataforma.
    expect(appDatabase, contains("import 'tenant_database_platform.dart';"));
    expect(appDatabase, contains('ativarEmpresa('));
    expect(appDatabase, contains('adotarBancoLegado'));
    expect(appDatabase, contains('caminhoBancoEmpresaPlatform'));
    expect(appDatabase, contains('salvarTenantAtivoPlatform'));

    // Android/IO continua garantindo um arquivo físico por empresa.
    expect(platformIo, contains('imperium_tenant_atual.txt'));
    expect(platformIo, contains('imperium_detailing_empresa_'));

    // A adoção do banco legado continua não destrutiva.
    expect(platformIo, contains('origem.copy(temporario.path)'));
    expect(platformIo, isNot(contains('origem.rename(')));
  });

  test('Schema de dominio continua v33', () {
    final source = File('lib/database/app_database.dart').readAsStringSync();

    expect(source, contains('static const int schemaVersion = 33;'));
  });

  test('Startup prepara tenant antes da sessao local', () {
    final source = File('lib/main.dart').readAsStringSync();

    final supabase = source.indexOf('await SupabaseBootstrap.inicializar();');
    final tenant = source.indexOf(
      'await OperacionalSyncService.instance.prepararTenantInicial();',
    );
    final runApp = source.indexOf('runApp(const ImperiumApp());');

    expect(supabase, greaterThanOrEqualTo(0));
    expect(tenant, greaterThan(supabase));
    expect(runApp, greaterThan(tenant));
    expect(source, contains('TenantRuntimeService.instance.revisao'));
  });

  test('Empresa Cloud valida vinculo antes de trocar banco', () {
    final source = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('empresa-cloud-multiempresa-v2'));
    expect(source, contains('Future<void> trocarEmpresa'));
    expect(source, contains("from('empresa_usuarios')"));
    expect(source, contains('.ativarEmpresa('));
    expect(source, contains("'isolamento_local_por_banco': true"));
  });

  test('Backup usa banco ativo e bloqueia restore de outro tenant', () {
    final source = File('lib/services/backup_service.dart').readAsStringSync();

    expect(source, contains('return _appDatabase.caminhoBancoAtual();'));
    expect(source, contains("'empresa_id': await _appDatabase.empresaAtivaId"));
    expect(source, contains('Este backup pertence a outra empresa'));
  });

  test('Arquivos novos usam pasta local do tenant', () {
    final storage = File(
      'lib/services/tenant_local_storage_service.dart',
    ).readAsStringSync();
    final fotos = File(
      'lib/screens/ordem_servico_fotos_page.dart',
    ).readAsStringSync();
    final checklist = File(
      'lib/screens/ordem_servico_checklist_page.dart',
    ).readAsStringSync();
    final assinatura = File(
      'lib/screens/ordem_servico_assinatura_page.dart',
    ).readAsStringSync();

    expect(storage, contains("'empresas'"));
    expect(storage, contains('empresaAtivaId'));
    expect(fotos, contains('TenantLocalStorageService.instance.pasta'));
    expect(checklist, contains('TenantLocalStorageService.instance.pasta'));
    expect(assinatura, contains('TenantLocalStorageService.instance.pasta'));
  });

  test('Central Cloud oferece troca e reinicia arvore do app', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> _trocarEmpresa'));
    expect(source, contains("'Trocar empresa'"));
    expect(
      source,
      contains('TenantRuntimeService.instance.reiniciarAplicacao'),
    );
  });
}
