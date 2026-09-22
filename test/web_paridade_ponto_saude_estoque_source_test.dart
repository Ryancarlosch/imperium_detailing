import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web revisa solicitacoes de ajuste do Ponto', () {
    final page = File('lib/web/web_ponto_page.dart').readAsStringSync();
    final service = File(
      'lib/services/web_cloud_ponto_service.dart',
    ).readAsStringSync();

    expect(page, contains("text: 'Solicitações'"));
    expect(page, contains('Solicitações de ajuste'));
    expect(page, contains('Registro atual'));
    expect(page, contains('Solicitado'));
    expect(page, contains("label: const Text('Aprovar')"));
    expect(page, contains("label: const Text('Rejeitar')"));

    expect(service, contains('listarSolicitacoesAjusteAdmin'));
    expect(service, contains('decidirSolicitacaoAjuste'));
    expect(service, contains("'ponto_listar_solicitacoes_ajuste_admin'"));
    expect(service, contains("'ponto_decidir_solicitacao_ajuste'"));
  });

  test('Central Cloud possui diagnostico de saude operacional', () {
    final page = File('lib/web/web_expansao_pages.dart').readAsStringSync();
    final service = File(
      'lib/services/web_cloud_expansao_service.dart',
    ).readAsStringSync();

    expect(page, contains('Saúde operacional'));
    expect(page, contains('Integridade de SQLite e foreign keys'));
    expect(service, contains('_diagnosticarSaudeCloud'));
    expect(service, contains("'estoque_negativo'"));
    expect(service, contains("'movimento_sem_documento'"));
    expect(service, contains("'nota_processada_sem_itens'"));
    expect(service, contains("'ponto_solicitacoes_pendentes'"));
  });

  test('Configuracao do estoque e compartilhada entre Web e Android', () {
    final page = File('lib/web/web_estoque_config_page.dart').readAsStringSync();
    final webService = File(
      'lib/services/web_estoque_config_service.dart',
    ).readAsStringSync();
    final mobileSync = File(
      'lib/services/estoque_config_cloud_service.dart',
    ).readAsStringSync();
    final motor = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/20260922141000_estoque_config_cloud.sql',
    ).readAsStringSync();

    for (final marker in <String>[
      'Controlar estoque',
      'Produtos nas Ordens de Serviço',
      'Baixa automática',
      'Exigir quantidade utilizada',
      'Alertar estoque baixo',
      'Estoque mínimo padrão',
    ]) {
      expect(page, contains(marker));
    }

    expect(webService, contains("'imperium_estoque_salvar_config'"));
    expect(mobileSync, contains("'imperium_estoque_config'"));
    expect(motor, contains('EstoqueConfigCloudService.instance.sincronizar'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('security invoker'));
    expect(sql, contains('private.imperium_pode_modulo'));
  });
}
