import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRM Web converte lead em cliente sem duplicar cadastro', () {
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/web/web_expansao_pages.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928211500_crm_web_conversao_agendamento.sql',
    ).readAsStringSync();

    expect(service, contains("'imperium_crm_converter_lead_web'"));
    expect(service, contains('converterLeadEmCliente'));
    expect(page, contains("'Converter em cliente'"));
    expect(page, contains('_service.converterLeadEmCliente'));

    expect(migration, contains("regexp_replace(coalesce(v_lead.telefone"));
    expect(migration, contains("lower(trim(coalesce(v_lead.email"));
    expect(migration, contains("'Conversão de cadastro'"));
    expect(migration, contains("'criado', v_criado"));
    expect(migration, contains('for update'));
  });

  test('CRM Web agenda lead convertido com veiculo do cliente', () {
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/web/web_expansao_pages.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260928211500_crm_web_conversao_agendamento.sql',
    ).readAsStringSync();

    expect(service, contains("'imperium_crm_agendar_lead_web'"));
    expect(service, contains('listarVeiculosClienteCrm'));
    expect(service, contains('agendarLead'));

    expect(page, contains("'Criar agendamento'"));
    expect(page, contains('_service.listarVeiculosClienteCrm'));
    expect(page, contains('_service.agendarLead'));

    expect(migration, contains("etapa = 'Agendado'"));
    expect(migration, contains("'Agendamento'"));
    expect(migration, contains('v.cliente_id = v_lead.cliente_id'));
    expect(migration, contains("'criado', true"));
  });
}
