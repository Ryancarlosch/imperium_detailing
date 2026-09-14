import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String blocoSync(String source, String assinatura) {
  final inicio = source.indexOf(assinatura);
  expect(
    inicio,
    greaterThanOrEqualTo(0),
    reason: 'Método $assinatura não encontrado.',
  );

  final proximo = source.indexOf(
    '\n  Future<void> _sync',
    inicio + assinatura.length,
  );

  return proximo < 0
      ? source.substring(inicio)
      : source.substring(inicio, proximo);
}

void main() {
  test('OS Cloud V4 cria contrato local sem alterar schema oficial', () {
    final source = File(
      'lib/services/os_finalizacao_cloud_v4_service.dart',
    ).readAsStringSync();

    expect(source, contains('imperium_sync_os_produtos_estado'));
    expect(source, contains('imperium_sync_os_produtos_conflitos'));
    expect(source, contains('imperium_sync_os_produtos'));
    expect(source, contains('imperium_sync_os_produto_lotes'));
    expect(source, contains('imperium_sync_os_mao_obra'));
    expect(source, contains('imperium_sync_os_ajustes_financeiros'));
    expect(source, contains("'imperium_os_produtos_publicar_v4'"));
    expect(source, contains('alteracao_concorrente'));
    expect(source, contains('resolverProdutosUsandoLocal'));
    expect(source, contains('resolverProdutosUsandoNuvem'));
  });

  test(
    'Motor sincroniza produtos depois do estoque e auxiliares apos financeiro',
    () {
      final source = File(
        'lib/services/operacional_sync_service.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("import 'os_finalizacao_cloud_v4_service.dart';"),
      );

      final estoque = blocoSync(source, 'Future<void> _syncEstoque');
      final downloadEstoque = estoque.indexOf('sincronizarDownloadNovos(');
      final produtos = estoque.indexOf('sincronizarProdutos(');

      expect(
        downloadEstoque,
        greaterThanOrEqualTo(0),
        reason: 'Download do estoque não encontrado dentro de _syncEstoque.',
      );
      expect(
        produtos,
        greaterThan(downloadEstoque),
        reason:
            'Produtos da OS devem sincronizar depois do download do estoque.',
      );
      expect(
        estoque,
        contains('SyncMotorBloqueadoException'),
        reason: 'Conflito de produtos deve bloquear o módulo de estoque.',
      );

      final financeiro = blocoSync(source, 'Future<void> _syncFinanceiro');
      final downloadV2 = financeiro.indexOf(
        'FinanceiroCloudV2Service.instance.sincronizarDownload',
      );
      final downloadV3 = financeiro.indexOf(
        'FinanceiroCloudV3Service.instance.sincronizarDownload',
      );
      final posFinanceiro = financeiro.indexOf('sincronizarPosFinanceiro(');

      expect(
        downloadV2,
        greaterThanOrEqualTo(0),
        reason: 'Download financeiro V2 não encontrado.',
      );
      expect(
        downloadV3,
        greaterThan(downloadV2),
        reason: 'Download financeiro V3 deve ocorrer depois do V2.',
      );
      expect(
        posFinanceiro,
        greaterThan(downloadV3),
        reason:
            'Auxiliares da finalização V4 devem sincronizar depois do financeiro.',
      );
    },
  );

  test('Web V4 usa contratos e RPC transacional', () {
    final service = File(
      'lib/services/web_os_finalizacao_v4_service.dart',
    ).readAsStringSync();

    final page = File(
      'lib/web/web_os_finalizacao_v4_page.dart',
    ).readAsStringSync();

    expect(service, contains("'imperium_os_produtos_publicar_v4'"));
    expect(service, contains("'imperium_os_finalizar_web_v4'"));
    expect(service, contains("'America/Sao_Paulo'"));
    expect(service, contains("'p_idempotency_key'"));
    expect(service, contains("'p_produtos_atualizado_em'"));
    expect(service, contains("status != 'Em andamento'"));
    expect(service, isNot(contains("import 'dart:io';")));

    expect(page, contains('class WebOsFinalizacaoV4Page'));
    expect(page, contains("'Em andamento'"));
    expect(page, contains('Produtos'));
    expect(page, contains('Finalizar'));
    expect(page, contains('Finalização transacional'));
    expect(page, isNot(contains("import 'dart:io';")));
  });

  test('Migracoes V4 documentam idempotencia FIFO DRE e imutabilidade', () {
    final principal = File(
      'supabase/migrations/'
      '20260914025104_os_cloud_v4_finalizacao_transacional.sql',
    ).readAsStringSync();

    final imutavel = File(
      'supabase/migrations/'
      '20260914032628_os_cloud_v4_produtos_imutaveis_pos_finalizacao.sql',
    ).readAsStringSync();

    final hardening = File(
      'supabase/migrations/'
      '20260914033237_os_cloud_v4_dre_e_fifo_interop_hardening.sql',
    ).readAsStringSync();

    final interop = File(
      'supabase/migrations/'
      '20260914033305_os_cloud_v4_fifo_produto_id_interop.sql',
    ).readAsStringSync();

    final principalLower = principal.toLowerCase();

    expect(principal, contains('imperium_os_finalizacoes_web'));
    expect(principalLower, contains('security invoker'));
    expect(principalLower, contains('for update'));
    expect(principal, contains('p_idempotency_key'));
    expect(principal, contains('imperium_estoque_movimentacoes'));
    expect(principal, contains('imperium_financeiro_movimentos'));
    expect(principal, contains('imperium_financeiro_os_mao_obra'));
    expect(principal, contains('fifo_web'));
    expect(principal, contains('horas_produtivas_mes'));

    expect(imutavel, contains('finalizada pelo Web'));
    expect(imutavel, contains('imperium_os_finalizacoes_web'));

    expect(hardening, contains("new.origem = 'Pagamento de OS'"));
    expect(hardening, contains('new.impacta_dre := false'));
    expect(hardening, contains('imperium_os_produto_resolver_v4'));
    expect(interop, contains('produto_id'));
    expect(interop, contains('imperium_os_produto_resolver_v4'));
  });

  test('Central Android expoe diagnostico e conflito de produtos V4', () {
    final source = File(
      'lib/screens/configuracoes_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('OsFinalizacaoCloudV4Service'));
    expect(source, contains('_diagnosticoFinalizacaoOs'));
    expect(source, contains('_conflitosProdutosOs'));
    expect(source, contains('_finalizacaoOsCloudV4Card'));
    expect(source, contains('_resolverProdutosOs'));
  });

  test('Navegacao Web expoe finalizacao V4', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains("import 'web_os_finalizacao_v4_page.dart';"));
    expect(source, contains("'Finalizar OS'"));
    expect(source, contains('WebOsFinalizacaoV4Page'));
  });

  test('Schema local e startup Android continuam protegidos', () {
    final db = File('lib/database/app_database.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(db, contains('static const int schemaVersion = 33;'));
    expect(
      main,
      contains('OperacionalSyncService.instance.prepararTenantInicial'),
    );
  });
}
