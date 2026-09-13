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

  test('Multiempresa V1 lista vinculos sem trocar tenant', () {
    final source = File(
      'lib/services/empresa_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('empresa-cloud-multiempresa-foundation-v1'));
    expect(source, contains('listarEmpresasVinculadas'));
    expect(source, contains('multiempresa_detectada'));
    expect(source, contains('troca_segura_disponivel'));
    expect(source, isNot(contains('trocarEmpresa(')));
    expect(source, isNot(contains('selecionarEmpresa(')));
  });

  test('Permissoes remotas liberam apenas modulos cloud coerentes', () {
    final source = File(
      'lib/services/funcionario_acesso_service.dart',
    ).readAsStringSync();

    for (final modulo in <String>[
      'ponto',
      'clientes',
      'agenda',
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

    expect(bloco, isNot(contains("'crm'")));
    expect(bloco, isNot(contains("'orcamentos'")));
    expect(bloco, isNot(contains("'precificacao'")));
  });

  test('Operacional sincroniza configuracao antes dos dados de dominio', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final config =
        RegExp(
          r'awaitConfiguracaoCloudService\.instance\.'
          r'sincronizar\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

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
