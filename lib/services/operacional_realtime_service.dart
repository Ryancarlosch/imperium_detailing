import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

typedef OperacionalRealtimeAtualizar = Future<void> Function();

/// Atualização reativa do núcleo operacional.
///
/// O Realtime não substitui o motor de sincronização. Ele apenas dispara um
/// ciclo normal quando outro aparelho altera Clientes, Veículos ou Agenda.
/// Toda reconciliação, CAS, conflitos, retry e offline continuam centralizados
/// nos serviços de sincronização existentes.
class OperacionalRealtimeService {
  OperacionalRealtimeService._();

  static final OperacionalRealtimeService instance =
      OperacionalRealtimeService._();

  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _empresaAssinada;
  int _geracao = 0;

  Future<bool> assinarEmpresa({
    required String empresaId,
    required OperacionalRealtimeAtualizar onAtualizar,
  }) async {
    final id = empresaId.trim();
    final client = SupabaseBootstrap.client;
    final user = client?.auth.currentUser;

    if (id.isEmpty || client == null || user == null) return false;

    if (_channel != null && _empresaAssinada == id) return true;

    await cancelar();

    try {
      final geracao = ++_geracao;
      final channel = client.channel('operacional-$id-$geracao');

      void registrar(String tabela) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tabela,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: id,
          ),
          callback: (_) {
            if (geracao != _geracao) return;
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 650), () {
              if (geracao != _geracao) return;
              unawaited(_executarAtualizacao(onAtualizar));
            });
          },
        );
      }

      registrar('imperium_clientes');
      registrar('imperium_veiculos');
      registrar('imperium_agendamentos');

      _channel = channel;
      _empresaAssinada = id;
      channel.subscribe();
      return true;
    } catch (_) {
      await cancelar();
      return false;
    }
  }

  Future<void> _executarAtualizacao(
    OperacionalRealtimeAtualizar onAtualizar,
  ) async {
    try {
      await onAtualizar();
    } catch (_) {
      // Realtime é um acelerador. Falha aqui não bloqueia o modo offline,
      // o timer de sincronização, o retorno ao app nem o botão manual.
    }
  }

  Future<void> cancelar() async {
    _geracao++;
    _debounce?.cancel();
    _debounce = null;
    _empresaAssinada = null;

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
