import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'precificacao e configuracoes mobile usam realtime com protecao local',
    () {
      final realtime = File(
        'lib/services/operacional_realtime_service.dart',
      ).readAsStringSync();
      final precificacao = File(
        'lib/screens/custo_servicos_page.dart',
      ).readAsStringSync();
      final central = File(
        'lib/screens/precificacao_cloud_central_page.dart',
      ).readAsStringSync();
      final custos = File('lib/screens/custos_page.dart').readAsStringSync();
      final configuracoes = File(
        'lib/screens/configuracoes_page.dart',
      ).readAsStringSync();
      final migration = File(
        'supabase/migrations/20260918022904_mobile_realtime_precificacao_configuracoes_v1.sql',
      ).readAsStringSync();

      for (final tabela in <String>[
        'imperium_precificacao_colaboradores_custo',
        'imperium_precificacao_config',
        'imperium_precificacao_servico_produtos',
        'imperium_precificacao_servicos',
        'imperium_precificacao_servicos_catalogo',
        'imperium_precificacao_simulacoes',
        'imperium_precificacao_snapshots',
        'imperium_configuracoes_empresa',
      ]) {
        expect(realtime, contains("registrar('$tabela')"));
        expect(migration, contains('public.$tabela'));
      }

      expect(migration, contains('alter publication supabase_realtime'));
      expect(migration, contains("pubname = 'supabase_realtime'"));

      for (final pagina in <String>[
        precificacao,
        central,
        custos,
        configuracoes,
      ]) {
        expect(
          pagina,
          contains("import '../services/operacional_realtime_service.dart';"),
        );
        expect(pagina, contains('StreamSubscription<void>?'));
        expect(pagina, contains('.atualizacoes'));
        expect(pagina, contains('_operacionalRealtimeSubscription?.cancel();'));
      }

      expect(precificacao, contains('unawaited(_recarregarPorRealtime())'));
      expect(precificacao, contains('_baseTemAlteracoesNaoSalvas'));
      expect(precificacao, contains('_salvandoBase'));
      expect(precificacao, contains('_salvandoFidelidade'));
      expect(precificacao, contains('_repository.carregar()'));

      expect(central, contains('unawaited(_recarregarPorRealtime())'));
      expect(central, contains('_sincronizando'));
      expect(central, contains('_cloud.listarConflitosPendentes'));
      expect(central, contains('_cloud.listarSimulacoes'));

      expect(custos, contains('unawaited(_recarregarPorRealtime())'));
      expect(custos, contains('_repository.obterResumoEstruturaCustos'));

      expect(
        configuracoes,
        contains('unawaited(_recarregarConfiguracoesPorRealtime())'),
      );
      expect(configuracoes, contains('_temAlteracoesNaoSalvas'));
      expect(configuracoes, contains('respeitarEdicaoLocal'));
      expect(configuracoes, contains('_salvando'));
      expect(configuracoes, contains('_processandoBackup'));
      expect(configuracoes, contains('_processandoAssinaturaEmpresa'));
      expect(
        configuracoes,
        contains('await _carregarConfiguracoes(respeitarEdicaoLocal: true);'),
      );
    },
  );
}
