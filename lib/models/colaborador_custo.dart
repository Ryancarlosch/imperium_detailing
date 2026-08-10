class ColaboradorCusto {
  const ColaboradorCusto({
    this.id,
    required this.nome,
    this.funcao = '',
    this.remuneracaoMensal = 0,
    this.encargosMensais = 0,
    this.outrosCustosMensais = 0,
    this.horasProdutivasMes = 0,
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final String nome;
  final String funcao;
  final double remuneracaoMensal;
  final double encargosMensais;
  final double outrosCustosMensais;
  final double horasProdutivasMes;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  double get custoMensalTotal =>
      remuneracaoMensal + encargosMensais + outrosCustosMensais;

  double get custoHoraProdutiva =>
      horasProdutivasMes <= 0 ? 0 : custoMensalTotal / horasProdutivasMes;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    return <String, dynamic>{
      if (incluirId && id != null) 'id': id,
      'nome': nome,
      'funcao': funcao,
      'remuneracao_mensal': remuneracaoMensal,
      'encargos_mensais': encargosMensais,
      'outros_custos_mensais': outrosCustosMensais,
      'horas_produtivas_mes': horasProdutivasMes,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };
  }

  factory ColaboradorCusto.fromMap(Map<String, dynamic> map) {
    return ColaboradorCusto(
      id: _int(map['id']),
      nome: (map['nome'] ?? '').toString(),
      funcao: (map['funcao'] ?? '').toString(),
      remuneracaoMensal: _double(map['remuneracao_mensal']),
      encargosMensais: _double(map['encargos_mensais']),
      outrosCustosMensais: _double(map['outros_custos_mensais']),
      horasProdutivasMes: _double(map['horas_produtivas_mes']),
      observacoes: (map['observacoes'] ?? '').toString(),
      ativo: _bool(map['ativo']),
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  static int? _int(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double _double(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static bool _bool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return value?.toString().toLowerCase() == 'true';
  }
}
