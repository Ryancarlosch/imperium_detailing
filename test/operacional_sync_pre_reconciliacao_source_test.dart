import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operacional reconcilia antes de publicar e bloqueia conflitos', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    final inicio = source.indexOf(
      'Future<void> _syncOperacionalBase(String empresaId) async',
    );
    final fim = source.indexOf(
      'Future<void> _syncOrdensServico(String empresaId) async',
      inicio,
    );

    expect(inicio, greaterThanOrEqualTo(0));
    expect(fim, greaterThan(inicio));

    final bloco = source.substring(inicio, fim);
    final blocoNormalizado = bloco.replaceAll('\r\n', '\n');

    final reconciliarPrimeiro = RegExp(
      r'OperacionalCloudV2Service\.instance\s*\.prepararUpload',
    ).firstMatch(bloco);
    final publicarCliente = bloco.indexOf('_publicarClientesLocais');
    final baixarClientes = bloco.indexOf('_baixarClientes');

    expect(reconciliarPrimeiro, isNotNull);
    expect(publicarCliente, greaterThan(reconciliarPrimeiro!.start));
    expect(baixarClientes, greaterThan(publicarCliente));

    expect(
      RegExp(
        r'OperacionalCloudV2Service\.instance\s*\.prepararUpload',
      ).allMatches(bloco).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      blocoNormalizado,
      contains(
        "throw const SyncMotorBloqueadoException(\n"
        "        'Conflitos pendentes em Clientes/Veículos/Agenda.',",
      ),
    );
  });
}
