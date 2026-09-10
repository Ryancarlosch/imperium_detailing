class CrmCampanha {
  const CrmCampanha({
    this.id,
    required this.nome,
    this.tipo = 'Manual',
    this.beneficioTipo = 'Percentual',
    this.beneficioValor = 0,
    this.beneficioDescricao = '',
    this.valorMinimo = 0,
    this.diasValidade = 30,
    this.diasSemRetorno = 180,
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  static const tipos = <String>[
    'Aniversário',
    'Reativação',
    'Indicação',
    'Manual',
  ];

  static const tiposBeneficio = <String>[
    'Percentual',
    'Valor',
    'Serviço',
    'Crédito',
  ];

  final int? id;
  final String nome;
  final String tipo;
  final String beneficioTipo;
  final double beneficioValor;
  final String beneficioDescricao;
  final double valorMinimo;
  final int diasValidade;
  final int diasSemRetorno;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  Map<String, dynamic> toMap({bool incluirId = true}) => {
    if (incluirId && id != null) 'id': id,
    'nome': nome,
    'tipo': tipo,
    'beneficio_tipo': beneficioTipo,
    'beneficio_valor': beneficioValor,
    'beneficio_descricao': beneficioDescricao,
    'valor_minimo': valorMinimo,
    'dias_validade': diasValidade,
    'dias_sem_retorno': diasSemRetorno,
    'ativo': ativo ? 1 : 0,
    'criado_em': criadoEm,
    'atualizado_em': atualizadoEm,
  };

  factory CrmCampanha.fromMap(Map<String, dynamic> map) => CrmCampanha(
    id: (map['id'] as num?)?.toInt(),
    nome: (map['nome'] ?? '').toString(),
    tipo: (map['tipo'] ?? 'Manual').toString(),
    beneficioTipo: (map['beneficio_tipo'] ?? 'Percentual').toString(),
    beneficioValor: _double(map['beneficio_valor']),
    beneficioDescricao: (map['beneficio_descricao'] ?? '').toString(),
    valorMinimo: _double(map['valor_minimo']),
    diasValidade: (map['dias_validade'] as num?)?.toInt() ?? 30,
    diasSemRetorno: (map['dias_sem_retorno'] as num?)?.toInt() ?? 180,
    ativo: (map['ativo'] as num?)?.toInt() != 0,
    criadoEm: (map['criado_em'] ?? '').toString(),
    atualizadoEm: (map['atualizado_em'] ?? '').toString(),
  );

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class CrmCupom {
  const CrmCupom({
    this.id,
    required this.codigo,
    this.campanhaId,
    this.clienteId,
    this.leadId,
    required this.beneficioTipo,
    required this.beneficioValor,
    required this.beneficioDescricao,
    required this.valorMinimo,
    required this.validadeInicio,
    required this.validadeFim,
    required this.status,
    this.usadoEm,
    this.ordemServicoId,
    required this.chaveGeracao,
    required this.criadoEm,
  });

  final int? id;
  final String codigo;
  final int? campanhaId;
  final int? clienteId;
  final int? leadId;
  final String beneficioTipo;
  final double beneficioValor;
  final String beneficioDescricao;
  final double valorMinimo;
  final String validadeInicio;
  final String validadeFim;
  final String status;
  final String? usadoEm;
  final int? ordemServicoId;
  final String chaveGeracao;
  final String criadoEm;

  factory CrmCupom.fromMap(Map<String, dynamic> map) => CrmCupom(
    id: (map['id'] as num?)?.toInt(),
    codigo: (map['codigo'] ?? '').toString(),
    campanhaId: (map['campanha_id'] as num?)?.toInt(),
    clienteId: (map['cliente_id'] as num?)?.toInt(),
    leadId: (map['lead_id'] as num?)?.toInt(),
    beneficioTipo: (map['beneficio_tipo'] ?? '').toString(),
    beneficioValor: _double(map['beneficio_valor']),
    beneficioDescricao: (map['beneficio_descricao'] ?? '').toString(),
    valorMinimo: _double(map['valor_minimo']),
    validadeInicio: (map['validade_inicio'] ?? '').toString(),
    validadeFim: (map['validade_fim'] ?? '').toString(),
    status: (map['status'] ?? 'Ativo').toString(),
    usadoEm: _textoNulo(map['usado_em']),
    ordemServicoId: (map['ordem_servico_id'] as num?)?.toInt(),
    chaveGeracao: (map['chave_geracao'] ?? '').toString(),
    criadoEm: (map['criado_em'] ?? '').toString(),
  );

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
