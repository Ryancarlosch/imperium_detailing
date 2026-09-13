import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Origem Web e persistente e monotona', () {
    final source = File(
      'lib/services/web_origem_service.dart',
    ).readAsStringSync();

    expect(source, contains('SharedPreferences.getInstance'));
    expect(source, contains('imperium_web_origem_dispositivo_v1'));
    expect(source, contains('imperium_web_origem_local_id_v1'));
    expect(source, contains('microsecondsSinceEpoch'));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('CRM e Orcamentos usam origem Web e CAS', () {
    final source = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    expect(source, contains("from('imperium_crm_leads')"));
    expect(source, contains("from('imperium_crm_interacoes')"));
    expect(source, contains("from('imperium_orcamentos')"));
    expect(source, contains("from('imperium_orcamento_itens')"));
    expect(source, contains("'origem_dispositivo'"));
    expect(source, contains("'origem_local_id'"));
    expect(source, contains(".eq('atualizado_em', atualizadoEmEsperado)"));
    expect(source, contains('Outro dispositivo alterou este registro'));
  });

  test('Precificacao Web preserva 220 horas e CAS', () {
    final source = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    expect(source, contains('ImperiumRegrasNegocio.horasMensaisPadrao'));
    expect(source, contains("from('imperium_precificacao_config')"));
    expect(source, contains("from('imperium_precificacao_simulacoes')"));
    expect(source, contains('horas_mensais_empresa'));
    expect(source, contains('_precoComMargem'));
    expect(source, contains('_arredondarPreco'));
  });

  test('Paginas V3 entregam CRM Orcamentos Precificacao Central', () {
    final source = File('lib/web/web_expansao_pages.dart').readAsStringSync();

    expect(source, contains('class WebCrmPage'));
    expect(source, contains('class WebOrcamentosPage'));
    expect(source, contains('class WebPrecificacaoPage'));
    expect(source, contains('class WebCentralCloudPage'));
    expect(source, contains('Novo lead'));
    expect(source, contains('Novo orçamento'));
    expect(source, contains('Novo cenário'));
    expect(source, contains('Central Web'));
  });

  test('Shell Web escala com sidebar e drawer', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains("import 'web_expansao_pages.dart';"));
    expect(source, contains('_WebNavItem'));
    expect(source, contains("'CRM'"));
    expect(source, contains("'Orçamentos'"));
    expect(source, contains("'Precificação'"));
    expect(source, contains("'Central Cloud'"));
    expect(source, contains('Drawer('));
    expect(source, contains('_menuLateral'));
    expect(source, isNot(contains('bottomNavigationBar:')));
  });

  test('V3 nao libera operacoes transacionais inseguras', () {
    final source = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains("from('imperium_estoque_movimentacoes').insert")),
    );
    expect(
      source,
      isNot(contains("from('imperium_financeiro_movimentos').insert")),
    );
    expect(source, isNot(contains("'status': 'Finalizada'")));
  });

  test('Android e schema continuam preservados', () {
    final main = File('lib/main.dart').readAsStringSync();
    final db = File('lib/database/app_database.dart').readAsStringSync();

    expect(
      main,
      contains('OperacionalSyncService.instance.prepararTenantInicial'),
    );
    expect(db, contains('static const int schemaVersion = 33;'));
  });
}
