import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static bool _inicializado = false;
  static String? _ultimoErro;

  static bool get inicializado => _inicializado;
  static String? get ultimoErro => _ultimoErro;

  static Future<void> inicializar() async {
    if (_inicializado || !SupabaseConfig.configurado) {
      return;
    }

    try {
      await Supabase.initialize(
        url: SupabaseConfig.projectUrl,
        publishableKey: SupabaseConfig.publishableKey,
        debug: false,
      );

      _inicializado = true;
      _ultimoErro = null;
    } catch (erro) {
      _inicializado = false;
      _ultimoErro = _textoErro(erro);
    }
  }

  static SupabaseClient? get client {
    if (!_inicializado) {
      return null;
    }

    return Supabase.instance.client;
  }

  static String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const <String>[
      'Exception: ',
      'AuthException: ',
      'PostgrestException: ',
      'StorageException: ',
      'SocketException: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty
        ? 'Falha desconhecida ao inicializar o Supabase.'
        : texto;
  }
}
