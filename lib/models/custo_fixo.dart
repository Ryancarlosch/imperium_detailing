class CustoFixo {
  const CustoFixo({
    this.id,
    required this.nome,
    required this.valorMensal,
    this.categoria = 'Despesa fixa',
    this.diaVencimento,
    this.planoContaId,
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final String nome;
  final double valorMensal;
  final String categoria;
  final int? diaVencimento;
  final int? planoContaId;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    return <String, dynamic>{
      if (incluirId && id != null) 'id': id,
      'nome': nome,
      'valor_mensal': valorMensal,
      'categoria': categoria,
      'dia_vencimento': diaVencimento,
      'plano_conta_id': planoContaId,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };
  }

  factory CustoFixo.fromMap(Map<String, dynamic> map) {
    return CustoFixo(
      id: _int(map['id']),
      nome: (map['nome'] ?? '').toString(),
      valorMensal: _double(map['valor_mensal']),
      categoria: (map['categoria'] ?? 'Despesa fixa').toString(),
      diaVencimento: _int(map['dia_vencimento']),
      planoContaId: _int(map['plano_conta_id']),
      observacoes: (map['observacoes'] ?? '').toString(),
      ativo: _bool(map['ativo']),
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  double get valorAnual => valorMensal * 12;

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
