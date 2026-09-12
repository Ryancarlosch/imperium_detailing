import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Estoque Cloud V2 baixa novos sem reaplicar saldo', () {
    final service = File(
      'lib/services/estoque_cloud_download_service.dart',
    ).readAsStringSync();

    expect(service, contains('estoque-cloud-download-v2'));
    expect(service, contains("_baixarItensNovos"));
    expect(service, contains("_baixarLotesNovos"));
    expect(service, contains("_baixarMovimentacoesNovas"));

    expect(service, contains("database.insert(\n        'itens_estoque'"));
    expect(service, contains("database.insert(\n        'estoque_lotes'"));
    expect(
      service,
      contains("database.insert(\n        'movimentacoes_estoque'"),
    );

    expect(
      service,
      isNot(contains('EstoqueRepository().registrarMovimentacao')),
    );
    expect(
      service,
      contains('não altera\n      // novamente itens_estoque.quantidade'),
    );
  });

  test('Estoque Cloud V2 nao sobrescreve registros ja mapeados', () {
    final service = File(
      'lib/services/estoque_cloud_download_service.dart',
    ).readAsStringSync();

    expect(service, contains('_mapaPorRemoto'));
    expect(service, contains('continue;'));
    expect(
      service,
      isNot(contains("database.update(\n        'itens_estoque'")),
    );
    expect(
      service,
      isNot(contains("database.update(\n        'estoque_lotes'")),
    );
  });

  test('Sync operacional baixa Estoque depois de OS Cloud', () {
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    expect(sync, contains("import 'estoque_cloud_download_service.dart';"));
    expect(
      sync,
      contains(
        'await EstoqueCloudDownloadService.instance.'
        'sincronizarDownloadNovos(empresaId);',
      ),
    );

    final osDownload = sync.indexOf(
      'await OsCloudDownloadService.instance.sincronizarDownloadNovos(empresaId);',
    );
    final estoqueDownload = sync.indexOf(
      'await EstoqueCloudDownloadService.instance.'
      'sincronizarDownloadNovos(empresaId);',
    );

    expect(osDownload, greaterThanOrEqualTo(0));
    expect(estoqueDownload, greaterThan(osDownload));
  });

  test('SQLite permanece v33', () {
    final database = File('lib/database/app_database.dart').readAsStringSync();

    expect(database, contains('static const int schemaVersion = 33;'));
  });
}
