import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Clientes compartilham nascimento entre Web Cloud e Android', () {
    final web = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_cloud_operacional_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928215000_clientes_data_nascimento_cloud.sql',
    ).readAsStringSync();

    expect(web, contains("'Data de nascimento'"));
    expect(web, contains('dataNascimento: nascimento.text'));
    expect(service, contains("'data_nascimento'"));
    expect(sync, contains("'data_nascimento': _nuloTexto"));
    expect(sync, contains("'id,nome,telefone,email,data_nascimento"));
    expect(migration, contains('add column if not exists data_nascimento'));
  });

  test('CRM Web gerencia campanhas e cupons com regras do mobile', () {
    final page = File(
      'lib/web/web_crm_campanhas_page.dart',
    ).readAsStringSync();
    final crm = File(
      'lib/web/web_expansao_pages.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    for (final marker in [
      'Aniversário',
      'Reativação',
      'Indicação',
      'Manual',
      'Percentual',
      'Valor',
      'Serviço',
      'Crédito',
      'Gerar benefícios agora',
      'Cupons e benefícios',
      'Cancelar benefício',
    ]) {
      expect(page, contains(marker));
    }

    expect(crm, contains('WebCrmCampanhasPage'));
    expect(crm, contains("'Campanhas e benefícios'"));
    expect(service, contains('salvarCampanha'));
    expect(service, contains('gerarBeneficiosCrm'));
    expect(service, contains('listarCuponsDetalhados'));
    expect(service, contains('cancelarCupom'));
  });

  test('Beneficios automaticos nao duplicam entre Web e mobile', () {
    final migration = File(
      'supabase/migrations/20260928221500_crm_beneficios_web_idempotentes.sql',
    ).readAsStringSync();
    final sync = File(
      'lib/services/crm_orcamentos_cloud_service.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/repositories/crm_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('geracao_tipo'));
    expect(migration, contains('geracao_periodo'));
    expect(migration, contains('imperium_crm_cupons_geracao_negocio_uq'));
    expect(migration, contains('imperium_crm_gerar_beneficios_web'));
    expect(migration, contains("tipo in ('Aniversário', 'Reativação')"));
    expect(migration, contains('on conflict do nothing'));

    expect(sync, contains('_geracaoCupom'));
    expect(sync, contains("'geracao_tipo'"));
    expect(sync, contains("'geracao_periodo'"));
    expect(repository, contains('geracaoTipo'));
    expect(repository, contains("'chave_geracao = ? OR '"));
  });
}
