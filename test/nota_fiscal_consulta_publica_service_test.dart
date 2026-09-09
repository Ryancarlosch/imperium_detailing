import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/services/nota_fiscal_consulta_publica_service.dart';

void main() {
  const chave = '35240845543915098211650170000016801096369037';

  test('parseia NFC-e publica com fornecedor, itens e valores', () {
    final service = NotaFiscalConsultaPublicaService();
    final parsed = service.parsearHtml('''
      <html><body>
        <h1>DOCUMENTO AUXILIAR DA NOTA FISCAL DE CONSUMIDOR ELETRÔNICA</h1>
        <div>HIPER PRESIDENTE PRUDENTE</div>
        <div>CNPJ: 45.543.915/0982-11</div>
        <div>AMC ROUP CONCE DOWNY (Código: 3397270 )</div>
        <div>Qtde.:1 UN: un Vl. Unit.: 54,99 | Vl. Total 54,99</div>
        <div>TOALHA UMED CARREFOU (Código: 5904374 )</div>
        <div>Qtde.:2 UN: un Vl. Unit.: 8,69 | Vl. Total 17,38</div>
        <div>Qtd. total de itens: 2</div>
        <div>Valor total R\$: 72,37</div>
        <div>Descontos R\$: 2,00</div>
        <div>Valor a pagar R\$: 70,37</div>
        <h3>Informações gerais da Nota</h3>
        <div>EMISSÃO NORMAL</div>
        <div>Número: 1680 Série: 17 Emissão: 08/08/2024 13:01:00 - Via Consumidor</div>
        <h3>Chave de acesso</h3>
        <div>Chave de acesso: 3524 0845 5439 1509 8211 6501 7000 0016 8010 9636 9037</div>
      </body></html>
      ''', chaveAcesso: chave);

    expect(parsed.nota.modelo, 65);
    expect(parsed.nota.numero, 1680);
    expect(parsed.nota.serie, 17);
    expect(parsed.nota.emitenteCnpjCpf, '45543915098211');
    expect(parsed.nota.emitenteNome, 'HIPER PRESIDENTE PRUDENTE');
    expect(parsed.nota.valorProdutos, closeTo(72.37, 0.001));
    expect(parsed.nota.valorDesconto, closeTo(2, 0.001));
    expect(parsed.nota.valorTotal, closeTo(70.37, 0.001));
    expect(parsed.nota.situacaoFiscal, 'autorizada');
    expect(parsed.itens, hasLength(2));
    expect(parsed.itens.first.codigoProduto, '3397270');
    expect(parsed.itens.first.ean, isNull);
    expect(parsed.itens.first.descricao, 'AMC ROUP CONCE DOWNY');
    expect(parsed.itens.first.quantidade, 1);
    expect(parsed.itens.first.valorUnitario, closeTo(54.99, 0.001));
    expect(parsed.itens.last.quantidade, 2);
    expect(parsed.itens.last.valorTotal, closeTo(17.38, 0.001));
  });

  test('parseia tabela padrao de produtos', () {
    final service = NotaFiscalConsultaPublicaService();
    final parsed = service.parsearHtml('''
      <html><body>
        <div>HIPER PRESIDENTE PRUDENTE</div>
        <div>CNPJ: 45.543.915/0982-11</div>
        <table>
          <tr><th>Código</th><th>Descrição</th><th>Qtde</th><th>UN</th><th>Vl Unit</th><th>Vl Total</th></tr>
          <tr><td>003277</td><td>PRODUTO A</td><td>1</td><td>CX</td><td>27,64</td><td>27,64</td></tr>
          <tr><td>085273</td><td>PRODUTO B</td><td>3</td><td>LT</td><td>22,00</td><td>66,00</td></tr>
        </table>
        <div>Valor a pagar R\$: 93,64</div>
        <div>Emissão: 08/08/2024 13:01:00</div>
        <div>Chave de acesso: 3524 0845 5439 1509 8211 6501 7000 0016 8010 9636 9037</div>
      </body></html>
      ''', chaveAcesso: chave);

    expect(parsed.itens, hasLength(2));
    expect(parsed.itens.first.unidade, 'CX');
    expect(parsed.itens.last.quantidade, 3);
    expect(parsed.nota.valorTotal, closeTo(93.64, 0.001));
  });

  test('rejeita pagina de homologacao', () {
    final service = NotaFiscalConsultaPublicaService();
    expect(
      () => service.parsearHtml(
        '<html><body>AMBIENTE DE HOMOLOGAÇÃO - SEM VALOR FISCAL $chave</body></html>',
        chaveAcesso: chave,
      ),
      throwsA(isA<ConsultaPublicaFiscalException>()),
    );
  });

  test('aceita pagina liberada mesmo com texto residual de captcha', () {
    final service = NotaFiscalConsultaPublicaService();
    final parsed = service.parsearHtml('''
      <html><body>
        <div>reCAPTCHA</div>
        <div>HIPER PRESIDENTE PRUDENTE</div>
        <div>CNPJ: 45.543.915/0982-11</div>
        <div>PRODUTO TESTE (Código: 123 )</div>
        <div>Qtde.:1 UN: un Vl. Unit.: 10,00 | Vl. Total 10,00</div>
        <div>Valor a pagar R\$: 10,00</div>
        <div>Emissão: 08/08/2024 13:01:00</div>
        <div>Chave de acesso: 3524 0845 5439 1509 8211 6501 7000 0016 8010 9636 9037</div>
      </body></html>
      ''', chaveAcesso: chave);

    expect(parsed.itens, hasLength(1));
    expect(parsed.nota.valorTotal, closeTo(10, 0.001));
  });

  test('pagina ainda parada no captcha sem itens continua pendente', () {
    final service = NotaFiscalConsultaPublicaService();
    expect(
      () => service.parsearHtml(
        '<html><body>reCAPTCHA $chave</body></html>',
        chaveAcesso: chave,
      ),
      throwsA(isA<ConsultaPublicaFiscalException>()),
    );
  });

  test('extrai URL oficial do QR e metadados da chave', () {
    final uri = NotaFiscalConsultaPublicaService.extrairUrlConsulta(
      'https://www.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=$chave|2|1|1|ABC',
    );

    expect(uri, isNotNull);
    expect(uri!.host, 'www.nfce.fazenda.sp.gov.br');
    expect(NotaFiscalConsultaPublicaService.modeloDaChave(chave), 65);
    expect(
      NotaFiscalConsultaPublicaService.cnpjEmitenteDaChave(chave),
      '45543915098211',
    );
    expect(NotaFiscalConsultaPublicaService.serieDaChave(chave), 17);
    expect(NotaFiscalConsultaPublicaService.numeroDaChave(chave), 1680);
  });

  test('aceita portal oficial e rejeita domínio externo', () {
    expect(
      NotaFiscalConsultaPublicaService.urlOficial(
        Uri.parse('https://sat.sef.sc.gov.br/nfce/consulta?p=$chave'),
      ),
      isTrue,
    );
    expect(
      NotaFiscalConsultaPublicaService.urlOficial(
        Uri.parse('https://exemplo.com/nfce/consulta?p=$chave'),
      ),
      isFalse,
    );
  });
}
