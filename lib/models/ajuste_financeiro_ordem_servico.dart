class AjusteFinanceiroOrdemServico {
  const AjusteFinanceiroOrdemServico({
    this.id,
    required this.ordemServicoId,
    required this.tipo,
    required this.valor,
    required this.motivo,
    this.status = 'Ativo',
    required this.criadoEm,
    this.canceladoEm,
    this.motivoCancelamento = '',
  });

  final int? id;
  final int ordemServicoId;
  final String tipo;
  final double valor;
  final String motivo;
  final String status;
  final String criadoEm;
  final String? canceladoEm;
  final String motivoCancelamento;

  bool get estaAtivo => status == 'Ativo';
  bool get estaCancelado => status == 'Cancelado';
  bool get ehDesconto => tipo == 'Desconto';
  bool get ehAcrescimo => tipo == 'Acréscimo';
  bool get ehJuros => tipo == 'Juros';

  double get impactoNoTotal => ehDesconto ? -valor : valor;

  factory AjusteFinanceiroOrdemServico.fromMap(Map<String, dynamic> map) {
    return AjusteFinanceiroOrdemServico(
      id: _int(map['id']),
      ordemServicoId: _int(map['ordem_servico_id']) ?? 0,
      tipo: _texto(map['tipo']),
      valor: _double(map['valor']),
      motivo: _texto(map['motivo']),
      status: _texto(map['status'], padrao: 'Ativo'),
      criadoEm: _texto(map['criado_em']),
      canceladoEm: _textoNulo(map['cancelado_em']),
      motivoCancelamento: _texto(map['motivo_cancelamento']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ordem_servico_id': ordemServicoId,
      'tipo': tipo,
      'valor': valor,
      'motivo': motivo,
      'status': status,
      'criado_em': criadoEm,
      'cancelado_em': canceladoEm,
      'motivo_cancelamento': motivoCancelamento,
    };
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String _texto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? padrao : texto;
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
