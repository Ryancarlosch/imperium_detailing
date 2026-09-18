import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

typedef FuncionarioAcessoRealtimeAtualizar = Future<void> Function();

/// Escuta apenas um sinal seguro de alteração do acesso do funcionário.
///
/// A tabela Realtime não expõe permissões, e-mail, login nem outros dados
/// sensíveis. Quando o sinal chega, a tela chama a RPC oficial de acesso e
/// aplica o estado retornado pela nuvem ao SQLite local.
class FuncionarioAcessoRealtimeService {
  FuncionarioAcessoRealtimeService._();

  static final FuncionarioAcessoRealtimeService instance =
      FuncionarioAcessoRealtimeService._();

  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _usuarioAssinado;
  int _geracao = 0;
  bool _executando = false;
  bool _pendente = false;

  Future<bool> assinar({
    required FuncionarioAcessoRealtimeAtualizar onAtualizar,
  }) async {
    final client = SupabaseBootstrap.client;
    final user = client?.auth.currentUser;
    final userId = user?.id.trim() ?? '';

    if (client == null || userId.isEmpty) {
      return false;
    }

    if (_channel != null && _usuarioAssinado == userId) {
      return true;
    }

    await cancelar();

    try {
      final geracao = ++_geracao;
      final channel = client.channel('funcionario-acesso-$userId-$geracao');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'imperium_funcionario_realtime_sinais',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'auth_user_id',
          value: userId,
        ),
        callback: (_) {
          if (geracao != _geracao) return;

          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 250), () {
            if (geracao != _geracao) return;
            unawaited(_executar(onAtualizar));
          });
        },
      );

      _channel = channel;
      _usuarioAssinado = userId;
      channel.subscribe();
      return true;
    } catch (_) {
      await cancelar();
      return false;
    }
  }

  Future<void> _executar(FuncionarioAcessoRealtimeAtualizar onAtualizar) async {
    if (_executando) {
      _pendente = true;
      return;
    }

    _executando = true;

    try {
      do {
        _pendente = false;
        try {
          await onAtualizar();
        } catch (_) {
          // O timer e o refresh manual continuam como fallback.
        }
      } while (_pendente);
    } finally {
      _executando = false;
    }
  }

  Future<void> cancelar() async {
    _geracao++;
    _debounce?.cancel();
    _debounce = null;
    _usuarioAssinado = null;
    _pendente = false;

    final channel = _channel;
    _channel = null;
    if (channel == null) return;

    final client = SupabaseBootstrap.client;
    if (client == null) return;

    try {
      await client.removeChannel(channel);
    } catch (_) {
      // A referência local já foi descartada; nova sessão poderá reassinar.
    }
  }
}
