class Cliente {
  final int? id;
  final String nome;
  final String telefone;
  final String email;
  final String endereco;
  final String observacoes;

  Cliente({
    this.id,
    required this.nome,
    required this.telefone,
    required this.email,
    required this.endereco,
    required this.observacoes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'endereco': endereco,
      'observacoes': observacoes,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'],
      nome: map['nome'],
      telefone: map['telefone'] ?? '',
      email: map['email'] ?? '',
      endereco: map['endereco'] ?? '',
      observacoes: map['observacoes'] ?? '',
    );
  }
}