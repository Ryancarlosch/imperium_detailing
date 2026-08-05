class FotoServico {
  final int? id;
  final int clienteId;
  final int veiculoId;
  final String caminhoAntes;
  final String caminhoDepois;
  final String descricao;
  final String data;

  const FotoServico({
    this.id,
    required this.clienteId,
    required this.veiculoId,
    required this.caminhoAntes,
    required this.caminhoDepois,
    required this.descricao,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'caminho_antes': caminhoAntes,
      'caminho_depois': caminhoDepois,
      'descricao': descricao,
      'data': data,
    };
  }

  factory FotoServico.fromMap(Map<String, dynamic> map) {
    return FotoServico(
      id: map['id'] as int?,
      clienteId: map['cliente_id'] as int,
      veiculoId: map['veiculo_id'] as int,
      caminhoAntes: map['caminho_antes'] as String? ?? '',
      caminhoDepois: map['caminho_depois'] as String? ?? '',
      descricao: map['descricao'] as String? ?? '',
      data: map['data'] as String? ?? '',
    );
  }

  FotoServico copyWith({
    int? id,
    int? clienteId,
    int? veiculoId,
    String? caminhoAntes,
    String? caminhoDepois,
    String? descricao,
    String? data,
  }) {
    return FotoServico(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      veiculoId: veiculoId ?? this.veiculoId,
      caminhoAntes: caminhoAntes ?? this.caminhoAntes,
      caminhoDepois: caminhoDepois ?? this.caminhoDepois,
      descricao: descricao ?? this.descricao,
      data: data ?? this.data,
    );
  }
}
