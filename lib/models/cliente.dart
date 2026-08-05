class Cliente {
  static const Object _valorNaoInformado = Object();

  const Cliente({
    this.id,
    required this.nome,
    required this.telefone,
    required this.email,
    required this.endereco,
    required this.observacoes,
    this.ativo = true,
    this.arquivadoEm,
  });

  final int? id;
  final String nome;
  final String telefone;
  final String email;
  final String endereco;
  final String observacoes;
  final bool ativo;
  final String? arquivadoEm;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'endereco': endereco,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'arquivado_em': arquivadoEm,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: _converterId(map['id']),
      nome: (map['nome'] ?? '').toString(),
      telefone: (map['telefone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      endereco: (map['endereco'] ?? '').toString(),
      observacoes: (map['observacoes'] ?? '').toString(),
      ativo: _converterAtivo(map['ativo']),
      arquivadoEm: _converterTextoOpcional(map['arquivado_em']),
    );
  }

  Cliente copyWith({
    int? id,
    String? nome,
    String? telefone,
    String? email,
    String? endereco,
    String? observacoes,
    bool? ativo,
    Object? arquivadoEm = _valorNaoInformado,
  }) {
    return Cliente(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      endereco: endereco ?? this.endereco,
      observacoes: observacoes ?? this.observacoes,
      ativo: ativo ?? this.ativo,
      arquivadoEm: identical(arquivadoEm, _valorNaoInformado)
          ? this.arquivadoEm
          : arquivadoEm as String?,
    );
  }

  static int? _converterId(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }

  static bool _converterAtivo(dynamic valor) {
    if (valor == null) {
      return true;
    }

    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = valor.toString().trim().toLowerCase();

    return texto != '0' && texto != 'false';
  }

  static String? _converterTextoOpcional(dynamic valor) {
    if (valor == null) {
      return null;
    }

    final texto = valor.toString().trim();

    return texto.isEmpty ? null : texto;
  }
}
