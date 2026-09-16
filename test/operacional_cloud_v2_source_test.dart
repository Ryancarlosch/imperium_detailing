import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Operacional V2 protege clientes veiculos e agenda por baseline', () {
    final service = File(
      'lib/services/operacional_cloud_v2_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/sync_motor_service.dart',
    ).readAsStringSync();

    for (final marker in <String>[
      'imperium_sync_operacional_conflitos',
      'imperium_sync_clientes',
      'imperium_sync_veiculos',
      'imperium_sync_agendamentos',
      'remoto_atualizado_em',
      'alteracao_concorrente',
      'alteracao_local_e_exclusao_remota',
      'resolverUsandoNuvem',
      'resolverUsandoLocal',
      "eq('atualizado_em', remotoEsperado)",
      "entidade: 'cliente'",
      "entidade: 'veiculo'",
      "entidade: 'agendamento'",
    ]) {
      expect(service, contains(marker));
    }

    expect(motor, contains("etapa.modulo == 'operacional'"));
    expect(
      motor,
      contains('OperacionalCloudV2Service.instance.prepararUpload'),
    );
    expect(
      motor,
      contains('Conflitos pendentes em Clientes, Veículos ou Agenda.'),
    );
  });

  test('Operacional V2 nao altera schemaVersion do SQLite de dominio', () {
    final db = File('lib/database/app_database.dart').readAsStringSync();
    expect(db, contains('static const int schemaVersion = 33;'));
  });
}
