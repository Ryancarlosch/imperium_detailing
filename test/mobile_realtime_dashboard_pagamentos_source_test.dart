import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard e pagamentos mobile atualizam apos sync realtime', () {
    final dashboard = File(
      'lib/screens/dashboard_page.dart',
    ).readAsStringSync();
    final pagamentos = File(
      'lib/screens/pagamentos_page.dart',
    ).readAsStringSync();

    expect(
      dashboard,
      contains("import '../services/operacional_realtime_service.dart';"),
    );
    expect(dashboard, contains('StreamSubscription<void>?'));
    expect(dashboard, contains('.atualizacoes'));
    expect(dashboard, contains('unawaited(_recarregarResumoPorRealtime())'));
    expect(
      dashboard,
      contains('Future<void> _recarregarResumoPorRealtime() async'),
    );
    expect(dashboard, contains('_dashboardRepository.carregarDashboard'));
    expect(dashboard, contains('_financeiroDashboardRepository.carregar'));
    expect(
      dashboard,
      contains('_operacionalRealtimeSubscription?.cancel();'),
    );

    expect(
      pagamentos,
      contains("import '../services/operacional_realtime_service.dart';"),
    );
    expect(pagamentos, contains('StreamSubscription<void>?'));
    expect(pagamentos, contains('.atualizacoes'));
    expect(pagamentos, contains('unawaited(_recarregarPorRealtime())'));
    expect(
      pagamentos,
      contains('Future<void> _recarregarPorRealtime() async'),
    );
    expect(pagamentos, contains('_repository.listarContasReceber'));
    expect(pagamentos, contains('_repository.obterResumoGeral'));
    expect(pagamentos, contains('_repository.buscarResumoOrdem'));
    expect(pagamentos, contains('_repository.listarPagamentosDaOrdem'));
    expect(pagamentos, contains('_repository.listarAjustesDaOrdem'));
    expect(pagamentos, contains('_executando'));
    expect(
      pagamentos,
      contains('_operacionalRealtimeSubscription?.cancel();'),
    );
  });
}
