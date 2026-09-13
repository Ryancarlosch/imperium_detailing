import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Financeiro V3 inclui auxiliares, conciliacao e Storage', () {
    final source = File(
      'lib/services/financeiro_cloud_v3_service.dart',
    ).readAsStringSync();

    expect(source, contains('financeiro-cloud-v3'));
    expect(source, contains('financeiro_custos_fixos'));
    expect(source, contains('financeiro_metas'));
    expect(source, contains('financeiro_conciliacoes_conta'));
    expect(source, contains('imperium-financeiro-comprovantes'));
    expect(source, contains('uploadBinary'));
    expect(source, contains('baixarComprovanteBytes'));
    expect(source, contains('diagnosticar'));
  });

  test('Custos e metas usam conflito + CAS antes de sobrescrever', () {
    final source = File(
      'lib/services/financeiro_cloud_v3_service.dart',
    ).readAsStringSync();

    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('cas_falhou_alteracao_concorrente'));
    expect(source, contains("entidade IN ('custo_fixo', 'meta')"));
    expect(source, contains(".eq('atualizado_em', esperado)"));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
  });

  test('Financeiro V3 nao usa repositories para baixar dados', () {
    final source = File(
      'lib/services/financeiro_cloud_v3_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('FinanceiroRepository(')));
    expect(source, isNot(contains('PagamentoRepository(')));
  });

  test('Sync operacional chama V3 dentro do fluxo financeiro', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final completarV2 =
        RegExp(
          r'awaitFinanceiroCloudV2Service\.instance\.'
          r'completarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final uploadV3 =
        RegExp(
          r'awaitFinanceiroCloudV3Service\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final downloadV2 =
        RegExp(
          r'awaitFinanceiroCloudV2Service\.instance\.'
          r'sincronizarDownload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final downloadV3 =
        RegExp(
          r'awaitFinanceiroCloudV3Service\.instance\.'
          r'sincronizarDownload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(completarV2, greaterThanOrEqualTo(0));
    expect(uploadV3, greaterThan(completarV2));
    expect(downloadV2, greaterThan(uploadV3));
    expect(downloadV3, greaterThan(downloadV2));
  });

  test('Migration V3 protege tabelas e bucket privado', () {
    final sql = File(
      'supabase/migrations/'
      '20260913012841_financeiro_cloud_v3_auxiliares_comprovantes.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_financeiro_custos_fixos'));
    expect(sql, contains('imperium_financeiro_metas'));
    expect(sql, contains('imperium_financeiro_conciliacoes'));
    expect(sql, contains('imperium-financeiro-comprovantes'));
    expect(sql, contains('public = excluded.public'));
    expect(sql, contains('private.imperium_pode_modulo'));
    expect(sql, contains('storage.objects'));
  });

  test('SQLite de dominio permanece v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
