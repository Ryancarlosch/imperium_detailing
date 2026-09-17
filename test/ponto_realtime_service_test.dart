import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Meu Ponto integra atualização Realtime com fallback seguro', () {
    final page = File('lib/screens/meu_ponto_page.dart').readAsStringSync();
    final service = File(
      'lib/services/ponto_realtime_service.dart',
    ).readAsStringSync();

    expect(page, contains('PontoRealtimeService.instance'));
    expect(page, contains('assinarColaborador'));
    expect(page, contains('unawaited(_realtime.cancelar())'));

    expect(service, contains("table: 'ponto_registros'"));
    expect(service, contains("column: 'colaborador_id'"));
    expect(service, contains("table: 'ponto_jornada'"));
    expect(service, contains("table: 'ponto_config'"));
    expect(service, contains("column: 'empresa_id'"));
    expect(service, contains('value: empresaId'));
    expect(service, contains('void agendarAtualizacao()'));
    expect(service, contains('Duration(milliseconds: 400)'));
    expect(service, contains('empresaAtualId()'));
    expect(service, contains('remotoIdPorLocal('));
  });

  test('Meu Ponto retoma Realtime ao voltar ao primeiro plano', () {
    final page = File('lib/screens/meu_ponto_page.dart').readAsStringSync();

    expect(page, contains('with WidgetsBindingObserver'));
    expect(page, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(page, contains('didChangeAppLifecycleState'));
    expect(page, contains('AppLifecycleState.resumed'));
    expect(page, contains('unawaited(_retomarSincronizacao())'));
    expect(page, contains('await _iniciarRealtime()'));
    expect(page, contains('await _carregar()'));
    expect(page, contains('WidgetsBinding.instance.removeObserver(this)'));
  });

  test('Migration publica jornada e configuração no Supabase Realtime', () {
    final migration = File(
      'supabase/migrations/20260917010144_ponto_realtime_jornada_config_v1.sql',
    ).readAsStringSync();

    expect(migration, contains("tablename = 'ponto_jornada'"));
    expect(migration, contains("tablename = 'ponto_config'"));
    expect(
      migration,
      contains(
        'alter publication supabase_realtime add table public.ponto_jornada',
      ),
    );
    expect(
      migration,
      contains(
        'alter publication supabase_realtime add table public.ponto_config',
      ),
    );
  });
}
