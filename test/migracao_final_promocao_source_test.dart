import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('promocao cloud final e sequencial reversivel e admin-only', () {
    final migration = File(
      'supabase/migrations/20260918130702_migracao_final_promocao_modulos_v1.sql',
    ).readAsStringSync();
    final service = File(
      'lib/services/migracao_final_promocao_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/screens/migracao_final_auditoria_page.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(migration, contains('imperium_migracao_modulos'));
    expect(migration, contains('enable row level security'));
    expect(migration, contains('private.usuario_admin_empresa(empresa_id)'));
    expect(migration, contains('promovido_por = (select auth.uid())'));
    expect(migration, contains('revoke all'));
    expect(migration, contains('from anon'));
    expect(
      migration,
      isNot(contains('grant delete on table public.imperium_migracao_modulos')),
    );

    final ordem = <String>[
      "'operacional'",
      "'ordens_servico'",
      "'arquivos_os'",
      "'crm_orcamentos'",
      "'estoque'",
      "'financeiro'",
      "'precificacao'",
      "'configuracoes'",
      "'ponto'",
    ];

    var posicaoAnterior = -1;
    for (final modulo in ordem) {
      final posicao = service.indexOf("chave: $modulo");
      expect(posicao, greaterThan(posicaoAnterior));
      posicaoAnterior = posicao;
    }

    expect(service, contains('MigracaoFinalGateV2Service.instance.avaliar()'));
    expect(service, contains('if (!gate.prontoParaPromover)'));
    expect(service, contains('_validarSequencia(estados)'));
    expect(service, contains('Future<MigracaoFinalModuloEstado> promoverProximo()'));
    expect(service, contains('Future<MigracaoFinalModuloEstado> rollbackUltimo()'));
    expect(service, contains("'status': 'promovido'"));
    expect(service, contains("'status': 'rollback'"));
    expect(service, isNot(contains('.delete()')));

    expect(page, contains('Promoção Cloud controlada'));
    expect(page, contains('Promover próximo módulo'));
    expect(page, contains('Rollback do último'));
    expect(page, contains('ação explícita nos controles de cutover'));

    final blocoOperacionalInicio = sync.indexOf(
      'Future<void> _syncOperacionalBase(String empresaId) async',
    );
    final blocoOperacionalFim = sync.indexOf(
      'Future<void> _syncOrdensServico(String empresaId) async',
      blocoOperacionalInicio,
    );
    final bloco = sync.substring(blocoOperacionalInicio, blocoOperacionalFim);

    expect(
      RegExp(
        r'OperacionalCloudV2Service\.instance\.prepararUpload',
      ).allMatches(bloco).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      bloco.indexOf('OperacionalCloudV2Service.instance.prepararUpload'),
      lessThan(bloco.indexOf('_publicarClientesLocais')),
    );
  });
}
