class ConfiguracaoEstoque {
  final int? id;
  final bool controlarEstoque;
  final bool controlarProdutosOrdemServico;
  final bool baixaAutomatica;
  final bool exigirQuantidade;
  final bool alertarEstoqueBaixo;
  final double estoqueMinimoPadrao;
  final String atualizadoEm;

  const ConfiguracaoEstoque({
    this.id,
    required this.controlarEstoque,
    required this.controlarProdutosOrdemServico,
    required this.baixaAutomatica,
    required this.exigirQuantidade,
    required this.alertarEstoqueBaixo,
    required this.estoqueMinimoPadrao,
    required this.atualizadoEm,
  });

  factory ConfiguracaoEstoque.padrao() {
    return ConfiguracaoEstoque(
      controlarEstoque: true,
      controlarProdutosOrdemServico: false,
      baixaAutomatica: false,
      exigirQuantidade: false,
      alertarEstoqueBaixo: true,
      estoqueMinimoPadrao: 1,
      atualizadoEm: DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'controlar_estoque': controlarEstoque ? 1 : 0,
      'controlar_produtos_ordem_servico': controlarProdutosOrdemServico ? 1 : 0,
      'baixa_automatica': baixaAutomatica ? 1 : 0,
      'exigir_quantidade': exigirQuantidade ? 1 : 0,
      'alertar_estoque_baixo': alertarEstoqueBaixo ? 1 : 0,
      'estoque_minimo_padrao': estoqueMinimoPadrao,
      'atualizado_em': atualizadoEm,
    };
  }

  factory ConfiguracaoEstoque.fromMap(Map<String, dynamic> map) {
    return ConfiguracaoEstoque(
      id: map['id'] as int?,
      controlarEstoque: (map['controlar_estoque'] as int? ?? 1) == 1,
      controlarProdutosOrdemServico:
          (map['controlar_produtos_ordem_servico'] as int? ?? 0) == 1,
      baixaAutomatica: (map['baixa_automatica'] as int? ?? 0) == 1,
      exigirQuantidade: (map['exigir_quantidade'] as int? ?? 0) == 1,
      alertarEstoqueBaixo: (map['alertar_estoque_baixo'] as int? ?? 1) == 1,
      estoqueMinimoPadrao:
          (map['estoque_minimo_padrao'] as num?)?.toDouble() ?? 1,
      atualizadoEm: map['atualizado_em']?.toString() ?? '',
    );
  }

  ConfiguracaoEstoque copyWith({
    int? id,
    bool? controlarEstoque,
    bool? controlarProdutosOrdemServico,
    bool? baixaAutomatica,
    bool? exigirQuantidade,
    bool? alertarEstoqueBaixo,
    double? estoqueMinimoPadrao,
    String? atualizadoEm,
  }) {
    return ConfiguracaoEstoque(
      id: id ?? this.id,
      controlarEstoque: controlarEstoque ?? this.controlarEstoque,
      controlarProdutosOrdemServico:
          controlarProdutosOrdemServico ?? this.controlarProdutosOrdemServico,
      baixaAutomatica: baixaAutomatica ?? this.baixaAutomatica,
      exigirQuantidade: exigirQuantidade ?? this.exigirQuantidade,
      alertarEstoqueBaixo: alertarEstoqueBaixo ?? this.alertarEstoqueBaixo,
      estoqueMinimoPadrao: estoqueMinimoPadrao ?? this.estoqueMinimoPadrao,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }
}
