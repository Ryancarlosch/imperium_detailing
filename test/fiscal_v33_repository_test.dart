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

  test('preliminar e tentativas são rastreadas sem duplicar a chave', () async {
    final db = await _abrirBancoFiscal();
    addTearDown(db.close);
    final repo = NotaFiscalEntradaRepository(databaseProvider: () async => db);

    final primeira = await repo.registrarPreliminar(
      chaveAcesso: _chave,
      origemImportacao: 'chaveManual',
      importadaEm: '2026-09-10T10:00:00.000',
    );
    final segunda = await repo.registrarPreliminar(
      chaveAcesso: _chave,
      origemImportacao: 'chaveManual',
      importadaEm: '2026-09-10T10:05:00.000',
    );
    expect(segunda.id, primeira.id);

    await repo.registrarTentativa(
      chaveAcesso: _chave,
      modelo: 55,
      canal: 'dfe',
      resultado: 'pendente',
      codigo: 'document_not_complete',
      mensagem: 'XML ainda não disponível',
      statusImportacao: 'pendente',
      momento: DateTime(2026, 9, 10, 10, 6),
    );
    await repo.registrarTentativa(
      chaveAcesso: _chave,
      modelo: 55,
      canal: 'dfe',
      resultado: 'erro',
      codigo: 'provider_error',
      mensagem: 'Falha temporária',
      statusImportacao: 'erro',
      momento: DateTime(2026, 9, 10, 10, 7),
    );

    final nota = await repo.buscarPorChave(_chave);
    expect(nota, isNotNull);
    expect(nota!.tentativasImportacao, 2);
    expect(nota.statusImportacao, 'erro');
    expect(nota.ultimoErroCodigo, 'provider_error');
    expect(await repo.listarTentativas(chaveAcesso: _chave), hasLength(2));
    expect(await db.query('notas_fiscais_entrada'), hasLength(1));
  });

  test(
    'reimportação completa atualiza a preliminar mantendo o mesmo id',
    () async {
      final db = await _abrirBancoFiscal();
      addTearDown(db.close);
      final repo = NotaFiscalEntradaRepository(
        databaseProvider: () async => db,
      );

      final preliminar = await repo.registrarPreliminar(
        chaveAcesso: _chave,
        origemImportacao: 'chaveManual',
        importadaEm: '2026-09-10T10:00:00.000',
      );

      final salva = await repo.salvarNotaCompleta(
        nota: NotaFiscalEntrada(
          chaveAcesso: _chave,
          modelo: 55,
          numero: 123,
          serie: 1,
          dataEmissao: '2026-09-10T09:00:00-03:00',
          emitenteCnpjCpf: '12345678000199',
          emitenteNome: 'Fornecedor Teste',
          valorProdutos: 10,
          valorTotal: 10,
          situacaoFiscal: 'autorizada',
          origemImportacao: 'xml',
          xmlOriginal: '<xml />',
          xmlHash: 'hash',
          importadaEm: '2026-09-10T10:00:00.000',
        ),
        itens: const [
          NotaFiscalEntradaItem(
            notaFiscalId: 0,
            numeroItem: 1,
            codigoProduto: 'A',
            descricao: 'Produto',
            unidade: 'UN',
            quantidade: 1,
            valorUnitario: 10,
            valorTotal: 10,
          ),
        ],
        removerItensAusentes: true,
      );

      expect(salva.id, preliminar.id);
      expect(salva.statusImportacao, 'processada');
      expect(salva.situacaoFiscal, 'autorizada');
      expect(await db.query('notas_fiscais_entrada'), hasLength(1));
      expect(await db.query('notas_fiscais_entrada_itens'), hasLength(1));
    },
  );
}

const _chave = '35260912345678000199550010000001231123456781';

Future<Database> _abrirBancoFiscal() async {
  final db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
  await db.execute('PRAGMA foreign_keys = ON');
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
      consulta_url TEXT,
      tentativas_importacao INTEGER NOT NULL DEFAULT 0,
      ultima_tentativa_em TEXT,
      ultimo_erro_codigo TEXT NOT NULL DEFAULT '',
      ultimo_erro_mensagem TEXT NOT NULL DEFAULT '',
      importada_em TEXT NOT NULL,
      observacoes TEXT NOT NULL DEFAULT ''
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
      FOREIGN KEY (nota_fiscal_id) REFERENCES notas_fiscais_entrada(id)
        ON DELETE CASCADE,
      UNIQUE (nota_fiscal_id, numero_item)
    )
  ''');
  await db.execute('''
    CREATE TABLE nota_fiscal_importacao_tentativas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nota_fiscal_id INTEGER,
      chave_acesso TEXT NOT NULL,
      modelo INTEGER,
      canal TEXT NOT NULL,
      resultado TEXT NOT NULL,
      codigo TEXT NOT NULL DEFAULT '',
      mensagem TEXT NOT NULL DEFAULT '',
      url TEXT,
      criado_em TEXT NOT NULL,
      FOREIGN KEY (nota_fiscal_id) REFERENCES notas_fiscais_entrada(id)
        ON DELETE SET NULL
    )
  ''');
  return db;
}
