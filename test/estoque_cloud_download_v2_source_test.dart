import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque Cloud V2 baixa novos sem reaplicar saldo', () {
    final service = File(
      'lib/services/estoque_cloud_download_service.dart',
    ).readAsStringSync();
    final compact = service.replaceAll(RegExp(r'\s+'), '');

    expect(service, contains('estoque-cloud-download-v2'));
    expect(service, contains('_baixarItensNovos'));
    expect(service, contains('_baixarLotesNovos'));
    expect(service, contains('_baixarMovimentacoesNovas'));

    expect(compact, contains("database.insert('itens_estoque',{"));
    expect(compact, contains("database.insert('estoque_lotes',{"));
    expect(compact, contains("database.insert('movimentacoes_estoque',{"));

    expect(
      service,
      isNot(contains('EstoqueRepository().registrarMovimentacao')),
    );
    expect(
      compact,
      contains('nãoalteranovamenteitens_estoque.quantidade'),
    );
  });

  test('Estoque Cloud V2 nao sobrescreve registros ja mapeados', () {
    final service = File(
      'lib/services/estoque_cloud_download_service.dart',
    ).readAsStringSync();
    final compact = service.replaceAll(RegExp(r'\s+'), '');

    expect(service, contains('_mapaPorRemoto'));
    expect(service, contains('continue;'));
    expect(compact, isNot(contains("database.update('itens_estoque'")));
    expect(compact, isNot(contains("database.update('estoque_lotes'")));
  });

  test('Sync operacional executa Estoque depois de OS Cloud', () {
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = sync.replaceAll(RegExp(r'\s+'), '');

    expect(sync, contains("import 'estoque_cloud_download_service.dart';"));
    expect(compact, contains("modulo:'ordens_servico',prioridade:30"));
    expect(compact, contains("modulo:'estoque',prioridade:60"));
    expect(
      compact,
      contains("dependencias:const<String>['ordens_servico']"),
    );
    expect(compact, contains('executar:()=>_syncEstoque(empresaId)'));
    expect(
      compact,
      contains(
        'awaitEstoqueCloudDownloadService.instance'
        '.sincronizarDownloadNovos(empresaId);',
      ),
    );
  });

  test('SQLite permanece v33', () {
    final database = File('lib/database/app_database.dart').readAsStringSync();

    expect(database, contains('static const int schemaVersion = 33;'));
  });
}
