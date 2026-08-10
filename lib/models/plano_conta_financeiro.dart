class PlanoContaFinanceiro {
  const PlanoContaFinanceiro({
    this.id,
    required this.codigo,
    required this.nome,
    required this.tipo,
    required this.natureza,
    required this.grupoDre,
    this.parentId,
    this.ativo = true,
    this.ordem = 0,
    this.criadoEm = '',
    this.atualizadoEm = '',
  });

  final int? id;
  final String codigo;
  final String nome;
  final String tipo;
  final String natureza;
  final String grupoDre;
  final int? parentId;
  final bool ativo;
  final int ordem;
  final String criadoEm;
  final String atualizadoEm;

  factory PlanoContaFinanceiro.fromMap(Map<String, dynamic> map) {
    return PlanoContaFinanceiro(
      id: _int(map['id']),
      codigo: (map['codigo'] ?? '').toString(),
      nome: (map['nome'] ?? '').toString(),
      tipo: (map['tipo'] ?? '').toString(),
      natureza: (map['natureza'] ?? '').toString(),
      grupoDre: (map['grupo_dre'] ?? 'Não DRE').toString(),
      parentId: _int(map['parent_id']),
      ativo: _int(map['ativo']) != 0,
      ordem: _int(map['ordem']) ?? 0,
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final map = <String, dynamic>{
      'codigo': codigo,
      'nome': nome,
      'tipo': tipo,
      'natureza': natureza,
      'grupo_dre': grupoDre,
      'parent_id': parentId,
      'ativo': ativo ? 1 : 0,
      'ordem': ordem,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };

    if (incluirId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  PlanoContaFinanceiro copyWith({
    int? id,
    String? codigo,
    String? nome,
    String? tipo,
    String? natureza,
    String? grupoDre,
    int? parentId,
    bool? ativo,
    int? ordem,
    String? criadoEm,
    String? atualizadoEm,
  }) {
    return PlanoContaFinanceiro(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      natureza: natureza ?? this.natureza,
      grupoDre: grupoDre ?? this.grupoDre,
      parentId: parentId ?? this.parentId,
      ativo: ativo ?? this.ativo,
      ordem: ordem ?? this.ordem,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  static int? _int(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }
}
