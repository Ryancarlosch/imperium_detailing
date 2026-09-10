class CrmLead {
  const CrmLead({
    this.id,
    required this.nome,
    this.telefone = '',
    this.email = '',
    this.clienteId,
    this.veiculoId,
    this.origem = 'Outro',
    this.servicoInteresse = '',
    this.veiculoInteresse = '',
    this.valorPotencial = 0,
    this.etapa = 'Novo contato',
    this.responsavel = '',
    this.proximoContato,
    this.observacoes = '',
    this.motivoPerda = '',
    this.agendamentoId,
    required this.criadoEm,
    required this.atualizadoEm,
    this.convertidoEm,
  });

  static const etapas = <String>[
    'Novo contato',
    'Qualificação',
    'Orçamento',
    'Aguardando cliente',
    'Negociação',
    'Agendado',
    'Ganho',
    'Perdido',
  ];

  static const origens = <String>[
    'WhatsApp',
    'Instagram',
    'Google',
    'Indicação',
    'Cliente antigo',
    'Telefone',
    'Presencial',
    'Outro',
  ];

  final int? id;
  final String nome;
  final String telefone;
  final String email;
  final int? clienteId;
  final int? veiculoId;
  final String origem;
  final String servicoInteresse;
  final String veiculoInteresse;
  final double valorPotencial;
  final String etapa;
  final String responsavel;
  final String? proximoContato;
  final String observacoes;
  final String motivoPerda;
  final int? agendamentoId;
  final String criadoEm;
  final String atualizadoEm;
  final String? convertidoEm;

  bool get aberto => etapa != 'Ganho' && etapa != 'Perdido';

  Map<String, dynamic> toMap({bool incluirId = true}) => {
    if (incluirId && id != null) 'id': id,
    'nome': nome,
    'telefone': telefone,
    'email': email,
    'cliente_id': clienteId,
    'veiculo_id': veiculoId,
    'origem': origem,
    'servico_interesse': servicoInteresse,
    'veiculo_interesse': veiculoInteresse,
    'valor_potencial': valorPotencial,
    'etapa': etapa,
    'responsavel': responsavel,
    'proximo_contato': proximoContato,
    'observacoes': observacoes,
    'motivo_perda': motivoPerda,
    'agendamento_id': agendamentoId,
    'criado_em': criadoEm,
    'atualizado_em': atualizadoEm,
    'convertido_em': convertidoEm,
  };

  factory CrmLead.fromMap(Map<String, dynamic> map) => CrmLead(
    id: _int(map['id']),
    nome: (map['nome'] ?? '').toString(),
    telefone: (map['telefone'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    clienteId: _int(map['cliente_id']),
    veiculoId: _int(map['veiculo_id']),
    origem: (map['origem'] ?? 'Outro').toString(),
    servicoInteresse: (map['servico_interesse'] ?? '').toString(),
    veiculoInteresse: (map['veiculo_interesse'] ?? '').toString(),
    valorPotencial: _double(map['valor_potencial']),
    etapa: (map['etapa'] ?? 'Novo contato').toString(),
    responsavel: (map['responsavel'] ?? '').toString(),
    proximoContato: _textoNulo(map['proximo_contato']),
    observacoes: (map['observacoes'] ?? '').toString(),
    motivoPerda: (map['motivo_perda'] ?? '').toString(),
    agendamentoId: _int(map['agendamento_id']),
    criadoEm: (map['criado_em'] ?? '').toString(),
    atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    convertidoEm: _textoNulo(map['convertido_em']),
  );

  CrmLead copyWith({
    String? nome,
    String? telefone,
    String? email,
    int? clienteId,
    int? veiculoId,
    String? origem,
    String? servicoInteresse,
    String? veiculoInteresse,
    double? valorPotencial,
    String? etapa,
    String? responsavel,
    Object? proximoContato = _naoInformado,
    String? observacoes,
    String? motivoPerda,
    int? agendamentoId,
    String? atualizadoEm,
    Object? convertidoEm = _naoInformado,
  }) => CrmLead(
    id: id,
    nome: nome ?? this.nome,
    telefone: telefone ?? this.telefone,
    email: email ?? this.email,
    clienteId: clienteId ?? this.clienteId,
    veiculoId: veiculoId ?? this.veiculoId,
    origem: origem ?? this.origem,
    servicoInteresse: servicoInteresse ?? this.servicoInteresse,
    veiculoInteresse: veiculoInteresse ?? this.veiculoInteresse,
    valorPotencial: valorPotencial ?? this.valorPotencial,
    etapa: etapa ?? this.etapa,
    responsavel: responsavel ?? this.responsavel,
    proximoContato: identical(proximoContato, _naoInformado)
        ? this.proximoContato
        : proximoContato as String?,
    observacoes: observacoes ?? this.observacoes,
    motivoPerda: motivoPerda ?? this.motivoPerda,
    agendamentoId: agendamentoId ?? this.agendamentoId,
    criadoEm: criadoEm,
    atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    convertidoEm: identical(convertidoEm, _naoInformado)
        ? this.convertidoEm
        : convertidoEm as String?,
  );

  static const Object _naoInformado = Object();

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}

class CrmInteracao {
  const CrmInteracao({
    this.id,
    required this.leadId,
    required this.tipo,
    required this.descricao,
    required this.dataInteracao,
    required this.criadoEm,
  });

  final int? id;
  final int leadId;
  final String tipo;
  final String descricao;
  final String dataInteracao;
  final String criadoEm;

  factory CrmInteracao.fromMap(Map<String, dynamic> map) => CrmInteracao(
    id: (map['id'] as num?)?.toInt(),
    leadId: (map['lead_id'] as num).toInt(),
    tipo: (map['tipo'] ?? 'Contato').toString(),
    descricao: (map['descricao'] ?? '').toString(),
    dataInteracao: (map['data_interacao'] ?? '').toString(),
    criadoEm: (map['criado_em'] ?? '').toString(),
  );
}
