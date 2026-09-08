import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/models/nota_fiscal_entrada.dart';
import 'package:imperium_detailing/models/nota_fiscal_entrada_item.dart';
import 'package:imperium_detailing/repositories/nota_fiscal_entrada_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('mesma chave nao duplica a nota preliminar', () async {
    final fixture = await _Fixture.create();

    final primeira = await fixture.repository.registrarPreliminar(
      chaveAcesso: _chave,
      origemImportacao: 'chaveManual',
      importadaEm: _data,
    );
    final segunda = await fixture.repository.registrarPreliminar(
      chaveAcesso: _chave,
      origemImportacao: 'qrCode',
      importadaEm: _data,
    );

    expect(segunda.id, primeira.id);
    expect(await fixture.db.query('notas_fiscais_entrada'), hasLength(1));
    await fixture.close();
  });

  test('preliminar e reaproveitada na importacao completa', () async {
    final fixture = await _Fixture.create();
    final preliminar = await fixture.repository.registrarPreliminar(
      chaveAcesso: _chave,
      origemImportacao: 'qrCode',
      importadaEm: _data,
    );

    final completa = await fixture.repository.salvarNotaCompleta(
      nota: _nota(),
      itens: [_item(1, descricao: 'Produto A')],
    );

    expect(completa.id, preliminar.id);
    expect(completa.statusImportacao, 'processada');
    expect(await fixture.db.query('notas_fiscais_entrada'), hasLength(1));
    await fixture.close();
  });

  test('itens nao duplicam e sao reconciliados por numero do item', () async {
    final fixture = await _Fixture.create();
    final nota = await fixture.repository.salvarNotaCompleta(
      nota: _nota(),
      itens: [
        _item(1, descricao: 'Produto A'),
        _item(2, descricao: 'Produto B'),
      ],
    );

    await fixture.repository.salvarNotaCompleta(
      nota: _nota(),
      itens: [
        _item(1, descricao: 'Produto A atualizado'),
        _item(3, descricao: 'Produto C'),
      ],
    );

    var itens = await fixture.repository.listarItensDaNota(nota.id!);
    expect(itens.map((item) => item.numeroItem), [1, 2, 3]);
    expect(itens.first.descricao, 'Produto A atualizado');

    await fixture.repository.salvarNotaCompleta(
      nota: _nota(),
      itens: [_item(1, descricao: 'Produto A final')],
      removerItensAusentes: true,
    );

    itens = await fixture.repository.listarItensDaNota(nota.id!);
    expect(itens, hasLength(1));
    expect(itens.single.numeroItem, 1);
    expect(itens.single.descricao, 'Produto A final');
    await fixture.close();
  });

  test('falha em item faz rollback da nota e dos itens', () async {
    final fixture = await _Fixture.create();

    expect(
      () => fixture.repository.salvarNotaCompleta(
        nota: _nota(),
        itens: [
          _item(1, descricao: 'Produto A'),
          _item(1, descricao: 'Item duplicado'),
        ],
      ),
      throwsArgumentError,
    );

    expect(await fixture.db.query('notas_fiscais_entrada'), isEmpty);
    expect(await fixture.db.query('notas_fiscais_entrada_itens'), isEmpty);
    await fixture.close();
  });

  test('excluir nota remove seus itens por cascade', () async {
    final fixture = await _Fixture.create();
    final nota = await fixture.repository.salvarNotaCompleta(
      nota: _nota(),
      itens: [_item(1)],
    );

    await fixture.repository.excluirNota(nota.id!);

    expect(await fixture.repository.buscarPorId(nota.id!), isNull);
    expect(await fixture.db.query('notas_fiscais_entrada_itens'), isEmpty);
    await fixture.close();
  });
}

const _chave = '12345678901234567890123456789012345678901234';
const _data = '2026-09-07T10:00:00.000Z';

NotaFiscalEntrada _nota() {
  return const NotaFiscalEntrada(
    chaveAcesso: _chave,
    modelo: 55,
    numero: 100,
    serie: 1,
    dataEmissao: '2026-09-06T10:00:00.000Z',
    emitenteCnpjCpf: '12345678000199',
    emitenteNome: 'Fornecedor Fiscal',
    valorProdutos: 100,
    valorTotal: 100,
    situacaoFiscal: 'autorizada',
    origemImportacao: 'xml',
    importadaEm: _data,
  );
}

NotaFiscalEntradaItem _item(int numero, {String descricao = 'Produto'}) {
  return NotaFiscalEntradaItem(
    notaFiscalId: 0,
    numeroItem: numero,
    descricao: descricao,
    unidade: 'UN',
    quantidade: 1,
    valorUnitario: 100,
    valorTotal: 100,
  );
}

class _Fixture {
  _Fixture(this.db, this.repository);

  final Database db;
  final NotaFiscalEntradaRepository repository;

  static Future<_Fixture> create() async {
    final db = await openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('CREATE TABLE fornecedores (id INTEGER PRIMARY KEY)');
    await db.execute('''
      CREATE TABLE notas_fiscais_entrada (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chave_acesso TEXT NOT NULL UNIQUE,
        modelo INTEGER,
        numero INTEGER,
        serie INTEGER,
        data_emissao TEXT,
        fornecedor_id INTEGER,
        emitente_cnpj_cpf TEXT,
        emitente_nome TEXT,
        valor_produtos REAL,
        valor_frete REAL NOT NULL DEFAULT 0,
        valor_seguro REAL NOT NULL DEFAULT 0,
        valor_desconto REAL NOT NULL DEFAULT 0,
        valor_outras_despesas REAL NOT NULL DEFAULT 0,
        valor_ipi REAL NOT NULL DEFAULT 0,
        valor_icms_st REAL NOT NULL DEFAULT 0,
        valor_total REAL,
        situacao_fiscal TEXT NOT NULL DEFAULT 'desconhecida',
        status_importacao TEXT NOT NULL DEFAULT 'pendente',
        origem_importacao TEXT NOT NULL,
        xml_original TEXT,
        xml_hash TEXT,
        importada_em TEXT NOT NULL,
        observacoes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (fornecedor_id) REFERENCES fornecedores (id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notas_fiscais_entrada_itens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nota_fiscal_id INTEGER NOT NULL,
        numero_item INTEGER NOT NULL,
        codigo_produto TEXT,
        ean TEXT,
        descricao TEXT NOT NULL,
        ncm TEXT,
        cfop TEXT,
        unidade TEXT NOT NULL,
        quantidade REAL NOT NULL,
        valor_unitario REAL NOT NULL,
        valor_total REAL NOT NULL,
        valor_desconto REAL NOT NULL DEFAULT 0,
        estoque_item_id INTEGER,
        observacoes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (nota_fiscal_id) REFERENCES notas_fiscais_entrada (id)
          ON DELETE CASCADE,
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
