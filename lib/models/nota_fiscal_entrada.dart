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
    this.consultaUrl,
    this.tentativasImportacao = 0,
    this.ultimaTentativaEm,
    this.ultimoErroCodigo = '',
    this.ultimoErroMensagem = '',
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
  final String? consultaUrl;
  final int tentativasImportacao;
  final String? ultimaTentativaEm;
  final String ultimoErroCodigo;
  final String ultimoErroMensagem;
  final String importadaEm;
  final String observacoes;

  bool get processada => statusImportacao == 'processada';
  bool get pendente => statusImportacao == 'pendente';
  bool get possuiFalhaImportacao => ultimoErroMensagem.trim().isNotEmpty;
  bool get possuiConsultaPublica => (consultaUrl ?? '').trim().isNotEmpty;

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
      'consulta_url': consultaUrl,
      'tentativas_importacao': tentativasImportacao,
      'ultima_tentativa_em': ultimaTentativaEm,
      'ultimo_erro_codigo': ultimoErroCodigo,
      'ultimo_erro_mensagem': ultimoErroMensagem,
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
      consultaUrl: _textoNulo(map['consulta_url']),
      tentativasImportacao: _int(map['tentativas_importacao']) ?? 0,
      ultimaTentativaEm: _textoNulo(map['ultima_tentativa_em']),
      ultimoErroCodigo: _texto(map['ultimo_erro_codigo']),
      ultimoErroMensagem: _texto(map['ultimo_erro_mensagem']),
      importadaEm: _texto(map['importada_em']),
      observacoes: _texto(map['observacoes']),
    );
  }

  NotaFiscalEntrada copyWith({
    int? id,
    String? chaveAcesso,
    int? modelo,
    int? numero,
    int? serie,
    String? dataEmissao,
    int? fornecedorId,
    String? emitenteCnpjCpf,
    String? emitenteNome,
    double? valorProdutos,
    double? valorFrete,
    double? valorSeguro,
    double? valorDesconto,
    double? valorOutrasDespesas,
    double? valorIpi,
    double? valorIcmsSt,
    double? valorTotal,
    String? situacaoFiscal,
    String? statusImportacao,
    String? origemImportacao,
    String? xmlOriginal,
    String? xmlHash,
    String? consultaUrl,
    int? tentativasImportacao,
    String? ultimaTentativaEm,
    String? ultimoErroCodigo,
    String? ultimoErroMensagem,
    String? importadaEm,
    String? observacoes,
  }) {
    return NotaFiscalEntrada(
      id: id ?? this.id,
      chaveAcesso: chaveAcesso ?? this.chaveAcesso,
      modelo: modelo ?? this.modelo,
      numero: numero ?? this.numero,
      serie: serie ?? this.serie,
      dataEmissao: dataEmissao ?? this.dataEmissao,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      emitenteCnpjCpf: emitenteCnpjCpf ?? this.emitenteCnpjCpf,
      emitenteNome: emitenteNome ?? this.emitenteNome,
      valorProdutos: valorProdutos ?? this.valorProdutos,
      valorFrete: valorFrete ?? this.valorFrete,
      valorSeguro: valorSeguro ?? this.valorSeguro,
      valorDesconto: valorDesconto ?? this.valorDesconto,
      valorOutrasDespesas: valorOutrasDespesas ?? this.valorOutrasDespesas,
      valorIpi: valorIpi ?? this.valorIpi,
      valorIcmsSt: valorIcmsSt ?? this.valorIcmsSt,
      valorTotal: valorTotal ?? this.valorTotal,
      situacaoFiscal: situacaoFiscal ?? this.situacaoFiscal,
      statusImportacao: statusImportacao ?? this.statusImportacao,
      origemImportacao: origemImportacao ?? this.origemImportacao,
      xmlOriginal: xmlOriginal ?? this.xmlOriginal,
      xmlHash: xmlHash ?? this.xmlHash,
      consultaUrl: consultaUrl ?? this.consultaUrl,
      tentativasImportacao: tentativasImportacao ?? this.tentativasImportacao,
      ultimaTentativaEm: ultimaTentativaEm ?? this.ultimaTentativaEm,
      ultimoErroCodigo: ultimoErroCodigo ?? this.ultimoErroCodigo,
      ultimoErroMensagem: ultimoErroMensagem ?? this.ultimoErroMensagem,
      importadaEm: importadaEm ?? this.importadaEm,
      observacoes: observacoes ?? this.observacoes,
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
