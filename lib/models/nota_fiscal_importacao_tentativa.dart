class NotaFiscalImportacaoTentativa {
  const NotaFiscalImportacaoTentativa({
    this.id,
    this.notaFiscalId,
    required this.chaveAcesso,
    this.modelo,
    required this.canal,
    required this.resultado,
    this.codigo = '',
    this.mensagem = '',
    this.url,
    required this.criadoEm,
  });

  final int? id;
  final int? notaFiscalId;
  final String chaveAcesso;
  final int? modelo;
  final String canal;
  final String resultado;
  final String codigo;
  final String mensagem;
  final String? url;
  final String criadoEm;

  bool get sucesso => resultado == 'sucesso';
  bool get pendente => resultado == 'pendente';
  bool get erro => resultado == 'erro';

  factory NotaFiscalImportacaoTentativa.fromMap(Map<String, dynamic> map) {
    return NotaFiscalImportacaoTentativa(
      id: _int(map['id']),
      notaFiscalId: _int(map['nota_fiscal_id']),
      chaveAcesso: (map['chave_acesso'] ?? '').toString(),
      modelo: _int(map['modelo']),
      canal: (map['canal'] ?? '').toString(),
      resultado: (map['resultado'] ?? '').toString(),
      codigo: (map['codigo'] ?? '').toString(),
      mensagem: (map['mensagem'] ?? '').toString(),
      url: _textoNulo(map['url']),
      criadoEm: (map['criado_em'] ?? '').toString(),
    );
  }

  static int? _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _textoNulo(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
