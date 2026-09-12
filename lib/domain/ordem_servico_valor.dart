/// Contrato monetario unico da Ordem de Servico.
///
/// Regra oficial:
/// 1. base = max(valor_total - desconto, 0)
/// 2. negociado = max(
///      base
///      - desconto_negociacao
///      + acrescimo_negociacao
///      + juros_parcelamento,
///      0,
///    )
class OrdemServicoValor {
  const OrdemServicoValor._();

  static double valorBase({required double valorTotal, double desconto = 0}) {
    return (valorTotal - desconto).clamp(0, double.infinity).toDouble();
  }

  static double valorNegociado({
    required double valorTotal,
    double desconto = 0,
    double descontoNegociacao = 0,
    double acrescimoNegociacao = 0,
    double jurosParcelamento = 0,
  }) {
    final base = valorBase(valorTotal: valorTotal, desconto: desconto);

    return (base - descontoNegociacao + acrescimoNegociacao + jurosParcelamento)
        .clamp(0, double.infinity)
        .toDouble();
  }

  static double valorBaseDeMapa(Map<String, Object?> ordem) {
    return valorBase(
      valorTotal: _double(ordem['valor_total']),
      desconto: _double(ordem['desconto']),
    );
  }

  static double valorNegociadoDeMapa(Map<String, Object?> ordem) {
    return valorNegociado(
      valorTotal: _double(ordem['valor_total']),
      desconto: _double(ordem['desconto']),
      descontoNegociacao: _double(ordem['desconto_negociacao']),
      acrescimoNegociacao: _double(ordem['acrescimo_negociacao']),
      jurosParcelamento: _double(ordem['juros_parcelamento']),
    );
  }

  static String sqlValorNegociado({String alias = ''}) {
    final aliasLimpo = alias.trim();

    if (aliasLimpo.isNotEmpty &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(aliasLimpo)) {
      throw ArgumentError.value(alias, 'alias', 'Alias SQL invalido.');
    }

    final prefixo = aliasLimpo.isEmpty ? '' : '$aliasLimpo.';

    return '''
MAX(
  MAX(
    COALESCE(${prefixo}valor_total, 0)
    - COALESCE(${prefixo}desconto, 0),
    0
  )
  - COALESCE(${prefixo}desconto_negociacao, 0)
  + COALESCE(${prefixo}acrescimo_negociacao, 0)
  + COALESCE(${prefixo}juros_parcelamento, 0),
  0
)''';
  }

  static double _double(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }
}
