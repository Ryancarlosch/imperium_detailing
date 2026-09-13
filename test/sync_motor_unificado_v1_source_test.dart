import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Motor unificado possui fila, ciclos, eventos e backoff', () {
    final source = File(
      'lib/services/sync_motor_service.dart',
    ).readAsStringSync();

    expect(source, contains('sync-motor-unificado-v1'));
    expect(source, contains('imperium_sync_motor_fila'));
    expect(source, contains('imperium_sync_motor_ciclos'));
    expect(source, contains('imperium_sync_motor_eventos'));
    expect(source, contains('proxima_tentativa_em'));
    expect(source, contains('Duration(seconds: segundos[indice])'));
    expect(source, contains('liberarBackoff'));
  });

  test('Operacional usa nove modulos no motor', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    for (final modulo in <String>[
      'configuracoes',
      'operacional',
      'ordens_servico',
      'arquivos_os',
      'crm_orcamentos',
      'estoque',
      'financeiro',
      'precificacao',
      'ponto',
    ]) {
      expect(source, contains("modulo: '$modulo'"));
    }

    expect(source, contains('SyncMotorService.instance.executar'));
    expect(source, contains('ignorarBackoff'));
  });

  test('Dependencias preservam ordem critica', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    expect(
      compact,
      contains(
        "modulo:'arquivos_os',prioridade:40,"
        "dependencias:const<String>['ordens_servico']",
      ),
    );
    expect(
      compact,
      contains(
        "modulo:'precificacao',prioridade:80,"
        "dependencias:const<String>['financeiro','estoque']",
      ),
    );
  });

  test('Conflitos bloqueiam modulo sem sobrescrever', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(source, contains('SyncMotorBloqueadoException'));
    expect(source, contains('Conflitos pendentes nos arquivos da OS.'));
    expect(source, contains('Conflitos pendentes em CRM/Orçamentos.'));
    expect(source, contains('Conflitos pendentes no Financeiro.'));
    expect(source, contains('Conflitos pendentes na Precificação.'));
  });

  test('Central Cloud mostra saude, fila e retry manual', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('Saúde da sincronização'));
    expect(source, contains('_diagnosticoSync'));
    expect(source, contains('_filaSync'));
    expect(source, contains('SyncMotorService.instance.diagnosticar'));
    expect(source, contains('ignorarBackoff: true'));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
