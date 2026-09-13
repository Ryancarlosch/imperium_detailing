import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Precificacao Cloud V1 compartilha nucleo completo', () {
    final source = File(
      'lib/services/precificacao_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('precificacao-cloud-v1'));
    expect(source, contains('_publicarConfig'));
    expect(source, contains('_publicarColaboradores'));
    expect(source, contains('_publicarCatalogo'));
    expect(source, contains('_publicarPreferencias'));
    expect(source, contains('_publicarReceitas'));
    expect(source, contains('_publicarSnapshots'));
    expect(source, contains('sincronizarDownload'));
    expect(source, contains('diagnosticar'));
  });

  test('Precificacao preserva regra oficial de 220 horas', () {
    final source = File(
      'lib/services/precificacao_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('ImperiumRegrasNegocio.horasMensaisPadrao'));
    expect(
      File('lib/config/imperium_regras_negocio.dart').readAsStringSync(),
      contains('horasMensaisPadrao = 220.0'),
    );
  });

  test('Snapshot leva custo, margem e taxa para nuvem', () {
    final source = File(
      'lib/services/precificacao_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains("'custo_produtos'"));
    expect(source, contains("'custo_estrutura'"));
    expect(source, contains("'custo_base'"));
    expect(source, contains("'preco_sugerido'"));
    expect(source, contains("'margem_atual'"));
    expect(source, contains("'taxa_cartao_media_percentual'"));
  });

  test('Sync operacional chama Precificacao apos Financeiro', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final finUpload =
        RegExp(
          r'awaitFinanceiroCloudV3Service\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final precUpload =
        RegExp(
          r'awaitPrecificacaoCloudService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final finDownload =
        RegExp(
          r'awaitFinanceiroCloudV3Service\.instance\.'
          r'sincronizarDownload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final precDownload =
        RegExp(
          r'awaitPrecificacaoCloudService\.instance\.'
          r'sincronizarDownload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(finUpload, greaterThanOrEqualTo(0));
    expect(precUpload, greaterThan(finUpload));
    expect(finDownload, greaterThan(precUpload));
    expect(precDownload, greaterThan(finDownload));
  });

  test('Migration tem seis tabelas e RLS financeiro', () {
    final sql = File(
      'supabase/migrations/20260913014517_precificacao_cloud_v1.sql',
    ).readAsStringSync();

    for (final tabela in <String>[
      'imperium_precificacao_config',
      'imperium_precificacao_servicos_catalogo',
      'imperium_precificacao_servicos',
      'imperium_precificacao_servico_produtos',
      'imperium_precificacao_colaboradores_custo',
      'imperium_precificacao_snapshots',
    ]) {
      expect(sql, contains(tabela));
    }

    expect(sql, contains('enable row level security'));
    expect(
      sql,
      contains("private.imperium_pode_modulo(empresa_id, 'financeiro')"),
    );
  });

  test('SQLite de dominio permanece v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
