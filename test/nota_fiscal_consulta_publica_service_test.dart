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

  test('parseia texto renderizado real do portal SAT SEF SC', () {
    const chaveSc = '42260983305235009841650150001422351123456784';
    final service = NotaFiscalConsultaPublicaService();

    final parsed = service.parsearHtml(
      '''
      <html><body>
        <div>Chave de acesso: 4226 0983 3052 3500 9841 6501 5000 1422 3511 2345 6784</div>
      </body></html>
      ''',
      chaveAcesso: chaveSc,
      textoVisivel: '''
COOPERATIVA AGROINDUSTRIAL ALFA
CNPJ: 83.305.235/0098-41
AV TRANCREDO NEVES , SN , , BOM JESUS , ITAIOPOLIS , SC
Filtrar itens...
CHA MATE LEAO PESSEGO 25SAQ (Código: 12065 )
Vl. Total
Qtde.:1 UN: UNIDVl. Unit.: 6,29
6,29
LEITE LVIDA AURORA PAR DESNATILT (Código: 702133 )
Vl. Total
Qtde.:2 UN: UNIDVl. Unit.: 4,99
9,98
Qtd. total de itens:
2
Valor total R\$:
16,27
Descontos R\$:
0,80
Valor a pagar R\$:
15,47
Forma de pagamento:
Valor pago R\$:
17 - Pagamento Instantâneo (PIX)
15,47
Informações gerais da Nota
EMISSÃO NORMAL
Número: 142235 Série: 15 Emissão: 02/09/2026 18:08:21 - Via Consumidor 2
Protocolo de Autorização: 242261350388217 02/09/2026 às 18:11:00
Ambiente de Produção - Versão XML: 4.00 - Versão XSLT: 2.07
''',
    );

    expect(parsed.nota.emitenteNome, 'COOPERATIVA AGROINDUSTRIAL ALFA');
    expect(parsed.nota.emitenteCnpjCpf, '83305235009841');
    expect(parsed.nota.numero, 142235);
    expect(parsed.nota.serie, 15);
    expect(parsed.nota.valorProdutos, closeTo(16.27, 0.001));
    expect(parsed.nota.valorDesconto, closeTo(0.80, 0.001));
    expect(parsed.nota.valorTotal, closeTo(15.47, 0.001));

    expect(parsed.itens, hasLength(2));
    expect(parsed.itens.first.codigoProduto, '12065');
    expect(parsed.itens.first.descricao, 'CHA MATE LEAO PESSEGO 25SAQ');
    expect(parsed.itens.first.unidade, 'UNID');
    expect(parsed.itens.first.quantidade, 1);
    expect(parsed.itens.first.valorUnitario, closeTo(6.29, 0.001));
    expect(parsed.itens.first.valorTotal, closeTo(6.29, 0.001));

    expect(parsed.itens.last.codigoProduto, '702133');
    expect(parsed.itens.last.quantidade, 2);
    expect(parsed.itens.last.valorUnitario, closeTo(4.99, 0.001));
    expect(parsed.itens.last.valorTotal, closeTo(9.98, 0.001));
  });

  test('identifica fornecedor quando CNPJ aparece antes da razão social', () {
    final service = NotaFiscalConsultaPublicaService();
    final parsed = service.parsearHtml('''
      <html><body>
        <div>CNPJ: 45.543.915/0982-11</div>
        <div>HIPER PRESIDENTE PRUDENTE</div>
        <div>PRODUTO TESTE (Código: 123 )</div>
        <div>Qtde.:1 UN: UN Vl. Unit.: 10,00 Vl. Total 10,00</div>
        <div>Valor a pagar R\$: 10,00</div>
        <div>Emissão: 08/08/2024 13:01:00</div>
        <div>Chave de acesso: 3524 0845 5439 1509 8211 6501 7000 0016 8010 9636 9037</div>
      </body></html>
      ''', chaveAcesso: chave);

    expect(parsed.nota.emitenteNome, 'HIPER PRESIDENTE PRUDENTE');
  });

  test('identifica fornecedor em linha tabular CNPJ razão social IE UF', () {
    final service = NotaFiscalConsultaPublicaService();
    final parsed = service.parsearHtml('''
      <html><body>
        <div>CNPJ Nome / Razão Social Inscrição Estadual UF</div>
        <div>45.543.915/0982-11 HIPER PRESIDENTE PRUDENTE IE: 123456789 SC</div>
        <div>PRODUTO TESTE (Código: 123 )</div>
        <div>Qtde.:1 UN: UN Vl. Unit.: 10,00 Vl. Total 10,00</div>
        <div>Valor a pagar R\$: 10,00</div>
        <div>Emissão: 08/08/2024 13:01:00</div>
        <div>Chave de acesso: 3524 0845 5439 1509 8211 6501 7000 0016 8010 9636 9037</div>
      </body></html>
      ''', chaveAcesso: chave);

    expect(parsed.nota.emitenteNome, 'HIPER PRESIDENTE PRUDENTE');
  });

  test('resolve URL relativa de frame fiscal no portal oficial', () {
    final resolved = NotaFiscalConsultaPublicaService.resolverUrlPortal(
      Uri.parse('https://sat.sef.sc.gov.br/nfce/consulta?p=abc'),
      '/tax.net/Sat.Dfe.NFCe.Web/Consultas/NFe_Print.aspx?id=1',
    );
    expect(resolved, isNotNull);
    expect(resolved!.host, 'sat.sef.sc.gov.br');
    expect(resolved.path, contains('NFe_Print.aspx'));

    expect(
      NotaFiscalConsultaPublicaService.resolverUrlPortal(
        Uri.parse('https://sat.sef.sc.gov.br/nfce/consulta'),
        'https://exemplo.com/frame',
      ),
      isNull,
    );
  });
}
