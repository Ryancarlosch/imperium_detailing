class MovimentacaoEstoque {
  final int? id;
  final int itemId;
  final String tipo;
  final double quantidade;
  final double? quantidadeAnterior;
  final double? quantidadePosterior;
  final double? custoUnitario;
  final String observacao;
  final String motivo;
  final String origem;
  final int? ordemServicoId;
  final int? loteId;
  final String data;

  const MovimentacaoEstoque({
    this.id,
    required this.itemId,
    required this.tipo,
    required this.quantidade,
    this.quantidadeAnterior,
    this.quantidadePosterior,
    this.custoUnitario,
    required this.observacao,
    this.motivo = '',
    this.origem = 'Manual',
    this.ordemServicoId,
    this.loteId,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_estoque_id': itemId,
      'tipo': tipo,
      'quantidade': quantidade,
      if (quantidadeAnterior != null) 'quantidade_anterior': quantidadeAnterior,
      if (quantidadePosterior != null)
        'quantidade_posterior': quantidadePosterior,
      if (custoUnitario != null) 'custo_unitario': custoUnitario,
      'observacoes': observacao,
      'motivo': motivo,
      'origem': origem,
      'ordem_servico_id': ordemServicoId,
      'lote_id': loteId,
      'data': data,
    };
  }

  factory MovimentacaoEstoque.fromMap(Map<String, dynamic> map) {
    return MovimentacaoEstoque(
      id: map['id'] as int?,
      itemId: (map['item_estoque_id'] as num).toInt(),
      tipo: map['tipo']?.toString() ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0,
      quantidadeAnterior: (map['quantidade_anterior'] as num?)?.toDouble(),
      quantidadePosterior: (map['quantidade_posterior'] as num?)?.toDouble(),
      custoUnitario: (map['custo_unitario'] as num?)?.toDouble(),
      observacao: map['observacoes']?.toString() ?? '',
      motivo: map['motivo']?.toString() ?? '',
      origem: map['origem']?.toString() ?? 'Manual',
      ordemServicoId: (map['ordem_servico_id'] as num?)?.toInt(),
      loteId: (map['lote_id'] as num?)?.toInt(),
      data: map['data']?.toString() ?? '',
    );
  }

  bool get entrada => tipo == 'ENTRADA';

  bool get saida => tipo == 'SAIDA';

  bool get ajuste => tipo == 'AJUSTE';
}
