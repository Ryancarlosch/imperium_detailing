import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque V3 reserva, consome e baixa alertas compartilhados', () {
    final source = File(
      'lib/services/estoque_cloud_reserva_service.dart',
    ).readAsStringSync();

    expect(source, contains('estoque-cloud-reserva-v3'));
    expect(source, contains('sincronizarReservas'));
    expect(source, contains('sincronizarAlertas'));
    expect(source, contains('imperium_estoque_reservar_os'));
    expect(source, contains('imperium_estoque_consumir_reserva_os'));
    expect(source, contains('imperium_estoque_liberar_reserva_os'));
    expect(source, contains('reserva_remota_insuficiente'));
    expect(source, contains('_atualizarBaselinesAposConsumo'));
  });

  test('Sync operacional reserva antes do upload e baixa alerta depois', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final osUpload = compact.indexOf(
      'awaitOsCloudUploadService.instance.sincronizarUpload(empresaId);',
    );
    final reserva =
        RegExp(
          r'awaitEstoqueCloudReservaService\.instance\.'
          r'sincronizarReservas\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;
    final estoqueUpload =
        RegExp(
          r'awaitEstoqueCloudUploadService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;
    final estoqueDownload =
        RegExp(
          r'awaitEstoqueCloudDownloadService\.instance\.'
          r'sincronizarDownloadNovos\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;
    final alerta =
        RegExp(
          r'awaitEstoqueCloudReservaService\.instance\.'
          r'sincronizarAlertas\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(osUpload, greaterThanOrEqualTo(0));
    expect(reserva, greaterThan(osUpload));
    expect(estoqueUpload, greaterThan(reserva));
    expect(estoqueDownload, greaterThan(estoqueUpload));
    expect(alerta, greaterThan(estoqueDownload));
  });

  test('Lotes e movimentos respeitam conflito de item', () {
    final source = File(
      'lib/services/estoque_cloud_upload_service.dart',
    ).readAsStringSync();

    expect(source, contains('estoque-cloud-item-conflict-guard-v3'));
    expect(source, contains("entidade: 'item'"));
  });

  test('Migration V3 protege tenant e serializa saldo', () {
    final sql = File(
      'supabase/migrations/20260912032554_estoque_reservas_saldo_alertas_v3.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_estoque_reservas_os'));
    expect(sql, contains('imperium_estoque_alertas'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(
      sql,
      contains("private.imperium_pode_modulo(p_empresa_id, 'estoque')"),
    );
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('revoke execute'));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
