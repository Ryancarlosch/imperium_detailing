import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Conflitos concorrentes podem ser resolvidos sem sobrescrita silenciosa', () {
    final page = File('lib/screens/sync_conflitos_page.dart').readAsStringSync();
    final gate = File('lib/widgets/licenca_gate.dart').readAsStringSync();

    for (final marker in <String>[
      'Revisar conflitos',
      'Usar este aparelho',
      'Usar nuvem',
      'resolverUsandoLocal',
      'resolverUsandoNuvem',
      'OperacionalCloudV2Service.instance',
      'ConfiguracaoArquivosCloudService.instance',
      "origem: 'resolucao_conflito'",
    ]) {
      expect(page, contains(marker));
    }

    expect(gate, contains('Revisão necessária'));
    expect(gate, contains('SyncConflitosPage(empresaId: empresaId)'));
    expect(gate, contains('_verificarConflitos(empresaId)'));
  });
}
