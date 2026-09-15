import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

class ImperiumAuthService {
  ImperiumAuthService._();

  static final ImperiumAuthService instance = ImperiumAuthService._();

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError(
        SupabaseBootstrap.ultimoErro ?? 'Supabase não está disponível.',
      );
    }
    return client;
  }

  User? get usuarioAtual => SupabaseBootstrap.client?.auth.currentUser;

  bool get autenticado => usuarioAtual != null;

  Future<User> entrarComEmailSenha({
    required String email,
    required String senha,
  }) async {
    final emailLimpo = email.trim().toLowerCase();
    final senhaLimpa = senha.trim();

    if (emailLimpo.isEmpty || !emailLimpo.contains('@')) {
      throw ArgumentError('Informe um e-mail válido.');
    }

    if (senhaLimpa.isEmpty) {
      throw ArgumentError('Informe sua senha.');
    }

    final resposta = await _client.auth.signInWithPassword(
      email: emailLimpo,
      password: senhaLimpa,
    );

    final usuario = resposta.user ?? _client.auth.currentUser;
    if (usuario == null) {
      throw StateError('Não foi possível concluir o login.');
    }

    return usuario;
  }

  Future<void> sair() async {
    final client = SupabaseBootstrap.client;
    if (client == null) return;
    await client.auth.signOut();
  }

  String textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'AuthException: ',
      'PostgrestException: ',
      'StateError: ',
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    final lower = texto.toLowerCase();

    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return 'E-mail ou senha incorretos.';
    }

    if (lower.contains('email not confirmed') ||
        lower.contains('email_not_confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }

    if (lower.contains('too many requests') ||
        lower.contains('rate limit') ||
        lower.contains('429')) {
      return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }

    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return 'Não foi possível conectar ao servidor. Verifique sua internet.';
    }

    return texto.isEmpty ? 'Falha ao acessar o Imperium.' : texto;
  }
}
