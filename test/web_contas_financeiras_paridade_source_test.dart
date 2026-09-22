import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Contas Web permitem criar editar ativar e desativar', () {
    final page = File(
      'lib/web/web_contas_financeiras_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_cloud_contas_service.dart',
    ).readAsStringSync();

    expect(page, contains("label: const Text('Nova conta')"));
    expect(page, contains("conta == null ? 'Nova conta' : 'Editar conta'"));
    expect(page, contains("conta.ativa ? 'Desativar' : 'Reativar'"));
    expect(service, contains('Future<Map<String, dynamic>> salvarConta'));
    expect(service, contains('atualizadoEmEsperado'));
    expect(service, contains("from('imperium_financeiro_contas')"));
    expect(service, contains('WebOrigemService.instance.proxima()'));
  });

  test('Extrato Web permite conciliacao com ajuste sem DRE', () {
    final page = File(
      'lib/web/web_contas_financeiras_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_cloud_contas_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260922114500_financeiro_web_conciliacao.sql',
    ).readAsStringSync();

    expect(page, contains("tooltip: 'Conciliar saldo'"));
    expect(page, contains("'Criar ajuste se houver diferença'"));
    expect(page, contains('Correção de caixa (9.05)'));
    expect(service, contains('registrarConciliacao'));
    expect(service, contains("'imperium_financeiro_conciliar_web'"));

    expect(migration, contains('security invoker'));
    expect(migration, isNot(contains('security definer')));
    expect(migration, contains("codigo = '9.05'"));
    expect(migration, contains("'Conciliação de conta'"));
    expect(migration, contains('impacta_dre'));
    expect(migration, contains('false'));
    expect(migration, contains('revoke all on function'));
    expect(migration, contains('grant execute on function'));
  });

  test('Contas Web anunciam sincronizacao com Android', () {
    final page = File(
      'lib/web/web_contas_financeiras_page.dart',
    ).readAsStringSync();

    expect(
      page,
      contains(
        'Alterações feitas aqui ficam disponíveis no Android no próximo ciclo de sincronização.',
      ),
    );
    expect(page, isNot(contains('Edição e conciliação Web serão liberadas')));
  });
}
