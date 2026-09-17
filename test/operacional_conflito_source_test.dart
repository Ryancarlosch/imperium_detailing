import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detector operacional protege conflitos de clientes e veiculos', () {
    final source = File(
      'lib/services/operacional_conflito_service.dart',
    ).readAsStringSync();

    expect(source, contains('class OperacionalConflitoService'));
    expect(source, contains('OperacionalConflitoService.forTesting'));
    expect(source, contains('imperium_sync_operacional_conflitos'));
    expect(source, contains("_detectarEntidade(tenant, 'cliente')"));
    expect(source, contains("_detectarEntidade(tenant, 'veiculo')"));
    expect(source, contains("motivo: 'registro_remoto_ausente'"));
    expect(source, contains("'alteracao_concorrente'"));
    expect(source, contains("'exclusao_remota_e_alteracao_local'"));
    expect(source, contains("mapa['local_hash']"));
    expect(source, contains("mapa['remoto_atualizado_em']"));
    expect(source, contains("remoto['atualizado_em']"));
    expect(source, contains("remoto['excluido_em']"));
    expect(source, contains('sha256.convert'));
    expect(source, contains('listarConflitosPendentes'));
    expect(source, contains('possuiConflitosPendentes'));
    expect(source, contains('diagnosticar'));
  });
}
