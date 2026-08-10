import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/ajuste_financeiro_ordem_servico.dart';
import '../models/pagamento_ordem_servico.dart';

class PagamentoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<List<PagamentoOrdemServico>> listarPagamentosDaOrdem(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_pagamentos',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: '''
        CASE status
          WHEN 'Pendente' THEN 1
          WHEN 'Pago' THEN 2
          WHEN 'Estornado' THEN 3
          WHEN 'Cancelado' THEN 4
          ELSE 5
        END,
        COALESCE(vencimento, data_pagamento, criado_em) ASC,
        COALESCE(parcela_numero, 999999) ASC,
        id ASC
      ''',
    );

    return resultado
        .map(
          (mapa) =>
              PagamentoOrdemServico.fromMap(Map<String, dynamic>.from(mapa)),
        )
        .toList();
  }

  Future<Map<String, dynamic>?> buscarResumoOrdem(int ordemServicoId) async {
    final database = await _appDatabase.database;
    await _atualizarStatusVencidos(database);

    final resultado = await database.rawQuery(
      '''
      SELECT
        os.*,
        clientes.nome AS cliente_nome,
        clientes.telefone AS cliente_telefone,
        clientes.email AS cliente_email,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        (
          SELECT COALESCE(
            SUM(
              CASE
                WHEN COALESCE(p.custo_total_no_momento, 0) > 0
                  THEN p.custo_total_no_momento
                ELSE COALESCE(p.quantidade, 0) *
                  CASE
                    WHEN COALESCE(p.custo_unitario_no_momento, 0) > 0
                      THEN p.custo_unitario_no_momento
                    ELSE COALESCE(p.custo_unitario, 0)
                  END
              END
            ),
            0
          )
          FROM ordem_servico_produtos p
          WHERE p.ordem_servico_id = os.id
        ) AS custo_produtos
      FROM ordens_servico os
      INNER JOIN clientes ON clientes.id = os.cliente_id
      LEFT JOIN veiculos ON veiculos.id = os.veiculo_id
      WHERE os.id = ?
      LIMIT 1
      ''',
      [ordemServicoId],
    );

    if (resultado.isEmpty) {
      return null;
    }

    final mapa = Map<String, dynamic>.from(resultado.first);
    final total = _valorFinal(mapa);
    final valorBase = _valorBase(mapa);
    final recebido = _double(mapa['valor_recebido']);

    final resumoPagamentos = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(taxa_operacao), 0) AS taxas_registradas,
        COALESCE(
          SUM(CASE WHEN status = 'Pago' THEN valor ELSE 0 END),
          0
        ) - COALESCE(SUM(taxa_operacao), 0) AS liquido_recebido
      FROM ordem_servico_pagamentos
      WHERE ordem_servico_id = ?
      ''',
      [ordemServicoId],
    );

    final taxasRegistradas = _double(
      resumoPagamentos.first['taxas_registradas'],
    );
    final liquidoRecebido = _double(resumoPagamentos.first['liquido_recebido']);
    final custoProdutos = _double(mapa['custo_produtos']);

    mapa['valor_base'] = valorBase;
    mapa['valor_final'] = total;
    mapa['valor_pendente'] = (total - recebido)
        .clamp(0, double.infinity)
        .toDouble();
    mapa['taxas_operacao'] = taxasRegistradas;
    mapa['valor_liquido_recebido'] = liquidoRecebido;
    mapa['resultado_apos_taxas_produtos'] = liquidoRecebido - custoProdutos;

    return mapa;
  }

  Future<List<Map<String, dynamic>>> listarContasReceber({
    String? status,
    bool incluirPagas = false,
  }) async {
    final database = await _appDatabase.database;
    await _atualizarStatusVencidos(database);

    final filtros = <String>["os.status = 'Finalizada'"];
    final argumentos = <Object?>[];

    if (!incluirPagas) {
      filtros.add("os.status_pagamento != 'Pago'");
      filtros.add("os.status_pagamento != 'Cancelado'");
    }

    final statusLimpo = status?.trim() ?? '';
    if (statusLimpo.isNotEmpty && statusLimpo != 'Todos') {
      filtros.add('os.status_pagamento = ?');
      argumentos.add(statusLimpo);
    }

    final resultado = await database.rawQuery('''
      SELECT
        os.id,
        os.numero,
        os.status,
        os.status_pagamento,
        os.valor_total,
        os.desconto,
        os.desconto_negociacao,
        os.acrescimo_negociacao,
        os.juros_parcelamento,
        os.valor_recebido,
        os.vencimento_pagamento,
        os.forma_pagamento,
        os.data_finalizacao,
        os.pagamento_atualizado_em,
        clientes.nome AS cliente_nome,
        clientes.telefone AS cliente_telefone,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        (
          SELECT COUNT(*)
          FROM ordem_servico_pagamentos p
          WHERE p.ordem_servico_id = os.id
            AND p.status = 'Pendente'
        ) AS parcelas_pendentes
      FROM ordens_servico os
      INNER JOIN clientes ON clientes.id = os.cliente_id
      LEFT JOIN veiculos ON veiculos.id = os.veiculo_id
      WHERE ${filtros.join(' AND ')}
      ORDER BY
        CASE os.status_pagamento
          WHEN 'Vencido' THEN 1
          WHEN 'Parcialmente pago' THEN 2
          WHEN 'Pendente' THEN 3
          WHEN 'Pago' THEN 4
          ELSE 5
        END,
        COALESCE(os.vencimento_pagamento, '9999-12-31') ASC,
        os.id DESC
      ''', argumentos);

    return resultado.map((item) {
      final mapa = Map<String, dynamic>.from(item);
      final total = _valorFinal(mapa);
      final recebido = _double(mapa['valor_recebido']);
      mapa['valor_base'] = _valorBase(mapa);
      mapa['valor_final'] = total;
      mapa['valor_pendente'] = (total - recebido)
          .clamp(0, double.infinity)
          .toDouble();
      return mapa;
    }).toList();
  }

  Future<Map<String, double>> obterResumoGeral() async {
    final database = await _appDatabase.database;
    await _atualizarStatusVencidos(database);

    final ordens = await database.rawQuery('''
      SELECT
        status_pagamento,
        MAX(
          COALESCE(valor_total, 0)
          - COALESCE(desconto, 0)
          - COALESCE(desconto_negociacao, 0)
          + COALESCE(acrescimo_negociacao, 0)
          + COALESCE(juros_parcelamento, 0),
          0
        ) AS total,
        COALESCE(valor_recebido, 0) AS recebido
      FROM ordens_servico
      WHERE status = 'Finalizada'
      ''');

    var totalReceber = 0.0;
    var totalVencido = 0.0;
    var totalRecebido = 0.0;

    for (final ordem in ordens) {
      final total = _double(ordem['total']);
      final recebido = _double(ordem['recebido']);
      final pendente = (total - recebido).clamp(0, double.infinity).toDouble();
      final statusPagamento = (ordem['status_pagamento'] ?? '').toString();

      totalRecebido += recebido;

      if (statusPagamento != 'Pago' && statusPagamento != 'Cancelado') {
        totalReceber += pendente;
      }

      if (statusPagamento == 'Vencido') {
        totalVencido += pendente;
      }
    }

    final resumoTaxas = await database.rawQuery('''
      SELECT COALESCE(SUM(taxa_operacao), 0) AS taxas
      FROM ordem_servico_pagamentos
      ''');

    final taxas = _double(resumoTaxas.first['taxas']);

    return {
      'a_receber': totalReceber,
      'vencido': totalVencido,
      'recebido': totalRecebido,
      'taxas': taxas,
      'liquido': totalRecebido - taxas,
    };
  }

  Future<List<AjusteFinanceiroOrdemServico>> listarAjustesDaOrdem(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_ajustes_financeiros',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'criado_em DESC, id DESC',
    );

    return resultado
        .map(
          (mapa) => AjusteFinanceiroOrdemServico.fromMap(
            Map<String, dynamic>.from(mapa),
          ),
        )
        .toList();
  }

  Future<int> registrarAjusteComercial({
    required int ordemServicoId,
    required String tipo,
    required double valor,
    required String motivo,
  }) async {
    final tipoLimpo = tipo.trim();
    final motivoLimpo = motivo.trim();

    if (!_tipoAjusteValido(tipoLimpo)) {
      throw ArgumentError('Tipo de ajuste financeiro inválido.');
    }

    if (valor <= 0) {
      throw ArgumentError('O valor do ajuste deve ser maior que zero.');
    }

    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe um motivo do ajuste com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);

      if ((ordem['status'] ?? '').toString().trim() != 'Finalizada') {
        throw StateError(
          'A negociação financeira só pode ser alterada após finalizar a OS.',
        );
      }

      if (await _possuiParcelasPendentes(transaction, ordemServicoId)) {
        throw StateError(
          'Cancele as parcelas pendentes antes de alterar a negociação.',
        );
      }

      final agora = DateTime.now().toIso8601String();

      final ajusteId = await transaction.insert(
        'ordem_servico_ajustes_financeiros',
        {
          'ordem_servico_id': ordemServicoId,
          'tipo': tipoLimpo,
          'valor': valor,
          'motivo': motivoLimpo,
          'status': 'Ativo',
          'criado_em': agora,
          'cancelado_em': null,
          'motivo_cancelamento': '',
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _sincronizarResumoAjustes(transaction, ordemServicoId);
      await _recalcularOrdem(transaction, ordemServicoId);

      return ajusteId;
    });
  }

  Future<void> estornarAjusteComercial({
    required int ajusteId,
    required String motivo,
  }) async {
    final motivoLimpo = motivo.trim();

    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe um motivo do estorno com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordem_servico_ajustes_financeiros',
        where: 'id = ?',
        whereArgs: [ajusteId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ajuste financeiro não encontrado.');
      }

      final ajuste = resultado.first;

      if ((ajuste['status'] ?? '').toString() != 'Ativo') {
        throw StateError('Este ajuste financeiro já foi cancelado.');
      }

      final ordemServicoId = _int(ajuste['ordem_servico_id']);
      if (ordemServicoId == null) {
        throw StateError('O ajuste não está vinculado a uma OS válida.');
      }

      if (await _possuiParcelasPendentes(transaction, ordemServicoId)) {
        throw StateError(
          'Cancele as parcelas pendentes antes de alterar a negociação.',
        );
      }

      final agora = DateTime.now().toIso8601String();

      await transaction.update(
        'ordem_servico_ajustes_financeiros',
        {
          'status': 'Cancelado',
          'cancelado_em': agora,
          'motivo_cancelamento': motivoLimpo,
        },
        where: 'id = ?',
        whereArgs: [ajusteId],
      );

      await _sincronizarResumoAjustes(transaction, ordemServicoId);
      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<Map<String, dynamic>?> calcularTaxaAutomatica({
    required String formaPagamento,
    required double valor,
    int parcelas = 1,
    int? contaFinanceiraId,
  }) async {
    if (!_ehFormaCartao(formaPagamento) || valor <= 0) {
      return null;
    }
    final database = await _appDatabase.database;
    final regra = await _buscarRegraTaxa(
      database,
      formaPagamento: formaPagamento.trim(),
      parcelas: parcelas.clamp(1, 48).toInt(),
      contaFinanceiraId: contaFinanceiraId,
    );
    if (regra == null) {
      return null;
    }

    final percentual = _double(regra['taxa_percentual']);
    final fixa = _double(regra['taxa_fixa']);
    final repassarCliente = _int(regra['repassar_cliente']) == 1;
    final valorCobrado = repassarCliente
        ? _calcularValorCobradoComRepasse(
            valorBase: valor,
            taxaPercentual: percentual,
            taxaFixa: fixa,
          )
        : valor;
    final taxa = _arredondarCentavos(
      valorCobrado * percentual / 100 + fixa,
    ).clamp(0, valorCobrado).toDouble();
    final acrescimo = (valorCobrado - valor)
        .clamp(0, double.infinity)
        .toDouble();

    return {
      'id': _int(regra['id']),
      'nome': (regra['nome'] ?? '').toString(),
      'taxa_percentual': percentual,
      'taxa_fixa': fixa,
      'taxa_operacao': taxa,
      'valor_base': valor,
      'valor_cobrado': valorCobrado,
      'acrescimo_cliente': acrescimo,
      'valor_liquido': (valorCobrado - taxa)
          .clamp(0, double.infinity)
          .toDouble(),
      'repassar_cliente': repassarCliente,
      'parcelas': _int(regra['parcelas']) ?? parcelas,
      'prazo_recebimento_dias': _int(regra['prazo_recebimento_dias']) ?? 0,
      'conta_id': _int(regra['conta_id']),
    };
  }

  Future<int> registrarPagamento({
    required int ordemServicoId,
    required double valor,
    required String formaPagamento,
    DateTime? dataPagamento,
    String? comprovanteCaminho,
    String observacoes = '',
    double taxaOperacao = 0,
    double? taxaPercentual,
    int? contaFinanceiraId,
    int parcelasTaxa = 1,
    int? regraTaxaId,
    bool aplicarRegraTaxaAutomatica = true,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction((transaction) {
      return registrarPagamentoComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        valor: valor,
        formaPagamento: formaPagamento,
        dataPagamento: dataPagamento ?? DateTime.now(),
        comprovanteCaminho: comprovanteCaminho,
        observacoes: observacoes,
        taxaOperacao: taxaOperacao,
        taxaPercentual: taxaPercentual,
        contaFinanceiraId: contaFinanceiraId,
        parcelasTaxa: parcelasTaxa,
        regraTaxaId: regraTaxaId,
        aplicarRegraTaxaAutomatica: aplicarRegraTaxaAutomatica,
      );
    });
  }

  Future<int> registrarPagamentoComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required double valor,
    required String formaPagamento,
    required DateTime dataPagamento,
    String? comprovanteCaminho,
    String observacoes = '',
    double taxaOperacao = 0,
    double? taxaPercentual,
    int? contaFinanceiraId,
    int parcelasTaxa = 1,
    int? regraTaxaId,
    bool aplicarRegraTaxaAutomatica = true,
  }) async {
    if (valor <= 0) {
      throw ArgumentError('O valor do pagamento deve ser maior que zero.');
    }

    final forma = formaPagamento.trim();
    if (forma.isEmpty) {
      throw ArgumentError('Informe a forma de pagamento.');
    }

    final parcelasReferencia = parcelasTaxa.clamp(1, 48).toInt();
    final cobranca = await _resolverTaxaPagamento(
      transaction,
      formaPagamento: forma,
      valor: valor,
      parcelas: parcelasReferencia,
      contaFinanceiraId: contaFinanceiraId,
      taxaOperacaoInformada: taxaOperacao,
      taxaPercentualInformada: taxaPercentual,
      regraTaxaIdInformada: regraTaxaId,
      aplicarAutomatica: aplicarRegraTaxaAutomatica,
    );

    _validarTaxa(
      valor: cobranca.valorCobrado,
      taxaOperacao: cobranca.taxaOperacao,
      taxaPercentual: cobranca.taxaPercentual,
    );

    final contaRecebimentoId =
        cobranca.contaFinanceiraId ?? contaFinanceiraId;

    var ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
    final statusOrdem = (ordem['status'] ?? '').toString().trim();

    if (statusOrdem != 'Finalizada') {
      throw StateError(
        'Pagamentos só podem ser registrados em Ordens de Serviço finalizadas.',
      );
    }

    final parcelasPendentes =
        Sqflite.firstIntValue(
          await transaction.rawQuery(
            '''
            SELECT COUNT(*)
            FROM ordem_servico_pagamentos
            WHERE ordem_servico_id = ?
              AND status = 'Pendente'
              AND parcela_numero IS NOT NULL
            ''',
            [ordemServicoId],
          ),
        ) ??
        0;

    if (parcelasPendentes > 0) {
      throw StateError(
        'Esta OS possui parcelas pendentes. Receba a parcela correspondente '
        'para manter o parcelamento consistente.',
      );
    }

    final totalAntesRepasse = _valorFinal(ordem);
    final recebidoAtual = await _somarPagamentosPagos(
      transaction,
      ordemServicoId,
    );
    final saldoAntesRepasse = (totalAntesRepasse - recebidoAtual)
        .clamp(0, double.infinity)
        .toDouble();

    if (valor - saldoAntesRepasse > 0.000001) {
      throw StateError(
        'O pagamento informado é maior que o saldo pendente da OS.',
      );
    }

    int? ajusteRepasseId;
    if (cobranca.acrescimoCliente > 0.000001) {
      ajusteRepasseId = await _registrarRepasseTaxaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        valor: cobranca.acrescimoCliente,
        regraTaxaId: cobranca.regraTaxaId,
        nomeRegra: cobranca.nomeRegra,
      );
      ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
    }

    final total = _valorFinal(ordem);
    final saldo = (total - recebidoAtual).clamp(0, double.infinity).toDouble();
    if (cobranca.valorCobrado - saldo > 0.000001) {
      throw StateError(
        'O valor cobrado após aplicar a taxa ultrapassa o saldo da OS.',
      );
    }

    final agora = DateTime.now().toIso8601String();
    final dataIso = dataPagamento.toIso8601String();

    final pagamentoId = await transaction.insert('ordem_servico_pagamentos', {
      'ordem_servico_id': ordemServicoId,
      'status': 'Pago',
      'valor': cobranca.valorCobrado,
      'forma_pagamento': forma,
      'data_pagamento': dataIso,
      'parcela_numero': null,
      'total_parcelas': null,
      'vencimento': null,
      'comprovante_caminho': _textoNulo(comprovanteCaminho),
      'observacoes': observacoes.trim(),
      'taxa_percentual': cobranca.taxaPercentual,
      'taxa_operacao': cobranca.taxaOperacao,
      'valor_liquido': cobranca.valorCobrado - cobranca.taxaOperacao,
      'regra_taxa_id': cobranca.regraTaxaId,
      'parcelas_taxa': parcelasReferencia,
      'estornado_em': null,
      'motivo_estorno': '',
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    if (ajusteRepasseId != null) {
      await transaction.update(
        'ordem_servico_ajustes_financeiros',
        {'pagamento_id': pagamentoId},
        where: 'id = ?',
        whereArgs: [ajusteRepasseId],
      );
    }

    await _criarMovimentoEntrada(
      transaction,
      ordem: ordem,
      pagamentoId: pagamentoId,
      valor: cobranca.valorCobrado,
      formaPagamento: forma,
      data: dataIso,
      contaFinanceiraId: contaRecebimentoId,
    );

    if (cobranca.taxaOperacao > 0.000001) {
      await _criarMovimentoTaxa(
        transaction,
        ordem: ordem,
        pagamentoId: pagamentoId,
        valor: cobranca.taxaOperacao,
        formaPagamento: forma,
        data: dataIso,
        contaFinanceiraId: contaRecebimentoId,
      );
    }

    await _recalcularOrdem(transaction, ordemServicoId);
    return pagamentoId;
  }

  Future<void> criarParcelamento({
    required int ordemServicoId,
    required int totalParcelas,
    required DateTime primeiroVencimento,
  }) async {
    if (totalParcelas < 2 || totalParcelas > 48) {
      throw ArgumentError('A quantidade de parcelas deve ficar entre 2 e 48.');
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);

      if ((ordem['status'] ?? '').toString().trim() != 'Finalizada') {
        throw StateError('Finalize a OS antes de criar o parcelamento.');
      }

      final pendentes =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*)
              FROM ordem_servico_pagamentos
              WHERE ordem_servico_id = ? AND status = 'Pendente'
              ''',
              [ordemServicoId],
            ),
          ) ??
          0;

      if (pendentes > 0) {
        throw StateError(
          'Já existe um parcelamento pendente para esta Ordem de Serviço.',
        );
      }

      final total = _valorFinal(ordem);
      final recebido = await _somarPagamentosPagos(transaction, ordemServicoId);
      final saldo = (total - recebido).clamp(0, double.infinity).toDouble();

      if (saldo <= 0.000001) {
        throw StateError('Esta Ordem de Serviço não possui saldo pendente.');
      }

      final centavos = (saldo * 100).round();
      final base = centavos ~/ totalParcelas;
      final resto = centavos % totalParcelas;
      final agora = DateTime.now().toIso8601String();

      for (var indice = 0; indice < totalParcelas; indice++) {
        final valorCentavos = base + (indice < resto ? 1 : 0);
        final vencimento = _somarMeses(primeiroVencimento, indice);

        await transaction.insert('ordem_servico_pagamentos', {
          'ordem_servico_id': ordemServicoId,
          'status': 'Pendente',
          'valor': valorCentavos / 100,
          'forma_pagamento': '',
          'data_pagamento': null,
          'parcela_numero': indice + 1,
          'total_parcelas': totalParcelas,
          'vencimento': _dataDia(vencimento),
          'comprovante_caminho': null,
          'observacoes': '',
          'taxa_percentual': null,
          'taxa_operacao': 0,
          'valor_liquido': 0,
          'estornado_em': null,
          'motivo_estorno': '',
          'criado_em': agora,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await transaction.update(
        'ordens_servico',
        {
          'vencimento_pagamento': _dataDia(primeiroVencimento),
          'pagamento_atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<void> receberParcela({
    required int pagamentoId,
    required String formaPagamento,
    DateTime? dataPagamento,
    String? comprovanteCaminho,
    String observacoes = '',
    double taxaOperacao = 0,
    double? taxaPercentual,
    int? contaFinanceiraId,
    int parcelasTaxa = 1,
    int? regraTaxaId,
    bool aplicarRegraTaxaAutomatica = true,
  }) async {
    final forma = formaPagamento.trim();
    if (forma.isEmpty) {
      throw ArgumentError('Informe a forma de pagamento.');
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordem_servico_pagamentos',
        where: 'id = ?',
        whereArgs: [pagamentoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Parcela não encontrada.');
      }

      final parcela = resultado.first;

      if ((parcela['status'] ?? '').toString() != 'Pendente') {
        throw StateError('Esta parcela não está pendente.');
      }

      final ordemServicoId = _int(parcela['ordem_servico_id']);
      if (ordemServicoId == null) {
        throw StateError('A parcela não está vinculada a uma OS válida.');
      }

      var ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
      final valorBase = _double(parcela['valor']);

      // O parcelamento da maquininha é independente das parcelas a receber da OS.
      final parcelasReferencia = parcelasTaxa.clamp(1, 48).toInt();
      final cobranca = await _resolverTaxaPagamento(
        transaction,
        formaPagamento: forma,
        valor: valorBase,
        parcelas: parcelasReferencia,
        contaFinanceiraId: contaFinanceiraId,
        taxaOperacaoInformada: taxaOperacao,
        taxaPercentualInformada: taxaPercentual,
        regraTaxaIdInformada: regraTaxaId,
        aplicarAutomatica: aplicarRegraTaxaAutomatica,
      );

      _validarTaxa(
        valor: cobranca.valorCobrado,
        taxaOperacao: cobranca.taxaOperacao,
        taxaPercentual: cobranca.taxaPercentual,
      );

      final contaRecebimentoId =
          cobranca.contaFinanceiraId ?? contaFinanceiraId;

      int? ajusteRepasseId;
      if (cobranca.acrescimoCliente > 0.000001) {
        ajusteRepasseId = await _registrarRepasseTaxaComTransacao(
          transaction,
          ordemServicoId: ordemServicoId,
          valor: cobranca.acrescimoCliente,
          regraTaxaId: cobranca.regraTaxaId,
          nomeRegra: cobranca.nomeRegra,
        );
        ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
      }

      final data = (dataPagamento ?? DateTime.now()).toIso8601String();
      final agora = DateTime.now().toIso8601String();

      await transaction.update(
        'ordem_servico_pagamentos',
        {
          'status': 'Pago',
          'valor': cobranca.valorCobrado,
          'forma_pagamento': forma,
          'data_pagamento': data,
          'comprovante_caminho': _textoNulo(comprovanteCaminho),
          'observacoes': observacoes.trim(),
          'taxa_percentual': cobranca.taxaPercentual,
          'taxa_operacao': cobranca.taxaOperacao,
          'valor_liquido': cobranca.valorCobrado - cobranca.taxaOperacao,
          'regra_taxa_id': cobranca.regraTaxaId,
          'parcelas_taxa': parcelasReferencia,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [pagamentoId],
      );

      if (ajusteRepasseId != null) {
        await transaction.update(
          'ordem_servico_ajustes_financeiros',
          {'pagamento_id': pagamentoId},
          where: 'id = ?',
          whereArgs: [ajusteRepasseId],
        );
      }

      await _criarMovimentoEntrada(
        transaction,
        ordem: ordem,
        pagamentoId: pagamentoId,
        valor: cobranca.valorCobrado,
        formaPagamento: forma,
        data: data,
        contaFinanceiraId: contaRecebimentoId,
      );

      if (cobranca.taxaOperacao > 0.000001) {
        await _criarMovimentoTaxa(
          transaction,
          ordem: ordem,
          pagamentoId: pagamentoId,
          valor: cobranca.taxaOperacao,
          formaPagamento: forma,
          data: data,
          contaFinanceiraId: contaRecebimentoId,
        );
      }

      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<void> estornarPagamento({
    required int pagamentoId,
    required String motivo,
  }) async {
    final motivoLimpo = motivo.trim();

    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe um motivo de estorno com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordem_servico_pagamentos',
        where: 'id = ?',
        whereArgs: [pagamentoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Pagamento não encontrado.');
      }

      final pagamento = resultado.first;

      if ((pagamento['status'] ?? '').toString() != 'Pago') {
        throw StateError(
          'Somente pagamentos confirmados podem ser estornados.',
        );
      }

      final ordemServicoId = _int(pagamento['ordem_servico_id']);
      if (ordemServicoId == null) {
        throw StateError('Pagamento sem Ordem de Serviço válida.');
      }

      final ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
      final agora = DateTime.now().toIso8601String();
      final valor = _double(pagamento['valor']);
      final forma = (pagamento['forma_pagamento'] ?? '').toString().trim();
      final parcelaNumero = _int(pagamento['parcela_numero']);
      final totalParcelas = _int(pagamento['total_parcelas']);
      final vencimento = _textoNulo(pagamento['vencimento']);
      final ajustesRepasse = await transaction.query(
        'ordem_servico_ajustes_financeiros',
        columns: ['id', 'valor'],
        where:
            "pagamento_id = ? AND status = 'Ativo' AND origem = 'Taxa de maquininha'",
        whereArgs: [pagamentoId],
      );
      final repasseCliente = ajustesRepasse.fold<double>(
        0,
        (total, item) => total + _double(item['valor']),
      );
      final movimentoOriginal = await transaction.query(
        'movimentos_financeiros',
        columns: ['conta_id'],
        where: "pagamento_id = ? AND LOWER(tipo) = 'entrada'",
        whereArgs: [pagamentoId],
        orderBy: 'id ASC',
        limit: 1,
      );
      final contaFinanceiraId = movimentoOriginal.isEmpty
          ? null
          : _int(movimentoOriginal.first['conta_id']);

      await transaction.update(
        'ordem_servico_pagamentos',
        {
          'status': 'Estornado',
          'estornado_em': agora,
          'motivo_estorno': motivoLimpo,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [pagamentoId],
      );

      if (ajustesRepasse.isNotEmpty) {
        await transaction.update(
          'ordem_servico_ajustes_financeiros',
          {
            'status': 'Cancelado',
            'cancelado_em': agora,
            'motivo_cancelamento':
                'Cancelado automaticamente pelo estorno do pagamento.',
          },
          where:
              "pagamento_id = ? AND status = 'Ativo' AND origem = 'Taxa de maquininha'",
          whereArgs: [pagamentoId],
        );
        await _sincronizarResumoAjustes(transaction, ordemServicoId);
      }

      final planoEstornoId = await _buscarPlanoContaId(transaction, '1.02.01');

      await transaction.insert('movimentos_financeiros', {
        'tipo': 'saída',
        'descricao': 'Estorno de pagamento da OS ${ordem['numero']}',
        'valor': valor,
        'forma_pagamento': forma.isEmpty ? 'Não informado' : forma,
        'data': agora,
        'cliente_id': ordem['cliente_id'],
        'agendamento_id': null,
        'ordem_servico_id': ordemServicoId,
        'pagamento_id': pagamentoId,
        'conta_id': contaFinanceiraId,
        'plano_conta_id': planoEstornoId,
        'natureza': 'Dedução de receita',
        'origem': 'Estorno de pagamento',
        'status': 'Realizado',
        'data_competencia': agora,
        'data_pagamento': agora,
        'impacta_dre': 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      if (parcelaNumero != null && totalParcelas != null) {
        await transaction.insert('ordem_servico_pagamentos', {
          'ordem_servico_id': ordemServicoId,
          'status': 'Pendente',
          'valor': (valor - repasseCliente)
              .clamp(0, double.infinity)
              .toDouble(),
          'forma_pagamento': '',
          'data_pagamento': null,
          'parcela_numero': parcelaNumero,
          'total_parcelas': totalParcelas,
          'vencimento': vencimento,
          'comprovante_caminho': null,
          'observacoes':
              'Parcela reaberta após estorno do pagamento #$pagamentoId.',
          'taxa_percentual': null,
          'taxa_operacao': 0,
          'valor_liquido': 0,
          'estornado_em': null,
          'motivo_estorno': '',
          'criado_em': agora,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<void> cancelarParcelamentoPendente(int ordemServicoId) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _buscarOrdemComTransacao(transaction, ordemServicoId);

      final agora = DateTime.now().toIso8601String();

      await transaction.update(
        'ordem_servico_pagamentos',
        {'status': 'Cancelado', 'atualizado_em': agora},
        where: "ordem_servico_id = ? AND status = 'Pendente'",
        whereArgs: [ordemServicoId],
      );

      await transaction.update(
        'ordens_servico',
        {'vencimento_pagamento': null, 'pagamento_atualizado_em': agora},
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<void> definirVencimento({
    required int ordemServicoId,
    DateTime? vencimento,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _buscarOrdemComTransacao(transaction, ordemServicoId);

      await transaction.update(
        'ordens_servico',
        {
          'vencimento_pagamento': vencimento == null
              ? null
              : _dataDia(vencimento),
          'pagamento_atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      await _recalcularOrdem(transaction, ordemServicoId);
    });
  }

  Future<bool> _possuiParcelasPendentes(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final total =
        Sqflite.firstIntValue(
          await transaction.rawQuery(
            '''
            SELECT COUNT(*)
            FROM ordem_servico_pagamentos
            WHERE ordem_servico_id = ?
              AND status = 'Pendente'
              AND parcela_numero IS NOT NULL
            ''',
            [ordemServicoId],
          ),
        ) ??
        0;

    return total > 0;
  }

  Future<void> _sincronizarResumoAjustes(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final resumo = await transaction.rawQuery(
      '''
      SELECT
        COALESCE(
          SUM(CASE WHEN tipo = 'Desconto' AND status = 'Ativo' THEN valor ELSE 0 END),
          0
        ) AS desconto,
        COALESCE(
          SUM(CASE WHEN tipo = 'Acréscimo' AND status = 'Ativo' THEN valor ELSE 0 END),
          0
        ) AS acrescimo,
        COALESCE(
          SUM(CASE WHEN tipo = 'Juros' AND status = 'Ativo' THEN valor ELSE 0 END),
          0
        ) AS juros
      FROM ordem_servico_ajustes_financeiros
      WHERE ordem_servico_id = ?
      ''',
      [ordemServicoId],
    );

    final desconto = _double(resumo.first['desconto']);
    final acrescimo = _double(resumo.first['acrescimo']);
    final juros = _double(resumo.first['juros']);

    final ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
    final valorBase = _valorBase(ordem);
    final novoTotal = valorBase - desconto + acrescimo + juros;

    if (novoTotal < -0.000001) {
      throw StateError(
        'O desconto informado ultrapassa o valor disponível da negociação.',
      );
    }

    final recebido = await _somarPagamentosPagos(transaction, ordemServicoId);

    if (novoTotal + 0.000001 < recebido) {
      throw StateError(
        'O ajuste deixaria o valor negociado abaixo do total já recebido.',
      );
    }

    await transaction.update(
      'ordens_servico',
      {
        'desconto_negociacao': desconto,
        'acrescimo_negociacao': acrescimo,
        'juros_parcelamento': juros,
        'pagamento_atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  static bool _tipoAjusteValido(String tipo) {
    return tipo == 'Desconto' || tipo == 'Acréscimo' || tipo == 'Juros';
  }

  Future<Map<String, Object?>> _buscarOrdemComTransacao(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final resultado = await transaction.query(
      'ordens_servico',
      columns: [
        'id',
        'numero',
        'status',
        'cliente_id',
        'valor_total',
        'desconto',
        'desconto_negociacao',
        'acrescimo_negociacao',
        'juros_parcelamento',
        'vencimento_pagamento',
      ],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Ordem de Serviço não encontrada.');
    }

    return resultado.first;
  }

  Future<double> _somarPagamentosPagos(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final resultado = await transaction.rawQuery(
      '''
      SELECT COALESCE(SUM(valor), 0) AS total
      FROM ordem_servico_pagamentos
      WHERE ordem_servico_id = ? AND status = 'Pago'
      ''',
      [ordemServicoId],
    );

    return _double(resultado.first['total']);
  }

  Future<String?> _formaPagamentoResumo(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final resultado = await transaction.rawQuery(
      '''
      SELECT DISTINCT TRIM(forma_pagamento) AS forma
      FROM ordem_servico_pagamentos
      WHERE ordem_servico_id = ?
        AND status = 'Pago'
        AND TRIM(COALESCE(forma_pagamento, '')) != ''
      ORDER BY forma
      ''',
      [ordemServicoId],
    );

    final formas = resultado
        .map((item) => item['forma']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();

    if (formas.isEmpty) {
      return null;
    }

    if (formas.length == 1) {
      return formas.single;
    }

    return 'Múltiplas formas';
  }

  Future<void> _criarMovimentoEntrada(
    Transaction transaction, {
    required Map<String, Object?> ordem,
    required int pagamentoId,
    required double valor,
    required String formaPagamento,
    required String data,
    int? contaFinanceiraId,
  }) async {
    final planoContaId = await _buscarPlanoContaId(transaction, '1.01');

    await transaction.insert('movimentos_financeiros', {
      'tipo': 'entrada',
      'descricao': 'Pagamento da OS ${ordem['numero']}',
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data': data,
      'cliente_id': ordem['cliente_id'],
      'agendamento_id': null,
      'ordem_servico_id': ordem['id'],
      'pagamento_id': pagamentoId,
      'conta_id': contaFinanceiraId,
      'plano_conta_id': planoContaId,
      'natureza': 'Receita operacional',
      'origem': 'Pagamento de OS',
      'status': 'Realizado',
      'data_competencia': data,
      'data_pagamento': data,
      'impacta_dre': 1,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> _criarMovimentoTaxa(
    Transaction transaction, {
    required Map<String, Object?> ordem,
    required int pagamentoId,
    required double valor,
    required String formaPagamento,
    required String data,
    int? contaFinanceiraId,
  }) async {
    final planoContaId = await _buscarPlanoContaId(transaction, '2.02.01');

    await transaction.insert('movimentos_financeiros', {
      'tipo': 'saída',
      'descricao': 'Taxa da maquininha - OS ${ordem['numero']}',
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data': data,
      'cliente_id': ordem['cliente_id'],
      'agendamento_id': null,
      'ordem_servico_id': ordem['id'],
      'pagamento_id': pagamentoId,
      'conta_id': contaFinanceiraId,
      'plano_conta_id': planoContaId,
      'natureza': 'Custo variável',
      'origem': 'Taxa de pagamento',
      'status': 'Realizado',
      'data_competencia': data,
      'data_pagamento': data,
      'impacta_dre': 1,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int?> _buscarPlanoContaId(
    Transaction transaction,
    String codigo,
  ) async {
    final resultado = await transaction.query(
      'financeiro_plano_contas',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return _int(resultado.first['id']);
  }

  Future<void> _recalcularOrdem(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final ordem = await _buscarOrdemComTransacao(transaction, ordemServicoId);
    final total = _valorFinal(ordem);
    final recebido = await _somarPagamentosPagos(transaction, ordemServicoId);
    final saldo = (total - recebido).clamp(0, double.infinity).toDouble();

    final vencimentosPendentes = await transaction.rawQuery(
      '''
      SELECT MIN(vencimento) AS proximo_vencimento
      FROM ordem_servico_pagamentos
      WHERE ordem_servico_id = ?
        AND status = 'Pendente'
        AND vencimento IS NOT NULL
        AND TRIM(vencimento) != ''
      ''',
      [ordemServicoId],
    );

    final vencimentoParcelas = _textoNulo(
      vencimentosPendentes.first['proximo_vencimento'],
    );
    final vencimentoOrdem = _textoNulo(ordem['vencimento_pagamento']);
    final vencimento = vencimentoParcelas ?? vencimentoOrdem;
    final formaPagamento = await _formaPagamentoResumo(
      transaction,
      ordemServicoId,
    );

    String statusPagamento;

    if ((ordem['status'] ?? '').toString() == 'Cancelada') {
      statusPagamento = 'Cancelado';
    } else if (total <= 0.000001 || saldo <= 0.000001) {
      statusPagamento = 'Pago';
    } else if (_estaVencido(vencimento)) {
      statusPagamento = 'Vencido';
    } else if (recebido > 0.000001) {
      statusPagamento = 'Parcialmente pago';
    } else {
      statusPagamento = 'Pendente';
    }

    await transaction.update(
      'ordens_servico',
      {
        'status_pagamento': statusPagamento,
        'valor_recebido': recebido,
        'vencimento_pagamento': vencimento,
        'pagamento_atualizado_em': DateTime.now().toIso8601String(),
        'lancado_financeiro': recebido > 0.000001 ? 1 : 0,
        'forma_pagamento': formaPagamento,
      },
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  Future<void> _atualizarStatusVencidos(Database database) async {
    final hoje = _dataDia(DateTime.now());

    await database.execute(
      '''
      UPDATE ordens_servico
      SET status_pagamento = CASE
        WHEN status != 'Finalizada' THEN status_pagamento
        WHEN MAX(
          COALESCE(valor_total, 0)
          - COALESCE(desconto, 0)
          - COALESCE(desconto_negociacao, 0)
          + COALESCE(acrescimo_negociacao, 0)
          + COALESCE(juros_parcelamento, 0),
          0
        ) <= COALESCE(valor_recebido, 0) + 0.000001
          THEN 'Pago'
        WHEN vencimento_pagamento IS NOT NULL
          AND TRIM(vencimento_pagamento) != ''
          AND substr(vencimento_pagamento, 1, 10) < ?
          THEN 'Vencido'
        WHEN COALESCE(valor_recebido, 0) > 0
          THEN 'Parcialmente pago'
        ELSE 'Pendente'
      END
      WHERE status = 'Finalizada'
      ''',
      [hoje],
    );
  }

  double _valorBase(Map<String, Object?> ordem) {
    final total = _double(ordem['valor_total']);
    final desconto = _double(ordem['desconto']);
    return (total - desconto).clamp(0, double.infinity).toDouble();
  }

  double _valorFinal(Map<String, Object?> ordem) {
    final valorBase = _valorBase(ordem);
    final descontoNegociacao = _double(ordem['desconto_negociacao']);
    final acrescimoNegociacao = _double(ordem['acrescimo_negociacao']);
    final jurosParcelamento = _double(ordem['juros_parcelamento']);

    return (valorBase -
            descontoNegociacao +
            acrescimoNegociacao +
            jurosParcelamento)
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<_TaxaPagamentoResolvida> _resolverTaxaPagamento(
    DatabaseExecutor executor, {
    required String formaPagamento,
    required double valor,
    required int parcelas,
    required int? contaFinanceiraId,
    required double taxaOperacaoInformada,
    required double? taxaPercentualInformada,
    required int? regraTaxaIdInformada,
    required bool aplicarAutomatica,
  }) async {
    if (!_ehFormaCartao(formaPagamento)) {
      return _TaxaPagamentoResolvida(valorCobrado: valor);
    }

    if (taxaOperacaoInformada > 0.000001 ||
        taxaPercentualInformada != null ||
        !aplicarAutomatica) {
      return _TaxaPagamentoResolvida(
        valorCobrado: valor,
        taxaOperacao: taxaOperacaoInformada,
        taxaPercentual: taxaPercentualInformada,
        regraTaxaId: regraTaxaIdInformada,
        contaFinanceiraId: contaFinanceiraId,
      );
    }

    final regra = await _buscarRegraTaxa(
      executor,
      formaPagamento: formaPagamento,
      parcelas: parcelas.clamp(1, 48).toInt(),
      contaFinanceiraId: contaFinanceiraId,
    );
    if (regra == null) {
      return _TaxaPagamentoResolvida(valorCobrado: valor);
    }

    final percentual = _double(regra['taxa_percentual']);
    final fixa = _double(regra['taxa_fixa']);
    final repassarCliente = _int(regra['repassar_cliente']) == 1;
    final valorCobrado = repassarCliente
        ? _calcularValorCobradoComRepasse(
            valorBase: valor,
            taxaPercentual: percentual,
            taxaFixa: fixa,
          )
        : valor;
    final taxa = _arredondarCentavos(
      valorCobrado * percentual / 100 + fixa,
    ).clamp(0, valorCobrado).toDouble();
    final acrescimoCliente = (valorCobrado - valor)
        .clamp(0, double.infinity)
        .toDouble();

    return _TaxaPagamentoResolvida(
      valorCobrado: valorCobrado,
      taxaOperacao: taxa,
      taxaPercentual: percentual > 0 ? percentual : null,
      regraTaxaId: _int(regra['id']),
      contaFinanceiraId: _int(regra['conta_id']),
      acrescimoCliente: acrescimoCliente,
      nomeRegra: (regra['nome'] ?? '').toString().trim(),
    );
  }

  Future<int> _registrarRepasseTaxaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required double valor,
    required int? regraTaxaId,
    required String nomeRegra,
  }) async {
    if (valor <= 0.000001) {
      throw ArgumentError('O acréscimo de repasse deve ser maior que zero.');
    }

    final agora = DateTime.now().toIso8601String();
    final nome = nomeRegra.trim().isEmpty
        ? 'Regra automática'
        : nomeRegra.trim();
    final ajusteId = await transaction.insert(
      'ordem_servico_ajustes_financeiros',
      {
        'ordem_servico_id': ordemServicoId,
        'tipo': 'Acréscimo',
        'valor': valor,
        'motivo': 'Repasse automático da taxa da maquininha: $nome.',
        'status': 'Ativo',
        'origem': 'Taxa de maquininha',
        'regra_taxa_id': regraTaxaId,
        'pagamento_id': null,
        'criado_em': agora,
        'cancelado_em': null,
        'motivo_cancelamento': '',
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await _sincronizarResumoAjustes(transaction, ordemServicoId);
    return ajusteId;
  }

  static double _arredondarCentavos(double valor) {
    return (valor * 100).roundToDouble() / 100;
  }

  static double _calcularValorCobradoComRepasse({
    required double valorBase,
    required double taxaPercentual,
    required double taxaFixa,
  }) {
    if (valorBase <= 0) {
      return 0;
    }

    final aliquota = taxaPercentual / 100;
    if (aliquota >= 1) {
      throw StateError(
        'Não é possível repassar automaticamente uma taxa de 100% ou mais.',
      );
    }

    final bruto = (valorBase + taxaFixa) / (1 - aliquota);
    return (bruto * 100).ceilToDouble() / 100;
  }

  Future<Map<String, Object?>?> _buscarRegraTaxa(
    DatabaseExecutor executor, {
    required String formaPagamento,
    required int parcelas,
    required int? contaFinanceiraId,
  }) async {
    final resultado = await executor.rawQuery(
      '''
      SELECT *
      FROM financeiro_regras_taxa
      WHERE ativo = 1
        AND forma_pagamento = ?
        AND parcelas = ?
        AND (
          ? IS NULL
          OR conta_id = ?
          OR conta_id IS NULL
        )
      ORDER BY
        CASE
          WHEN ? IS NOT NULL AND conta_id = ? THEN 0
          WHEN conta_id IS NOT NULL THEN 1
          ELSE 2
        END,
        prioridade DESC,
        id DESC
      LIMIT 1
      ''',
      [
        formaPagamento.trim(),
        parcelas,
        contaFinanceiraId,
        contaFinanceiraId,
        contaFinanceiraId,
        contaFinanceiraId,
      ],
    );
    if (resultado.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(resultado.first);
  }

  static bool _ehFormaCartao(String formaPagamento) {
    final forma = formaPagamento.trim();
    return forma == 'Cartão de crédito' || forma == 'Cartão de débito';
  }

  static void _validarTaxa({
    required double valor,
    required double taxaOperacao,
    required double? taxaPercentual,
  }) {
    if (taxaOperacao < 0) {
      throw ArgumentError('A taxa da operação não pode ser negativa.');
    }

    if (taxaOperacao - valor > 0.000001) {
      throw ArgumentError(
        'A taxa da operação não pode ser maior que o valor recebido.',
      );
    }

    if (taxaPercentual != null &&
        (taxaPercentual < 0 || taxaPercentual > 100)) {
      throw ArgumentError('A taxa percentual deve ficar entre 0% e 100%.');
    }
  }

  static int? _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static bool _estaVencido(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return false;
    }

    final data = DateTime.tryParse(valor);
    if (data == null) {
      return false;
    }

    final hoje = DateTime.now();

    return DateTime(
      data.year,
      data.month,
      data.day,
    ).isBefore(DateTime(hoje.year, hoje.month, hoje.day));
  }

  static DateTime _somarMeses(DateTime data, int meses) {
    final primeiro = DateTime(data.year, data.month + meses, 1);
    final ultimoDia = DateTime(primeiro.year, primeiro.month + 1, 0).day;
    final dia = data.day > ultimoDia ? ultimoDia : data.day;
    return DateTime(primeiro.year, primeiro.month, dia);
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }
}

class _TaxaPagamentoResolvida {
  const _TaxaPagamentoResolvida({
    required this.valorCobrado,
    this.taxaOperacao = 0,
    this.taxaPercentual,
    this.regraTaxaId,
    this.contaFinanceiraId,
    this.acrescimoCliente = 0,
    this.nomeRegra = '',
  });

  final double valorCobrado;
  final double taxaOperacao;
  final double? taxaPercentual;
  final int? regraTaxaId;
  final int? contaFinanceiraId;
  final double acrescimoCliente;
  final String nomeRegra;
}
