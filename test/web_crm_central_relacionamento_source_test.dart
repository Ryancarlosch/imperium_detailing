import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Central CRM Cloud gera as mesmas quatro origens do mobile', () {
    final migration = File(
      'supabase/migrations/20260928224500_crm_acoes_relacionamento_cloud.sql',
    ).readAsStringSync();

    expect(migration, contains('imperium_crm_acoes_relacionamento'));
    expect(migration, contains("'Follow-up lead'"));
    expect(migration, contains("'Follow-up orçamento'"));
    expect(migration, contains("'Pós-venda'"));
    expect(migration, contains("'Benefício/cupom'"));
    expect(migration, contains('imperium_crm_sincronizar_acoes_web'));
    expect(migration, contains('imperium_crm_concluir_acao_web'));
    expect(migration, contains('imperium_crm_adiar_acao_web'));
    expect(migration, contains('imperium_crm_ignorar_acao_web'));
    expect(migration, contains('security invoker'));
    expect(migration, contains('for update'));
  });

  test('Estado da Central CRM e reconciliado com os IDs locais do Android', () {
    final sync = File(
      'lib/services/crm_acoes_cloud_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    for (final marker in [
      'imperium_sync_crm_leads',
      'imperium_sync_orcamentos',
      'imperium_sync_ordens_servico',
      'imperium_sync_crm_cupons',
      'imperium_sync_clientes',
      'imperium_sync_crm_acoes',
      '_estadoLocalTemAcao',
      '_estadoRemotoTemAcao',
    ]) {
      expect(sync, contains(marker));
    }

    expect(motor, contains('CrmAcoesCloudService.instance.sincronizar'));
    expect(
      motor.indexOf('OsOrcamentoVinculoCloudService.instance.sincronizar'),
      lessThan(motor.indexOf('CrmAcoesCloudService.instance.sincronizar')),
    );
  });

  test('Web opera a mesma fila com WhatsApp concluir adiar e ignorar', () {
    final page = File(
      'lib/web/web_crm_operacao_page.dart',
    ).readAsStringSync();
    final crm = File(
      'lib/web/web_expansao_pages.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    for (final marker in [
      'Central de relacionamento',
      'Operação comercial',
      'WhatsApp',
      'Concluir',
      'Próximo contato',
      'Adiar',
      'Ignorar',
      'Follow-ups, orçamentos, pós-venda e benefícios',
    ]) {
      expect(page, contains(marker));
    }

    expect(crm, contains('WebCrmOperacaoPage'));
    expect(crm, contains("'Central de relacionamento'"));
    expect(service, contains('listarAcoesCrm'));
    expect(service, contains('concluirAcaoCrm'));
    expect(service, contains('adiarAcaoCrm'));
    expect(service, contains('ignorarAcaoCrm'));
  });
}
