class RegraTaxaCartao {
  const RegraTaxaCartao({
    this.id,
    required this.nome,
    required this.formaPagamento,
    this.parcelas = 1,
    this.contaId,
    this.taxaPercentual = 0,
    this.taxaFixa = 0,
    this.prazoRecebimentoDias = 0,
    this.prioridade = 0,
    this.repassarCliente = false,
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final String nome;
  final String formaPagamento;
  final int parcelas;
  final int? contaId;
  final double taxaPercentual;
  final double taxaFixa;
  final int prazoRecebimentoDias;
  final int prioridade;
  final bool repassarCliente;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  double calcularTaxa(double valorCobrado) {
    if (valorCobrado <= 0) {
      return 0;
    }
    final percentual = valorCobrado * taxaPercentual / 100;
    final total = _arredondarCentavos(percentual + taxaFixa);
    return total.clamp(0, valorCobrado).toDouble();
  }

  double calcularValorCobrado(double valorBase) {
    if (!repassarCliente || valorBase <= 0) {
      return valorBase.clamp(0, double.infinity).toDouble();
    }

    final aliquota = taxaPercentual / 100;
    if (aliquota >= 1) {
      throw StateError(
        'Não é possível repassar uma taxa percentual de 100% ou mais.',
      );
    }

    final bruto = (valorBase + taxaFixa) / (1 - aliquota);
    return (bruto * 100).ceilToDouble() / 100;
  }

  double calcularAcrescimoCliente(double valorBase) {
    final cobrado = calcularValorCobrado(valorBase);
    return (cobrado - valorBase).clamp(0, double.infinity).toDouble();
  }

  static double _arredondarCentavos(double valor) {
    return (valor * 100).roundToDouble() / 100;
  }

  Map<String, dynamic> toMap({bool incluirId = true}) {
    return {
      if (incluirId && id != null) 'id': id,
      'nome': nome,
      'forma_pagamento': formaPagamento,
      'parcelas': parcelas,
      'conta_id': contaId,
      'taxa_percentual': taxaPercentual,
      'taxa_fixa': taxaFixa,
      'prazo_recebimento_dias': prazoRecebimentoDias,
      'prioridade': prioridade,
      'repassar_cliente': repassarCliente ? 1 : 0,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };
  }

  factory RegraTaxaCartao.fromMap(Map<String, dynamic> map) {
    return RegraTaxaCartao(
      id: _int(map['id']),
      nome: (map['nome'] ?? '').toString(),
      formaPagamento: (map['forma_pagamento'] ?? '').toString(),
      parcelas: _int(map['parcelas']) ?? 1,
      contaId: _int(map['conta_id']),
      taxaPercentual: _double(map['taxa_percentual']),
      taxaFixa: _double(map['taxa_fixa']),
      prazoRecebimentoDias: _int(map['prazo_recebimento_dias']) ?? 0,
      prioridade: _int(map['prioridade']) ?? 0,
      repassarCliente: _int(map['repassar_cliente']) == 1,
      observacoes: (map['observacoes'] ?? '').toString(),
      ativo: _int(map['ativo']) != 0,
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
