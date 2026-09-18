import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRM e Orcamentos mobile atualizam apos sync realtime', () {
    final realtime = File(
      'lib/services/operacional_realtime_service.dart',
    ).readAsStringSync();
    final crm = File('lib/screens/crm_page.dart').readAsStringSync();
    final crmOperacao = File(
      'lib/screens/crm_operacao_page.dart',
    ).readAsStringSync();
    final orcamentos = File(
      'lib/screens/orcamentos_page.dart',
    ).readAsStringSync();
    final detalheOrcamento = File(
      'lib/screens/orcamento_detalhes_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260918022017_mobile_realtime_crm_orcamentos_v1.sql',
    ).readAsStringSync();

    for (final tabela in <String>[
      'imperium_orcamentos',
      'imperium_orcamento_itens',
      'imperium_crm_leads',
      'imperium_crm_interacoes',
      'imperium_crm_campanhas',
      'imperium_crm_cupons',
    ]) {
      expect(realtime, contains("registrar('$tabela')"));
      expect(migration, contains('public.$tabela'));
    }

    expect(migration, contains('alter publication supabase_realtime'));
    expect(migration, contains("pubname = 'supabase_realtime'"));

    expect(
      RegExp(r'StreamSubscription<void>\?').allMatches(crm).length,
      greaterThanOrEqualTo(3),
    );
    expect(
      RegExp(r'unawaited\(_recarregarPorRealtime\(\)\)').allMatches(crm).length,
      greaterThanOrEqualTo(3),
    );
    expect(crm, contains('_repository.listarLeads'));
    expect(crm, contains('widget.repository.listarInteracoes'));
    expect(crm, contains('widget.repository.listarCampanhas'));
    expect(crm, contains('widget.repository.listarCupons'));

    expect(crmOperacao, contains('StreamSubscription<void>?'));
    expect(crmOperacao, contains('.atualizacoes'));
    expect(crmOperacao, contains('unawaited(_recarregarPorRealtime())'));
    expect(crmOperacao, contains('_repository.sincronizarAcoes()'));
    expect(crmOperacao, contains('_repository.listarAcoes'));

    expect(orcamentos, contains('StreamSubscription<void>?'));
    expect(orcamentos, contains('.atualizacoes'));
    expect(orcamentos, contains('unawaited(_recarregarPorRealtime())'));
    expect(orcamentos, contains('_repository.listarOrcamentosComDetalhes'));

    expect(detalheOrcamento, contains('StreamSubscription<void>?'));
    expect(detalheOrcamento, contains('.atualizacoes'));
    expect(detalheOrcamento, contains('unawaited(_recarregarPorRealtime())'));
    expect(
      detalheOrcamento,
      contains('_repository.buscarOrcamentoComDetalhes'),
    );
    expect(detalheOrcamento, contains('_alterandoStatus'));
    expect(detalheOrcamento, contains('_excluindo'));

    for (final pagina in <String>[
      crm,
      crmOperacao,
      orcamentos,
      detalheOrcamento,
    ]) {
      expect(
        pagina,
        contains("import '../services/operacional_realtime_service.dart';"),
      );
      expect(pagina, contains('_operacionalRealtimeSubscription?.cancel();'));
    }
  });
}
