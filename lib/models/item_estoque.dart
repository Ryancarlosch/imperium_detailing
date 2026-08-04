class ItemEstoque {
  final int? id;
  final String nome;
  final String categoria;
  final double quantidade;
  final double quantidadeMinima;
  final String unidade;
  final double valorTotalPago;
  final double quantidadeTotal;
  final double custoUnitario;
  final double custoUnitarioCalculado;
  final String fornecedor;
  final String observacoes;
  final bool ativo;
  final String atualizadoEm;

  const ItemEstoque({
    this.id,
    required this.nome,
    required this.categoria,
    required this.quantidade,
    required this.quantidadeMinima,
    required this.unidade,
    this.valorTotalPago = 0,
    this.quantidadeTotal = 0,
    required this.custoUnitario,
    this.custoUnitarioCalculado = 0,
    required this.fornecedor,
    required this.observacoes,
    this.ativo = true,
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

  double get valorTotal => quantidade * custoUnitarioEfetivo;

  bool get possuiDadosCompra => valorTotalPago > 0 && quantidadeTotal > 0;

  double get custoUnitarioEfetivo {
    if (custoUnitarioCalculado > 0) {
      return custoUnitarioCalculado;
    }

    return custoUnitario;
  }

  double get quantidadeTotalNormalizada =>
      quantidadeTotal * fatorNormalizacaoUnidade(unidade);

  String get unidadeNormalizada => unidadeNormalizadaParaBase(unidade);

  double get custoUnitarioCalculadoOuLegado {
    if (custoUnitarioCalculado > 0) {
      return custoUnitarioCalculado;
    }

    return custoUnitario;
  }

  static double fatorNormalizacaoUnidade(String unidade) {
    switch (normalizarUnidadeEntrada(unidade)) {
      case 'l':
        return 1000;
      case 'kg':
        return 1000;
      default:
        return 1;
    }
  }

  static String unidadeNormalizadaParaBase(String unidade) {
    switch (normalizarUnidadeEntrada(unidade)) {
      case 'l':
        return 'ml';
      case 'kg':
        return 'g';
      case 'metro':
        return 'metro';
      case 'unidade':
        return 'unidade';
      case 'ml':
        return 'ml';
      case 'g':
        return 'g';
      default:
        return 'unidade';
    }
  }

  static String normalizarUnidadeEntrada(String unidade) {
    switch (unidade.trim().toLowerCase()) {
      case 'l':
      case 'litro':
      case 'litros':
        return 'l';
      case 'ml':
      case 'mililitro':
      case 'mililitros':
        return 'ml';
      case 'kg':
      case 'quilo':
      case 'quilos':
      case 'quilograma':
      case 'quilogramas':
        return 'kg';
      case 'g':
      case 'grama':
      case 'gramas':
        return 'g';
      case 'm':
      case 'metro':
      case 'metros':
        return 'metro';
      case 'un':
      case 'und':
      case 'unidade':
      case 'unidades':
      default:
        return 'unidade';
    }
  }

  static double quantidadeNormalizada(double quantidade, String unidade) {
    return quantidade * fatorNormalizacaoUnidade(unidade);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'categoria': categoria,
      'quantidade': quantidade,
      'quantidade_minima': quantidadeMinima,
      'unidade': unidade,
      'valor_total_pago': valorTotalPago,
      'quantidade_total': quantidadeTotal,
      'custo_unitario': custoUnitarioEfetivo,
      'custo_unitario_calculado': custoUnitarioCalculadoOuLegado,
      'fornecedor': fornecedor,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'atualizado_em': atualizadoEm,
    };
  }

  factory ItemEstoque.fromMap(Map<String, dynamic> map) {
    final custoCalculado =
        (map['custo_unitario_calculado'] as num?)?.toDouble() ?? 0;
    final custoLegado = (map['custo_unitario'] as num?)?.toDouble() ?? 0;

    return ItemEstoque(
      id: map['id'] as int?,
      nome: map['nome'] as String? ?? '',
      categoria: map['categoria'] as String? ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0,
      quantidadeMinima: (map['quantidade_minima'] as num?)?.toDouble() ?? 0,
      unidade: map['unidade'] as String? ?? 'unidade',
      valorTotalPago: (map['valor_total_pago'] as num?)?.toDouble() ?? 0,
      quantidadeTotal: (map['quantidade_total'] as num?)?.toDouble() ?? 0,
      custoUnitarioCalculado: custoCalculado > 0 ? custoCalculado : custoLegado,
      custoUnitario: custoCalculado > 0 ? custoCalculado : custoLegado,
      fornecedor: map['fornecedor'] as String? ?? '',
      observacoes: map['observacoes'] as String? ?? '',
      ativo: (map['ativo'] as num?)?.toInt() != 0,
      atualizadoEm: map['atualizado_em'] as String? ?? '',
    );
  }
}
