import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration registra central cloud e quatro RPCs', () {
    final sql = File(
      'supabase/migrations/20260928204602_crm_acoes_relacionamento_cloud.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_crm_acoes_relacionamento'));
    expect(sql, contains('imperium_crm_sincronizar_acoes_web'));
    expect(sql, contains('imperium_crm_concluir_acao_web'));
    expect(sql, contains('imperium_crm_adiar_acao_web'));
    expect(sql, contains('imperium_crm_ignorar_acao_web'));
    expect(sql, contains('enable row level security'));
  });

  test('Web usa a fila cloud e as mesmas RPCs de estado', () {
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();
    final page = File('lib/web/web_crm_operacao_page.dart').readAsStringSync();

    expect(service, contains('imperium_crm_acoes_relacionamento'));
    expect(service, contains('imperium_crm_sincronizar_acoes_web'));
    expect(service, contains('imperium_crm_concluir_acao_web'));
    expect(service, contains('imperium_crm_adiar_acao_web'));
    expect(service, contains('imperium_crm_ignorar_acao_web'));
    expect(page, contains('Central de relacionamento'));
    expect(page, contains('listarAcoesCrm'));
  });

  test('Android persiste CAS remoto e fila offline de acoes', () {
    final database = File('lib/database/app_database.dart').readAsStringSync();
    final sync = File(
      'lib/services/crm_acoes_relacionamento_cloud_service.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/repositories/crm_operacao_repository.dart',
    ).readAsStringSync();

    expect(database, contains('static const int schemaVersion = 34;'));
    expect(database, contains('remoto_id TEXT'));
    expect(database, contains('remoto_atualizado_em TEXT'));
    expect(database, contains('sync_pendente INTEGER NOT NULL DEFAULT 0'));

    expect(sync, contains('imperium_crm_sincronizar_acoes_web'));
    expect(sync, contains('imperium_crm_concluir_acao_web'));
    expect(sync, contains('imperium_crm_adiar_acao_web'));
    expect(sync, contains('imperium_crm_ignorar_acao_web'));
    expect(sync, contains('p_atualizado_em_base'));
    expect(sync, contains('sync_pendente = 1 AND remoto_id IS NOT NULL'));

    expect(repository, contains("'sync_pendente': 1"));
    expect(
      repository,
      contains('CrmAcoesRelacionamentoCloudService.instance.sincronizar()'),
    );
  });
}
