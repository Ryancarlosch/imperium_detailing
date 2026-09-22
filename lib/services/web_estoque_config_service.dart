import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebEstoqueConfigService {
  WebEstoqueConfigService._();

  static final WebEstoqueConfigService instance = WebEstoqueConfigService._();

  final WebOrigemService _origem = WebOrigemService.instance;

  dynamic get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de configurar o estoque.');
    }
    return empresaId;
  }

  Future<Map<String, dynamic>> carregar() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_estoque_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    return <String, dynamic>{
      'empresa_id': empresaId,
      'controlar_estoque': true,
      'controlar_produtos_ordem_servico': false,
      'baixa_automatica': false,
      'exigir_quantidade': false,
      'alertar_estoque_baixo': true,
      'estoque_minimo_padrao': 1.0,
      'atualizado_em': null,
    };
  }

  Future<Map<String, dynamic>> salvar({
    required bool controlarEstoque,
    required bool controlarProdutosOrdemServico,
    required bool baixaAutomatica,
    required bool exigirQuantidade,
    required bool alertarEstoqueBaixo,
    required double estoqueMinimoPadrao,
    String? atualizadoEmBase,
  }) async {
    if (estoqueMinimoPadrao < 0) {
      throw ArgumentError('O estoque mínimo padrão não pode ser negativo.');
    }

    final empresaId = await _empresaId();
    final origem = await _origem.dispositivoId();
    final agora = DateTime.now().toUtc().toIso8601String();

    final raw = await _client.rpc(
      'imperium_estoque_salvar_config',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_controlar_estoque': controlarEstoque,
        'p_controlar_produtos_ordem_servico':
            controlarEstoque && controlarProdutosOrdemServico,
        'p_baixa_automatica':
            controlarEstoque &&
            controlarProdutosOrdemServico &&
            baixaAutomatica,
        'p_exigir_quantidade':
            controlarEstoque &&
            controlarProdutosOrdemServico &&
            exigirQuantidade,
        'p_alertar_estoque_baixo': controlarEstoque && alertarEstoqueBaixo,
        'p_estoque_minimo_padrao': estoqueMinimoPadrao,
        'p_origem_dispositivo': origem,
        'p_origem_atualizado_em': agora,
        'p_atualizado_em_base': (atualizadoEmBase ?? '').trim().isEmpty
            ? null
            : atualizadoEmBase,
      },
    );

    if (raw is! Map) {
      throw StateError('A configuração do estoque não retornou dados.');
    }
    return Map<String, dynamic>.from(raw);
  }
}
