import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

/// Cancelamento seguro de OS no Web.
///
/// O banco aceita apenas OS `Aberta` ou `Em andamento` e executa na mesma
/// transação: CAS da OS, cancelamento de cobranças pendentes, liberação de
/// reserva de estoque, atualização do agendamento e auditoria idempotente.
class WebOsCancelamentoV5Service {
  WebOsCancelamentoV5Service._();

  static final WebOsCancelamentoV5Service instance =
      WebOsCancelamentoV5Service._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de cancelar a OS.');
    }
    return empresa;
  }

  Future<Map<String, dynamic>> cancelar({
    required Map<String, dynamic> ordem,
    required String motivo,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    final ordemId = (ordem['id'] ?? '').toString().trim();
    final status = (ordem['status'] ?? '').toString().trim();
    final atualizadoEm = (ordem['atualizado_em'] ?? '').toString().trim();
    final motivoLimpo = motivo.trim();

    if (ordemId.isEmpty) {
      throw ArgumentError('Ordem de Serviço inválida.');
    }

    if (status == 'Cancelada') {
      return <String, dynamic>{
        'ordem_id': ordemId,
        'status': 'Cancelada',
        'ja_cancelada': true,
      };
    }

    if (status == 'Finalizada') {
      throw StateError(
        'OS finalizada não pode ser cancelada por este fluxo. '
        'Use o fluxo de estorno/correção.',
      );
    }

    if (status != 'Aberta' && status != 'Em andamento') {
      throw StateError('Somente OS Aberta ou Em andamento pode ser cancelada.');
    }

    if (atualizadoEm.isEmpty) {
      throw StateError(
        'A versão da OS não está disponível. Atualize a lista e tente novamente.',
      );
    }

    if (motivoLimpo.length < 3) {
      throw ArgumentError('Informe o motivo do cancelamento.');
    }

    final origem = await WebOrigemService.instance.proxima();
    final assinatura = sha256
        .convert(utf8.encode('$empresaId|$ordemId|$atualizadoEm|$motivoLimpo'))
        .toString();
    final idempotencyKey = 'web-cancelar-$assinatura';

    final raw = await client.rpc(
      'imperium_os_cancelar_web_v5',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_ordem_id': ordemId,
        'p_os_atualizado_em': atualizadoEm,
        'p_idempotency_key': idempotencyKey,
        'p_origem_dispositivo': origem.dispositivoId,
        'p_origem_base': origem.localId,
        'p_motivo': motivoLimpo,
      },
    );

    return Map<String, dynamic>.from(raw as Map);
  }
}
