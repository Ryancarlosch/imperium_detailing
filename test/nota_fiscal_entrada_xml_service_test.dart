import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/repositories/nota_fiscal_entrada_repository.dart';
import 'package:imperium_detailing/services/nota_fiscal_entrada_xml_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('parseia NF-e modelo 55 com valores e item', () {
    final resultado = NotaFiscalEntradaXmlService().parsear(
      _xml(modelo: 55, processado: true),
    );

    expect(resultado.nota.chaveAcesso, _chave);
    expect(resultado.nota.modelo, 55);
    expect(resultado.nota.numero, 123);
    expect(resultado.nota.serie, 1);
    expect(resultado.nota.emitenteCnpjCpf, '12345678000199');
    expect(resultado.nota.emitenteNome, 'Fornecedor Teste');
    expect(resultado.nota.valorProdutos, 10.0);
    expect(resultado.nota.valorFrete, 1.5);
    expect(resultado.nota.valorSeguro, 0.5);
    expect(resultado.nota.valorDesconto, 0.25);
    expect(resultado.nota.valorOutrasDespesas, 0.75);
    expect(resultado.nota.valorIpi, 0.1);
    expect(resultado.nota.valorIcmsSt, 0.2);
    expect(resultado.nota.valorTotal, 12.3);
    expect(resultado.nota.situacaoFiscal, 'autorizada');
    expect(resultado.nota.xmlOriginal, _xml(modelo: 55, processado: true));
    expect(resultado.nota.xmlHash, isNotEmpty);
    expect(resultado.itens, hasLength(1));
    expect(resultado.itens.single.numeroItem, 1);
    expect(resultado.itens.single.codigoProduto, 'ABC');
    expect(resultado.itens.single.ean, '7891234567890');
    expect(resultado.itens.single.descricao, 'Produto Teste');
    expect(resultado.itens.single.ncm, '12345678');
    expect(resultado.itens.single.cfop, '5102');
    expect(resultado.itens.single.unidade, 'UN');
    expect(resultado.itens.single.quantidade, 2.0);
    expect(resultado.itens.single.valorUnitario, 5.0);
    expect(resultado.itens.single.valorTotal, 10.0);
    expect(resultado.itens.single.valorDesconto, 0.25);
  });

  test('parseia NFC-e modelo 65 e aceita valor total zero', () {
    final resultado = NotaFiscalEntradaXmlService().parsear(
      _xml(modelo: 65, valorTotal: '0.00', incluirProtocolo: false),
    );

    expect(resultado.nota.modelo, 65);
    expect(resultado.nota.valorTotal, 0);
    expect(resultado.nota.situacaoFiscal, 'desconhecida');
  });

  test('parseia XML com namespace SEFAZ', () {
    final resultado = NotaFiscalEntradaXmlService().parsear(
      _xml(modelo: 55, namespace: 'http://www.portalfiscal.inf.br/nfe'),
    );

    expect(resultado.nota.modelo, 55);
    expect(resultado.itens.single.descricao, 'Produto Teste');
  });

  test('parseia nfeProc e valida protocolo autorizado', () {
    final resultado = NotaFiscalEntradaXmlService().parsear(
      _xml(modelo: 55, processado: true),
    );

    expect(resultado.nota.situacaoFiscal, 'autorizada');
    expect(resultado.nota.chaveAcesso, _chave);
  });

  test('rejeita XML invalido e XML sem infNFe', () {
    final service = NotaFiscalEntradaXmlService();

    expect(() => service.parsear('<NFe>'), throwsA(isA<FormatException>()));
    expect(
      () => service.parsear('<root><ide /></root>'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita modelo nao suportado e chave invalida', () {
    final service = NotaFiscalEntradaXmlService();

    expect(
      () => service.parsear(_xml(modelo: 99)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.parsear(_xml(modelo: 55, chave: '123')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejeita chaves divergentes entre infNFe e protocolo', () {
    expect(
      () => NotaFiscalEntradaXmlService().parsear(
        _xml(modelo: 55, processado: true, chaveProtocolo: _outraChave),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('importar duas vezes o mesmo XML nao duplica nota nem itens', () async {
    final fixture = await _Fixture.create();
    final service = NotaFiscalEntradaXmlService(repository: fixture.repository);
    final xml = _xml(modelo: 55);

    final primeira = await service.importarXml(xml);
    final segunda = await service.importarXml(xml);

    expect(segunda.id, primeira.id);
    expect(await fixture.db.query('notas_fiscais_entrada'), hasLength(1));
    expect(await fixture.db.query('notas_fiscais_entrada_itens'), hasLength(1));
    await fixture.close();
  });
}

const _chave = '00000000000000000000000000000000000000000000';
const _outraChave = '00000000000000000000000000000000000000000001';

String _xml({
  required int modelo,
  String chave = _chave,
  String? chaveProtocolo,
  String namespace = '',
  bool processado = false,
  bool incluirProtocolo = true,
  String valorTotal = '12.30',
}) {
  final prefix = namespace.isEmpty ? '' : ' xmlns="$namespace"';
  final nfe =
      '''
<NFe$prefix>
  <infNFe Id="NFe$chave" versao="4.00">
    <ide>
      <mod>$modelo</mod><nNF>123</nNF><serie>1</serie>
      <dhEmi>2026-09-08T10:00:00-03:00</dhEmi>
    </ide>
    <emit><CNPJ>12345678000199</CNPJ><xNome>Fornecedor Teste</xNome></emit>
    <det nItem="1"><prod>
      <cProd>ABC</cProd><cEAN>7891234567890</cEAN><xProd>Produto Teste</xProd>
      <NCM>12345678</NCM><CFOP>5102</CFOP><uCom>UN</uCom>
      <qCom>2.0000</qCom><vUnCom>5.00</vUnCom><vProd>10.00</vProd><vDesc>0.25</vDesc>
    </prod><imposto><IPI><IPITrib><vIPI>0.10</vIPI></IPITrib></IPI></imposto></det>
    <total><ICMSTot>
      <vProd>10.00</vProd><vFrete>1.50</vFrete><vSeg>0.50</vSeg><vDesc>0.25</vDesc>
      <vOutro>0.75</vOutro><vST>0.20</vST><vIPI>0.10</vIPI><vNF>$valorTotal</vNF>
    </ICMSTot></total>
  </infNFe>
</NFe>
''';
  if (!processado) return nfe;

  final protocoloChave = chaveProtocolo ?? chave;
  return '''<nfeProc$prefix versao="4.00">$nfe
  <protNFe><infProt><chNFe>$protocoloChave</chNFe><cStat>100</cStat></infProt></protNFe>
</nfeProc>''';
}

class _Fixture {
  _Fixture(this.db, this.repository);

  final Database db;
  final NotaFiscalEntradaRepository repository;

  static Future<_Fixture> create() async {
    final db = await openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE notas_fiscais_entrada (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chave_acesso TEXT NOT NULL UNIQUE, modelo INTEGER, numero INTEGER,
        serie INTEGER, data_emissao TEXT, fornecedor_id INTEGER,
        emitente_cnpj_cpf TEXT, emitente_nome TEXT, valor_produtos REAL,
        valor_frete REAL NOT NULL DEFAULT 0, valor_seguro REAL NOT NULL DEFAULT 0,
        valor_desconto REAL NOT NULL DEFAULT 0, valor_outras_despesas REAL NOT NULL DEFAULT 0,
        valor_ipi REAL NOT NULL DEFAULT 0, valor_icms_st REAL NOT NULL DEFAULT 0,
        valor_total REAL, situacao_fiscal TEXT NOT NULL DEFAULT 'desconhecida',
        status_importacao TEXT NOT NULL DEFAULT 'pendente', origem_importacao TEXT NOT NULL,
        xml_original TEXT, xml_hash TEXT, importada_em TEXT NOT NULL,
        observacoes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE notas_fiscais_entrada_itens (
        id INTEGER PRIMARY KEY AUTOINCREMENT, nota_fiscal_id INTEGER NOT NULL,
        numero_item INTEGER NOT NULL, codigo_produto TEXT, ean TEXT,
        descricao TEXT NOT NULL, ncm TEXT, cfop TEXT, unidade TEXT NOT NULL,
        quantidade REAL NOT NULL, valor_unitario REAL NOT NULL, valor_total REAL NOT NULL,
        valor_desconto REAL NOT NULL DEFAULT 0, estoque_item_id INTEGER,
        observacoes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (nota_fiscal_id) REFERENCES notas_fiscais_entrada(id) ON DELETE CASCADE,
        UNIQUE (nota_fiscal_id, numero_item)
      )
    ''');
    return _Fixture(
      db,
      NotaFiscalEntradaRepository(databaseProvider: () async => db),
    );
  }

  Future<void> close() => db.close();
}
