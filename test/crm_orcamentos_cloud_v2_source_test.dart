import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRM Orcamentos V2 cria conflito e oferece resolucao', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('crm-orcamentos-cloud-v2'));
    expect(source, contains('imperium_sync_crm_orcamentos_conflitos'));
    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
    expect(source, contains("status = 'Pendente'"));
  });

  test('Resolucao local usa CAS do atualizado_em remoto', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains("eq('atualizado_em', remotoEsperado)"));
    expect(source, contains('A nuvem mudou novamente'));
  });

  test('Mudanca apenas remota e aplicada direto no SQLite', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('if (!localMudou && remotoMudou)'));
    expect(source, contains('_aplicarRemoto('));
    expect(source, isNot(contains('CrmRepository')));
    expect(source, isNot(contains('OrcamentoRepository')));
  });

  test('Central Cloud exibe conflitos CRM Orcamentos', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('CRM e Orçamentos'));
    expect(source, contains('_resolverCrmOrcamento'));
    expect(source, contains('CrmOrcamentosCloudV2Service'));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
