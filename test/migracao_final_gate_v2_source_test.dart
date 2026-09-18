import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gate v2 bloqueia promocao enquanto houver pendencias tecnicas', () {
    final gate = File(
      'lib/services/migracao_final_gate_v2_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/screens/migracao_final_auditoria_page.dart',
    ).readAsStringSync();
    final validar = File('VALIDAR_APP.ps1').readAsStringSync();

    for (final chave in <String>[
      "chave: 'tenant'",
      "chave: 'sqlite'",
      "chave: 'backup'",
      "chave: 'motor_sync'",
      "chave: 'cobertura_sync'",
      "chave: 'filas'",
      "chave: 'conflitos'",
      "chave: 'storage'",
      "chave: 'auditoria_cloud'",
    ]) {
      expect(gate, contains(chave));
    }

    expect(gate, contains('MigracaoFinalAuditoriaService.instance.auditar()'));
    expect(gate, contains("motorStatus == 'Sucesso'"));
    expect(gate, contains('saude.exclusoesSyncPendentes == 0'));
    expect(gate, contains('saude.pontoPendentes == 0'));
    expect(gate, contains('conflitosTotal == 0'));
    expect(gate, contains('auditoria.tudoConfere'));
    expect(gate, contains('backupDepoisDoSync'));
    expect(gate, contains('ultimoBackupTamanhoBytes > 0'));

    for (final modulo in <String>[
      'OperacionalCloudV2Service',
      'OsCloudV3Service',
      'OsArquivosCloudV2Service',
      'CrmOrcamentosCloudV2Service',
      'EstoqueCloudConflitoService',
      'FinanceiroCloudV2Service',
      'PrecificacaoCloudV2Service',
      'ConfiguracaoCloudService',
      'ConfiguracaoArquivosCloudService',
    ]) {
      expect(gate, contains(modulo));
    }

    // Gate é somente leitura e não executa promoção automática.
    expect(gate, isNot(contains('database.insert(')));
    expect(gate, isNot(contains('database.update(')));
    expect(gate, isNot(contains('database.delete(')));
    expect(gate, isNot(contains('promover(')));

    expect(page, contains('Pré-requisitos do Gate V2'));
    expect(page, contains('Gate V2 aprovado para a próxima etapa'));
    expect(page, contains('bloqueio(s) antes da promoção Cloud'));
    expect(page, contains('Comparação SQLite × Cloud'));

    expect(validar, contains('flutter analyze'));
    expect(validar, contains('flutter test'));
    expect(validar, contains('git diff --check'));
    expect(validar, contains('VALIDACAO IMPERIUM APROVADA.'));
  });
}
