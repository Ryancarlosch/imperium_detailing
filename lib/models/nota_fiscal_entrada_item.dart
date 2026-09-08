class NotaFiscalEntradaItem {
  const NotaFiscalEntradaItem({
    this.id,
    required this.notaFiscalId,
    required this.numeroItem,
    this.codigoProduto,
    this.ean,
    required this.descricao,
    this.ncm,
    this.cfop,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.valorDesconto = 0,
    this.estoqueItemId,
    this.observacoes = '',
  });

  final int? id;
  final int notaFiscalId;
  final int numeroItem;
  final String? codigoProduto;
  final String? ean;
  final String descricao;
  final String? ncm;
  final String? cfop;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double valorTotal;
  final double valorDesconto;
  final int? estoqueItemId;
  final String observacoes;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final mapa = <String, dynamic>{
      'nota_fiscal_id': notaFiscalId,
      'numero_item': numeroItem,
      'codigo_produto': codigoProduto,
      'ean': ean,
      'descricao': descricao,
      'ncm': ncm,
      'cfop': cfop,
      'unidade': unidade,
      'quantidade': quantidade,
      'valor_unitario': valorUnitario,
      'valor_total': valorTotal,
      'valor_desconto': valorDesconto,
      'estoque_item_id': estoqueItemId,
      'observacoes': observacoes,
    };

    if (incluirId && id != null) mapa['id'] = id;
    return mapa;
  }

  factory NotaFiscalEntradaItem.fromMap(Map<String, dynamic> map) {
    return NotaFiscalEntradaItem(
      id: _int(map['id']),
      notaFiscalId: _int(map['nota_fiscal_id']) ?? 0,
      numeroItem: _int(map['numero_item']) ?? 0,
      codigoProduto: _textoNulo(map['codigo_produto']),
      ean: _textoNulo(map['ean']),
      descricao: _texto(map['descricao']),
      ncm: _textoNulo(map['ncm']),
      cfop: _textoNulo(map['cfop']),
      unidade: _texto(map['unidade']),
      quantidade: _double(map['quantidade']),
      valorUnitario: _double(map['valor_unitario']),
      valorTotal: _double(map['valor_total']),
      valorDesconto: _double(map['valor_desconto']),
      estoqueItemId: _int(map['estoque_item_id']),
      observacoes: _texto(map['observacoes']),
    );
  }

  static int? _int(dynamic valor) => valor is num
      ? valor.toInt()
      : int.tryParse(valor?.toString().trim() ?? '');

  static double _double(dynamic valor) => valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String? _textoNulo(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }
}
