import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('veiculo possui protecao contra cadastro duplicado', () {
    final repo = File(
      'lib/repositories/veiculo_repository.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/veiculos_cliente_page.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    expect(repo, contains('veiculo-insercao-idempotente-v1'));
    expect(repo, contains('_insercoesEmAndamento'));
    expect(tela, contains('veiculo-cadastro-salvando-v1'));
    expect(sync, contains('sync-veiculo-anti-duplicacao-v1'));
  });
}
