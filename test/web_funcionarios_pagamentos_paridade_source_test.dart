import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web oferece folha e pagamentos de funcionarios', () {
    final page = File(
      'lib/web/web_financeiro_administracao_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_financeiro_administracao_service.dart',
    ).readAsStringSync();

    expect(page, contains("text: 'Folha e pagamentos'"));
    expect(page, contains("label: const Text('Registrar pagamento')"));
    expect(page, contains('Remuneração base'));
    expect(page, contains('Pago no mês'));
    expect(page, contains('fechamento de ponto'));

    expect(service, contains('listarPagamentosColaboradores'));
    expect(service, contains('registrarPagamentoColaborador'));
    expect(
      service,
      contains("'imperium_financeiro_pagar_colaborador_web'"),
    );
  });

  test('Pagamento Web cria movimento e vinculo de forma atomica', () {
    final sql = File(
      'supabase/migrations/20260922121000_financeiro_pagamentos_colaboradores_cloud.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_financeiro_pagamentos_colaboradores'));
    expect(sql, contains('imperium_financeiro_pagar_colaborador_web'));
    expect(sql, contains('security invoker'));
    expect(sql, isNot(contains('security definer')));
    expect(sql, contains("'Pagamento de funcionário'"));
    expect(sql, contains("'Realizado'"));
    expect(sql, contains('impacta_dre'));
    expect(sql, contains('true'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('grant execute on function'));
  });

  test('Mobile sincroniza pagamentos sem recriar a saida financeira', () {
    final sync = File(
      'lib/services/pagamento_colaborador_cloud_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(sync, contains('financeiro_pagamentos_colaboradores'));
    expect(
      sync,
      contains('imperium_financeiro_pagamentos_colaboradores'),
    );
    expect(sync, contains('imperium_sync_financeiro_pagamentos_colaboradores'));
    expect(sync, contains('imperium_sync_financeiro_movimentos'));
    expect(
      sync,
      contains('evitando criar uma segunda saída financeira'),
    );

    expect(
      motor,
      contains("import 'pagamento_colaborador_cloud_service.dart';"),
    );
    expect(
      motor,
      contains(
        'PagamentoColaboradorCloudService.instance.sincronizar(empresaId)',
      ),
    );
  });
}
