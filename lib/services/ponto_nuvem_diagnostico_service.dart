import 'package:supabase_flutter/supabase_flutter.dart';

import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

class PontoNuvemDiagnosticoService {
  PontoNuvemDiagnosticoService._();

  static final PontoNuvemDiagnosticoService instance =
      PontoNuvemDiagnosticoService._();

  static const int versaoBackendEsperada = 6;

  final PontoNuvemService _nuvem = PontoNuvemService.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<Map<String, dynamic>> diagnosticar({
    required String empresaEsperadaId,
  }) async {
    final client = _client;
    final usuario = client?.auth.currentUser;

    if (client == null || usuario == null) {
      return const {
        'saudavel': false,
        'diagnostico_disponivel': false,
        'mensagem': 'Conta Supabase não conectada.',
      };
    }

    final empresaAtual = await _nuvem.empresaAtualId();

    if (empresaAtual == null || empresaAtual.isEmpty) {
      return const {
        'saudavel': false,
        'diagnostico_disponivel': false,
        'mensagem': 'Empresa da sessão não identificada.',
      };
    }

    if (empresaEsperadaId.trim().isNotEmpty &&
        empresaEsperadaId.trim() != empresaAtual) {
      return {
        'saudavel': false,
        'diagnostico_disponivel': true,
        'empresa_confere': false,
        'empresa_atual_id': empresaAtual,
        'empresa_esperada_id': empresaEsperadaId.trim(),
        'mensagem':
            'Bloqueado: a empresa desta tela não corresponde à empresa '
            'autenticada.',
      };
    }

    try {
      final resposta = await client.rpc(
        'ponto_diagnostico',
        params: {'p_empresa_id': empresaAtual},
      );

      final remoto = _mapa(resposta);

      return avaliar(
        remoto: remoto,
        empresaEsperadaId: empresaEsperadaId.trim(),
        empresaAtualId: empresaAtual,
      );
    } catch (erro) {
      return {
        'saudavel': false,
        'diagnostico_disponivel': false,
        'empresa_confere': true,
        'empresa_atual_id': empresaAtual,
        'backend_version': 0,
        'mensagem':
            'Diagnóstico V$versaoBackendEsperada ainda não disponível no '
            'Supabase. Aplique o SQL mestre atualizado antes de concluir '
            'Ponto/Funcionários.',
        'erro_tecnico': _textoErro(erro),
      };
    }
  }

  static Map<String, dynamic> avaliar({
    required Map<String, dynamic> remoto,
    required String empresaEsperadaId,
    required String empresaAtualId,
  }) {
    final empresaRetornada = (remoto['empresa_id'] ?? empresaAtualId)
        .toString()
        .trim();
    final esperada = empresaEsperadaId.trim();
    final atual = empresaAtualId.trim();

    final empresaConfere =
        atual.isNotEmpty &&
        empresaRetornada == atual &&
        (esperada.isEmpty || esperada == atual);

    final versao = _int(remoto['backend_version']);
    final rpcOnline = remoto['rpc_batida_online'] == true;
    final rpcOffline = remoto['rpc_batida_offline'] == true;
    final idempotencia = remoto['tabela_idempotencia'] == true;
    final realtime = remoto['realtime_ponto_registros'] == true;
    final syncEstado = remoto['sync_estado_disponivel'] == true;
    final migracao = remoto['migracao_concluida'] == true;

    final backendAtualizado =
        versao >= PontoNuvemDiagnosticoService.versaoBackendEsperada;

    final saudavel =
        empresaConfere &&
        backendAtualizado &&
        rpcOnline &&
        rpcOffline &&
        idempotencia &&
        realtime &&
        syncEstado &&
        migracao;

    return {
      ...remoto,
      'diagnostico_disponivel': true,
      'empresa_confere': empresaConfere,
      'backend_atualizado': backendAtualizado,
      'saudavel': saudavel,
      'mensagem': saudavel
          ? 'Ponto na nuvem pronto para validação final em dois aparelhos.'
          : 'Ainda existem requisitos pendentes antes de concluir '
                'Ponto/Funcionários.',
    };
  }

  static Map<String, dynamic> _mapa(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is Map) {
      return valor.map<String, dynamic>(
        (chave, item) => MapEntry(chave.toString(), item),
      );
    }

    return const {};
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.length > 500 ? texto.substring(0, 500) : texto;
  }
}
