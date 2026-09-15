import '../database/app_database.dart';
import '../models/item_estoque.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebEstoqueProdutosService {
  WebEstoqueProdutosService._();

  static final WebEstoqueProdutosService instance =
      WebEstoqueProdutosService._();

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId ?? '').trim();
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de usar o estoque.');
    }
    return empresaId;
  }

  Future<List<Map<String, dynamic>>> listarItens({
    bool incluirInativos = false,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    dynamic query = client
        .from('imperium_estoque_itens')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null);

    if (!incluirInativos) {
      query = query.eq('ativo', true);
    }

    final resposta = await query.order('nome');
    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> criarProduto({
    required String nome,
    required String categoria,
    required double quantidadeMinima,
    required String unidadeBase,
    String ean = '',
    String fornecedor = '',
    String observacoes = '',
    double quantidadeInicial = 0,
    String unidadeCompra = 'unidade',
    double? valorTotalPago,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final nomeLimpo = nome.trim();
    if (nomeLimpo.length < 2) {
      throw ArgumentError('Informe o nome do produto.');
    }
    if (!quantidadeMinima.isFinite || quantidadeMinima < 0) {
      throw ArgumentError('Quantidade mínima inválida.');
    }
    if (!quantidadeInicial.isFinite || quantidadeInicial < 0) {
      throw ArgumentError('Quantidade inicial inválida.');
    }

    final base = ItemEstoque.unidadeNormalizadaParaBase(unidadeBase);
    var quantidadeNormalizada = 0.0;
    String? unidadeOriginal;
    double? quantidadeOriginal;

    if (quantidadeInicial > 0) {
      if (valorTotalPago == null ||
          !valorTotalPago.isFinite ||
          valorTotalPago <= 0) {
        throw ArgumentError('Informe o valor total pago da entrada inicial.');
      }

      final baseCompra = ItemEstoque.unidadeNormalizadaParaBase(unidadeCompra);
      if (baseCompra != base) {
        throw ArgumentError(
          'A unidade da compra não é compatível com a unidade base ($base).',
        );
      }

      unidadeOriginal = ItemEstoque.normalizarUnidadeEntrada(unidadeCompra);
      quantidadeOriginal = quantidadeInicial;
      quantidadeNormalizada = ItemEstoque.quantidadeNormalizada(
        quantidadeInicial,
        unidadeOriginal,
      );
    }

    final empresaId = await _empresaId();
    final origem = await WebOrigemService.instance.proxima();
    final resposta = await client.rpc(
      'imperium_estoque_criar_item_web',
      params: {
        'p_empresa_id': empresaId,
        'p_origem_dispositivo': origem.dispositivoId,
        'p_origem_local_id': origem.localId,
        'p_nome': nomeLimpo,
        'p_categoria': categoria.trim(),
        'p_quantidade_minima': quantidadeMinima,
        'p_unidade': base,
        'p_ean': ean.trim(),
        'p_fornecedor': fornecedor.trim(),
        'p_observacoes': observacoes.trim(),
        'p_quantidade_inicial': quantidadeNormalizada,
        'p_quantidade_original': quantidadeOriginal,
        'p_unidade_original': unidadeOriginal,
        'p_valor_total_pago': valorTotalPago,
        'p_data': DateTime.now().toUtc().toIso8601String(),
      },
    );

    if (resposta is Map) return Map<String, dynamic>.from(resposta);
    throw StateError('Resposta inválida ao cadastrar produto.');
  }

  Future<Map<String, dynamic>> atualizarProduto({
    required Map<String, dynamic> item,
    required String nome,
    required String categoria,
    required double quantidadeMinima,
    required String unidadeBase,
    required bool ativo,
    String ean = '',
    String fornecedor = '',
    String observacoes = '',
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final itemId = (item['id'] ?? '').toString().trim();
    final atualizadoEm = (item['atualizado_em'] ?? '').toString().trim();
    if (itemId.isEmpty || atualizadoEm.isEmpty) {
      throw StateError('Produto remoto sem versão para edição segura.');
    }

    final nomeLimpo = nome.trim();
    if (nomeLimpo.length < 2) {
      throw ArgumentError('Informe o nome do produto.');
    }
    if (!quantidadeMinima.isFinite || quantidadeMinima < 0) {
      throw ArgumentError('Quantidade mínima inválida.');
    }

    final empresaId = await _empresaId();
    final resposta = await client.rpc(
      'imperium_estoque_atualizar_item_web',
      params: {
        'p_empresa_id': empresaId,
        'p_item_estoque_id': itemId,
        'p_atualizado_em': atualizadoEm,
        'p_nome': nomeLimpo,
        'p_categoria': categoria.trim(),
        'p_quantidade_minima': quantidadeMinima,
        'p_unidade': ItemEstoque.unidadeNormalizadaParaBase(unidadeBase),
        'p_ean': ean.trim(),
        'p_fornecedor': fornecedor.trim(),
        'p_observacoes': observacoes.trim(),
        'p_ativo': ativo,
        'p_data': DateTime.now().toUtc().toIso8601String(),
      },
    );

    if (resposta is Map) return Map<String, dynamic>.from(resposta);
    throw StateError('Resposta inválida ao atualizar produto.');
  }
}
