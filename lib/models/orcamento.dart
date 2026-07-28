class Orcamento {
  final int? id;
  final int clienteId;
  final int? veiculoId;
  final String servico;
  final String descricao;
  final double valor;
  final String dataEmissao;
  final String validade;
  final String status;
  final String observacoes;

  const Orcamento({
    this.id,
    required this.clienteId,
    this.veiculoId,
    required this.servico,
    required this.descricao,
    required this.valor,
    required this.dataEmissao,
    required this.validade,
    required this.status,
    required this.observacoes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'servico': servico,
      'descricao': descricao,
      'valor': valor,
      'data_emissao': dataEmissao,
      'validade': validade,
      'status': status,
      'observacoes': observacoes,
    };
  }

  factory Orcamento.fromMap(
    Map<String, dynamic> map,
  ) {
    return Orcamento(
      id: map['id'] as int?,
      clienteId: map['cliente_id'] as int,
      veiculoId: map['veiculo_id'] as int?,
      servico: map['servico'] as String? ?? '',
      descricao: map['descricao'] as String? ?? '',
      valor:
          (map['valor'] as num?)?.toDouble() ?? 0,
      dataEmissao:
          map['data_emissao'] as String? ?? '',
      validade: map['validade'] as String? ?? '',
      status: map['status'] as String? ?? 'Pendente',
      observacoes:
          map['observacoes'] as String? ?? '',
    );
  }
}
