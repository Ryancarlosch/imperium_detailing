import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Config Cloud V1 sincroniza somente dados portaveis', () {
    final source = File(
      'lib/services/configuracao_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('configuracoes-cloud-v1'));
    expect(source, contains('imperium_configuracoes_empresa'));
    expect(source, contains('cas_falhou_alteracao_concorrente'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));

    expect(source, isNot(contains("'caminho_logo'")));
    expect(source, isNot(contains("'caminho_assinatura_empresa'")));
    expect(source, isNot(contains("'ultimo_backup_caminho'")));
  });

  test('Multiempresa V2 lista vinculos e permite troca segura de tenant', () {
    final source = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('empresa-cloud-multiempresa-v2'));
    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('multiempresa_detectada'));
    expect(source, contains('troca_segura_disponivel'));
    expect(source, contains('Future<void> trocarEmpresa(String empresaId)'));
    expect(source, contains('_appDatabase.ativarEmpresa'));
    expect(source, contains('adotarBancoLegado:'));
    expect(source, contains("papel != 'admin' && papel != 'proprietario'"));
  });

  test('Permissoes remotas liberam modulos cloud ja integrados', () {
    final source = File(
      'lib/services/funcionario_acesso_service.dart',
    ).readAsStringSync();

    for (final modulo in <String>[
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
      expect(source, contains("'$modulo'"));
    }

    final bloco =
        RegExp(
          r'modulosRemotosProntos\s*=\s*<String>\{([^}]*)\}',
          dotAll: true,
        ).firstMatch(source)?.group(1) ??
        '';

    expect(bloco, contains("'crm'"));
    expect(bloco, contains("'orcamentos'"));
    expect(bloco, isNot(contains("'precificacao'")));
  });

  test('Operacional sincroniza configuracao antes dos dados de dominio', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    expect(compact, contains("modulo:'configuracoes',prioridade:10"));
    expect(compact, contains("modulo:'operacional',prioridade:20"));
    expect(compact, contains('executar:()=>_syncConfiguracoes(empresaId)'));
    expect(compact, contains('executar:()=>_syncOperacionalBase(empresaId)'));

    final config = compact.indexOf(
      'awaitConfiguracaoCloudService.instance.sincronizar(empresaId);',
    );
    final exclusoes = compact.indexOf('await_processarExclusoes(empresaId);');

    expect(config, greaterThanOrEqualTo(0));
    expect(exclusoes, greaterThan(config));
  });

  test('Central Cloud exibe empresas, modulos e conflitos', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('Empresas vinculadas'));
    expect(source, contains('Permissões Cloud ativas'));
    expect(source, contains('Conflitos de configuração'));
    expect(source, contains('Usar nuvem'));
    expect(source, contains('Usar local'));
    expect(source, contains('troca de empresa'));
  });

  test('Migration possui RLS e SQLite continua v33', () {
    final sql = File(
      'supabase/migrations/20260913021355_configuracoes_cloud_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_configuracoes_empresa'));
    expect(sql, contains('enable row level security'));
    expect(
      sql,
      contains("private.imperium_pode_modulo(empresa_id, 'configuracoes')"),
    );

    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
