import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OS mobile usa Realtime como gatilho e continua lendo o SQLite', () {
    final realtime = File(
      'lib/services/operacional_realtime_service.dart',
    ).readAsStringSync();
    final pagina = File(
      'lib/screens/ordens_servico_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260917185732_os_mobile_realtime_v1.sql',
    ).readAsStringSync();

    for (final tabela in <String>[
      'imperium_ordens_servico',
      'imperium_ordem_servico_itens',
      'imperium_financeiro_pagamentos_os',
    ]) {
      expect(realtime, contains("registrar('$tabela')"));
      expect(migration, contains('public.$tabela'));
    }

    expect(migration, contains('alter publication supabase_realtime'));
    expect(migration, contains("pubname = 'supabase_realtime'"));

    expect(
      pagina,
      contains("import '../services/operacional_realtime_service.dart';"),
    );
    expect(pagina, contains('StreamSubscription<void>?'));
    expect(pagina, contains('.atualizacoes'));
    expect(pagina, contains('unawaited(_recarregarPorRealtime())'));
    expect(pagina, contains('Future<void> _recarregarPorRealtime() async'));
    expect(pagina, contains('_recarregandoPorRealtime'));
    expect(pagina, contains('_executandoAcao'));
    expect(pagina, contains('_carregando'));
    expect(pagina, contains('listarOrdensServicoComDetalhes'));
    expect(pagina, contains('statusConsultado != _statusSelecionado'));
    expect(pagina, contains('pesquisaConsultada != _pesquisaController.text'));
    expect(pagina, contains('_operacionalRealtimeSubscription?.cancel();'));

    final consultaLocal = pagina.indexOf(
      '_repository.listarOrdensServicoComDetalhes',
      pagina.indexOf('Future<void> _recarregarPorRealtime() async'),
    );
    final setState = pagina.indexOf('setState(() {', consultaLocal);
    expect(consultaLocal, greaterThanOrEqualTo(0));
    expect(setState, greaterThan(consultaLocal));
  });
}
