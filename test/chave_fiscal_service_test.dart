import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/repositories/nota_fiscal_entrada_repository.dart';
import 'package:imperium_detailing/services/chave_fiscal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('aceita chave valida com DV correto', () {
    final resultado = ChaveFiscalService().extrair(
      _chave,
      origem: 'chaveManual',
    );
    expect(resultado.chave, _chave);
  });

  test('extrai metadados fiscais diretamente da chave', () {
    const chaveNfce = '35240845543915098211650170000016801096369037';
    final dados = ChaveFiscalService.metadados(chaveNfce);

    expect(dados.modelo, 65);
    expect(dados.cnpjEmitente, '45543915098211');
    expect(dados.serie, 17);
    expect(dados.numero, 1680);
  });

  test('rejeita chave de 44 digitos com DV errado', () {
    expect(
      () => ChaveFiscalService().extrair(
        '00000000000000000000000000000000000000000001',
        origem: 'chaveManual',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('aceita chave formatada com espacos', () {
    final resultado = ChaveFiscalService().extrair(
      '0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000',
      origem: 'codigoBarras',
    );
    expect(resultado.chave, _chave);
  });

  test('extrai chave do parametro p de URL QR NFC-e', () {
    final resultado = ChaveFiscalService().extrair(
      'https://nfce.exemplo.test/consulta?p=$_chave|2|1|ABC',
      origem: 'qrCode',
    );
    expect(resultado.chave, _chave);
  });

  test('extrai chave de conteudo que a contem claramente', () {
    final resultado = ChaveFiscalService().extrair(
      'codigo=$_chave;ambiente=2',
      origem: 'codigoBarras',
    );
    expect(resultado.chave, _chave);
  });

  test('rejeita conteudo sem chave', () {
    expect(
      () => ChaveFiscalService().extrair('sem chave aqui', origem: 'qrCode'),
      throwsA(isA<FormatException>()),
    );
  });

  test('registro preliminar repetido nao duplica', () async {
    final fixture = await _Fixture.create();
    final service = ChaveFiscalService(repository: fixture.repository);

    final primeira = await service.registrarPreliminar(
      _chave,
      origem: 'qrCode',
    );
    final segunda = await service.registrarPreliminar(
      '$_chave|2|1|ABC',
      origem: 'qrCode',
    );

    expect(segunda.id, primeira.id);
    expect(await fixture.db.query('notas_fiscais_entrada'), hasLength(1));
    expect(segunda.statusImportacao, 'pendente');
    await fixture.close();
  });
}

const _chave = '00000000000000000000000000000000000000000000';

class _Fixture {
  _Fixture(this.db, this.repository);

  final Database db;
  final NotaFiscalEntradaRepository repository;

  static Future<_Fixture> create() async {
    final db = await openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE notas_fiscais_entrada (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chave_acesso TEXT NOT NULL UNIQUE,
        modelo INTEGER, numero INTEGER, serie INTEGER, data_emissao TEXT,
        fornecedor_id INTEGER, emitente_cnpj_cpf TEXT, emitente_nome TEXT,
        valor_produtos REAL, valor_frete REAL NOT NULL DEFAULT 0,
        valor_seguro REAL NOT NULL DEFAULT 0, valor_desconto REAL NOT NULL DEFAULT 0,
        valor_outras_despesas REAL NOT NULL DEFAULT 0, valor_ipi REAL NOT NULL DEFAULT 0,
        valor_icms_st REAL NOT NULL DEFAULT 0, valor_total REAL,
        situacao_fiscal TEXT NOT NULL DEFAULT 'desconhecida',
        status_importacao TEXT NOT NULL DEFAULT 'pendente',
        origem_importacao TEXT NOT NULL, xml_original TEXT, xml_hash TEXT,
        importada_em TEXT NOT NULL, observacoes TEXT NOT NULL DEFAULT ''
      )
    ''');
    return _Fixture(
      db,
      NotaFiscalEntradaRepository(databaseProvider: () async => db),
    );
  }

  Future<void> close() => db.close();
}
