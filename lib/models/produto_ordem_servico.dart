class ProdutoOrdemServico {
  final int? id;
  final int ordemServicoId;
  final int? produtoId;
  final String produtoNome;
  final double quantidade;
  final String unidade;
  final double custoUnitario;
  final bool baixadoEstoque;

  const ProdutoOrdemServico({
    this.id,
    required this.ordemServicoId,
    this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    required this.unidade,
    required this.custoUnitario,
    this.baixadoEstoque = false,
  });

  double get custoTotal {
    return quantidade * custoUnitario;
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
      'baixado_estoque': baixadoEstoque ? 1 : 0,
    };
  }

  factory ProdutoOrdemServico.fromMap(
      Map<String, dynamic> map,
      ) {
    return ProdutoOrdemServico(
      id: _converterIntNulo(
        map['id'],
      ),
      ordemServicoId: _converterInt(
        map['ordem_servico_id'],
      ),
      produtoId: _converterIntNulo(
        map['produto_id'],
      ),
      produtoNome:
      (map['produto_nome'] ?? '').toString(),
      quantidade: _converterDouble(
        map['quantidade'],
      ),
      unidade: (map['unidade'] ?? '').toString(),
      custoUnitario: _converterDouble(
        map['custo_unitario'],
      ),
      baixadoEstoque: _converterBool(
        map['baixado_estoque'],
      ),
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
    bool? baixadoEstoque,
  }) {
    return ProdutoOrdemServico(
      id: id ?? this.id,
      ordemServicoId:
      ordemServicoId ?? this.ordemServicoId,
      produtoId: removerProdutoId
          ? null
          : produtoId ?? this.produtoId,
      produtoNome:
      produtoNome ?? this.produtoNome,
      quantidade:
      quantidade ?? this.quantidade,
      unidade: unidade ?? this.unidade,
      custoUnitario:
      custoUnitario ?? this.custoUnitario,
      baixadoEstoque:
      baixadoEstoque ?? this.baixadoEstoque,
    );
  }

  static int _converterInt(
      dynamic valor,
      ) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(
      valor?.toString().trim() ?? '',
    ) ??
        0;
  }

  static int? _converterIntNulo(
      dynamic valor,
      ) {
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

  static double _converterDouble(
      dynamic valor,
      ) {
    if (valor is num) {
      return valor.toDouble();
    }

    final texto = valor
        ?.toString()
        .trim()
        .replaceAll(',', '.') ??
        '';

    return double.tryParse(texto) ?? 0;
  }

  static bool _converterBool(
      dynamic valor,
      ) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt() == 1;
    }

    final texto =
    valor?.toString().trim().toLowerCase();

    return texto == '1' ||
        texto == 'true' ||
        texto == 'sim';
  }
}