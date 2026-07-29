import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class ResumoFinanceiroPdf {
  const ResumoFinanceiroPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    required double subtotal,
    double desconto = 0,
    double acrescimo = 0,
    double valorPago = 0,
    double? totalInformado,
    String formaPagamento = '',
    String condicaoPagamento = '',
    bool mostrarSaldo = false,
    String titulo = 'RESUMO FINANCEIRO',
  }) {
    final totalCalculado =
        subtotal - desconto + acrescimo;

    final total = totalInformado ??
        (totalCalculado < 0
            ? 0
            : totalCalculado);

    final saldo = total - valorPago;

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.8,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          _criarTitulo(
            contexto: contexto,
            titulo: titulo,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Row(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _criarDadosPagamento(
                    formaPagamento:
                    formaPagamento,
                    condicaoPagamento:
                    condicaoPagamento,
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Container(
                  width: 205,
                  child: _criarValores(
                    contexto: contexto,
                    subtotal: subtotal,
                    desconto: desconto,
                    acrescimo: acrescimo,
                    total: total,
                    valorPago: valorPago,
                    saldo: saldo,
                    mostrarSaldo: mostrarSaldo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget criarPorMapa({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> dados,
    String titulo = 'RESUMO FINANCEIRO',
    bool mostrarSaldo = false,
  }) {
    final subtotal = _primeiroNumero(
      dados,
      [
        'subtotal',
        'valor_subtotal',
        'total_servicos',
      ],
    );

    final desconto = _primeiroNumero(
      dados,
      [
        'desconto',
        'valor_desconto',
      ],
    );

    final acrescimo = _primeiroNumero(
      dados,
      [
        'acrescimo',
        'valor_acrescimo',
        'taxa',
      ],
    );

    final total = _primeiroNumeroNullable(
      dados,
      [
        'total',
        'valor_total',
        'valor_final',
      ],
    );

    final valorPago = _primeiroNumero(
      dados,
      [
        'valor_pago',
        'pago',
        'entrada',
      ],
    );

    final formaPagamento = _primeiroTexto(
      dados,
      [
        'forma_pagamento',
        'pagamento',
        'metodo_pagamento',
      ],
    );

    final condicaoPagamento = _primeiroTexto(
      dados,
      [
        'condicao_pagamento',
        'parcelamento',
        'observacao_pagamento',
      ],
    );

    return criar(
      contexto: contexto,
      subtotal: subtotal,
      desconto: desconto,
      acrescimo: acrescimo,
      valorPago: valorPago,
      totalInformado: total,
      formaPagamento: formaPagamento,
      condicaoPagamento:
      condicaoPagamento,
      mostrarSaldo: mostrarSaldo,
      titulo: titulo,
    );
  }

  static pw.Widget _criarTitulo({
    required DocumentoPdfContexto contexto,
    required String titulo,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      decoration: pw.BoxDecoration(
        color: contexto.corPrincipal,
        borderRadius:
        const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(7),
          topRight: pw.Radius.circular(7),
        ),
      ),
      child: pw.Text(
        titulo.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  static pw.Widget _criarDadosPagamento({
    required String formaPagamento,
    required String condicaoPagamento,
  }) {
    final possuiDados =
        formaPagamento.trim().isNotEmpty ||
            condicaoPagamento
                .trim()
                .isNotEmpty;

    if (!possuiDados) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius:
          pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          'Forma de pagamento não informada.',
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey600,
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        if (formaPagamento
            .trim()
            .isNotEmpty)
          _criarCampoPagamento(
            rotulo: 'Forma de pagamento',
            valor: formaPagamento.trim(),
          ),
        if (formaPagamento
            .trim()
            .isNotEmpty &&
            condicaoPagamento
                .trim()
                .isNotEmpty)
          pw.SizedBox(height: 11),
        if (condicaoPagamento
            .trim()
            .isNotEmpty)
          _criarCampoPagamento(
            rotulo: 'Condição de pagamento',
            valor: condicaoPagamento.trim(),
          ),
      ],
    );
  }

  static pw.Widget _criarCampoPagamento({
    required String rotulo,
    required String valor,
  }) {
    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          rotulo.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: PdfColors.grey600,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey900,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _criarValores({
    required DocumentoPdfContexto contexto,
    required double subtotal,
    required double desconto,
    required double acrescimo,
    required double total,
    required double valorPago,
    required double saldo,
    required bool mostrarSaldo,
  }) {
    return pw.Column(
      children: [
        _criarLinhaValor(
          rotulo: 'Subtotal',
          valor: subtotal,
        ),
        if (desconto > 0) ...[
          pw.SizedBox(height: 7),
          _criarLinhaValor(
            rotulo: 'Desconto',
            valor: -desconto,
            corValor: PdfColors.green700,
          ),
        ],
        if (acrescimo > 0) ...[
          pw.SizedBox(height: 7),
          _criarLinhaValor(
            rotulo: 'Acréscimo',
            valor: acrescimo,
            corValor: PdfColors.orange700,
          ),
        ],
        pw.SizedBox(height: 9),
        pw.Divider(
          color: PdfColors.grey300,
          thickness: 0.7,
        ),
        pw.SizedBox(height: 8),
        _criarLinhaTotal(
          contexto: contexto,
          total: total,
        ),
        if (valorPago > 0) ...[
          pw.SizedBox(height: 9),
          _criarLinhaValor(
            rotulo: 'Valor pago',
            valor: valorPago,
            corValor: PdfColors.green700,
          ),
        ],
        if (mostrarSaldo) ...[
          pw.SizedBox(height: 7),
          _criarLinhaValor(
            rotulo: saldo > 0
                ? 'Saldo pendente'
                : 'Saldo',
            valor: saldo < 0 ? 0 : saldo,
            destaque: true,
            corValor: saldo > 0
                ? PdfColors.red700
                : PdfColors.green700,
          ),
        ],
      ],
    );
  }

  static pw.Widget _criarLinhaValor({
    required String rotulo,
    required double valor,
    bool destaque = false,
    PdfColor? corValor,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            rotulo,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
              fontWeight: destaque
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Text(
          _formatarMoeda(valor),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 8.5,
            color:
            corValor ?? PdfColors.grey900,
            fontWeight: destaque
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  static pw.Widget _criarLinhaTotal({
    required DocumentoPdfContexto contexto,
    required double total,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: pw.BoxDecoration(
        color: contexto.corSecundaria,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: contexto.corPrincipal,
          width: 0.8,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'TOTAL',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.7,
              ),
            ),
          ),
          pw.Text(
            _formatarMoeda(total),
            style: pw.TextStyle(
              fontSize: 13,
              color: contexto.corPrincipal,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static String _primeiroTexto(
      Map<dynamic, dynamic> mapa,
      List<String> chaves,
      ) {
    for (final chave in chaves) {
      final valor =
      (mapa[chave] ?? '').toString().trim();

      if (valor.isNotEmpty &&
          valor.toLowerCase() != 'null') {
        return valor;
      }
    }

    return '';
  }

  static double _primeiroNumero(
      Map<dynamic, dynamic> mapa,
      List<String> chaves,
      ) {
    return _primeiroNumeroNullable(
      mapa,
      chaves,
    ) ??
        0;
  }

  static double? _primeiroNumeroNullable(
      Map<dynamic, dynamic> mapa,
      List<String> chaves,
      ) {
    for (final chave in chaves) {
      final valor = mapa[chave];

      if (valor == null) {
        continue;
      }

      if (valor is num) {
        return valor.toDouble();
      }

      final convertido = _converterNumero(
        valor.toString(),
      );

      if (convertido != null) {
        return convertido;
      }
    }

    return null;
  }

  static double? _converterNumero(
      String valor,
      ) {
    var texto = valor.trim();

    if (texto.isEmpty ||
        texto.toLowerCase() == 'null') {
      return null;
    }

    texto = texto
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.contains(',') &&
        texto.contains('.')) {
      texto = texto
          .replaceAll('.', '')
          .replaceAll(',', '.');
    } else if (texto.contains(',')) {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto);
  }

  static String _formatarMoeda(
      double valor,
      ) {
    final negativo = valor < 0;
    final absoluto = valor.abs();

    final partes =
    absoluto.toStringAsFixed(2).split('.');

    final inteiro = partes[0];
    final decimal = partes[1];

    final buffer = StringBuffer();

    for (var indice = 0;
    indice < inteiro.length;
    indice++) {
      final posicaoRestante =
          inteiro.length - indice;

      buffer.write(inteiro[indice]);

      if (posicaoRestante > 1 &&
          posicaoRestante % 3 == 1) {
        buffer.write('.');
      }
    }

    final sinal = negativo ? '- ' : '';

    return '${sinal}R\$ ${buffer.toString()},$decimal';
  }
}