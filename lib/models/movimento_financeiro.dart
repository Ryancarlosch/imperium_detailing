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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'descricao': descricao,
      'valor': valor,
      'forma_pagamento': formaPagamento,
      'data': data,
      'cliente_id': clienteId,
      'agendamento_id': agendamentoId,
    };
  }

  factory MovimentoFinanceiro.fromMap(
      Map<String, dynamic> map,
      ) {
    return MovimentoFinanceiro(
      id: map['id'] as int?,
      tipo: map['tipo'] ?? '',
      descricao: map['descricao'] ?? '',
      valor: (map['valor'] as num).toDouble(),
      formaPagamento:
      map['forma_pagamento'] ?? '',
      data: map['data'] ?? '',
      clienteId: map['cliente_id'] as int?,
      agendamentoId:
      map['agendamento_id'] as int?,
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
    int? agendamentoId,
  }) {
    return MovimentoFinanceiro(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      formaPagamento:
      formaPagamento ??
          this.formaPagamento,
      data: data ?? this.data,
      clienteId:
      clienteId ?? this.clienteId,
      agendamentoId:
      agendamentoId ??
          this.agendamentoId,
    );
  }
}