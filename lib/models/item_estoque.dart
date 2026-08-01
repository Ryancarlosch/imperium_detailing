class ItemEstoque {
  final int? id;
  final String nome;
  final String categoria;
  final double quantidade;
  final double quantidadeMinima;
  final String unidade;
  final double custoUnitario;
  final String fornecedor;
  final String observacoes;
  final String atualizadoEm;

  const ItemEstoque({
    this.id,
    required this.nome,
    required this.categoria,
    required this.quantidade,
    required this.quantidadeMinima,
    required this.unidade,
    required this.custoUnitario,
    required this.fornecedor,
    required this.observacoes,
    required this.atualizadoEm,
  });

  bool get estoqueZerado => quantidade <= 0;

  bool get estoqueBaixo {
    if (estoqueZerado) {
      return true;
    }

    if (quantidadeMinima <= 0) {
      return false;
    }

    return quantidade <= quantidadeMinima;
  }

  double get valorTotal => quantidade * custoUnitario;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'categoria': categoria,
      'quantidade': quantidade,
      'quantidade_minima': quantidadeMinima,
      'unidade': unidade,
      'custo_unitario': custoUnitario,
      'fornecedor': fornecedor,
      'observacoes': observacoes,
      'atualizado_em': atualizadoEm,
    };
  }

  factory ItemEstoque.fromMap(Map<String, dynamic> map) {
    return ItemEstoque(
      id: map['id'] as int?,
      nome: map['nome'] as String? ?? '',
      categoria: map['categoria'] as String? ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0,
      quantidadeMinima: (map['quantidade_minima'] as num?)?.toDouble() ?? 0,
      unidade: map['unidade'] as String? ?? 'un',
      custoUnitario: (map['custo_unitario'] as num?)?.toDouble() ?? 0,
      fornecedor: map['fornecedor'] as String? ?? '',
      observacoes: map['observacoes'] as String? ?? '',
      atualizadoEm: map['atualizado_em'] as String? ?? '',
    );
  }
}
