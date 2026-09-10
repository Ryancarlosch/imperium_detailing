import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class NotaFiscalCorrecaoImpacto {
  const NotaFiscalCorrecaoImpacto({
    required this.notaFiscalId,
    required this.chaveAcesso,
    required this.numero,
    required this.emitente,
    required this.entradasEstoque,
    required this.lotesConsumidos,
    required this.financeirosPrevistos,
    required this.financeirosRealizados,
    required this.valorFinanceiroRealizado,
    required this.podeDesfazerAutomaticamente,
    required this.bloqueios,
  });

  final int notaFiscalId;
  final String chaveAcesso;
  final String numero;
  final String emitente;
  final int entradasEstoque;
  final int lotesConsumidos;
  final int financeirosPrevistos;
  final int financeirosRealizados;
  final double valorFinanceiroRealizado;
  final bool podeDesfazerAutomaticamente;
  final List<String> bloqueios;

  bool get possuiEstoque => entradasEstoque > 0;
  bool get possuiFinanceiro =>
      financeirosPrevistos > 0 || financeirosRealizados > 0;
  bool get possuiIntegracoes => possuiEstoque || possuiFinanceiro;
}

class NotaFiscalCorrecaoService {
  NotaFiscalCorrecaoService({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  Future<NotaFiscalCorrecaoImpacto> analisar(int notaFiscalId) async {
    final database = await _databaseProvider();
    return _analisar(database, notaFiscalId);
  }

  Future<void> desfazerIntegracoes({
    required int notaFiscalId,
    required String motivo,
  }) async {
    final motivoLimpo = _validarMotivo(motivo);
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      final impacto = await _analisar(transaction, notaFiscalId);
      if (!impacto.podeDesfazerAutomaticamente) {
        throw StateError(impacto.bloqueios.join('\n'));
      }
      await _desfazerEstoque(transaction, impacto, motivoLimpo);
      await _desfazerFinanceiro(transaction, impacto, motivoLimpo);
      await _registrarRevisao(
        transaction,
        impacto: impacto,
        tipo: 'Desfazer integrações',
        motivo: motivoLimpo,
        detalhes:
            'Estoque: ${impacto.entradasEstoque} entrada(s). '
            'Financeiro: ${impacto.financeirosPrevistos} previsto(s), '
            '${impacto.financeirosRealizados} realizado(s).',
      );
    });
  }

  Future<void> excluirNotaComDesfazimento({
    required int notaFiscalId,
    required String motivo,
  }) async {
    final motivoLimpo = _validarMotivo(motivo);
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      final impacto = await _analisar(transaction, notaFiscalId);
      if (!impacto.podeDesfazerAutomaticamente) {
        throw StateError(impacto.bloqueios.join('\n'));
      }

      await _desfazerEstoque(transaction, impacto, motivoLimpo);
      await _desfazerFinanceiro(transaction, impacto, motivoLimpo);
      await _registrarRevisao(
        transaction,
        impacto: impacto,
        tipo: 'Excluir nota',
        motivo: motivoLimpo,
        detalhes:
            'Nota removida após desfazimento seguro. '
            'Estoque: ${impacto.entradasEstoque} entrada(s). '
            'Financeiro: ${impacto.financeirosPrevistos} previsto(s), '
            '${impacto.financeirosRealizados} realizado(s).',
      );

      await transaction.delete(
        'notas_fiscais_entrada',
        where: 'id = ?',
        whereArgs: [notaFiscalId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> listarAuditoria({
    int? notaFiscalId,
    String? chaveAcesso,
  }) async {
    final database = await _databaseProvider();
    final filtros = <String>[];
    final args = <Object?>[];
    if (notaFiscalId != null) {
      filtros.add('nota_fiscal_id = ?');
      args.add(notaFiscalId);
    }
    final chave = chaveAcesso?.trim() ?? '';
    if (chave.isNotEmpty) {
      filtros.add('chave_acesso_snapshot = ?');
      args.add(chave);
    }
    return database.query(
      'nota_fiscal_entrada_revisoes',
      where: filtros.isEmpty ? null : filtros.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'criado_em DESC, id DESC',
    );
  }

  Future<NotaFiscalCorrecaoImpacto> _analisar(
    DatabaseExecutor database,
    int notaFiscalId,
  ) async {
    final nota = await database.query(
      'notas_fiscais_entrada',
      columns: ['id', 'chave_acesso', 'numero', 'emitente_nome'],
      where: 'id = ?',
      whereArgs: [notaFiscalId],
      limit: 1,
    );
    if (nota.isEmpty) throw StateError('Nota fiscal não encontrada.');

    final movimentosEstoque = await database.rawQuery(
      '''
      SELECT
        me.id,
        me.item_estoque_id,
        me.quantidade,
        me.lote_id,
        me.nota_fiscal_item_id,
        l.quantidade_normalizada,
        l.quantidade_disponivel,
        l.ativo AS lote_ativo,
        (
          SELECT COUNT(*)
          FROM ordem_servico_produto_lotes opl
          WHERE opl.lote_id = me.lote_id
            AND COALESCE(opl.quantidade, 0) > 0
        ) AS usos_os
      FROM movimentacoes_estoque me
      LEFT JOIN estoque_lotes l ON l.id = me.lote_id
      WHERE me.nota_fiscal_id = ?
        AND me.tipo = 'ENTRADA'
        AND me.origem = 'Nota fiscal de entrada'
      ORDER BY me.id ASC
      ''',
      [notaFiscalId],
    );

    var lotesConsumidos = 0;
    final bloqueios = <String>[];
    for (final movimento in movimentosEstoque) {
      final original = _double(movimento['quantidade_normalizada']);
      final disponivel = _double(movimento['quantidade_disponivel']);
      final usosOs = _int(movimento['usos_os']);
      final loteAtivo = _int(movimento['lote_ativo']);
      final consumido =
          usosOs > 0 ||
          (original > 0 && disponivel + 0.000001 < original) ||
          (loteAtivo == 0 && original > 0 && disponivel < original);
      if (consumido) lotesConsumidos++;
    }
    if (lotesConsumidos > 0) {
      bloqueios.add(
        'Há $lotesConsumidos lote(s) desta nota já consumidos por Ordens de Serviço. '
        'Revise essas OS antes de desfazer a nota para não alterar custos históricos.',
      );
    }

    final financeiros = await database.rawQuery(
      '''
      SELECT status, COUNT(*) AS total, COALESCE(SUM(valor), 0) AS valor
      FROM movimentos_financeiros
      WHERE nota_fiscal_id = ?
        AND origem = 'Nota fiscal de entrada'
        AND status IN ('Previsto', 'Realizado')
      GROUP BY status
      ''',
      [notaFiscalId],
    );
    var previstos = 0;
    var realizados = 0;
    var valorRealizado = 0.0;
    for (final row in financeiros) {
      final status = (row['status'] ?? '').toString();
      if (status == 'Previsto') previstos = _int(row['total']);
      if (status == 'Realizado') {
        realizados = _int(row['total']);
        valorRealizado = _double(row['valor']);
      }
    }

    final realizadosSemConta =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM movimentos_financeiros
            WHERE nota_fiscal_id = ?
              AND origem = 'Nota fiscal de entrada'
              AND status = 'Realizado'
              AND conta_id IS NULL
            ''',
            [notaFiscalId],
          ),
        ) ??
        0;
    if (realizadosSemConta > 0) {
      bloqueios.add(
        'Há $realizadosSemConta pagamento(s) realizado(s) sem conta financeira. '
        'Corrija o vínculo da conta antes de desfazer a nota.',
      );
    }

    final n = nota.first;
    return NotaFiscalCorrecaoImpacto(
      notaFiscalId: notaFiscalId,
      chaveAcesso: (n['chave_acesso'] ?? '').toString(),
      numero: (n['numero'] ?? '').toString(),
      emitente: (n['emitente_nome'] ?? '').toString(),
      entradasEstoque: movimentosEstoque.length,
      lotesConsumidos: lotesConsumidos,
      financeirosPrevistos: previstos,
      financeirosRealizados: realizados,
      valorFinanceiroRealizado: valorRealizado,
      podeDesfazerAutomaticamente: bloqueios.isEmpty,
      bloqueios: bloqueios,
    );
  }

  Future<void> _desfazerEstoque(
    DatabaseExecutor database,
    NotaFiscalCorrecaoImpacto impacto,
    String motivo,
  ) async {
    final movimentos = await database.query(
      'movimentacoes_estoque',
      where:
          "nota_fiscal_id = ? AND tipo = 'ENTRADA' "
          "AND origem = 'Nota fiscal de entrada'",
      whereArgs: [impacto.notaFiscalId],
      orderBy: 'id ASC',
    );

    for (final movimento in movimentos) {
      final movimentoId = _int(movimento['id']);
      final itemId = _int(movimento['item_estoque_id']);
      final loteId = _intNulo(movimento['lote_id']);
      final quantidade = _double(movimento['quantidade']);
      final itemFiscalId = _intNulo(movimento['nota_fiscal_item_id']);
      final itemRows = await database.query(
        'itens_estoque',
        columns: [
          'id',
          'quantidade',
          'custo_unitario',
          'custo_unitario_calculado',
        ],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw StateError('Item de estoque #$itemId não encontrado no estorno.');
      }
      final anterior = _double(itemRows.first['quantidade']);
      final posterior = anterior - quantidade;
      if (posterior < -0.000001) {
        throw StateError(
          'O estoque atual do item #$itemId é menor que a entrada que precisa ser estornada.',
        );
      }
      final quantidadeFinal = posterior < 0 ? 0.0 : posterior;
      final agora = DateTime.now().toIso8601String();

      if (loteId != null) {
        final lote = await database.query(
          'estoque_lotes',
          columns: ['id', 'quantidade_normalizada', 'quantidade_disponivel'],
          where: 'id = ?',
          whereArgs: [loteId],
          limit: 1,
        );
        if (lote.isNotEmpty) {
          final original = _double(lote.first['quantidade_normalizada']);
          final disponivel = _double(lote.first['quantidade_disponivel']);
          if (original > 0 && disponivel + 0.000001 < original) {
            throw StateError('O lote #$loteId já foi parcialmente consumido.');
          }
          await database.update(
            'estoque_lotes',
            {'quantidade_disponivel': 0.0, 'ativo': 0},
            where: 'id = ?',
            whereArgs: [loteId],
          );
        }
      }

      await database.update(
        'movimentacoes_estoque',
        {
          'origem': 'Nota fiscal de entrada estornada',
          'motivo': 'Entrada fiscal estornada: $motivo',
        },
        where: 'id = ?',
        whereArgs: [movimentoId],
      );

      await database.insert('movimentacoes_estoque', {
        'item_estoque_id': itemId,
        'tipo': 'SAIDA',
        'quantidade': quantidade,
        'quantidade_anterior': anterior,
        'quantidade_posterior': quantidadeFinal,
        'custo_unitario': _double(movimento['custo_unitario']),
        'observacoes': 'Estorno da nota fiscal ${impacto.chaveAcesso}',
        'motivo': motivo,
        'origem': 'Estorno de nota fiscal de entrada',
        'ordem_servico_id': null,
        'lote_id': loteId,
        'nota_fiscal_id': impacto.notaFiscalId,
        'nota_fiscal_item_id': itemFiscalId,
        'data': agora,
      });

      final custoRows = await database.rawQuery(
        '''
        SELECT
          COALESCE(SUM(quantidade_disponivel), 0) AS qtd,
          COALESCE(SUM(quantidade_disponivel * custo_unitario), 0) AS valor
        FROM estoque_lotes
        WHERE item_estoque_id = ?
          AND ativo = 1
          AND quantidade_disponivel > 0
        ''',
        [itemId],
      );
      final qtdAtiva = _double(custoRows.first['qtd']);
      final valorAtivo = _double(custoRows.first['valor']);
      final custoCalculado = qtdAtiva > 0
          ? valorAtivo / qtdAtiva
          : _double(itemRows.first['custo_unitario']);

      await database.update(
        'itens_estoque',
        {
          'quantidade': quantidadeFinal,
          'custo_unitario_calculado': custoCalculado,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
    }

    if (movimentos.isNotEmpty) {
      await _registrarRevisao(
        database,
        impacto: impacto,
        tipo: 'Estorno estoque',
        motivo: motivo,
        detalhes: '${movimentos.length} entrada(s) fiscal(is) estornada(s).',
      );
    }
  }

  Future<void> _desfazerFinanceiro(
    DatabaseExecutor database,
    NotaFiscalCorrecaoImpacto impacto,
    String motivo,
  ) async {
    final movimentos = await database.query(
      'movimentos_financeiros',
      where:
          "nota_fiscal_id = ? AND origem = 'Nota fiscal de entrada' "
          "AND status IN ('Previsto', 'Realizado')",
      whereArgs: [impacto.notaFiscalId],
      orderBy: 'id ASC',
    );
    final agora = DateTime.now().toIso8601String();
    var estornos = 0;

    for (final movimento in movimentos) {
      final id = _int(movimento['id']);
      final status = (movimento['status'] ?? '').toString();

      if (status == 'Previsto') {
        await database.update(
          'movimentos_financeiros',
          {
            'status': 'Cancelado',
            'observacoes': _juntarObservacao(
              (movimento['observacoes'] ?? '').toString(),
              'Cancelado por correção da nota fiscal: $motivo',
            ),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        continue;
      }

      // Um realizado precisa continuar no histórico de caixa. Se apenas o
      // marcássemos como Cancelado, o saldo já seria recomposto pelo motor
      // financeiro e uma segunda entrada de estorno duplicaria a devolução.
      // Mantemos o realizado, retiramos seu efeito de DRE e mudamos a origem
      // para liberar uma nova integração fiscal da mesma nota.
      await database.update(
        'movimentos_financeiros',
        {
          'origem': 'Nota fiscal de entrada estornada',
          'impacta_dre': 0,
          'observacoes': _juntarObservacao(
            (movimento['observacoes'] ?? '').toString(),
            'Estornado por correção da nota fiscal: $motivo',
          ),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final contaId = _intNulo(movimento['conta_id']);
      if (contaId == null) {
        throw StateError(
          'Pagamento realizado #$id não possui conta financeira para estorno.',
        );
      }

      final tipoOriginal = (movimento['tipo'] ?? 'Saída').toString();
      final tipoEstorno = tipoOriginal == 'Entrada' ? 'Saída' : 'Entrada';

      await database.insert('movimentos_financeiros', {
        'tipo': tipoEstorno,
        'descricao':
            'Estorno: ${(movimento['descricao'] ?? 'Compra fiscal').toString()}',
        'valor': _double(movimento['valor']),
        'forma_pagamento': (movimento['forma_pagamento'] ?? 'Estorno')
            .toString(),
        'data': agora,
        'cliente_id': null,
        'agendamento_id': null,
        'ordem_servico_id': null,
        'pagamento_id': null,
        'plano_conta_id': _intNulo(movimento['plano_conta_id']),
        'conta_id': contaId,
        'fornecedor_id': _intNulo(movimento['fornecedor_id']),
        'transferencia_id': null,
        'nota_fiscal_id': impacto.notaFiscalId,
        'parcela_numero': null,
        'total_parcelas': 1,
        'natureza': 'Estorno',
        'origem': 'Estorno de nota fiscal de entrada',
        'status': 'Realizado',
        'data_competencia': agora,
        'data_vencimento': null,
        'data_pagamento': agora,
        'numero_documento':
            'ESTORNO ${(movimento['numero_documento'] ?? '').toString()}',
        'observacoes':
            'Estorno gerado pela correção da nota ${impacto.chaveAcesso}. Motivo: $motivo',
        'impacta_dre': 0,
      });
      estornos++;
    }

    if (movimentos.isNotEmpty) {
      await _registrarRevisao(
        database,
        impacto: impacto,
        tipo: 'Estorno financeiro',
        motivo: motivo,
        detalhes:
            '${impacto.financeirosPrevistos} previsto(s) cancelado(s); '
            '$estornos estorno(s) de caixa criado(s).',
      );
    }
  }

  Future<void> _registrarRevisao(
    DatabaseExecutor database, {
    required NotaFiscalCorrecaoImpacto impacto,
    required String tipo,
    required String motivo,
    required String detalhes,
  }) async {
    await database.insert('nota_fiscal_entrada_revisoes', {
      'nota_fiscal_id': impacto.notaFiscalId,
      'chave_acesso_snapshot': impacto.chaveAcesso,
      'numero_snapshot': impacto.numero,
      'emitente_snapshot': impacto.emitente,
      'tipo': tipo,
      'motivo': motivo,
      'detalhes': detalhes,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  static String _validarMotivo(String motivo) {
    final limpo = motivo.trim();
    if (limpo.length < 5) {
      throw ArgumentError('Informe um motivo com pelo menos 5 caracteres.');
    }
    return limpo;
  }

  static String _juntarObservacao(String atual, String nova) {
    final limpa = atual.trim();
    return limpa.isEmpty ? nova : '$limpa\n$nova';
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
