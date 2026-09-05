import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consulta por placa fica atras do Supabase e preenche o cadastro', () {
    final service = File(
      'lib/services/consulta_placa_service.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/veiculos_cliente_page.dart',
    ).readAsStringSync();
    final edge = File(
      'supabase/functions/consultar-placa/index.ts',
    ).readAsStringSync();

    expect(service, contains('consulta-placa-automatica-v1'));
    expect(service, contains('ConsultaPlacaNaoEncontradaException'));
    expect(service, contains('if (response.status == 404)'));
    expect(tela, contains('on ConsultaPlacaNaoEncontradaException catch'));
    expect(service, contains("client.functions.invoke("));
    expect(service, contains("'consultar-placa'"));

    expect(tela, contains('consulta-placa-ui-helper-v1'));
    expect(tela, contains('consulta-placa-auto-onchanged-v1'));
    expect(tela, contains('marcaController.text = resultado.marca'));
    expect(tela, contains('modeloController.text = resultado.modelo'));
    expect(tela, contains('corController.text = resultado.cor'));
    expect(tela, contains('anoController.text = resultado.anoPreferencial'));

    expect(edge, contains('consulta-placa-edge-auth-v1'));
    expect(edge, contains('FALCON_DATAHUB_TOKEN'));
    expect(
      edge,
      contains('https://datahub.falcon-server.com.br/private/v1/placas/'),
    );

    // A chave privada jamais deve ser hardcoded no app.
    expect(service, isNot(contains('FALCON_DATAHUB_TOKEN')));
  });
}
