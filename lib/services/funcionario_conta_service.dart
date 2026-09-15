import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

class FuncionarioContaService {
  FuncionarioContaService._();

  static final FuncionarioContaService instance = FuncionarioContaService._();

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError(
        SupabaseBootstrap.ultimoErro ?? 'Supabase não está disponível.',
      );
    }
    return client;
  }

  Future<Map<String, dynamic>> prepararAcessoAdmin({
    required String empresaId,
    required String colaboradorRemotoId,
    required String email,
    required String login,
    required Map<String, bool> permissoes,
  }) async {
    final client = _client;
    final session = client.auth.currentSession;
    final emailLimpo = email.trim().toLowerCase();

    if (session == null) {
      throw StateError('Sua sessão expirou. Entre novamente para continuar.');
    }

    if (empresaId.trim().isEmpty || colaboradorRemotoId.trim().isEmpty) {
      throw ArgumentError('Empresa ou funcionário inválido.');
    }

    if (emailLimpo.isEmpty || !emailLimpo.contains('@')) {
      throw ArgumentError('Informe um e-mail válido para o funcionário.');
    }

    final resposta = await client.functions.invoke(
      'imperium-funcionario-conta',
      body: <String, dynamic>{
        'empresa_id': empresaId.trim(),
        'colaborador_id': colaboradorRemotoId.trim(),
        'email': emailLimpo,
        'login': login.trim().toLowerCase(),
        'permissoes': permissoes,
        'enviar_email': true,
      },
      headers: <String, String>{
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );

    final data = resposta.data;
    if (data is! Map) {
      throw StateError('Resposta inválida ao preparar a conta do funcionário.');
    }

    final resultado = Map<String, dynamic>.from(data);
    if (resultado['ok'] != true) {
      final mensagem = (resultado['message'] ?? resultado['mensagem'] ?? '')
          .toString()
          .trim();
      throw StateError(
        mensagem.isEmpty
            ? 'Não foi possível preparar a conta do funcionário.'
            : mensagem,
      );
    }

    return resultado;
  }
}
