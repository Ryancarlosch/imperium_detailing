import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auditoria da migracao final permanece somente leitura e protegida', () {
    final migration = File(
      'supabase/migrations/20260918024916_migracao_final_auditoria_v1.sql',
    ).readAsStringSync();
    final service = File(
      'lib/services/migracao_final_auditoria_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/screens/migracao_final_auditoria_page.dart',
    ).readAsStringSync();
    final saude = File(
      'lib/screens/saude_sistema_page.dart',
    ).readAsStringSync();

    expect(migration, contains('security invoker'));
    expect(migration, contains('private.usuario_admin_empresa'));
    expect(
      migration,
      contains('revoke all on function public.imperium_migracao_auditoria_v1'),
    );
    expect(migration, contains('from public, anon'));
    expect(migration, contains('grant execute'));
    expect(migration, contains('to authenticated'));

    for (final chave in <String>[
      'clientes_contagem',
      'veiculos_contagem',
      'ordens_servico_contagem',
      'estoque_itens_contagem',
      'financeiro_movimentos_contagem',
      'pagamentos_os_contagem',
      'estoque_quantidade_total',
      'financeiro_entradas_realizadas',
      'financeiro_saidas_realizadas',
      'pagamentos_os_pagos_total',
    ]) {
      expect(migration, contains("'$chave'"));
      expect(service, contains("'$chave'"));
    }

    expect(service, contains('final empresaLocal = await _appDatabase.empresaAtivaId'));
    expect(
      service,
      contains(
        "'O SQLite ativo não corresponde à empresa selecionada na nuvem.'",
      ),
    );
    expect(service, contains("client.rpc("));
    expect(
      service,
      contains("'imperium_migracao_auditoria_v1'"),
    );

    // A auditoria local executa somente SELECTs.
    expect(service, isNot(contains('database.insert(')));
    expect(service, isNot(contains('database.update(')));
    expect(service, isNot(contains('database.delete(')));

    expect(
      page,
      contains("title: const Text('Auditoria da migração final')"),
    );
    expect(page, contains('Ela não promove a nuvem nem altera dados.'));
    expect(page, contains('SQLite e Cloud conferem neste gate'));
    expect(page, contains('Não promova a nuvem como fonte principal'));

    expect(
      saude,
      contains("import 'migracao_final_auditoria_page.dart';"),
    );
    expect(saude, contains("label: const Text('Auditar migração final')"));
    expect(saude, contains('MigracaoFinalAuditoriaPage'));
    expect(
      saude,
      isNot(contains('migra Financeiro nem Estoque para a nuvem')),
    );
  });
}
