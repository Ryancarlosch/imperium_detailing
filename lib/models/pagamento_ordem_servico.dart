class PagamentoOrdemServico {
  const PagamentoOrdemServico({
    this.id,
    required this.ordemServicoId,
    this.status = 'Pago',
    required this.valor,
    this.formaPagamento = '',
    this.dataPagamento,
    this.parcelaNumero,
    this.totalParcelas,
    this.vencimento,
    this.comprovanteCaminho,
    this.observacoes = '',
    this.taxaPercentual,
    this.taxaOperacao = 0,
    this.valorLiquido = 0,
    this.regraTaxaId,
    this.parcelasTaxa = 1,
    this.estornadoEm,
    this.motivoEstorno = '',
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final int ordemServicoId;
  final String status;
  final double valor;
  final String formaPagamento;
  final String? dataPagamento;
  final int? parcelaNumero;
  final int? totalParcelas;
  final String? vencimento;
  final String? comprovanteCaminho;
  final String observacoes;
  final double? taxaPercentual;
  final double taxaOperacao;
  final double valorLiquido;
  final int? regraTaxaId;
  final int parcelasTaxa;
  final String? estornadoEm;
  final String motivoEstorno;
  final String criadoEm;
  final String atualizadoEm;

  bool get estaPago => status == 'Pago';
  bool get estaPendente => status == 'Pendente';
  bool get estaEstornado => status == 'Estornado';
  bool get estaCancelado => status == 'Cancelado';

  bool get estaVencido {
    if (!estaPendente || vencimento == null) {
      return false;
    }

    final data = DateTime.tryParse(vencimento!);
    if (data == null) {
      return false;
    }

    final hoje = DateTime.now();
    final limite = DateTime(hoje.year, hoje.month, hoje.day);
    final vencimentoDia = DateTime(data.year, data.month, data.day);
    return vencimentoDia.isBefore(limite);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ordem_servico_id': ordemServicoId,
      'status': status,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data_pagamento': dataPagamento,
      'parcela_numero': parcelaNumero,
      'total_parcelas': totalParcelas,
      'vencimento': vencimento,
      'comprovante_caminho': comprovanteCaminho,
      'observacoes': observacoes,
      'taxa_percentual': taxaPercentual,
      'taxa_operacao': taxaOperacao,
      'valor_liquido': valorLiquido,
      'regra_taxa_id': regraTaxaId,
      'parcelas_taxa': parcelasTaxa,
      'estornado_em': estornadoEm,
      'motivo_estorno': motivoEstorno,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };
  }

  factory PagamentoOrdemServico.fromMap(Map<String, dynamic> map) {
    final valor = _double(map['valor']);
    final taxaOperacao = _double(map['taxa_operacao']);
    final valorLiquido = map['valor_liquido'] == null
        ? (valor - taxaOperacao).clamp(0, double.infinity).toDouble()
        : _double(map['valor_liquido']);

    return PagamentoOrdemServico(
      id: _int(map['id']),
      ordemServicoId: _int(map['ordem_servico_id']) ?? 0,
      status: _texto(map['status'], padrao: 'Pago'),
      valor: valor,
      formaPagamento: _texto(map['forma_pagamento']),
      dataPagamento: _textoNulo(map['data_pagamento']),
      parcelaNumero: _int(map['parcela_numero']),
      totalParcelas: _int(map['total_parcelas']),
      vencimento: _textoNulo(map['vencimento']),
      comprovanteCaminho: _textoNulo(map['comprovante_caminho']),
      observacoes: _texto(map['observacoes']),
      taxaPercentual: map['taxa_percentual'] == null
          ? null
          : _double(map['taxa_percentual']),
      taxaOperacao: taxaOperacao,
      valorLiquido: valorLiquido,
      regraTaxaId: _int(map['regra_taxa_id']),
      parcelasTaxa: _int(map['parcelas_taxa']) ?? 1,
      estornadoEm: _textoNulo(map['estornado_em']),
      motivoEstorno: _texto(map['motivo_estorno']),
      criadoEm: _texto(map['criado_em']),
      atualizadoEm: _texto(map['atualizado_em']),
    );
  }

  PagamentoOrdemServico copyWith({
    int? id,
    int? ordemServicoId,
    String? status,
    double? valor,
    String? formaPagamento,
    String? dataPagamento,
    bool removerDataPagamento = false,
    int? parcelaNumero,
    bool removerParcelaNumero = false,
    int? totalParcelas,
    bool removerTotalParcelas = false,
    String? vencimento,
    bool removerVencimento = false,
    String? comprovanteCaminho,
    bool removerComprovante = false,
    String? observacoes,
    double? taxaPercentual,
    bool removerTaxaPercentual = false,
    double? taxaOperacao,
    double? valorLiquido,
    int? regraTaxaId,
    bool removerRegraTaxa = false,
    int? parcelasTaxa,
    String? estornadoEm,
    bool removerEstorno = false,
    String? motivoEstorno,
    String? criadoEm,
    String? atualizadoEm,
  }) {
    return PagamentoOrdemServico(
      id: id ?? this.id,
      ordemServicoId: ordemServicoId ?? this.ordemServicoId,
      status: status ?? this.status,
      valor: valor ?? this.valor,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      dataPagamento: removerDataPagamento
          ? null
          : dataPagamento ?? this.dataPagamento,
      parcelaNumero: removerParcelaNumero
          ? null
          : parcelaNumero ?? this.parcelaNumero,
      totalParcelas: removerTotalParcelas
          ? null
          : totalParcelas ?? this.totalParcelas,
      vencimento: removerVencimento ? null : vencimento ?? this.vencimento,
      comprovanteCaminho: removerComprovante
          ? null
          : comprovanteCaminho ?? this.comprovanteCaminho,
      observacoes: observacoes ?? this.observacoes,
      taxaPercentual: removerTaxaPercentual
          ? null
          : taxaPercentual ?? this.taxaPercentual,
      taxaOperacao: taxaOperacao ?? this.taxaOperacao,
      valorLiquido: valorLiquido ?? this.valorLiquido,
      regraTaxaId: removerRegraTaxa ? null : regraTaxaId ?? this.regraTaxaId,
      parcelasTaxa: parcelasTaxa ?? this.parcelasTaxa,
      estornadoEm: removerEstorno ? null : estornadoEm ?? this.estornadoEm,
      motivoEstorno: motivoEstorno ?? this.motivoEstorno,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
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
}
