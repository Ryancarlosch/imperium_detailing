class Agendamento {
  final int? id;
  final int clienteId;
  final int veiculoId;
  final String servico;
  final String data;
  final String hora;
  final double valor;
  final String status;
  final String observacoes;

  Agendamento({
    this.id,
    required this.clienteId,
    required this.veiculoId,
    required this.servico,
    required this.data,
    required this.hora,
    required this.valor,
    required this.status,
    required this.observacoes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'servico': servico,
      'data': data,
      'hora': hora,
      'valor': valor,
      'status': status,
      'observacoes': observacoes,
    };
  }

  factory Agendamento.fromMap(Map<String, dynamic> map) {
    return Agendamento(
      id: map['id'] as int?,
      clienteId: map['cliente_id'] as int,
      veiculoId: map['veiculo_id'] as int,
      servico: map['servico'] as String? ?? '',
      data: map['data'] as String? ?? '',
      hora: map['hora'] as String? ?? '',
      valor: (map['valor'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'Agendado',
      observacoes: map['observacoes'] as String? ?? '',
    );
  }

  Agendamento copyWith({
    int? id,
    int? clienteId,
    int? veiculoId,
    String? servico,
    String? data,
    String? hora,
    double? valor,
    String? status,
    String? observacoes,
  }) {
    return Agendamento(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      veiculoId: veiculoId ?? this.veiculoId,
      servico: servico ?? this.servico,
      data: data ?? this.data,
      hora: hora ?? this.hora,
      valor: valor ?? this.valor,
      status: status ?? this.status,
      observacoes: observacoes ?? this.observacoes,
    );
  }
}
