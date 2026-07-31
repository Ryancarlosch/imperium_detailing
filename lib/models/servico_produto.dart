class ServicoProduto {
  const ServicoProduto({
    this.id,
    required this.servicoId,
    required this.itemEstoqueId,
    required this.quantidadePadrao,
    required this.unidade,
    required this.obrigatorio,
    required this.marcadoPorPadrao,
    required this.ordem,
    this.produtoNome = '',
    this.custoUnitario = 0,
  });

  final int? id;
  final int servicoId;
  final int itemEstoqueId;
  final double quantidadePadrao;
  final String unidade;
  final bool obrigatorio;
  final bool marcadoPorPadrao;
  final int ordem;
  final String produtoNome;
  final double custoUnitario;

  double get custoPrevisto =>
      quantidadePadrao * custoUnitario;

  Map<String, dynamic> toMap({
    bool incluirId = true,
  }) {
    final mapa = <String, dynamic>{
      'servico_id': servicoId,
      'item_estoque_id': itemEstoqueId,
      'quantidade_padrao': quantidadePadrao,
      'unidade': unidade,
      'obrigatorio': obrigatorio ? 1 : 0,
      'marcado_por_padrao': marcadoPorPadrao ? 1 : 0,
      'ordem': ordem,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory ServicoProduto.fromMap(
    Map<String, dynamic> map,
  ) {
    return ServicoProduto(
      id: _int(map['id']),
      servicoId: _int(map['servico_id']) ?? 0,
      itemEstoqueId:
          _int(map['item_estoque_id']) ?? 0,
      quantidadePadrao:
          _double(map['quantidade_padrao']),
      unidade: map['unidade']?.toString() ?? '',
      obrigatorio: _bool(map['obrigatorio']),
      marcadoPorPadrao:
          _bool(map['marcado_por_padrao']),
      ordem: _int(map['ordem']) ?? 0,
      produtoNome:
          map['produto_nome']?.toString() ?? '',
      custoUnitario:
          _double(map['custo_unitario']),
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(
          valor?.toString().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;

    final texto =
        valor?.toString().trim().toLowerCase() ?? '';

    return texto == '1' ||
        texto == 'true' ||
        texto == 'sim';
  }
}
