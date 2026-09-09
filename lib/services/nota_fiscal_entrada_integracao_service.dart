import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/fornecedor.dart';
import '../models/item_estoque.dart';
import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';

class NotaFiscalEntradaIntegracaoService {
  NotaFiscalEntradaIntegracaoService({
    NotaFiscalEntradaRepository? notaRepository,
    Future<Database> Function()? databaseProvider,
  }) : _notaRepository = notaRepository ?? NotaFiscalEntradaRepository(),
       _databaseProvider =
           databaseProvider ?? (() => AppDatabase.instance.database);

  final NotaFiscalEntradaRepository _notaRepository;
  final Future<Database> Function() _databaseProvider;

  Future<int?> fornecedorExistentePorDocumento(String documento) async {
    final normalizado = _normalizarDocumento(documento);
    if (normalizado.isEmpty) return null;

    final database = await _databaseProvider();
    final resultados = await database.rawQuery(
      '''
      SELECT id
      FROM fornecedores
      WHERE REPLACE(REPLACE(REPLACE(REPLACE(documento, '.', ''), '/', ''), '-', ''), ' ', '') = ?
      ORDER BY ativo DESC, id ASC
      LIMIT 1
      ''',
      [normalizado],
    );
    if (resultados.isEmpty) return null;
    return _int(resultados.first['id']);
  }

  Future<int> criarFornecedorConfirmado({
    required String nome,
    required String documento,
  }) async {
    final nomeLimpo = nome.trim();
    final documentoLimpo = documento.trim();
    if (nomeLimpo.length < 2 || documentoLimpo.isEmpty) {
      throw ArgumentError('Nome e documento do fornecedor são obrigatórios.');
    }

    final existente = await fornecedorExistentePorDocumento(documentoLimpo);
    if (existente != null) return existente;

    final agora = DateTime.now().toIso8601String();
    final database = await _databaseProvider();
    return database.insert(
      'fornecedores',
      Fornecedor(
        nome: nomeLimpo,
        documento: documentoLimpo,
        criadoEm: agora,
        atualizadoEm: agora,
      ).toMap(incluirId: false),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<int>> localizarItensPorEan(String ean) async {
    final normalizado = _normalizarDocumento(ean);
    if (normalizado.isEmpty) return const [];
    final database = await _databaseProvider();
    final resultados = await database.rawQuery(
      '''
      SELECT id
      FROM itens_estoque
      WHERE ativo = 1
        AND REPLACE(REPLACE(TRIM(COALESCE(ean, '')), '-', ''), ' ', '') = ?
      ORDER BY id ASC
      ''',
      [normalizado],
    );
    return resultados
        .map((item) => _int(item['id']))
        .where((id) => id > 0)
        .toList();
  }

  Future<List<int>> localizarItensPorDescricaoExata(String descricao) async {
    final nome = descricao.trim();
    if (nome.isEmpty) return const [];
    final database = await _databaseProvider();
    final resultados = await database.rawQuery(
      '''
      SELECT id
      FROM itens_estoque
      WHERE ativo = 1
        AND LOWER(TRIM(nome)) = LOWER(TRIM(?))
      ORDER BY id ASC
      ''',
      [nome],
    );
    return resultados
        .map((item) => _int(item['id']))
        .where((id) => id > 0)
        .toList();
  }

  Future<void> vincularFornecedorDaNota({
    required int notaFiscalId,
    required int fornecedorId,
  }) => _notaRepository.vincularFornecedor(notaFiscalId, fornecedorId);

  Future<void> vincularItemFiscal({
    required int itemFiscalId,
    required int estoqueItemId,
  }) => _notaRepository.vincularItemEstoque(itemFiscalId, estoqueItemId);

  Future<void> confirmarEntradaEstoque(int notaFiscalId) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final nota = await _buscarNota(transaction, notaFiscalId);
      if (nota == null) throw StateError('Nota fiscal não encontrada.');
      if (nota.statusImportacao != 'processada') {
        throw StateError('A nota precisa estar processada antes da entrada.');
      }
      if ({
        'cancelada',
        'denegada',
        'inutilizada',
      }.contains(nota.situacaoFiscal)) {
        throw StateError(
          'Documento fiscal ${nota.situacaoFiscal} não pode gerar entrada de estoque.',
        );
      }

      final itens = await transaction.query(
        'notas_fiscais_entrada_itens',
        where: 'nota_fiscal_id = ?',
        whereArgs: [notaFiscalId],
        orderBy: 'numero_item ASC',
      );
      if (itens.isEmpty) throw StateError('A nota não possui itens.');
      if (itens.any((item) => _int(item['estoque_item_id']) <= 0)) {
        throw StateError('Todos os itens precisam ser vinculados ao estoque.');
      }

      for (final row in itens) {
        final itemFiscalId = _int(row['id']);
        final estoqueItemId = _int(row['estoque_item_id']);
        final jaLancado = await transaction.query(
          'movimentacoes_estoque',
          columns: ['id'],
          where:
              'nota_fiscal_id = ? AND nota_fiscal_item_id = ? '
              "AND tipo = 'ENTRADA' AND origem = 'Nota fiscal de entrada'",
          whereArgs: [notaFiscalId, itemFiscalId],
          limit: 1,
        );
        if (jaLancado.isNotEmpty) continue;

        await _registrarEntradaItem(
          transaction,
          nota: nota,
          itemFiscal: row,
          itemFiscalId: itemFiscalId,
          estoqueItemId: estoqueItemId,
        );
      }
    });
  }

  Future<void> _registrarEntradaItem(
    DatabaseExecutor database, {
    required NotaFiscalEntrada nota,
    required Map<String, Object?> itemFiscal,
    required int itemFiscalId,
    required int estoqueItemId,
  }) async {
    final estoque = await database.query(
      'itens_estoque',
      where: 'id = ? AND ativo = 1',
      whereArgs: [estoqueItemId],
      limit: 1,
    );
    if (estoque.isEmpty) throw StateError('Item de estoque não encontrado.');

    final quantidadeFiscal = _double(itemFiscal['quantidade']);
    if (quantidadeFiscal <= 0) throw StateError('Quantidade fiscal inválida.');
    final unidade = (itemFiscal['unidade'] ?? 'un').toString();
    final quantidade =
        quantidadeFiscal * ItemEstoque.fatorNormalizacaoUnidade(unidade);
    final valorBruto = _double(itemFiscal['valor_total']);
    final valorDesconto = _double(itemFiscal['valor_desconto']);
    final valorTotal = valorBruto - valorDesconto;
    if (valorTotal < 0) {
      throw StateError('Valor líquido do item fiscal inválido.');
    }

    final custoNovo = valorTotal / quantidade;
    final atual = ItemEstoque.fromMap(estoque.first);
    final quantidadeAnterior = atual.quantidade;
    final quantidadePosterior = quantidadeAnterior + quantidade;
    final custoCadastro = custoNovo > 0
        ? custoNovo
        : atual.custoUnitarioEfetivo;
    final agora = DateTime.now().toIso8601String();

    final loteId = await database.insert('estoque_lotes', {
      'item_estoque_id': estoqueItemId,
      'data_compra': nota.dataEmissao ?? agora,
      'quantidade_original': quantidadeFiscal,
      'quantidade_normalizada': quantidade,
      'quantidade_disponivel': quantidade,
      'unidade_original': unidade,
      'unidade_base': ItemEstoque.unidadeNormalizadaParaBase(unidade),
      'valor_total_pago': valorTotal,
      'custo_unitario': custoNovo,
      'fornecedor': nota.emitenteNome ?? '',
      'observacao': 'Entrada da nota fiscal ${nota.chaveAcesso}',
      'ativo': 1,
      'criado_em': agora,
    });

    await database.update(
      'itens_estoque',
      {
        'quantidade': quantidadePosterior,
        'unidade': ItemEstoque.unidadeNormalizadaParaBase(unidade),
        'valor_total_pago': valorTotal,
        'quantidade_total': quantidade,
        'custo_unitario': custoCadastro,
        'custo_unitario_calculado': custoCadastro,
        'fornecedor': (nota.emitenteNome ?? '').trim().isEmpty
            ? atual.fornecedor
            : nota.emitenteNome!.trim(),
        'atualizado_em': agora,
      },
      where: 'id = ?',
      whereArgs: [estoqueItemId],
    );

    await database.insert('movimentacoes_estoque', {
      'item_estoque_id': estoqueItemId,
      'tipo': 'ENTRADA',
      'quantidade': quantidade,
      'quantidade_anterior': quantidadeAnterior,
      'quantidade_posterior': quantidadePosterior,
      'custo_unitario': custoNovo,
      'observacoes': 'Entrada da nota fiscal ${nota.chaveAcesso}',
      'motivo': 'Compra fiscal',
      'origem': 'Nota fiscal de entrada',
      'ordem_servico_id': null,
      'lote_id': loteId,
      'nota_fiscal_id': nota.id,
      'nota_fiscal_item_id': itemFiscalId,
      'data': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<NotaFiscalEntrada?> _buscarNota(
    DatabaseExecutor database,
    int id,
  ) async {
    final rows = await database.query(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(Map<String, dynamic>.from(rows.first));
  }

  static String _normalizarDocumento(String valor) =>
      valor.replaceAll(RegExp(r'\D'), '');

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
