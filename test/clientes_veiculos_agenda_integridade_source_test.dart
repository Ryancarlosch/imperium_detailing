import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync operacional preserva empresa_id', () {
    final s = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    for (final m in <String>[
      'imperium_sync_clientes',
      'imperium_sync_veiculos',
      'imperium_sync_agendamentos',
      '_publicarClientesLocais',
      '_publicarVeiculosLocais',
      '_publicarAgendamentosLocais',
      '_baixarClientes',
      '_baixarVeiculos',
      '_baixarAgendamentos',
      ".eq('empresa_id', empresaId)",
      "'empresa_id': empresaId",
    ]) {
      expect(s, contains(m), reason: 'Ausente: $m');
    }
  });
}
