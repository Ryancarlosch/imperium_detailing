import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assinaturas usam checkout InfinitePay validado no backend', () {
    final service = File(
      'lib/services/assinatura_checkout_service.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/licenca_status_page.dart',
    ).readAsStringSync();
    final checkout = File(
      'supabase/functions/imperium-infinitepay-checkout/index.ts',
    ).readAsStringSync();
    final webhook = File(
      'supabase/functions/imperium-infinitepay-webhook/index.ts',
    ).readAsStringSync();
    final retorno = File(
      'supabase/functions/imperium-infinitepay-retorno/index.ts',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260916034900_infinitepay_assinaturas_v1.sql',
    ).readAsStringSync();

    expect(service, contains("client.rpc('imperium_planos_disponiveis')"));
    expect(service, contains("'imperium-infinitepay-checkout'"));
    expect(tela, contains('Opções de assinatura'));
    expect(tela, contains('A InfinitePay processa o pagamento'));
    expect(
      tela,
      isNot(contains('será conectada à InfinitePay na próxima etapa')),
    );

    expect(
      checkout,
      contains('const INFINITEPAY_HANDLE = "imperium_detailing"'),
    );
    expect(checkout, contains('https://api.checkout.infinitepay.io/links'));
    expect(checkout, contains('imperium-infinitepay-webhook'));
    expect(checkout, contains('imperium-infinitepay-retorno'));

    expect(
      webhook,
      contains('https://api.checkout.infinitepay.io/payment_check'),
    );
    expect(webhook, contains('amount !== cobranca.valor_centavos'));
    expect(webhook, contains('imperium_confirmar_pagamento_infinitepay'));
    expect(
      retorno,
      contains('https://api.checkout.infinitepay.io/payment_check'),
    );

    expect(migration, contains("('mensal', 'Mensal', 1, 2000"));
    expect(migration, contains("('trimestral', 'Trimestral', 3, 5000"));
    expect(migration, contains("('anual', 'Anual', 12, 20000"));
    expect(migration, contains('for update of c'));
    expect(migration, contains("status_base = 'ativa'"));

    // A confirmação do pagamento fica no backend, não no Flutter.
    expect(service, isNot(contains('payment_check')));
    expect(tela, isNot(contains('payment_check')));
  });
}
