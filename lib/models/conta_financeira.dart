class ContaFinanceira {
  const ContaFinanceira({
    this.id,
    required this.nome,
    this.tipo = 'Conta bancária',
    this.instituicao = '',
    this.saldoInicial = 0,
    this.dataSaldoInicial,
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
    this.saldoAtual,
  });

  final int? id;
  final String nome;
  final String tipo;
  final String instituicao;
  final double saldoInicial;
  final String? dataSaldoInicial;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;
  final double? saldoAtual;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final mapa = <String, dynamic>{
      'nome': nome,
      'tipo': tipo,
      'instituicao': instituicao,
      'saldo_inicial': saldoInicial,
      'data_saldo_inicial': dataSaldoInicial,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory ContaFinanceira.fromMap(Map<String, dynamic> map) {
    return ContaFinanceira(
      id: _int(map['id']),
      nome: _texto(map['nome']),
      tipo: _texto(map['tipo'], padrao: 'Conta bancária'),
      instituicao: _texto(map['instituicao']),
      saldoInicial: _double(map['saldo_inicial']),
      dataSaldoInicial: _textoNulo(map['data_saldo_inicial']),
      observacoes: _texto(map['observacoes']),
      ativo: _bool(map['ativo']),
      criadoEm: _texto(map['criado_em']),
      atualizadoEm: _texto(map['atualizado_em']),
      saldoAtual: map.containsKey('saldo_atual')
          ? _double(map['saldo_atual'])
          : null,
    );
  }

  ContaFinanceira copyWith({
    int? id,
    String? nome,
    String? tipo,
    String? instituicao,
    double? saldoInicial,
    String? dataSaldoInicial,
    bool removerDataSaldoInicial = false,
    String? observacoes,
    bool? ativo,
    String? criadoEm,
    String? atualizadoEm,
    double? saldoAtual,
  }) {
    return ContaFinanceira(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      instituicao: instituicao ?? this.instituicao,
      saldoInicial: saldoInicial ?? this.saldoInicial,
      dataSaldoInicial: removerDataSaldoInicial
          ? null
          : dataSaldoInicial ?? this.dataSaldoInicial,
      observacoes: observacoes ?? this.observacoes,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      saldoAtual: saldoAtual ?? this.saldoAtual,
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String _texto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? padrao : texto;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final texto = valor?.toString().trim().toLowerCase();
    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
