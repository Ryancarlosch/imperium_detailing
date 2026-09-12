import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Financeiro V2 protege upload antes do V1', () {
    final source = File(
      'lib/services/financeiro_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('financeiro-cloud-v2'));
    expect(source, contains('prepararUpload'));
    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('imperium_sync_financeiro_conflitos'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
  });

  test('Download financeiro nao usa repositories que duplicam lancamentos', () {
    final source = File(
      'lib/services/financeiro_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('PagamentoRepository(')));
    expect(source, isNot(contains('FinanceiroRepository(')));
    expect(source, contains("'ordem_servico_pagamentos'"));
    expect(source, contains("'movimentos_financeiros'"));
    expect(source, contains('insert direto, sem PagamentoRepository'));
    expect(source, contains('insert direto, sem FinanceiroRepository'));
  });

  test('Financeiro V2 inclui complementos operacionais', () {
    final source = File(
      'lib/services/financeiro_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('_publicarFornecedores'));
    expect(source, contains('_publicarRegrasTaxa'));
    expect(source, contains('_publicarTransferencias'));
    expect(source, contains('_vincularRegrasNosPagamentos'));
    expect(source, contains('_vincularComplementosNosMovimentos'));
  });

  test('Sync operacional usa prepare V2, V1, complete V2 e download V2', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final preparar = compact.indexOf(
      'awaitFinanceiroCloudV2Service.instance.prepararUpload(empresaId)',
    );
    final uploadV1 = compact.indexOf(
      'awaitFinanceiroCloudUploadService.instance.sincronizarUpload(empresaId);',
    );
    final completar =
        RegExp(
          r'awaitFinanceiroCloudV2Service\.instance\.'
          r'completarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;
    final download =
        RegExp(
          r'awaitFinanceiroCloudV2Service\.instance\.'
          r'sincronizarDownload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(preparar, greaterThanOrEqualTo(0));
    expect(uploadV1, greaterThan(preparar));
    expect(completar, greaterThan(uploadV1));
    expect(download, greaterThan(completar));
  });

  test('Migration V2 possui complementos, RLS e FKs financeiras', () {
    final sql = File(
      'supabase/migrations/20260912034429_financeiro_cloud_v2_complementos.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_financeiro_fornecedores'));
    expect(sql, contains('imperium_financeiro_regras_taxa'));
    expect(sql, contains('imperium_financeiro_transferencias'));
    expect(sql, contains('regra_taxa_id uuid'));
    expect(sql, contains('fornecedor_id uuid'));
    expect(sql, contains('transferencia_id uuid'));
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
