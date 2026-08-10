class Fornecedor {
  const Fornecedor({
    this.id,
    required this.nome,
    this.documento = '',
    this.telefone = '',
    this.email = '',
    this.endereco = '',
    this.cidade = '',
    this.estado = '',
    this.categoria = '',
    this.observacoes = '',
    this.ativo = true,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int? id;
  final String nome;
  final String documento;
  final String telefone;
  final String email;
  final String endereco;
  final String cidade;
  final String estado;
  final String categoria;
  final String observacoes;
  final bool ativo;
  final String criadoEm;
  final String atualizadoEm;

  Map<String, dynamic> toMap({bool incluirId = true}) {
    final mapa = <String, dynamic>{
      'nome': nome,
      'documento': documento,
      'telefone': telefone,
      'email': email,
      'endereco': endereco,
      'cidade': cidade,
      'estado': estado,
      'categoria': categoria,
      'observacoes': observacoes,
      'ativo': ativo ? 1 : 0,
      'criado_em': criadoEm,
      'atualizado_em': atualizadoEm,
    };

    if (incluirId && id != null) {
      mapa['id'] = id;
    }

    return mapa;
  }

  factory Fornecedor.fromMap(Map<String, dynamic> map) {
    return Fornecedor(
      id: _int(map['id']),
      nome: _texto(map['nome']),
      documento: _texto(map['documento']),
      telefone: _texto(map['telefone']),
      email: _texto(map['email']),
      endereco: _texto(map['endereco']),
      cidade: _texto(map['cidade']),
      estado: _texto(map['estado']),
      categoria: _texto(map['categoria']),
      observacoes: _texto(map['observacoes']),
      ativo: _bool(map['ativo']),
      criadoEm: _texto(map['criado_em']),
      atualizadoEm: _texto(map['atualizado_em']),
    );
  }

  Fornecedor copyWith({
    int? id,
    String? nome,
    String? documento,
    String? telefone,
    String? email,
    String? endereco,
    String? cidade,
    String? estado,
    String? categoria,
    String? observacoes,
    bool? ativo,
    String? criadoEm,
    String? atualizadoEm,
  }) {
    return Fornecedor(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      documento: documento ?? this.documento,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      endereco: endereco ?? this.endereco,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      categoria: categoria ?? this.categoria,
      observacoes: observacoes ?? this.observacoes,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static String _texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final texto = valor?.toString().trim().toLowerCase();
    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
