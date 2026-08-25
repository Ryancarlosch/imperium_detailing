import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Etapa 1 mantém arquivos críticos versionados', () {
    const obrigatorios = [
      'lib/services/ponto_nuvem_service.dart',
      'lib/services/ponto_offline_sync_service.dart',
      'lib/services/ponto_nuvem_diagnostico_service.dart',
      'lib/services/ponto_realtime_service.dart',
      'lib/services/funcionario_acesso_service.dart',
      'lib/services/licenca_service.dart',
      'imperium_supabase_ponto_operacoes.sql',
      'ROADMAP-IMPERIUM-MESTRE.md',
    ];

    for (final caminho in obrigatorios) {
      expect(
        File(caminho).existsSync(),
        isTrue,
        reason: 'Arquivo crítico ausente: $caminho',
      );
    }
  });

  test('SQL mestre contém recursos críticos da Etapa 1', () {
    final sql = File(
      'imperium_supabase_ponto_operacoes.sql',
    ).readAsStringSync();

    expect(sql, contains('ponto_registrar_batida'));
    expect(sql, contains('ponto_registrar_batida_offline'));
    expect(sql, contains('ponto_diagnostico'));
    expect(sql, contains('ponto_batidas_idempotencia'));
    expect(sql, contains('supabase_realtime'));
    expect(sql, contains('ponto_sync_estado'));
  });
}
