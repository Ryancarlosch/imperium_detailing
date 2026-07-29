class MovimentacaoEstoque {
  final int? id;
  final int itemId;
  final String tipo;
  final double quantidade;
  final String observacao;
  final int? ordemServicoId;
  final String data;

  const MovimentacaoEstoque({
    this.id,
    required this.itemId,
    required this.tipo,
    required this.quantidade,
    required this.observacao,
    this.ordemServicoId,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'tipo': tipo,
      'quantidade': quantidade,
      'observacao': observacao,
      'ordem_servico_id': ordemServicoId,
      'data': data,
    };
  }

  factory MovimentacaoEstoque.fromMap(
      Map<String, dynamic> map,
      ) {
    return MovimentacaoEstoque(
      id: map['id'] as int?,
      itemId: map['item_id'] as int,
      tipo: map['tipo']?.toString() ?? '',
      quantidade:
      (map['quantidade'] as num?)?.toDouble() ??
          0,
      observacao:
      map['observacao']?.toString() ?? '',
      ordemServicoId:
      map['ordem_servico_id'] as int?,
      data: map['data']?.toString() ?? '',
    );
  }

  bool get entrada => tipo == 'ENTRADA';

  bool get saida => tipo == 'SAIDA';

  bool get ajuste => tipo == 'AJUSTE';
}