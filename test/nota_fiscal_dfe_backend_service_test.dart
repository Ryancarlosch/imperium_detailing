import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/models/nota_fiscal_entrada.dart';
import 'package:imperium_detailing/services/nota_fiscal_dfe_backend_service.dart';

void main() {
  const chaveNfe = '35240845543915098211550170000016801096369034';

  test('importa XML devolvido pelo backend DF-e', () async {
    String? xmlRecebido;
    final service = NotaFiscalDfeBackendService(
      invoker: (chave) async {
        expect(chave, chaveNfe);
        return {'ok': true, 'xml': '<nfeProc>teste</nfeProc>'};
      },
      xmlImporter: (xml) async {
        xmlRecebido = xml;
        return const NotaFiscalEntrada(
          chaveAcesso: chaveNfe,
          modelo: 55,
          numero: 1680,
          serie: 17,
          emitenteCnpjCpf: '45543915098211',
          emitenteNome: 'FORNECEDOR TESTE',
          valorTotal: 100,
          situacaoFiscal: 'autorizada',
          statusImportacao: 'processada',
          origemImportacao: 'xml',
          importadaEm: '2026-09-08T00:00:00.000',
        );
      },
    );

    final nota = await service.consultarEImportar(chaveNfe);

    expect(xmlRecebido, '<nfeProc>teste</nfeProc>');
    expect(nota.statusImportacao, 'processada');
    expect(nota.modelo, 55);
  });

  test('propaga erro estruturado devolvido pelo backend', () async {
    final service = NotaFiscalDfeBackendService(
      invoker: (_) async => {
        'ok': false,
        'code': 'provider_not_configured',
        'message': 'Provedor ainda não configurado.',
      },
    );

    await expectLater(
      service.consultarEImportar(chaveNfe),
      throwsA(
        isA<DfeBackendException>()
            .having((e) => e.codigo, 'codigo', 'provider_not_configured')
            .having(
              (e) => e.mensagem,
              'mensagem',
              'Provedor ainda não configurado.',
            ),
      ),
    );
  });

  test('não envia NFC-e modelo 65 ao conector DF-e', () async {
    const chaveNfce = '35240845543915098211650170000016801096369037';
    var chamou = false;
    final service = NotaFiscalDfeBackendService(
      invoker: (_) async {
        chamou = true;
        return {'ok': true, 'xml': '<xml />'};
      },
    );

    await expectLater(
      service.consultarEImportar(chaveNfce),
      throwsA(isA<DfeBackendException>()),
    );
    expect(chamou, isFalse);
  });
}
