class MovimentoFinanceiro {
  const MovimentoFinanceiro({
    this.id,
    required this.tipo,
    required this.descricao,
    required this.valor,
    this.formaPagamento = '',
    required this.data,
    this.clienteId,
    this.agendamentoId,
    this.ordemServicoId,
    this.pagamentoId,
    this.planoContaId,
    this.contaId,
    this.fornecedorId,
    this.transferenciaId,
    this.notaFiscalId,
    this.parcelaNumero,
    this.totalParcelas = 1,
    this.natureza = 'Não classificado',
    this.origem = 'Manual',
    this.status = 'Realizado',
    this.dataCompetencia,
    this.dataVencimento,
    this.dataPagamento,
    this.numeroDocumento = '',
    this.observacoes = '',
    this.impactaDre = true,
  });

  final int? id;
  final String tipo;
  final String descricao;
  final double valor;
  final String formaPagamento;
  final String data;
  final int? clienteId;
  final int? agendamentoId;
  final int? ordemServicoId;
  final int? pagamentoId;
  final int? planoContaId;
  final int? contaId;
  final int? fornecedorId;
  final int? transferenciaId;
  final int? notaFiscalId;
  final int? parcelaNumero;
  final int totalParcelas;
  final String natureza;
  final String origem;
  final String status;
  final String? dataCompetencia;
  final String? dataVencimento;
  final String? dataPagamento;
  final String numeroDocumento;
  final String observacoes;
  final bool impactaDre;

  bool get estaRealizado => status == 'Realizado';
  bool get estaPrevisto => status == 'Previsto';
  bool get estaCancelado => status == 'Cancelado';
  bool get automatico =>
      pagamentoId != null || ordemServicoId != null || origem != 'Manual';

  bool get estaAtrasado {
    if (!estaPrevisto || dataVencimento == null) {
      return false;
    }

    final vencimento = DateTime.tryParse(dataVencimento!);
    if (vencimento == null) {
      return false;
    }

    final hoje = DateTime.now();
    return DateTime(
      vencimento.year,
      vencimento.month,
      vencimento.day,
    ).isBefore(DateTime(hoje.year, hoje.month, hoje.day));
  }

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final mapa = <String, dynamic>{
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data': data,
      'cliente_id': clienteId,
      'agendamento_id': agendamentoId,
      'ordem_servico_id': ordemServicoId,
      'pagamento_id': pagamentoId,
      'plano_conta_id': planoContaId,
      'conta_id': contaId,
      'fornecedor_id': fornecedorId,
      'transferencia_id': transferenciaId,
      'nota_fiscal_id': notaFiscalId,
      'parcela_numero': parcelaNumero,
      'total_parcelas': totalParcelas,
      'natureza': natureza,
      'origem': origem,
      'status': status,
      'data_competencia': dataCompetencia,
      'data_vencimento': dataVencimento,
      'data_pagamento': dataPagamento,
      'numero_documento': numeroDocumento,
      'observacoes': observacoes,
      'impacta_dre': impactaDre ? 1 : 0,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory MovimentoFinanceiro.fromMap(Map<String, dynamic> map) {
    return MovimentoFinanceiro(
      id: _int(map['id']),
      tipo: _texto(map['tipo']),
      descricao: _texto(map['descricao']),
      valor: _double(map['valor']),
      formaPagamento: _texto(map['forma_pagamento']),
      data: _texto(map['data']),
      clienteId: _int(map['cliente_id']),
      agendamentoId: _int(map['agendamento_id']),
      ordemServicoId: _int(map['ordem_servico_id']),
      pagamentoId: _int(map['pagamento_id']),
      planoContaId: _int(map['plano_conta_id']),
      contaId: _int(map['conta_id']),
      fornecedorId: _int(map['fornecedor_id']),
      transferenciaId: _int(map['transferencia_id']),
      notaFiscalId: _int(map['nota_fiscal_id']),
      parcelaNumero: _int(map['parcela_numero']),
      totalParcelas: _int(map['total_parcelas']) ?? 1,
      natureza: _texto(map['natureza'], padrao: 'Não classificado'),
      origem: _texto(map['origem'], padrao: 'Manual'),
      status: _texto(map['status'], padrao: 'Realizado'),
      dataCompetencia: _textoNulo(map['data_competencia']),
      dataVencimento: _textoNulo(map['data_vencimento']),
      dataPagamento: _textoNulo(map['data_pagamento']),
      numeroDocumento: _texto(map['numero_documento']),
      observacoes: _texto(map['observacoes']),
      impactaDre: _bool(map['impacta_dre'], padrao: true),
    );
  }

  MovimentoFinanceiro copyWith({
    int? id,
    String? tipo,
    String? descricao,
    double? valor,
    String? formaPagamento,
    String? data,
    int? clienteId,
    bool removerClienteId = false,
    int? agendamentoId,
    bool removerAgendamentoId = false,
    int? ordemServicoId,
    bool removerOrdemServicoId = false,
    int? pagamentoId,
    bool removerPagamentoId = false,
    int? planoContaId,
    bool removerPlanoContaId = false,
    int? contaId,
    bool removerContaId = false,
    int? fornecedorId,
    bool removerFornecedorId = false,
    int? transferenciaId,
    bool removerTransferenciaId = false,
    int? notaFiscalId,
    bool removerNotaFiscalId = false,
    int? parcelaNumero,
    bool removerParcelaNumero = false,
    int? totalParcelas,
    String? natureza,
    String? origem,
    String? status,
    String? dataCompetencia,
    bool removerDataCompetencia = false,
    String? dataVencimento,
    bool removerDataVencimento = false,
    String? dataPagamento,
    bool removerDataPagamento = false,
    String? numeroDocumento,
    String? observacoes,
    bool? impactaDre,
  }) {
    return MovimentoFinanceiro(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      data: data ?? this.data,
      clienteId: removerClienteId ? null : clienteId ?? this.clienteId,
      agendamentoId: removerAgendamentoId
          ? null
          : agendamentoId ?? this.agendamentoId,
      ordemServicoId: removerOrdemServicoId
          ? null
          : ordemServicoId ?? this.ordemServicoId,
      pagamentoId: removerPagamentoId ? null : pagamentoId ?? this.pagamentoId,
      planoContaId: removerPlanoContaId
          ? null
          : planoContaId ?? this.planoContaId,
      contaId: removerContaId ? null : contaId ?? this.contaId,
      fornecedorId: removerFornecedorId
          ? null
          : fornecedorId ?? this.fornecedorId,
      transferenciaId: removerTransferenciaId
          ? null
          : transferenciaId ?? this.transferenciaId,
      notaFiscalId: removerNotaFiscalId
          ? null
          : notaFiscalId ?? this.notaFiscalId,
      parcelaNumero: removerParcelaNumero
          ? null
          : parcelaNumero ?? this.parcelaNumero,
      totalParcelas: totalParcelas ?? this.totalParcelas,
      natureza: natureza ?? this.natureza,
      origem: origem ?? this.origem,
      status: status ?? this.status,
      dataCompetencia: removerDataCompetencia
          ? null
          : dataCompetencia ?? this.dataCompetencia,
      dataVencimento: removerDataVencimento
          ? null
          : dataVencimento ?? this.dataVencimento,
      dataPagamento: removerDataPagamento
          ? null
          : dataPagamento ?? this.dataPagamento,
      numeroDocumento: numeroDocumento ?? this.numeroDocumento,
      observacoes: observacoes ?? this.observacoes,
      impactaDre: impactaDre ?? this.impactaDre,
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String _texto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? padrao : texto;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static bool _bool(dynamic valor, {bool padrao = false}) {
    if (valor == null) return padrao;
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final texto = valor.toString().trim().toLowerCase();
    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
