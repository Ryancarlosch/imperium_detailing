import 'package:supabase_flutter/supabase_flutter.dart';

import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

class PontoSolicitacaoAjusteService {
  PontoSolicitacaoAjusteService._();

  static final PontoSolicitacaoAjusteService instance =
      PontoSolicitacaoAjusteService._();

  final PontoNuvemService _pontoNuvem = PontoNuvemService.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<_ContextoPontoAjuste> _contexto(int colaboradorLocalId) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError(
        'Entre com a conta do funcionário na nuvem para solicitar correção.',
      );
    }

    final empresaId = await _pontoNuvem.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      throw StateError('Empresa da nuvem não identificada neste aparelho.');
    }

    final colaboradorRemotoId = await _pontoNuvem.remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (colaboradorRemotoId == null || colaboradorRemotoId.trim().isEmpty) {
      throw StateError(
        'Este funcionário ainda não está vinculado ao Ponto na nuvem.',
      );
    }

    return _ContextoPontoAjuste(
      client: client,
      empresaId: empresaId,
      colaboradorRemotoId: colaboradorRemotoId,
    );
  }

  Future<Map<String, dynamic>> solicitar({
    required int colaboradorLocalId,
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    required String motivo,
  }) async {
    final contexto = await _contexto(colaboradorLocalId);

    final resposta = await contexto.client.rpc(
      'ponto_solicitar_ajuste',
      params: {
        'p_empresa_id': contexto.empresaId,
        'p_colaborador_id': contexto.colaboradorRemotoId,
        'p_data': _data(data),
        'p_situacao': situacao,
        'p_entrada': _hora(entrada),
        'p_intervalo_inicio': _hora(intervaloInicio),
        'p_intervalo_fim': _hora(intervaloFim),
        'p_saida': _hora(saida),
        'p_observacoes': observacoes.trim(),
        'p_motivo': motivo.trim(),
      },
    );

    return _mapa(resposta);
  }

  Future<List<Map<String, dynamic>>> listarMinhas({
    required int colaboradorLocalId,
    int limite = 50,
  }) async {
    final contexto = await _contexto(colaboradorLocalId);

    final resposta = await contexto.client.rpc(
      'ponto_minhas_solicitacoes_ajuste',
      params: {
        'p_empresa_id': contexto.empresaId,
        'p_colaborador_id': contexto.colaboradorRemotoId,
        'p_limite': limite.clamp(1, 200),
      },
    );

    return _lista(resposta);
  }

  Future<List<Map<String, dynamic>>> listarAdmin({
    String status = 'Pendente',
    int limite = 100,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Conecte a conta administradora da empresa na nuvem.');
    }

    final empresaId = await _pontoNuvem.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      throw StateError('Empresa da nuvem não identificada neste aparelho.');
    }

    final resposta = await client.rpc(
      'ponto_listar_solicitacoes_ajuste_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_status': status,
        'p_limite': limite.clamp(1, 300),
      },
    );

    return _lista(resposta);
  }

  Future<Map<String, dynamic>> decidir({
    required String solicitacaoId,
    required bool aprovar,
    String motivo = '',
  }) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Conecte a conta administradora da empresa na nuvem.');
    }

    final resposta = await client.rpc(
      'ponto_decidir_solicitacao_ajuste',
      params: {
        'p_solicitacao_id': solicitacaoId,
        'p_aprovar': aprovar,
        'p_motivo': motivo.trim(),
      },
    );

    return _mapa(resposta);
  }

  Future<Map<String, dynamic>> cancelar(String solicitacaoId) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre com a conta do funcionário na nuvem.');
    }

    final resposta = await client.rpc(
      'ponto_cancelar_solicitacao_ajuste',
      params: {'p_solicitacao_id': solicitacaoId},
    );

    return _mapa(resposta);
  }

  static String textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'PostgrestException: ',
      'AuthException: ',
      'Exception: ',
      'Invalid argument(s): ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Não foi possível concluir a operação.' : texto;
  }

  static Map<String, dynamic> _mapa(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }
    if (valor is Map) {
      return Map<String, dynamic>.from(valor);
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _lista(dynamic valor) {
    if (valor is! List) {
      return const <Map<String, dynamic>>[];
    }

    return valor
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _data(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  static String? _hora(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return null;
    }
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }
}

class _ContextoPontoAjuste {
  const _ContextoPontoAjuste({
    required this.client,
    required this.empresaId,
    required this.colaboradorRemotoId,
  });

  final SupabaseClient client;
  final String empresaId;
  final String colaboradorRemotoId;
}
