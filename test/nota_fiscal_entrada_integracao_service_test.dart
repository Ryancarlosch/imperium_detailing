import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/services/nota_fiscal_entrada_integracao_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('encontra fornecedor por CNPJ normalizado e nao duplica', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.db.insert('fornecedores', {
      'nome': 'Fornecedor',
      'documento': '12.345.678/0001-99',
      'criado_em': 'x',
      'atualizado_em': 'x',
    });
    final service = fixture.service;

    expect(await service.fornecedorExistentePorDocumento('12345678000199'), 1);
    expect(
      await service.criarFornecedorConfirmado(
        nome: 'Mesmo fornecedor',
        documento: '12345678000199',
      ),
      1,
    );
    expect(await fixture.db.query('fornecedores'), hasLength(1));
  });

  test(
    'localiza item por descricao exata quando EAN nao veio no DANFE',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final itemId = await fixture.db.insert('itens_estoque', {
        'nome': 'Shampoo Neutro 5L',
        'ean': '',
        'quantidade': 0,
        'custo_unitario': 10,
        'custo_unitario_calculado': 10,
        'ativo': 1,
        'unidade': 'un',
        'atualizado_em': 'x',
      });

      expect(
        await fixture.service.localizarItensPorDescricaoExata(
          '  shampoo neutro 5l  ',
        ),
        [itemId],
      );
    },
  );

  test('vincula item por EAN e registra entrada uma única vez', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final itemId = await fixture.db.insert('itens_estoque', {
      'nome': 'Shampoo',
      'ean': '7891234567890',
      'quantidade': 0,
      'custo_unitario': 10,
      'custo_unitario_calculado': 10,
      'ativo': 1,
      'unidade': 'un',
      'atualizado_em': 'x',
    });
    final notaId = await fixture.criarNota(itemId: itemId);
    final service = fixture.service;

    expect(await service.localizarItensPorEan('7891234567890'), [itemId]);
    await service.confirmarEntradaEstoque(notaId);
    await service.confirmarEntradaEstoque(notaId);

    final item = await fixture.db.query(
      'itens_estoque',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    expect(item.single['quantidade'], 2.0);
    expect(item.single['quantidade_total'], 2.0);
    expect(item.single['valor_total_pago'], 20.0);
    expect(item.single['custo_unitario_calculado'], 10.0);
    expect(await fixture.db.query('movimentacoes_estoque'), hasLength(1));
    expect(await fixture.db.query('estoque_lotes'), hasLength(1));
  });

  test('documento não autorizado não movimenta estoque', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final itemId = await fixture.db.insert('itens_estoque', {
      'nome': 'Produto',
      'quantidade': 0,
      'custo_unitario': 10,
      'custo_unitario_calculado': 10,
      'ativo': 1,
      'unidade': 'un',
      'atualizado_em': 'x',
    });
    final notaId = await fixture.criarNota(
      itemId: itemId,
      situacaoFiscal: 'cancelada',
    );

    await expectLater(
      fixture.service.confirmarEntradaEstoque(notaId),
      throwsA(isA<StateError>()),
    );
    expect(await fixture.db.query('movimentacoes_estoque'), isEmpty);
    expect(await fixture.db.query('estoque_lotes'), isEmpty);
  });

  test('falha em item sem vínculo faz rollback da entrada', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final itemId = await fixture.db.insert('itens_estoque', {
      'nome': 'Shampoo',
      'quantidade': 0,
      'custo_unitario': 10,
      'custo_unitario_calculado': 10,
      'ativo': 1,
      'unidade': 'un',
      'atualizado_em': 'x',
    });
    final notaId = await fixture.criarNota(
      itemId: itemId,
      segundoSemVinculo: true,
    );

    expect(
      () => fixture.service.confirmarEntradaEstoque(notaId),
      throwsStateError,
    );
    expect(await fixture.db.query('movimentacoes_estoque'), isEmpty);
    expect(await fixture.db.query('estoque_lotes'), isEmpty);
    final item = await fixture.db.query(
      'itens_estoque',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    expect(item.single['quantidade'], 0.0);
  });
}

class _Fixture {
  _Fixture(this.db, this.service);
  final Database db;
  final NotaFiscalEntradaIntegracaoService service;

  static Future<_Fixture> create() async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute(
      'CREATE TABLE fornecedores (id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT, documento TEXT, criado_em TEXT, atualizado_em TEXT, ativo INTEGER NOT NULL DEFAULT 1)',
    );
    await db.execute(
      'CREATE TABLE itens_estoque (id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT, categoria TEXT NOT NULL DEFAULT \'\', ean TEXT NOT NULL DEFAULT \'\', quantidade REAL NOT NULL DEFAULT 0, quantidade_minima REAL NOT NULL DEFAULT 0, quantidade_total REAL NOT NULL DEFAULT 0, valor_total_pago REAL NOT NULL DEFAULT 0, custo_unitario REAL NOT NULL DEFAULT 0, custo_unitario_calculado REAL NOT NULL DEFAULT 0, unidade TEXT NOT NULL DEFAULT \'un\', fornecedor TEXT NOT NULL DEFAULT \'\', observacoes TEXT NOT NULL DEFAULT \'\', ativo INTEGER NOT NULL DEFAULT 1, atualizado_em TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE notas_fiscais_entrada (id INTEGER PRIMARY KEY AUTOINCREMENT, chave_acesso TEXT UNIQUE, fornecedor_id INTEGER, emitente_nome TEXT, emitente_cnpj_cpf TEXT, status_importacao TEXT, data_emissao TEXT, valor_total REAL, origem_importacao TEXT, situacao_fiscal TEXT, importada_em TEXT)',
    );
    await db.execute(
      'CREATE TABLE notas_fiscais_entrada_itens (id INTEGER PRIMARY KEY AUTOINCREMENT, nota_fiscal_id INTEGER, numero_item INTEGER, descricao TEXT, unidade TEXT, quantidade REAL, valor_unitario REAL, valor_total REAL, valor_desconto REAL NOT NULL DEFAULT 0, estoque_item_id INTEGER)',
    );
    await db.execute(
      'CREATE TABLE estoque_lotes (id INTEGER PRIMARY KEY AUTOINCREMENT, item_estoque_id INTEGER, data_compra TEXT, quantidade_original REAL, quantidade_normalizada REAL, quantidade_disponivel REAL, unidade_original TEXT, unidade_base TEXT, valor_total_pago REAL, custo_unitario REAL, fornecedor TEXT, observacao TEXT, ativo INTEGER, criado_em TEXT)',
    );
    await db.execute(
      'CREATE TABLE movimentacoes_estoque (id INTEGER PRIMARY KEY AUTOINCREMENT, item_estoque_id INTEGER, tipo TEXT, quantidade REAL, quantidade_anterior REAL, quantidade_posterior REAL, custo_unitario REAL, observacoes TEXT, motivo TEXT, origem TEXT, ordem_servico_id INTEGER, lote_id INTEGER, nota_fiscal_id INTEGER, nota_fiscal_item_id INTEGER, data TEXT)',
    );
    await db.execute(
      "CREATE UNIQUE INDEX idx_mov_estoque_nf_item_entrada_unica ON movimentacoes_estoque (nota_fiscal_id, nota_fiscal_item_id) WHERE nota_fiscal_id IS NOT NULL AND nota_fiscal_item_id IS NOT NULL AND tipo = 'ENTRADA' AND origem = 'Nota fiscal de entrada'",
    );
    return _Fixture(
      db,
      NotaFiscalEntradaIntegracaoService(databaseProvider: () async => db),
    );
  }

  Future<int> criarNota({
    required int itemId,
    bool segundoSemVinculo = false,
    String situacaoFiscal = 'autorizada',
  }) async {
    final nota = await db.insert('notas_fiscais_entrada', {
      'chave_acesso': '00000000000000000000000000000000000000000000',
      'emitente_nome': 'Fornecedor',
      'emitente_cnpj_cpf': '12345678000199',
      'status_importacao': 'processada',
      'data_emissao': '2026-09-08',
      'valor_total': 20,
      'origem_importacao': 'xml',
      'situacao_fiscal': situacaoFiscal,
      'importada_em': 'x',
    });
    await db.insert('notas_fiscais_entrada_itens', {
      'nota_fiscal_id': nota,
      'numero_item': 1,
      'descricao': 'A',
      'unidade': 'un',
      'quantidade': 2,
      'valor_unitario': 10,
      'valor_total': 20,
      'estoque_item_id': itemId,
    });
    if (segundoSemVinculo) {
      await db.insert('notas_fiscais_entrada_itens', {
        'nota_fiscal_id': nota,
        'numero_item': 2,
        'descricao': 'B',
        'unidade': 'un',
        'quantidade': 1,
        'valor_unitario': 1,
        'valor_total': 1,
      });
    }
    return nota;
  }

  Future<void> close() => db.close();
}
