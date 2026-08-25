import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

typedef PontoRealtimeAtualizar = Future<void> Function();

class PontoRealtimeService {
  PontoRealtimeService._();

  static final PontoRealtimeService instance = PontoRealtimeService._();

  final PontoNuvemService _nuvem = PontoNuvemService.instance;

  RealtimeChannel? _channel;
  Timer? _debounce;
  int _geracao = 0;

  Future<bool> assinarColaborador({
    required int colaboradorLocalId,
    required PontoRealtimeAtualizar onAtualizar,
  }) async {
    await cancelar();

    try {
      final client = SupabaseBootstrap.client;
      final user = client?.auth.currentUser;

      if (client == null || user == null || colaboradorLocalId <= 0) {
        return false;
      }

      final empresaId = await _nuvem.empresaAtualId();
      if (empresaId == null || empresaId.trim().isEmpty) {
        return false;
      }

      final remotoId = await _nuvem.remotoIdPorLocal(
        colaboradorLocalId,
        empresaId: empresaId,
      );

      if (remotoId == null || remotoId.trim().isEmpty) {
        return false;
      }

      final geracao = ++_geracao;
      final channel = client.channel(
        'ponto-registros-$empresaId-$remotoId-$geracao',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'ponto_registros',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'colaborador_id',
          value: remotoId,
        ),
        callback: (_) {
          if (geracao != _geracao) return;

          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () {
            if (geracao != _geracao) return;
            unawaited(_executarAtualizacao(onAtualizar));
          });
        },
      );

      _channel = channel;
      channel.subscribe();

      return true;
    } catch (_) {
      await cancelar();
      return false;
    }
  }

  Future<void> _executarAtualizacao(PontoRealtimeAtualizar onAtualizar) async {
    try {
      await onAtualizar();
    } catch (_) {
      // Realtime é melhoria de atualização. Falha aqui nunca bloqueia
      // o uso offline nem o botão de atualização manual.
    }
  }

  Future<void> cancelar() async {
    _geracao++;
    _debounce?.cancel();
    _debounce = null;

    final channel = _channel;
    _channel = null;

    if (channel == null) return;

    final client = SupabaseBootstrap.client;
    if (client == null) return;

    try {
      await client.removeChannel(channel);
    } catch (_) {
      // Nada a fazer: a assinatura será descartada localmente.
    }
  }
}
