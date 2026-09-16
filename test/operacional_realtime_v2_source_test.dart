import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Realtime operacional filtra por empresa e dispara motor normal', () {
    final realtime = File(
      'lib/services/operacional_realtime_service.dart',
    ).readAsStringSync();
    final gate = File('lib/widgets/licenca_gate.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260916234000_operacional_realtime_v2.sql',
    ).readAsStringSync();

    expect(realtime, contains("table: 'imperium_clientes'"));
    expect(realtime, contains("table: 'imperium_veiculos'"));
    expect(realtime, contains("table: 'imperium_agendamentos'"));
    expect(realtime, contains("column: 'empresa_id'"));
    expect(realtime, contains('Duration(milliseconds: 650)'));
    expect(realtime, contains('unawaited(_executarAtualizacao(onAtualizar))'));

    expect(gate, contains('OperacionalRealtimeService.instance'));
    expect(gate, contains('assinarEmpresa'));
    expect(
      gate,
      contains('OperacionalSyncService.instance.tentarSincronizarTudo()'),
    );
    expect(gate, contains('unawaited(_realtime.cancelar())'));

    expect(migration, contains('alter publication supabase_realtime'));
    expect(migration, contains('public.imperium_clientes'));
    expect(migration, contains('public.imperium_veiculos'));
    expect(migration, contains('public.imperium_agendamentos'));
  });
}
