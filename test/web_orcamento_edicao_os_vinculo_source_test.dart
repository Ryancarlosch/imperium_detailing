import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web edita orcamento de forma atomica com cliente veiculo e itens', () {
    final page = File('lib/web/web_expansao_pages.dart').readAsStringSync();
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928170500_orcamento_web_edicao_atomica_v3.sql',
    ).readAsStringSync();

    expect(page, contains("'Editar orçamento'"));
    expect(page, contains('_service.editarOrcamento'));
    expect(page, contains('itensIniciais'));
    expect(page, contains("'atualizado_em': item.atualizadoEm"));

    expect(service, contains('editarOrcamento'));
    expect(service, contains("'imperium_orcamento_web_editar_v3'"));
    expect(service, contains("'p_cliente_id'"));
    expect(service, contains("'p_veiculo_id'"));

    expect(migration, contains('security invoker'));
    expect(migration, contains("private.imperium_pode_modulo"));
    expect(migration, contains('for update'));
    expect(migration, contains('O veículo selecionado não pertence ao cliente'));
  });

  test('Orcamento aprovado gera uma unica OS vinculada', () {
    final page = File('lib/web/web_expansao_pages.dart').readAsStringSync();
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928173500_orcamento_vinculo_os_cloud.sql',
    ).readAsStringSync();

    expect(page, contains("'Gerar Ordem de Serviço'"));
    expect(page, contains('_service.gerarOsDeOrcamento'));
    expect(service, contains("'imperium_orcamento_gerar_os_web'"));

    expect(migration, contains('add column if not exists orcamento_id uuid'));
    expect(migration, contains('idx_imperium_os_orcamento_ativo_uq'));
    expect(migration, contains("v_orc.status <> 'Aprovado'"));
    expect(migration, contains("'criada', false"));
    expect(migration, contains('insert into public.imperium_ordem_servico_itens'));
  });

  test('Mobile reconcilia o vinculo de orcamento depois do CRM', () {
    final vinculo = File(
      'lib/services/os_orcamento_vinculo_cloud_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(vinculo, contains("'imperium_sync_ordens_servico'"));
    expect(vinculo, contains("'imperium_sync_orcamentos'"));
    expect(vinculo, contains("'orcamento_id': orcamentoRemoto"));
    expect(vinculo, contains("'orcamento_id': orcamentoLocalId"));

    expect(
      motor,
      contains('OsOrcamentoVinculoCloudService.instance.sincronizar'),
    );
    expect(
      motor.indexOf('CrmOrcamentosCloudV2Service.instance.sincronizarDepoisDoDownload'),
      lessThan(
        motor.indexOf('OsOrcamentoVinculoCloudService.instance.sincronizar'),
      ),
    );
  });
}
