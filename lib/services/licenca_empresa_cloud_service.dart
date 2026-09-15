import 'package:supabase_flutter/supabase_flutter.dart';

import 'licenca_service.dart';
import 'supabase_bootstrap.dart';

class LicencaEmpresaCloudService {
  const LicencaEmpresaCloudService();

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<LicencaStatus> consultar(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) {
      throw StateError('Empresa inválida para validar a licença.');
    }

    final client = _client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    if (client.auth.currentUser == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final resposta = await client.rpc(
      'imperium_status_licenca_empresa',
      params: {'p_empresa_id': id},
    );

    final status = _extrairStatus(resposta);
    if (status.empresaId != id) {
      throw StateError(
        'A licença retornada não pertence à empresa selecionada.',
      );
    }

    return status;
  }

  LicencaStatus _extrairStatus(dynamic resposta) {
    if (resposta is List && resposta.isNotEmpty && resposta.first is Map) {
      return LicencaStatus.fromMap(
        Map<String, dynamic>.from(resposta.first as Map),
      );
    }

    if (resposta is Map) {
      return LicencaStatus.fromMap(Map<String, dynamic>.from(resposta));
    }

    throw StateError(
      'Não foi encontrada uma licença autorizada para esta empresa.',
    );
  }
}
