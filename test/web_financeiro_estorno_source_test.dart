import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estorno financeiro web usa CAS, idempotencia e dois modos', () {
    final service = File(
      'lib/services/web_financeiro_estorno_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260917124628_financeiro_estorno_web_v1.sql',
    ).readAsStringSync();
    final lower = migration.toLowerCase();

    expect(
      service,
      contains("'imperium_financeiro_estornar_pagamento_web_v1'"),
    );
    expect(service, contains('WebFinanceiroEstornoModo { correcao, devolucao }'));
    expect(service, contains("'p_pagamento_atualizado_em'"));
    expect(service, contains("'p_idempotency_key'"));
    expect(service, contains("'p_origem_dispositivo'"));
    expect(service, contains("'p_origem_base'"));
    expect(service, contains("'America/Sao_Paulo'"));
    expect(service, contains('sha256'));

    expect(lower, contains('security invoker'));
    expect(
      lower,
      contains('imperium_financeiro_estornar_pagamento_web_v1'),
    );
    expect(lower, contains("v_modo not in ('correcao','devolucao')"));
    expect(lower, contains("status = 'estornado'"));
    expect(lower, contains("v_modo = 'correcao'"));
    expect(lower, contains("v_modo = 'devolucao'"));
    expect(lower, contains("'devolução ao cliente'"));
    expect(lower, contains("codigo = '1.02.01'"));
    expect(lower, contains("origem = 'taxa de maquininha'"));
    expect(lower, contains('trg_imperium_os_ajuste_taxa_estorno_guard'));
    expect(lower, contains('p_pagamento_atualizado_em'));
    expect(lower, contains('estorno_web_idempotency_key'));
    expect(lower, contains('status_pagamento = v_status_pagamento'));
    expect(lower, contains('valor_recebido = v_recebido'));
    expect(lower, contains('from public, anon'));
    expect(lower, contains('to authenticated'));
  });
}
