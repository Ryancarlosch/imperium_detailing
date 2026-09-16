import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Garante o contrato comercial: somente o administrador define precos.
  test('admin controla planos e cliente apenas seleciona opcao do servidor', () {
    final adminService = File(
      'lib/services/imperium_planos_admin_service.dart',
    ).readAsStringSync();
    final adminPage = File(
      'lib/screens/imperium_planos_page.dart',
    ).readAsStringSync();
    final contaPage = File(
      'lib/screens/supabase_conta_page.dart',
    ).readAsStringSync();
    final checkoutService = File(
      'lib/services/assinatura_checkout_service.dart',
    ).readAsStringSync();
    final adminEdge = File(
      'supabase/functions/imperium-admin-planos/index.ts',
    ).readAsStringSync();
    final checkoutEdge = File(
      'supabase/functions/imperium-infinitepay-checkout/index.ts',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260916043000_infinitepay_planos_admin_snapshot_v1.sql',
    ).readAsStringSync();

    expect(adminService, contains("'imperium-admin-planos'"));
    expect(adminPage, contains('Novo plano'));
    expect(
      adminPage,
      contains('Somente planos ativos aparecem para o cliente.'),
    );
    expect(contaPage, contains('Planos de assinatura'));
    expect(contaPage, contains('ImperiumPlanosPage'));

    expect(adminEdge, contains('IMPERIUM_EMPRESA_ID'));
    expect(adminEdge, contains('Acesso restrito ao administrador comercial'));
    expect(adminEdge, contains('.from("imperium_planos_assinatura")'));
    expect(adminEdge, isNot(contains('.delete(')));

    // O app do cliente manda apenas empresa e codigo do plano. Valor e duracao
    // sao obtidos novamente pelo servidor antes de criar o checkout.
    expect(checkoutService, contains("'plano_codigo': plano"));
    expect(checkoutService, isNot(contains("'valor_centavos':")));
    expect(
      checkoutEdge,
      contains('.select("codigo,nome,meses,valor_centavos,moeda,ativo")'),
    );
    expect(checkoutEdge, contains('price: plano.valor_centavos'));
    expect(checkoutEdge, contains('plano_meses: plano.meses'));

    // Uma cobranca aberta preserva duracao e valor mesmo se o administrador
    // editar o plano depois.
    expect(migration, contains('add column if not exists plano_meses integer'));
    expect(
      migration,
      contains('make_interval(months => v_cobranca.plano_meses)'),
    );
    expect(
      migration,
      isNot(contains('join public.imperium_planos_assinatura as p')),
    );
  });
}
