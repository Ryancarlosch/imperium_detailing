class OrdemServico {
  const OrdemServico({
    this.id,
    this.orcamentoId,
    this.agendamentoId,
    required this.clienteId,
    this.veiculoId,
    required this.numero,
    required this.status,
    required this.dataAbertura,
    this.dataInicio,
    this.dataFinalizacao,
    this.horaEntrada,
    this.horaSaida,
    this.funcionarioResponsavel = '',
    this.observacoes = '',
    this.valorTotal = 0,
    this.desconto = 0,
    this.formaPagamento,
    this.quilometragemEntrada = '',
    this.combustivelEntrada = '',
    this.assinaturaCliente,
    this.lancadoFinanceiro = false,
  });

  final int? id;
  final int? orcamentoId;
  final int? agendamentoId;
  final int clienteId;
  final int? veiculoId;
  final String numero;
  final String status;
  final String dataAbertura;
  final String? dataInicio;
  final String? dataFinalizacao;
  final String? horaEntrada;
  final String? horaSaida;
  final String funcionarioResponsavel;
  final String observacoes;
  final double valorTotal;
  final double desconto;
  final String? formaPagamento;
  final String quilometragemEntrada;
  final String combustivelEntrada;
  final String? assinaturaCliente;
  final bool lancadoFinanceiro;

  double get valorFinal {
    final resultado = valorTotal - desconto;

    if (resultado < 0) {
      return 0;
    }

    return resultado;
  }

  bool get estaAberta {
    return status == 'Aberta';
  }

  bool get estaEmAndamento {
    return status == 'Em andamento';
  }

  bool get estaFinalizada {
    return status == 'Finalizada';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orcamento_id': orcamentoId,
      'agendamento_id': agendamentoId,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'numero': numero,
      'status': status,
      'data_abertura': dataAbertura,
      'data_inicio': dataInicio,
      'data_finalizacao': dataFinalizacao,
      'hora_entrada': horaEntrada,
      'hora_saida': horaSaida,
      'funcionario_responsavel': funcionarioResponsavel,
      'observacoes': observacoes,
      'valor_total': valorTotal,
      'desconto': desconto,
      'forma_pagamento': formaPagamento,
      'quilometragem_entrada': quilometragemEntrada,
      'combustivel_entrada': combustivelEntrada,
      'assinatura_cliente': assinaturaCliente,
      'lancado_financeiro': lancadoFinanceiro ? 1 : 0,
    };
  }

  factory OrdemServico.fromMap(Map<String, dynamic> map) {
    return OrdemServico(
      id: _converterInt(map['id']),
      orcamentoId: _converterInt(map['orcamento_id']),
      agendamentoId: _converterInt(map['agendamento_id']),
      clienteId: _converterInt(map['cliente_id']) ?? 0,
      veiculoId: _converterInt(map['veiculo_id']),
      numero: _converterTexto(map['numero']),
      status: _converterTexto(map['status'], padrao: 'Aberta'),
      dataAbertura: _converterTexto(map['data_abertura']),
      dataInicio: _converterTextoNulo(map['data_inicio']),
      dataFinalizacao: _converterTextoNulo(map['data_finalizacao']),
      horaEntrada: _converterTextoNulo(map['hora_entrada']),
      horaSaida: _converterTextoNulo(map['hora_saida']),
      funcionarioResponsavel: _converterTexto(map['funcionario_responsavel']),
      observacoes: _converterTexto(map['observacoes']),
      valorTotal: _converterDouble(map['valor_total']),
      desconto: _converterDouble(map['desconto']),
      formaPagamento: _converterTextoNulo(map['forma_pagamento']),
      quilometragemEntrada: _converterTexto(map['quilometragem_entrada']),
      combustivelEntrada: _converterTexto(map['combustivel_entrada']),
      assinaturaCliente: _converterTextoNulo(map['assinatura_cliente']),
      lancadoFinanceiro: _converterBool(map['lancado_financeiro']),
    );
  }

  OrdemServico copyWith({
    int? id,
    int? orcamentoId,
    bool removerOrcamentoId = false,
    int? agendamentoId,
    bool removerAgendamentoId = false,
    int? clienteId,
    int? veiculoId,
    bool removerVeiculoId = false,
    String? numero,
    String? status,
    String? dataAbertura,
    String? dataInicio,
    bool removerDataInicio = false,
    String? dataFinalizacao,
    bool removerDataFinalizacao = false,
    String? horaEntrada,
    bool removerHoraEntrada = false,
    String? horaSaida,
    bool removerHoraSaida = false,
    String? funcionarioResponsavel,
    String? observacoes,
    double? valorTotal,
    double? desconto,
    String? formaPagamento,
    bool removerFormaPagamento = false,
    String? quilometragemEntrada,
    String? combustivelEntrada,
    String? assinaturaCliente,
    bool removerAssinaturaCliente = false,
    bool? lancadoFinanceiro,
  }) {
    return OrdemServico(
      id: id ?? this.id,
      orcamentoId: removerOrcamentoId ? null : orcamentoId ?? this.orcamentoId,
      agendamentoId: removerAgendamentoId
          ? null
          : agendamentoId ?? this.agendamentoId,
      clienteId: clienteId ?? this.clienteId,
      veiculoId: removerVeiculoId ? null : veiculoId ?? this.veiculoId,
      numero: numero ?? this.numero,
      status: status ?? this.status,
      dataAbertura: dataAbertura ?? this.dataAbertura,
      dataInicio: removerDataInicio ? null : dataInicio ?? this.dataInicio,
      dataFinalizacao: removerDataFinalizacao
          ? null
          : dataFinalizacao ?? this.dataFinalizacao,
      horaEntrada: removerHoraEntrada ? null : horaEntrada ?? this.horaEntrada,
      horaSaida: removerHoraSaida ? null : horaSaida ?? this.horaSaida,
      funcionarioResponsavel:
          funcionarioResponsavel ?? this.funcionarioResponsavel,
      observacoes: observacoes ?? this.observacoes,
      valorTotal: valorTotal ?? this.valorTotal,
      desconto: desconto ?? this.desconto,
      formaPagamento: removerFormaPagamento
          ? null
          : formaPagamento ?? this.formaPagamento,
      quilometragemEntrada: quilometragemEntrada ?? this.quilometragemEntrada,
      combustivelEntrada: combustivelEntrada ?? this.combustivelEntrada,
      assinaturaCliente: removerAssinaturaCliente
          ? null
          : assinaturaCliente ?? this.assinaturaCliente,
      lancadoFinanceiro: lancadoFinanceiro ?? this.lancadoFinanceiro,
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

  static double _converterDouble(dynamic valor) {
    if (valor == null) {
      return 0;
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
      return 0;
    }

    if (texto.contains(',')) {
      return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }

    return double.tryParse(texto) ?? 0;
  }

  static String _converterTexto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  static String? _converterTextoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return null;
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
