import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web corrige OS finalizada sem alterar valores ou pagamentos', () {
    final page = File('lib/web/web_ordens_v3_page.dart').readAsStringSync();
    final service = File(
      'lib/services/web_os_v3_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928203000_os_revisoes_correcao_web.sql',
    ).readAsStringSync();

    expect(page, contains("'Corrigir OS finalizada'"));
    expect(page, contains("'Histórico de correções'"));
    expect(page, contains("'Motivo da correção *'"));
    expect(page, contains('A OS continuará Finalizada'));
    expect(page, contains('_service.corrigirFinalizada'));

    expect(service, contains("'imperium_os_corrigir_finalizada_web'"));
    expect(service, contains('motivoLimpo.length < 5'));
    expect(service, contains('WebOrigemService.instance.proxima'));

    expect(migration, contains("v_os.status <> 'Finalizada'"));
    expect(migration, contains('quantidade_revisoes = v_numero'));
    expect(migration, contains('assinatura_desatualizada'));
    expect(migration, contains("'Correcao administrativa'"));
    expect(migration, isNot(contains('valor_total =')));
    expect(migration, isNot(contains('status_pagamento =')));
  });

  test(
    'Correcao recalcula derivados sem mudar quantidade ou custo de estoque',
    () {
      final migration = File(
        'supabase/migrations/20260928203000_os_revisoes_correcao_web.sql',
      ).readAsStringSync();

      expect(migration, contains("'AUTO_OS_FINALIZACAO'"));
      expect(migration, contains('imperium_financeiro_os_mao_obra'));
      expect(migration, contains('imperium_estoque_movimentacoes'));
      expect(migration, contains('grant update (data)'));
      expect(migration, contains('set data = v_saida_iso'));
      expect(migration, isNot(contains('set quantidade =')));
      expect(migration, isNot(contains('set custo_unitario =')));
    },
  );

  test('Revisoes de OS sincronizam de forma append only com Android', () {
    final sync = File(
      'lib/services/os_revisoes_cloud_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(sync, contains("'imperium_ordem_servico_revisoes'"));
    expect(sync, contains("'imperium_sync_os_revisoes'"));
    expect(sync, contains("'ordem_servico_revisoes'"));
    expect(sync, contains('_publicarLocais'));
    expect(sync, contains('_baixarRemotas'));
    expect(sync, isNot(contains(".update(payload)")));
    expect(sync, isNot(contains(".delete()")));

    expect(motor, contains('OsRevisoesCloudService.instance.sincronizar'));
    expect(
      motor.indexOf('OsCloudV3Service.instance.possuiConflitosPendentes'),
      lessThan(motor.indexOf('OsRevisoesCloudService.instance.sincronizar')),
    );
  });
}
