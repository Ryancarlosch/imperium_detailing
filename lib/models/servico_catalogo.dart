class ServicoCatalogo {
  const ServicoCatalogo({
    this.id,
    required this.nome,
    required this.categoria,
    required this.descricao,
    required this.observacoesPadrao,
    required this.precoMinimo,
    required this.precoPadrao,
    required this.precoMaximo,
    required this.duracaoMinutos,
    required this.ativo,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final String nome;
  final String categoria;
  final String descricao;
  final String observacoesPadrao;
  final double precoMinimo;
  final double precoPadrao;
  final double precoMaximo;
  final int duracaoMinutos;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  String get duracaoFormatada {
    final horas = duracaoMinutos ~/ 60;
    final minutos = duracaoMinutos % 60;

    if (horas <= 0) {
      return '${minutos}min';
    }

    if (minutos == 0) {
      return '${horas}h';
    }

    return '${horas}h ${minutos}min';
  }

  Map<String, dynamic> toMap({
    bool incluirId = true,
  }) {
    final mapa = <String, dynamic>{
      'nome': nome,
      'categoria': categoria,
      'descricao': descricao,
      'observacoes_padrao': observacoesPadrao,
      'preco_minimo': precoMinimo,
      'preco_padrao': precoPadrao,
      'preco_maximo': precoMaximo,
      'duracao_minutos': duracaoMinutos,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory ServicoCatalogo.fromMap(
    Map<String, dynamic> map,
  ) {
    return ServicoCatalogo(
      id: _int(map['id']),
      nome: map['nome']?.toString() ?? '',
      categoria: map['categoria']?.toString() ?? '',
      descricao: map['descricao']?.toString() ?? '',
      observacoesPadrao:
          map['observacoes_padrao']?.toString() ?? '',
      precoMinimo: _double(map['preco_minimo']),
      precoPadrao: _double(map['preco_padrao']),
      precoMaximo: _double(map['preco_maximo']),
      duracaoMinutos: _int(map['duracao_minutos']) ?? 0,
      ativo: _bool(map['ativo']),
      criadoEm: map['criado_em']?.toString() ?? '',
      atualizadoEm: map['atualizado_em']?.toString() ?? '',
    );
  }

  ServicoCatalogo copyWith({
    int? id,
    String? nome,
    String? categoria,
    String? descricao,
    String? observacoesPadrao,
    double? precoMinimo,
    double? precoPadrao,
    double? precoMaximo,
    int? duracaoMinutos,
    bool? ativo,
    String? criadoEm,
    String? atualizadoEm,
  }) {
    return ServicoCatalogo(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      categoria: categoria ?? this.categoria,
      descricao: descricao ?? this.descricao,
      observacoesPadrao:
          observacoesPadrao ?? this.observacoesPadrao,
      precoMinimo: precoMinimo ?? this.precoMinimo,
      precoPadrao: precoPadrao ?? this.precoPadrao,
      precoMaximo: precoMaximo ?? this.precoMaximo,
      duracaoMinutos:
          duracaoMinutos ?? this.duracaoMinutos,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
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
