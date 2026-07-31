class MovimentoFinanceiro {
  final int? id;
  final String tipo;
  final String descricao;
  final double valor;
  final String formaPagamento;
  final String data;
  final int? clienteId;
  final int? agendamentoId;

  const MovimentoFinanceiro({
    this.id,
    required this.tipo,
    required this.descricao,
    required this.valor,
    required this.formaPagamento,
    required this.data,
    this.clienteId,
    this.agendamentoId,
  });

  Map<String, dynamic> toMap({
    bool incluirId = true,
  }) {
    final mapa = <String, dynamic>{
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data': data,
      'cliente_id': clienteId,
      'agendamento_id': agendamentoId,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory MovimentoFinanceiro.fromMap(
      Map<String, dynamic> map,
      ) {
    return MovimentoFinanceiro(
      id: _converterInt(map['id']),
      tipo: (map['tipo'] ?? '').toString(),
      descricao: (map['descricao'] ?? '').toString(),
      valor: _converterDouble(map['valor']),
      formaPagamento:
      (map['forma_pagamento'] ?? '').toString(),
      data: (map['data'] ?? '').toString(),
      clienteId: _converterInt(
        map['cliente_id'],
      ),
      agendamentoId: _converterInt(
        map['agendamento_id'],
      ),
    );
  }

  static int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    return int.tryParse(
      valor.toString(),
    );
  }

  static double _converterDouble(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
      valor.toString().replaceAll(',', '.'),
    ) ??
        0;
  }

  MovimentoFinanceiro copyWith({
    int? id,
    String? tipo,
    String? descricao,
    double? valor,
    String? formaPagamento,
    String? data,
    int? clienteId,
    int? agendamentoId,
  }) {
    return MovimentoFinanceiro(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      formaPagamento:
      formaPagamento ?? this.formaPagamento,
      data: data ?? this.data,
      clienteId:
      clienteId ?? this.clienteId,
      agendamentoId:
      agendamentoId ?? this.agendamentoId,
    );
  }
}