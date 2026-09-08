import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';

class NotaFiscalEntradaRepository {
  NotaFiscalEntradaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  static const _origensPreliminares = {'qrCode', 'codigoBarras', 'chaveManual'};

  Future<NotaFiscalEntrada?> buscarPorId(int id) async {
    final database = await _databaseProvider();
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<NotaFiscalEntrada?> buscarPorChave(String chaveAcesso) async {
    final database = await _databaseProvider();
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'chave_acesso = ?',
      whereArgs: [chaveAcesso.trim()],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<List<NotaFiscalEntradaItem>> listarItensDaNota(
    int notaFiscalId,
  ) async {
    final database = await _databaseProvider();
    final resultado = await database.query(
      'notas_fiscais_entrada_itens',
      where: 'nota_fiscal_id = ?',
      whereArgs: [notaFiscalId],
      orderBy: 'numero_item ASC',
    );

    return resultado
        .map(
          (item) =>
              NotaFiscalEntradaItem.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<NotaFiscalEntrada>> listar({String? statusImportacao}) async {
    final database = await _databaseProvider();
    final status = statusImportacao?.trim();
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: status == null || status.isEmpty ? null : 'status_importacao = ?',
      whereArgs: status == null || status.isEmpty ? null : [status],
      orderBy: 'importada_em DESC, id DESC',
    );

    return resultado
        .map(
          (item) => NotaFiscalEntrada.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> vincularFornecedor(int notaFiscalId, int fornecedorId) async {
    final database = await _databaseProvider();
    await database.update(
      'notas_fiscais_entrada',
      {'fornecedor_id': fornecedorId},
      where: 'id = ?',
      whereArgs: [notaFiscalId],
    );
  }

  Future<void> vincularItemEstoque(int itemFiscalId, int estoqueItemId) async {
    final database = await _databaseProvider();
    await database.update(
      'notas_fiscais_entrada_itens',
      {'estoque_item_id': estoqueItemId},
      where: 'id = ?',
      whereArgs: [itemFiscalId],
    );
  }

  Future<NotaFiscalEntrada> registrarPreliminar({
    required String chaveAcesso,
    required String origemImportacao,
    required String importadaEm,
  }) async {
    final chave = chaveAcesso.trim();
    if (chave.length != 44) {
      throw ArgumentError('A chave de acesso deve ter 44 caracteres.');
    }
    if (!_origensPreliminares.contains(origemImportacao)) {
      throw ArgumentError('Origem inválida para nota preliminar.');
    }

    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final existente = await _buscarPorChaveExecutor(transaction, chave);
      if (existente != null) return existente;

      final id = await transaction.insert('notas_fiscais_entrada', {
        'chave_acesso': chave,
        'situacao_fiscal': 'desconhecida',
        'status_importacao': 'pendente',
        'origem_importacao': origemImportacao,
        'importada_em': importadaEm,
      });

      final criado = await _buscarPorIdExecutor(transaction, id);
      if (criado == null) {
        throw StateError('Nota preliminar não encontrada após inserção.');
      }
      return criado;
    });
  }

  Future<NotaFiscalEntrada> salvarNotaCompleta({
    required NotaFiscalEntrada nota,
    required List<NotaFiscalEntradaItem> itens,
    bool removerItensAusentes = false,
  }) async {
    _validarNotaCompleta(nota);
    _validarItens(itens);

    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final existente = await _buscarPorChaveExecutor(
        transaction,
        nota.chaveAcesso.trim(),
      );

      final int notaId;
      if (existente == null) {
        notaId = await transaction.insert(
          'notas_fiscais_entrada',
          _dadosNotaCompleta(nota),
        );
      } else {
        notaId = existente.id!;
        await transaction.update(
          'notas_fiscais_entrada',
          _dadosFiscaisPendentes(existente, nota),
          where: 'id = ?',
          whereArgs: [notaId],
        );
      }

      final numerosRecebidos = <int>{};
      for (final item in itens) {
        if (!numerosRecebidos.add(item.numeroItem)) {
          throw ArgumentError(
            'Não é permitido repetir numeroItem na mesma nota.',
          );
        }

        final dados = item.toMap(incluirId: false)..['nota_fiscal_id'] = notaId;
        final atual = await transaction.query(
          'notas_fiscais_entrada_itens',
          where: 'nota_fiscal_id = ? AND numero_item = ?',
          whereArgs: [notaId, item.numeroItem],
          limit: 1,
        );

        if (atual.isEmpty) {
          await transaction.insert('notas_fiscais_entrada_itens', dados);
        } else {
          await transaction.update(
            'notas_fiscais_entrada_itens',
            dados,
            where: 'id = ?',
            whereArgs: [atual.first['id']],
          );
        }
      }

      if (removerItensAusentes) {
        final atuais = await transaction.query(
          'notas_fiscais_entrada_itens',
          columns: ['id', 'numero_item'],
          where: 'nota_fiscal_id = ?',
          whereArgs: [notaId],
        );
        for (final atual in atuais) {
          if (!numerosRecebidos.contains(_int(atual['numero_item']))) {
            await transaction.delete(
              'notas_fiscais_entrada_itens',
              where: 'id = ?',
              whereArgs: [atual['id']],
            );
          }
        }
      }

      final salva = await _buscarPorIdExecutor(transaction, notaId);
      if (salva == null) {
        throw StateError('Nota não encontrada após processamento.');
      }
      return salva;
    });
  }

  Future<void> excluirNota(int id) async {
    final database = await _databaseProvider();
    await database.delete(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<NotaFiscalEntrada?> _buscarPorChaveExecutor(
    DatabaseExecutor database,
    String chave,
  ) async {
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'chave_acesso = ?',
      whereArgs: [chave],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<NotaFiscalEntrada?> _buscarPorIdExecutor(
    DatabaseExecutor database,
    int id,
  ) async {
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Map<String, dynamic> _dadosNotaCompleta(NotaFiscalEntrada nota) {
    return nota.toMap(incluirId: false)
      ..['chave_acesso'] = nota.chaveAcesso.trim()
      ..['status_importacao'] = 'processada';
  }

  Map<String, dynamic> _dadosFiscaisPendentes(
    NotaFiscalEntrada existente,
    NotaFiscalEntrada nova,
  ) {
    final pendente = existente.statusImportacao == 'pendente';
    final dados = <String, dynamic>{
      'modelo': existente.modelo ?? nova.modelo,
      'numero': existente.numero ?? nova.numero,
      'serie': existente.serie ?? nova.serie,
      'data_emissao': existente.dataEmissao ?? nova.dataEmissao,
      'fornecedor_id': existente.fornecedorId ?? nova.fornecedorId,
      'emitente_cnpj_cpf': existente.emitenteCnpjCpf ?? nova.emitenteCnpjCpf,
      'emitente_nome': existente.emitenteNome ?? nova.emitenteNome,
      'valor_produtos': pendente
          ? nova.valorProdutos
          : existente.valorProdutos ?? nova.valorProdutos,
      'valor_frete': pendente ? nova.valorFrete : existente.valorFrete,
      'valor_seguro': pendente ? nova.valorSeguro : existente.valorSeguro,
      'valor_desconto': pendente ? nova.valorDesconto : existente.valorDesconto,
      'valor_outras_despesas': pendente
          ? nova.valorOutrasDespesas
          : existente.valorOutrasDespesas,
      'valor_ipi': pendente ? nova.valorIpi : existente.valorIpi,
      'valor_icms_st': pendente ? nova.valorIcmsSt : existente.valorIcmsSt,
      'valor_total': pendente
          ? nova.valorTotal
          : existente.valorTotal ?? nova.valorTotal,
      'situacao_fiscal': nova.situacaoFiscal,
      'status_importacao': 'processada',
      'origem_importacao': existente.origemImportacao,
      'xml_original': existente.xmlOriginal ?? nova.xmlOriginal,
      'xml_hash': existente.xmlHash ?? nova.xmlHash,
      'importada_em': existente.importadaEm,
      'observacoes': existente.observacoes,
    };
    return dados;
  }

  void _validarNotaCompleta(NotaFiscalEntrada nota) {
    if (nota.chaveAcesso.trim().length != 44) {
      throw ArgumentError('A chave de acesso deve ter 44 caracteres.');
    }
    if (nota.modelo != 55 && nota.modelo != 65) {
      throw ArgumentError('Modelo fiscal deve ser 55 ou 65.');
    }
    if (nota.numero == null || nota.serie == null) {
      throw ArgumentError('Número e série são obrigatórios.');
    }
    if ((nota.dataEmissao ?? '').trim().isEmpty) {
      throw ArgumentError('Data de emissão é obrigatória.');
    }
    if ((nota.emitenteNome ?? '').trim().isEmpty ||
        (nota.emitenteCnpjCpf ?? '').trim().isEmpty) {
      throw ArgumentError('Nome e CNPJ/CPF do emitente são obrigatórios.');
    }
    if (nota.valorTotal == null) {
      throw ArgumentError('Valor total é obrigatório.');
    }
  }

  void _validarItens(List<NotaFiscalEntradaItem> itens) {
    for (final item in itens) {
      if (item.numeroItem <= 0 || item.descricao.trim().isEmpty) {
        throw ArgumentError('Item fiscal inválido.');
      }
    }
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
