import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telas operacionais abertas acompanham o sync Realtime', () {
    for (final caminho in <String>[
      'lib/screens/clientes_page.dart',
      'lib/screens/veiculos_page.dart',
      'lib/screens/agenda_page.dart',
    ]) {
      final source = File(caminho).readAsStringSync();

      expect(
        source,
        contains("import '../services/operacional_realtime_service.dart';"),
        reason: caminho,
      );
      expect(source, contains('StreamSubscription<void>?'), reason: caminho);
      expect(source, contains('.atualizacoes'), reason: caminho);
      expect(
        source,
        contains('unawaited(_recarregarPorRealtime())'),
        reason: caminho,
      );
      expect(
        source,
        contains('_operacionalRealtimeSubscription?.cancel();'),
        reason: caminho,
      );
    }
  });

  test('refresh Realtime das telas evita execucoes concorrentes', () {
    for (final caminho in <String>[
      'lib/screens/clientes_page.dart',
      'lib/screens/veiculos_page.dart',
      'lib/screens/agenda_page.dart',
    ]) {
      final source = File(caminho).readAsStringSync();

      expect(source, contains('bool _atualizandoRealtime = false;'));
      expect(
        source,
        contains('if (!mounted || _atualizandoRealtime) return;'),
        reason: caminho,
      );
      expect(source, contains('_atualizandoRealtime = true;'), reason: caminho);
      expect(
        source,
        contains('_atualizandoRealtime = false;'),
        reason: caminho,
      );
    }
  });
}
