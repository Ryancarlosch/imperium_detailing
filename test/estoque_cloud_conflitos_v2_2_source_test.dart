import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V2.2 oferece resolucao local e nuvem com auditoria', () {
    final source = File(
      'lib/services/estoque_cloud_conflito_resolucao_service.dart',
    ).readAsStringSync();

    expect(source, contains('estoque-cloud-resolucao-v2-2'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
    expect(source, contains("'status': 'Resolvido'"));
    expect(source, contains("'resolucao': resolucao"));
    expect(source, contains('listarHistorico'));
  });

  test('Resolver usando local atualiza remoto antes de encerrar', () {
    final source = File(
      'lib/services/estoque_cloud_conflito_resolucao_service.dart',
    ).readAsStringSync();

    final start = source.indexOf('Future<void> resolverUsandoLocal');
    final update = source.indexOf('.update(payload)', start);
    final map = source.indexOf('_atualizarMapa(', update);
    final end = source.indexOf('_encerrar(', map);

    expect(start, greaterThanOrEqualTo(0));
    expect(update, greaterThan(start));
    expect(map, greaterThan(update));
    expect(end, greaterThan(map));
  });

  test('Resolver usando nuvem atualiza SQLite antes de encerrar', () {
    final source = File(
      'lib/services/estoque_cloud_conflito_resolucao_service.dart',
    ).readAsStringSync();

    final start = source.indexOf('Future<void> resolverUsandoNuvem');
    final apply = source.indexOf('_aplicarItemRemoto(', start);
    final end = source.indexOf('_encerrar(', apply);

    expect(start, greaterThanOrEqualTo(0));
    expect(apply, greaterThan(start));
    expect(end, greaterThan(apply));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
