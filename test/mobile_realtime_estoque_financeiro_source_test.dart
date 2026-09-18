import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estoque e financeiro mobile atualizam apos sync realtime', () {
    final realtime = File(
      'lib/services/operacional_realtime_service.dart',
    ).readAsStringSync();
    final estoque = File('lib/screens/estoque_page.dart').readAsStringSync();
    final financeiro = File(
      'lib/screens/financeiro_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260918020141_mobile_realtime_estoque_financeiro_v1.sql',
    ).readAsStringSync();

    for (final tabela in <String>[
      'imperium_estoque_itens',
      'imperium_estoque_lotes',
      'imperium_estoque_movimentacoes',
      'imperium_financeiro_contas',
      'imperium_financeiro_movimentos',
    ]) {
      expect(realtime, contains("registrar('$tabela')"));
      expect(migration, contains('public.$tabela'));
    }

    for (final pagina in <String>[estoque, financeiro]) {
      expect(
        pagina,
        contains("import '../services/operacional_realtime_service.dart';"),
      );
      expect(pagina, contains('StreamSubscription<void>?'));
      expect(pagina, contains('.atualizacoes'));
      expect(pagina, contains('unawaited(_recarregarPorRealtime())'));
      expect(pagina, contains('Future<void> _recarregarPorRealtime() async'));
      expect(pagina, contains('_recarregandoPorRealtime'));
      expect(pagina, contains('_operacionalRealtimeSubscription?.cancel();'));
    }

    expect(estoque, contains('_repository.listarItens'));
    expect(estoque, contains('_repository.listarMovimentacoes'));
    expect(estoque, contains('_repository.obterConfiguracao'));
    expect(financeiro, contains('_dashboard.carregar'));
    expect(financeiro, contains('_contasRepository.listar'));
  });
}
