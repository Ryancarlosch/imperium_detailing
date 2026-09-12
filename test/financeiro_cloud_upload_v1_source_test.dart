import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Financeiro Cloud V1 publica dependencias na ordem correta', () {
    final source = File(
      'lib/services/financeiro_cloud_upload_service.dart',
    ).readAsStringSync();

    expect(source, contains('financeiro-cloud-upload-v1'));

    final plano = source.indexOf('await _publicarPlanoContas(empresaId);');
    final contas = source.indexOf('await _publicarContas(empresaId);');
    final pagamentos = source.indexOf('await _publicarPagamentos(empresaId);');
    final movimentos = source.indexOf('await _publicarMovimentos(empresaId);');

    expect(plano, greaterThanOrEqualTo(0));
    expect(contas, greaterThan(plano));
    expect(pagamentos, greaterThan(contas));
    expect(movimentos, greaterThan(pagamentos));
  });

  test('Financeiro V1 e upload-only e nao altera saldo local', () {
    final source = File(
      'lib/services/financeiro_cloud_upload_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('sincronizarDownload')));
    expect(source, isNot(contains("database.insert('movimentos_financeiros'")));
    expect(source, isNot(contains("database.update('financeiro_contas'")));
    expect(source, contains('imperium_sync_financeiro_movimentos'));
  });

  test('Sync operacional chama Financeiro depois das dependencias', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final osUpload = compact.indexOf(
      'awaitOsCloudUploadService.instance.sincronizarUpload(empresaId);',
    );
    final financeiro =
        RegExp(
          r'awaitFinanceiroCloudUploadService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(osUpload, greaterThanOrEqualTo(0));
    expect(financeiro, greaterThan(osUpload));
  });

  test('Migration Financeiro V1 possui RLS e isolamento multiempresa', () {
    final sql = File(
      'supabase/migrations/20260912033511_financeiro_cloud_upload_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_financeiro_plano_contas'));
    expect(sql, contains('imperium_financeiro_contas'));
    expect(sql, contains('imperium_financeiro_pagamentos_os'));
    expect(sql, contains('imperium_financeiro_movimentos'));
    expect(sql, contains('enable row level security'));
    expect(
      sql,
      contains("private.imperium_pode_modulo(empresa_id, 'financeiro')"),
    );
    expect(sql, contains('empresa_id'));
  });

  test('SQLite continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
