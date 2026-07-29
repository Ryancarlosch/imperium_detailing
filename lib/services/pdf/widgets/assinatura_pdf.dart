import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class AssinaturaPdf {
  const AssinaturaPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    String nomeCliente = '',
    String nomeResponsavel = '',
    String documentoCliente = '',
    String documentoResponsavel = '',
    String tituloCliente = 'ASSINATURA DO CLIENTE',
    String tituloResponsavel = 'RESPONSÁVEL PELA EMPRESA',
    String local = '',
    String data = '',
    bool mostrarCliente = true,
    bool mostrarResponsavel = true,
    bool mostrarDataLocal = true,
  }) {
    if (!mostrarCliente && !mostrarResponsavel) {
      return pw.SizedBox();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (mostrarDataLocal)
          _criarDataLocal(
            local: local,
            data: data,
          ),
        if (mostrarDataLocal)
          pw.SizedBox(height: 34),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (mostrarCliente)
              pw.Expanded(
                child: _criarAssinatura(
                  contexto: contexto,
                  titulo: tituloCliente,
                  nome: nomeCliente,
                  documento: documentoCliente,
                ),
              ),
            if (mostrarCliente && mostrarResponsavel)
              pw.SizedBox(width: 34),
            if (mostrarResponsavel)
              pw.Expanded(
                child: _criarAssinatura(
                  contexto: contexto,
                  titulo: tituloResponsavel,
                  nome: nomeResponsavel,
                  documento: documentoResponsavel,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget criarCliente({
    required DocumentoPdfContexto contexto,
    String nomeCliente = '',
    String documentoCliente = '',
    String titulo = 'ASSINATURA DO CLIENTE',
    String local = '',
    String data = '',
    bool mostrarDataLocal = true,
  }) {
    return criar(
      contexto: contexto,
      nomeCliente: nomeCliente,
      documentoCliente: documentoCliente,
      tituloCliente: titulo,
      local: local,
      data: data,
      mostrarCliente: true,
      mostrarResponsavel: false,
      mostrarDataLocal: mostrarDataLocal,
    );
  }

  static pw.Widget criarResponsavel({
    required DocumentoPdfContexto contexto,
    String nomeResponsavel = '',
    String documentoResponsavel = '',
    String titulo = 'RESPONSÁVEL PELA EMPRESA',
    String local = '',
    String data = '',
    bool mostrarDataLocal = true,
  }) {
    return criar(
      contexto: contexto,
      nomeResponsavel: nomeResponsavel,
      documentoResponsavel: documentoResponsavel,
      tituloResponsavel: titulo,
      local: local,
      data: data,
      mostrarCliente: false,
      mostrarResponsavel: true,
      mostrarDataLocal: mostrarDataLocal,
    );
  }

  static pw.Widget criarPorMapas({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> cliente,
    Map<dynamic, dynamic>? empresa,
    String local = '',
    String data = '',
    bool mostrarCliente = true,
    bool mostrarResponsavel = true,
    bool mostrarDataLocal = true,
  }) {
    final nomeCliente = _primeiroTexto(
      cliente,
      [
        'nome',
        'cliente_nome',
        'nome_cliente',
        'razao_social',
      ],
    );

    final documentoCliente = _primeiroTexto(
      cliente,
      [
        'cpf_cnpj',
        'cpf',
        'cnpj',
        'documento',
        'cliente_cpf_cnpj',
      ],
    );

    final nomeResponsavel = _primeiroTexto(
      empresa ?? const {},
      [
        'responsavel',
        'nome_responsavel',
        'proprietario',
        'nome_proprietario',
        'empresa_responsavel',
      ],
      padrao: contexto.nomeEmpresa,
    );

    final documentoResponsavel = _primeiroTexto(
      empresa ?? const {},
      [
        'cpf_responsavel',
        'documento_responsavel',
        'cnpj',
        'empresa_cnpj',
      ],
    );

    return criar(
      contexto: contexto,
      nomeCliente: nomeCliente,
      nomeResponsavel: nomeResponsavel,
      documentoCliente: documentoCliente,
      documentoResponsavel: documentoResponsavel,
      local: local,
      data: data,
      mostrarCliente: mostrarCliente,
      mostrarResponsavel: mostrarResponsavel,
      mostrarDataLocal: mostrarDataLocal,
    );
  }

  static pw.Widget _criarDataLocal({
    required String local,
    required String data,
  }) {
    final localLimpo = local.trim();
    final dataLimpa = data.trim();

    if (localLimpo.isEmpty && dataLimpa.isEmpty) {
      return pw.SizedBox();
    }

    final partes = <String>[];

    if (localLimpo.isNotEmpty) {
      partes.add(localLimpo);
    }

    if (dataLimpa.isNotEmpty) {
      partes.add(dataLimpa);
    }

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        partes.join(', '),
        style: const pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  static pw.Widget _criarAssinatura({
    required DocumentoPdfContexto contexto,
    required String titulo,
    required String nome,
    required String documento,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 44,
          alignment: pw.Alignment.bottomCenter,
          child: pw.Container(
            width: double.infinity,
            height: 0.8,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          titulo.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7,
            color: contexto.corSecundaria,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        if (nome.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            nome.trim(),
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey900,
            ),
          ),
        ],
        if (documento.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            _formatarDocumento(documento),
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ],
    );
  }

  static String _primeiroTexto(
      Map<dynamic, dynamic> mapa,
      List<String> chaves, {
        String padrao = '',
      }) {
    for (final chave in chaves) {
      final valor =
      (mapa[chave] ?? '').toString().trim();

      if (valor.isNotEmpty &&
          valor.toLowerCase() != 'null') {
        return valor;
      }
    }

    return padrao.trim();
  }

  static String _formatarDocumento(
      String documento,
      ) {
    final texto = documento.trim();

    if (texto.isEmpty) {
      return '';
    }

    final numeros = texto.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (numeros.length == 11) {
      return 'CPF: ${numeros.substring(0, 3)}.'
          '${numeros.substring(3, 6)}.'
          '${numeros.substring(6, 9)}-'
          '${numeros.substring(9, 11)}';
    }

    if (numeros.length == 14) {
      return 'CNPJ: ${numeros.substring(0, 2)}.'
          '${numeros.substring(2, 5)}.'
          '${numeros.substring(5, 8)}/'
          '${numeros.substring(8, 12)}-'
          '${numeros.substring(12, 14)}';
    }

    return texto;
  }
}