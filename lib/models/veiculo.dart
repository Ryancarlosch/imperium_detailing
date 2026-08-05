class Veiculo {
  final int? id;
  final int clienteId;
  final String marca;
  final String modelo;
  final String placa;
  final String cor;
  final String ano;
  final String observacoes;

  Veiculo({
    this.id,
    required this.clienteId,
    required this.marca,
    required this.modelo,
    required this.placa,
    required this.cor,
    required this.ano,
    required this.observacoes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'marca': marca,
      'modelo': modelo,
      'placa': placa,
      'cor': cor,
      'ano': ano,
      'observacoes': observacoes,
    };
  }

  factory Veiculo.fromMap(Map<String, dynamic> map) {
    return Veiculo(
      id: map['id'] as int?,
      clienteId: map['cliente_id'] as int,
      marca: map['marca'] as String? ?? '',
      modelo: map['modelo'] as String? ?? '',
      placa: map['placa'] as String? ?? '',
      cor: map['cor'] as String? ?? '',
      ano: map['ano'] as String? ?? '',
      observacoes: map['observacoes'] as String? ?? '',
    );
  }
}
