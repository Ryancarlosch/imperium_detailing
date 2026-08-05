class OrdemServicoItem {
  const OrdemServicoItem({
    this.id,
    required this.ordemServicoId,
    required this.servico,
    this.descricao = '',
    this.quantidade = 1,
    this.valorUnitario = 0,
    this.ordem = 0,
    this.concluido = false,
  });

  final int? id;
  final int ordemServicoId;
  final String servico;
  final String descricao;
  final double quantidade;
  final double valorUnitario;
  final int ordem;
  final bool concluido;

  double get subtotal {
    return quantidade * valorUnitario;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ordem_servico_id': ordemServicoId,
      'servico': servico,
      'descricao': descricao,
      'quantidade': quantidade,
      'valor_unitario': valorUnitario,
      'ordem': ordem,
      'concluido': concluido ? 1 : 0,
    };
  }

  factory OrdemServicoItem.fromMap(Map<String, dynamic> map) {
    return OrdemServicoItem(
      id: _converterInt(map['id']),
      ordemServicoId: _converterInt(map['ordem_servico_id']) ?? 0,
      servico: _converterTexto(map['servico'], padrao: 'Serviço'),
      descricao: _converterTexto(map['descricao']),
      quantidade: _converterDouble(map['quantidade'], padrao: 1),
      valorUnitario: _converterDouble(map['valor_unitario']),
      ordem: _converterInt(map['ordem']) ?? 0,
      concluido: _converterBool(map['concluido']),
    );
  }

  OrdemServicoItem copyWith({
    int? id,
    int? ordemServicoId,
    String? servico,
    String? descricao,
    double? quantidade,
    double? valorUnitario,
    int? ordem,
    bool? concluido,
  }) {
    return OrdemServicoItem(
      id: id ?? this.id,
      ordemServicoId: ordemServicoId ?? this.ordemServicoId,
      servico: servico ?? this.servico,
      descricao: descricao ?? this.descricao,
      quantidade: quantidade ?? this.quantidade,
      valorUnitario: valorUnitario ?? this.valorUnitario,
      ordem: ordem ?? this.ordem,
      concluido: concluido ?? this.concluido,
    );
  }

  static int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString().trim());
  }

  static double _converterDouble(dynamic valor, {double padrao = 0}) {
    if (valor == null) {
      return padrao;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    final texto = valor
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.contains(',')) {
      return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ??
          padrao;
    }

    return double.tryParse(texto) ?? padrao;
  }

  static String _converterTexto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  static bool _converterBool(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = valor?.toString().trim().toLowerCase();

    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
