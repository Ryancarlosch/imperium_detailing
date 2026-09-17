import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

enum WebFinanceiroEstornoModo { correcao, devolucao }

/// Estorno/correção de recebimentos da OS no Web.
///
/// A transação real acontece no PostgreSQL. O snapshot `atualizado_em` do
/// pagamento é usado como CAS e a chave determinística permite retry seguro.
class WebFinanceiroEstornoService {
  WebFinanceiroEstornoService._();

  static final WebFinanceiroEstornoService instance =
      WebFinanceiroEstornoService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de estornar o pagamento.');
    }
    return empresa;
  }

  Future<Map<String, dynamic>> estornar({
    required Map<String, dynamic> pagamento,
    required WebFinanceiroEstornoModo modo,
    required String motivo,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    final pagamentoId = (pagamento['id'] ?? '').toString().trim();
    final status = (pagamento['status'] ?? '').toString().trim();
    final atualizadoEm = (pagamento['atualizado_em'] ?? '').toString().trim();
    final motivoLimpo = motivo.trim();

    if (pagamentoId.isEmpty) {
      throw ArgumentError('Pagamento inválido.');
    }

    if (status != 'Pago') {
      throw StateError('Somente pagamentos confirmados podem ser estornados.');
    }

    if (atualizadoEm.isEmpty) {
      throw StateError(
        'A versão do pagamento não está disponível. Atualize a página e tente novamente.',
      );
    }

    if (motivoLimpo.length < 5) {
      throw ArgumentError('Informe um motivo com pelo menos 5 caracteres.');
    }

    final origem = await WebOrigemService.instance.proxima();
    final assinatura = sha256
        .convert(
          utf8.encode(
            '$empresaId|$pagamentoId|$atualizadoEm|${modo.name}|$motivoLimpo',
          ),
        )
        .toString();
    final idempotencyKey = 'web-estorno-$assinatura';

    final raw = await client.rpc(
      'imperium_financeiro_estornar_pagamento_web_v1',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_pagamento_id': pagamentoId,
        'p_pagamento_atualizado_em': atualizadoEm,
        'p_modo': modo.name,
        'p_motivo': motivoLimpo,
        'p_idempotency_key': idempotencyKey,
        'p_origem_dispositivo': origem.dispositivoId,
        'p_origem_base': origem.localId,
        'p_timezone': 'America/Sao_Paulo',
      },
    );

    return Map<String, dynamic>.from(raw as Map);
  }
}
