import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card operacional exibe diagnostico e resolve conflitos', () {
    final source = File(
      'lib/widgets/operacional_conflitos_card.dart',
    ).readAsStringSync();

    expect(source, contains('class OperacionalConflitosCard'));
    expect(source, contains('OperacionalCloudV2Service.instance'));
    expect(source, contains('listarConflitosPendentes'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
    expect(source, contains('Clientes, Veículos e Agenda'));
    expect(source, contains('Conflitos pendentes'));
    expect(source, contains('Usar nuvem'));
    expect(source, contains('Este aparelho'));
    expect(source, contains("origem: 'resolucao_conflito_operacional'"));
  });

  test('central cloud exibe o card de conflitos operacional', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains("../widgets/operacional_conflitos_card.dart"));
    expect(
      source,
      contains('OperacionalConflitosCard(onSincronizar: _sincronizar)'),
    );
  });
}
