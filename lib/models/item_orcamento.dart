class ItemOrcamento {
  final int? id;
  final int? orcamentoId;
  final String servico;
  final String descricao;
  final double quantidade;
  final double valorUnitario;
  final int ordem;

  const ItemOrcamento({
    this.id,
    this.orcamentoId,
    required this.servico,
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
    required this.ordem,
  });

  double get subtotal {
    return quantidade * valorUnitario;
  }

  ItemOrcamento copyWith({
    int? id,
    int? orcamentoId,
    String? servico,
    String? descricao,
    double? quantidade,
    double? valorUnitario,
    int? ordem,
  }) {
    return ItemOrcamento(
      id: id ?? this.id,
      orcamentoId: orcamentoId ?? this.orcamentoId,
      servico: servico ?? this.servico,
      descricao: descricao ?? this.descricao,
      quantidade: quantidade ?? this.quantidade,
      valorUnitario: valorUnitario ?? this.valorUnitario,
      ordem: ordem ?? this.ordem,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orcamento_id': orcamentoId,
      'servico': servico,
      'descricao': descricao,
      'quantidade': quantidade,
      'valor_unitario': valorUnitario,
      'ordem': ordem,
    };
  }

  factory ItemOrcamento.fromMap(Map<String, dynamic> map) {
    return ItemOrcamento(
      id: _converterInt(map['id']),
      orcamentoId: _converterInt(map['orcamento_id']),
      servico: map['servico']?.toString() ?? '',
      descricao: map['descricao']?.toString() ?? '',
      quantidade: _converterDouble(map['quantidade'], 1),
      valorUnitario: _converterDouble(map['valor_unitario'], 0),
      ordem: _converterInt(map['ordem']) ?? 0,
    );
  }

  static int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }

  static double _converterDouble(dynamic valor, double padrao) {
    if (valor == null) {
      return padrao;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.')) ?? padrao;
  }
}
