import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conflitos operacional usam uma unica fonte de verdade', () {
    final facade = File(
      'lib/services/operacional_conflito_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/sync_motor_service.dart',
    ).readAsStringSync();

    expect(facade, contains("import 'operacional_cloud_v2_service.dart';"));
    expect(facade, contains('OperacionalCloudV2Service.instance'));
    expect(facade, contains('_delegate.prepararUpload'));
    expect(facade, contains('_delegate.listarConflitosPendentes'));
    expect(facade, contains('_delegate.resolverUsandoLocal'));
    expect(facade, contains('_delegate.resolverUsandoNuvem'));
    expect(
      facade,
      isNot(contains('CREATE TABLE IF NOT EXISTS imperium_sync_operacional_conflitos')),
    );

    expect(motor, contains("import 'operacional_cloud_v2_service.dart';"));
    expect(motor, contains("if (etapa.modulo == 'operacional')"));
    expect(motor, contains('OperacionalCloudV2Service.instance'));
    expect(motor, contains('.prepararUpload(empresaId)'));
    expect(
      motor,
      contains('Conflitos pendentes em Clientes, Veículos ou Agenda.'),
    );
  });
}
