import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class OrdemServicoRevisaoRepository {
  Future<int> registrarComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String tipo,
    required String motivo,
    required Map<String, dynamic> dadosAnteriores,
    required Map<String, dynamic> dadosNovos,
  }) async {
    final tipoLimpo = tipo.trim();
    final motivoLimpo = motivo.trim();

    if (tipoLimpo.isEmpty) {
      throw ArgumentError('O tipo da correção não pode estar vazio.');
    }

    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe um motivo de correção com pelo menos 5 caracteres.',
      );
    }

    final resultado = await transaction.query(
      'ordens_servico',
      columns: [
        'id',
        'status',
        'assinatura_cliente',
        'quantidade_revisoes',
        'assinatura_desatualizada',
      ],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Ordem de Serviço não encontrada.');
    }

    final ordem = resultado.first;
    final status = (ordem['status'] ?? '').toString().trim();

    if (status != 'Finalizada') {
      throw StateError(
        'Somente Ordens de Serviço finalizadas podem receber '
        'uma correção auditada.',
      );
    }

    final quantidadeAtual =
        (ordem['quantidade_revisoes'] as num?)?.toInt() ?? 0;
    final numeroRevisao = quantidadeAtual + 1;

    final assinatura = (ordem['assinatura_cliente'] ?? '').toString().trim();
    final assinaturaJaDesatualizada =
        (ordem['assinatura_desatualizada'] as num?)?.toInt() == 1;
    final assinaturaDesatualizada =
        assinatura.isNotEmpty || assinaturaJaDesatualizada;

    final agora = DateTime.now();

    final linhasAlteradas = await transaction.update(
      'ordens_servico',
      {
        'revisada_em': agora.toIso8601String(),
        'motivo_ultima_revisao': motivoLimpo,
        'quantidade_revisoes': numeroRevisao,
        'assinatura_desatualizada': assinaturaDesatualizada ? 1 : 0,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [ordemServicoId, 'Finalizada'],
    );

    if (linhasAlteradas == 0) {
      throw StateError(
        'A Ordem de Serviço não pôde ser atualizada para registrar '
        'a correção.',
      );
    }

    await transaction.insert('ordem_servico_revisoes', {
      'ordem_servico_id': ordemServicoId,
      'numero_revisao': numeroRevisao,
      'tipo': tipoLimpo,
      'motivo': motivoLimpo,
      'dados_anteriores_json': jsonEncode(dadosAnteriores),
      'dados_novos_json': jsonEncode(dadosNovos),
      'criado_em': agora.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    return numeroRevisao;
  }
}
