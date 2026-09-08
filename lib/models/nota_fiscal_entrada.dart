class NotaFiscalEntrada {
  const NotaFiscalEntrada({
    this.id,
    required this.chaveAcesso,
    this.modelo,
    this.numero,
    this.serie,
    this.dataEmissao,
    this.fornecedorId,
    this.emitenteCnpjCpf,
    this.emitenteNome,
    this.valorProdutos,
    this.valorFrete = 0,
    this.valorSeguro = 0,
    this.valorDesconto = 0,
    this.valorOutrasDespesas = 0,
    this.valorIpi = 0,
    this.valorIcmsSt = 0,
    this.valorTotal,
    this.situacaoFiscal = 'desconhecida',
    this.statusImportacao = 'pendente',
    required this.origemImportacao,
    this.xmlOriginal,
    this.xmlHash,
    required this.importadaEm,
    this.observacoes = '',
  });

  final int? id;
  final String chaveAcesso;
  final int? modelo;
  final int? numero;
  final int? serie;
  final String? dataEmissao;
  final int? fornecedorId;
  final String? emitenteCnpjCpf;
  final String? emitenteNome;
  final double? valorProdutos;
  final double valorFrete;
  final double valorSeguro;
  final double valorDesconto;
  final double valorOutrasDespesas;
  final double valorIpi;
  final double valorIcmsSt;
  final double? valorTotal;
  final String situacaoFiscal;
  final String statusImportacao;
  final String origemImportacao;
  final String? xmlOriginal;
  final String? xmlHash;
  final String importadaEm;
  final String observacoes;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final mapa = <String, dynamic>{
      'chave_acesso': chaveAcesso,
      'modelo': modelo,
      'numero': numero,
      'serie': serie,
      'data_emissao': dataEmissao,
      'fornecedor_id': fornecedorId,
      'emitente_cnpj_cpf': emitenteCnpjCpf,
      'emitente_nome': emitenteNome,
      'valor_produtos': valorProdutos,
      'valor_frete': valorFrete,
      'valor_seguro': valorSeguro,
      'valor_desconto': valorDesconto,
      'valor_outras_despesas': valorOutrasDespesas,
      'valor_ipi': valorIpi,
      'valor_icms_st': valorIcmsSt,
      'valor_total': valorTotal,
      'situacao_fiscal': situacaoFiscal,
      'status_importacao': statusImportacao,
      'origem_importacao': origemImportacao,
      'xml_original': xmlOriginal,
      'xml_hash': xmlHash,
      'importada_em': importadaEm,
      'observacoes': observacoes,
    };

    if (incluirId && id != null) mapa['id'] = id;
    return mapa;
  }

  factory NotaFiscalEntrada.fromMap(Map<String, dynamic> map) {
    return NotaFiscalEntrada(
      id: _int(map['id']),
      chaveAcesso: _texto(map['chave_acesso']),
      modelo: _int(map['modelo']),
      numero: _int(map['numero']),
      serie: _int(map['serie']),
      dataEmissao: _textoNulo(map['data_emissao']),
      fornecedorId: _int(map['fornecedor_id']),
      emitenteCnpjCpf: _textoNulo(map['emitente_cnpj_cpf']),
      emitenteNome: _textoNulo(map['emitente_nome']),
      valorProdutos: _doubleNulo(map['valor_produtos']),
      valorFrete: _double(map['valor_frete']),
      valorSeguro: _double(map['valor_seguro']),
      valorDesconto: _double(map['valor_desconto']),
      valorOutrasDespesas: _double(map['valor_outras_despesas']),
      valorIpi: _double(map['valor_ipi']),
      valorIcmsSt: _double(map['valor_icms_st']),
      valorTotal: _doubleNulo(map['valor_total']),
      situacaoFiscal: _textoOu(map['situacao_fiscal'], 'desconhecida'),
      statusImportacao: _textoOu(map['status_importacao'], 'pendente'),
      origemImportacao: _texto(map['origem_importacao']),
      xmlOriginal: _textoNulo(map['xml_original']),
      xmlHash: _textoNulo(map['xml_hash']),
      importadaEm: _texto(map['importada_em']),
      observacoes: _texto(map['observacoes']),
    );
  }

  static int? _int(dynamic valor) => valor is num
      ? valor.toInt()
      : int.tryParse(valor?.toString().trim() ?? '');

  static double _double(dynamic valor) => valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;

  static double? _doubleNulo(dynamic valor) {
    if (valor == null) return null;
    return _double(valor);
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String? _textoNulo(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }

  static String _textoOu(dynamic valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }
}
