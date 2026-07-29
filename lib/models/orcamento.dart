import 'item_orcamento.dart';

class Orcamento {
  final int? id;
  final int clienteId;
  final int? veiculoId;

  // Campos antigos mantidos temporariamente
  // para compatibilidade com as telas atuais.
  final String servico;
  final String descricao;
  final double valor;

  final String dataEmissao;
  final String validade;
  final String status;
  final String observacoes;
  final double desconto;

  // Lista dos serviços do orçamento.
  final List<ItemOrcamento> itens;

  const Orcamento({
    this.id,
    required this.clienteId,
    this.veiculoId,
    this.servico = '',
    this.descricao = '',
    this.valor = 0,
    required this.dataEmissao,
    required this.validade,
    this.status = 'Pendente',
    this.observacoes = '',
    this.desconto = 0,
    this.itens = const [],
  });

  double get subtotal {
    if (itens.isNotEmpty) {
      return itens.fold<double>(
        0,
            (total, item) => total + item.subtotal,
      );
    }

    return valor;
  }

  double get valorTotal {
    final total = subtotal - desconto;

    if (total < 0) {
      return 0;
    }

    return total;
  }

  int get quantidadeItens => itens.length;

  bool get possuiItens => itens.isNotEmpty;

  Orcamento copyWith({
    int? id,
    int? clienteId,
    int? veiculoId,
    bool removerVeiculo = false,
    String? servico,
    String? descricao,
    double? valor,
    String? dataEmissao,
    String? validade,
    String? status,
    String? observacoes,
    double? desconto,
    List<ItemOrcamento>? itens,
  }) {
    return Orcamento(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      veiculoId: removerVeiculo
          ? null
          : veiculoId ?? this.veiculoId,
      servico: servico ?? this.servico,
      descricao: descricao ?? this.descricao,
      valor: valor ?? this.valor,
      dataEmissao:
      dataEmissao ?? this.dataEmissao,
      validade: validade ?? this.validade,
      status: status ?? this.status,
      observacoes:
      observacoes ?? this.observacoes,
      desconto: desconto ?? this.desconto,
      itens: itens ?? this.itens,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'servico': servico,
      'descricao': descricao,
      'valor': valorTotal,
      'data_emissao': dataEmissao,
      'validade': validade,
      'status': status,
      'observacoes': observacoes,
      'desconto': desconto,
    };
  }

  factory Orcamento.fromMap(
      Map<String, dynamic> map, {
        List<ItemOrcamento> itens = const [],
      }) {
    return Orcamento(
      id: _converterInt(map['id']),
      clienteId:
      _converterInt(map['cliente_id']) ?? 0,
      veiculoId:
      _converterInt(map['veiculo_id']),
      servico:
      map['servico']?.toString() ?? '',
      descricao:
      map['descricao']?.toString() ?? '',
      valor: _converterDouble(
        map['valor'],
        0,
      ),
      dataEmissao:
      map['data_emissao']?.toString() ?? '',
      validade:
      map['validade']?.toString() ?? '',
      status:
      map['status']?.toString() ??
          'Pendente',
      observacoes:
      map['observacoes']?.toString() ?? '',
      desconto: _converterDouble(
        map['desconto'],
        0,
      ),
      itens: itens,
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

    return int.tryParse(valor.toString());
  }

  static double _converterDouble(
      dynamic valor,
      double padrao,
      ) {
    if (valor == null) {
      return padrao;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
      valor.toString().replaceAll(',', '.'),
    ) ??
        padrao;
  }
}