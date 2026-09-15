import '../database/app_database.dart';
import '../models/item_estoque.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebEstoqueCloudService {
  WebEstoqueCloudService._();

  static final WebEstoqueCloudService instance = WebEstoqueCloudService._();

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId ?? '').trim();
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de usar o estoque.');
    }
    return empresaId;
  }

  Future<List<Map<String, dynamic>>> listarItens() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final resposta = await client
        .from('imperium_estoque_itens')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .eq('ativo', true)
        .order('nome');

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarMovimentacoes() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final resposta = await client
        .from('imperium_estoque_movimentacoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em', ascending: false)
        .limit(100);

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarAlertas() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final resposta = await client
        .from('imperium_estoque_alertas')
        .select()
        .eq('empresa_id', empresaId)
        .eq('status', 'Ativo')
        .order('atualizado_em', ascending: false);

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarReservasAtivas() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final resposta = await client
        .from('imperium_estoque_reservas_os')
        .select('item_estoque_id,quantidade,status')
        .eq('empresa_id', empresaId)
        .eq('status', 'Ativa');

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> movimentar({
    required Map<String, dynamic> item,
    required String tipo,
    required double quantidade,
    String unidadeOriginal = 'unidade',
    double? valorTotalPago,
    String fornecedor = '',
    String observacoes = '',
    String motivo = '',
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final itemId = (item['id'] ?? '').toString().trim();
    if (itemId.isEmpty) throw ArgumentError('Produto remoto inválido.');

    final tipoNormalizado = tipo.trim().toUpperCase();
    if (!const {'ENTRADA', 'SAIDA', 'AJUSTE'}.contains(tipoNormalizado)) {
      throw ArgumentError('Tipo de movimentação inválido.');
    }

    if (!quantidade.isFinite || quantidade < 0) {
      throw ArgumentError('Quantidade inválida.');
    }
    if (tipoNormalizado != 'AJUSTE' && quantidade <= 0) {
      throw ArgumentError('A quantidade deve ser maior que zero.');
    }
    if (tipoNormalizado == 'AJUSTE' && motivo.trim().isEmpty) {
      throw ArgumentError('Informe o motivo do ajuste manual.');
    }

    var quantidadeRpc = quantidade;
    double? quantidadeOriginal;
    String? unidadeEntrada;

    if (tipoNormalizado == 'ENTRADA') {
      if (valorTotalPago == null ||
          !valorTotalPago.isFinite ||
          valorTotalPago <= 0) {
        throw ArgumentError('Informe o valor total pago da entrada.');
      }

      final baseItem = ItemEstoque.unidadeNormalizadaParaBase(
        (item['unidade'] ?? 'unidade').toString(),
      );
      final baseEntrada = ItemEstoque.unidadeNormalizadaParaBase(
        unidadeOriginal,
      );
      if (baseItem != baseEntrada) {
        throw ArgumentError(
          'A unidade informada não é compatível com a unidade do produto ($baseItem).',
        );
      }

      quantidadeOriginal = quantidade;
      unidadeEntrada = ItemEstoque.normalizarUnidadeEntrada(unidadeOriginal);
      quantidadeRpc = ItemEstoque.quantidadeNormalizada(
        quantidade,
        unidadeEntrada,
      );
    }

    final empresaId = await _empresaId();
    final origem = await WebOrigemService.instance.proxima();
    final resposta = await client.rpc(
      'imperium_estoque_movimentar_web',
      params: {
        'p_empresa_id': empresaId,
        'p_item_estoque_id': itemId,
        'p_tipo': tipoNormalizado,
        'p_quantidade': quantidadeRpc,
        'p_origem_dispositivo': origem.dispositivoId,
        'p_origem_local_id': origem.localId,
        'p_observacoes': observacoes.trim(),
        'p_motivo': motivo.trim(),
        'p_valor_total_pago': valorTotalPago,
        'p_quantidade_original': quantidadeOriginal,
        'p_unidade_original': unidadeEntrada,
        'p_fornecedor': fornecedor.trim(),
        'p_data': DateTime.now().toUtc().toIso8601String(),
      },
    );

    if (resposta is Map) {
      return Map<String, dynamic>.from(resposta);
    }
    throw StateError('Resposta inválida ao movimentar estoque.');
  }

  static Map<String, double> reservasPorItem(
    List<Map<String, dynamic>> reservas,
  ) {
    final resultado = <String, double>{};
    for (final reserva in reservas) {
      final itemId = (reserva['item_estoque_id'] ?? '').toString();
      if (itemId.isEmpty) continue;
      resultado[itemId] =
          (resultado[itemId] ?? 0) + _double(reserva['quantidade']);
    }
    return resultado;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
