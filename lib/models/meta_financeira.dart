class MetaFinanceira {
  const MetaFinanceira({
    this.id,
    required this.ano,
    required this.mes,
    required this.tipo,
    this.planoContaId,
    required this.valorMeta,
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final int ano;
  final int mes;
  final String tipo;
  final int? planoContaId;
  final double valorMeta;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    return {
      if (incluirId && id != null) 'id': id,
      'ano': ano,
      'mes': mes,
      'tipo': tipo,
      'plano_conta_id': planoContaId,
      'valor_meta': valorMeta,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };
  }

  factory MetaFinanceira.fromMap(Map<String, dynamic> map) {
    return MetaFinanceira(
      id: _int(map['id']),
      ano: _int(map['ano']) ?? 0,
      mes: _int(map['mes']) ?? 0,
      tipo: (map['tipo'] ?? '').toString(),
      planoContaId: _int(map['plano_conta_id']),
      valorMeta: _double(map['valor_meta']),
      observacoes: (map['observacoes'] ?? '').toString(),
      ativo: _int(map['ativo']) != 0,
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
