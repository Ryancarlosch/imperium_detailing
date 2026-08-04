class ProdutoOrdemServico {
  final int? id;
  final int ordemServicoId;
  final int? produtoId;
  final String produtoNome;
  final double quantidade;
  final String unidade;
  final double custoUnitario;
  final double custoUnitarioNoMomento;
  final double custoTotalNoMomento;
  final String composicaoLotesJson;
  final bool baixadoEstoque;

  const ProdutoOrdemServico({
    this.id,
    required this.ordemServicoId,
    this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    required this.unidade,
    required this.custoUnitario,
    double? custoUnitarioNoMomento,
    double? custoTotalNoMomento,
    this.composicaoLotesJson = '',
    this.baixadoEstoque = false,
  }) : custoUnitarioNoMomento = custoUnitarioNoMomento ?? custoUnitario,
       custoTotalNoMomento =
           custoTotalNoMomento ??
           quantidade * (custoUnitarioNoMomento ?? custoUnitario);

  double get custoTotal {
    return custoTotalNoMomento;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ordem_servico_id': ordemServicoId,
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'quantidade': quantidade,
      'unidade': unidade,
      'custo_unitario': custoUnitario,
      'custo_unitario_no_momento': custoUnitarioNoMomento,
      'custo_total_no_momento': custoTotalNoMomento,
      'composicao_lotes_json': composicaoLotesJson,
      'baixado_estoque': baixadoEstoque ? 1 : 0,
    };
  }

  factory ProdutoOrdemServico.fromMap(Map<String, dynamic> map) {
    final custoUnitarioLegado = _converterDouble(map['custo_unitario']);
    final custoUnitarioNoMomento = _converterDouble(
      map['custo_unitario_no_momento'],
    );
    final custoTotalNoMomento = _converterDouble(map['custo_total_no_momento']);
    final quantidade = _converterDouble(map['quantidade']);
    final custoUnitarioEfetivo = map.containsKey('custo_unitario_no_momento')
        ? custoUnitarioNoMomento
        : custoUnitarioLegado;

    return ProdutoOrdemServico(
      id: _converterIntNulo(map['id']),
      ordemServicoId: _converterInt(map['ordem_servico_id']),
      produtoId: _converterIntNulo(map['produto_id']),
      produtoNome: (map['produto_nome'] ?? '').toString(),
      quantidade: quantidade,
      unidade: (map['unidade'] ?? '').toString(),
      custoUnitario: custoUnitarioEfetivo,
      custoUnitarioNoMomento: custoUnitarioEfetivo,
      custoTotalNoMomento: custoTotalNoMomento > 0
          ? custoTotalNoMomento
          : quantidade * custoUnitarioEfetivo,
      composicaoLotesJson: (map['composicao_lotes_json'] ?? '').toString(),
      baixadoEstoque: _converterBool(map['baixado_estoque']),
    );
  }

  ProdutoOrdemServico copyWith({
    int? id,
    int? ordemServicoId,
    int? produtoId,
    bool removerProdutoId = false,
    String? produtoNome,
    double? quantidade,
    String? unidade,
    double? custoUnitario,
    double? custoUnitarioNoMomento,
    double? custoTotalNoMomento,
    String? composicaoLotesJson,
    bool? baixadoEstoque,
  }) {
    final custoUnitarioEfetivo =
        custoUnitarioNoMomento ?? custoUnitario ?? this.custoUnitarioNoMomento;
    final quantidadeEfetiva = quantidade ?? this.quantidade;

    return ProdutoOrdemServico(
      id: id ?? this.id,
      ordemServicoId: ordemServicoId ?? this.ordemServicoId,
      produtoId: removerProdutoId ? null : produtoId ?? this.produtoId,
      produtoNome: produtoNome ?? this.produtoNome,
      quantidade: quantidadeEfetiva,
      unidade: unidade ?? this.unidade,
      custoUnitario: custoUnitario ?? custoUnitarioEfetivo,
      custoUnitarioNoMomento: custoUnitarioEfetivo,
      custoTotalNoMomento:
          custoTotalNoMomento ?? quantidadeEfetiva * custoUnitarioEfetivo,
      composicaoLotesJson: composicaoLotesJson ?? this.composicaoLotesJson,
      baixadoEstoque: baixadoEstoque ?? this.baixadoEstoque,
    );
  }

  static int _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString().trim() ?? '') ?? 0;
  }

  static int? _converterIntNulo(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    final texto = valor.toString().trim();

    if (texto.isEmpty) {
      return null;
    }

    return int.tryParse(texto);
  }

  static double _converterDouble(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    final texto = valor?.toString().trim().replaceAll(',', '.') ?? '';

    return double.tryParse(texto) ?? 0;
  }

  static bool _converterBool(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt() == 1;
    }

    final texto = valor?.toString().trim().toLowerCase();

    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
