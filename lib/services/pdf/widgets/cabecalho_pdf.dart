import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/configuracao.dart';
import '../documento_pdf_service.dart';

class CabecalhoPdf {
  const CabecalhoPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    required String tipoDocumento,
    required String numeroDocumento,
    String status = '',
    String subtitulo = 'ESTÉTICA AUTOMOTIVA',
    bool mostrarQrCode = true,
  }) {
    final configuracao = contexto.configuracao;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: contexto.corSecundaria,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: contexto.corPrincipal, width: 1.2),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _criarLogo(contexto: contexto),
          pw.SizedBox(width: 15),
          pw.Expanded(
            child: _criarDadosEmpresa(
              contexto: contexto,
              configuracao: configuracao,
              subtitulo: subtitulo,
            ),
          ),
          pw.SizedBox(width: 15),
          _criarDadosDocumento(
            contexto: contexto,
            tipoDocumento: tipoDocumento,
            numeroDocumento: numeroDocumento,
            status: status,
            mostrarQrCode: mostrarQrCode,
          ),
        ],
      ),
    );
  }

  static pw.Widget criarCabecalhoPaginasSeguintes({
    required DocumentoPdfContexto contexto,
    required String tipoDocumento,
    required String numeroDocumento,
  }) {
    final nomeEmpresa = _nomeEmpresa(contexto.configuracao);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.7),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (contexto.logo != null) ...[
            pw.Container(
              width: 28,
              height: 28,
              padding: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(5),
                border: pw.Border.all(color: contexto.corPrincipal, width: 0.6),
              ),
              child: pw.Image(contexto.logo!, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 8),
          ],
          pw.Expanded(
            child: pw.Text(
              nomeEmpresa.toUpperCase(),
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Text(
            _tituloDocumento(
              tipoDocumento: tipoDocumento,
              numeroDocumento: numeroDocumento,
            ),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _criarLogo({required DocumentoPdfContexto contexto}) {
    return pw.Container(
      width: 78,
      height: 78,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: contexto.corPrincipal, width: 1),
      ),
      child: contexto.logo != null
          ? pw.Image(contexto.logo!, fit: pw.BoxFit.contain)
          : pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'ID',
                    style: pw.TextStyle(
                      fontSize: 23,
                      fontWeight: pw.FontWeight.bold,
                      color: contexto.corPrincipal,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'IMPERIUM',
                    style: pw.TextStyle(
                      fontSize: 5.5,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static pw.Widget _criarDadosEmpresa({
    required DocumentoPdfContexto contexto,
    required Configuracao configuracao,
    required String subtitulo,
  }) {
    final nome = _nomeEmpresa(configuracao);
    final linhas = _dadosEmpresa(configuracao);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          nome.toUpperCase(),
          maxLines: 2,
          style: pw.TextStyle(
            fontSize: 19,
            fontWeight: pw.FontWeight.bold,
            color: contexto.corPrincipal,
            letterSpacing: 1,
          ),
        ),
        if (subtitulo.trim().isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            subtitulo.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey300,
              letterSpacing: 1.3,
            ),
          ),
        ],
        if (linhas.isNotEmpty) ...[
          pw.SizedBox(height: 9),
          ...linhas.map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                linha,
                maxLines: 2,
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey300,
                  lineSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _criarDadosDocumento({
    required DocumentoPdfContexto contexto,
    required String tipoDocumento,
    required String numeroDocumento,
    required String status,
    required bool mostrarQrCode,
  }) {
    final possuiWhatsApp = _possuiWhatsApp(contexto.configuracao);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          tipoDocumento.toUpperCase(),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        if (numeroDocumento.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Nº ${numeroDocumento.trim()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey300),
          ),
        ],
        if (status.trim().isNotEmpty) ...[
          pw.SizedBox(height: 7),
          _criarStatus(status),
        ],
        if (mostrarQrCode && possuiWhatsApp) ...[
          pw.SizedBox(height: 9),
          _criarQrCode(contexto: contexto),
        ],
      ],
    );
  }

  static pw.Widget _criarStatus(String status) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _corStatus(status),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        status.toUpperCase(),
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 6.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _criarQrCode({required DocumentoPdfContexto contexto}) {
    final numero = _numeroWhatsApp(contexto.configuracao);

    if (numero.isEmpty) {
      return pw.SizedBox();
    }

    final link = 'https://wa.me/$numero';

    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: link,
            width: 42,
            height: 42,
            color: PdfColors.black,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'WhatsApp',
            style: pw.TextStyle(
              fontSize: 5.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _dadosEmpresa(Configuracao configuracao) {
    final linhas = <String>[];

    if (configuracao.razaoSocial.trim().isNotEmpty) {
      linhas.add(configuracao.razaoSocial.trim());
    }

    final registros = <String>[];

    if (configuracao.cnpj.trim().isNotEmpty) {
      registros.add('CNPJ: ${configuracao.cnpj.trim()}');
    }

    if (configuracao.inscricaoEstadual.trim().isNotEmpty) {
      registros.add('IE: ${configuracao.inscricaoEstadual.trim()}');
    }

    if (registros.isNotEmpty) {
      linhas.add(registros.join(' • '));
    }

    if (configuracao.enderecoCompleto.trim().isNotEmpty) {
      linhas.add(configuracao.enderecoCompleto.trim());
    }

    final contatos = <String>[];

    if (configuracao.telefone.trim().isNotEmpty) {
      contatos.add('Tel.: ${configuracao.telefone.trim()}');
    }

    if (configuracao.whatsapp.trim().isNotEmpty &&
        configuracao.whatsapp.trim() != configuracao.telefone.trim()) {
      contatos.add('WhatsApp: ${configuracao.whatsapp.trim()}');
    }

    if (contatos.isNotEmpty) {
      linhas.add(contatos.join(' • '));
    }

    final digitais = <String>[];

    if (configuracao.email.trim().isNotEmpty) {
      digitais.add(configuracao.email.trim());
    }

    if (configuracao.site.trim().isNotEmpty) {
      digitais.add(configuracao.site.trim());
    }

    if (configuracao.instagram.trim().isNotEmpty) {
      var instagram = configuracao.instagram.trim();

      if (!instagram.startsWith('@')) {
        instagram = '@$instagram';
      }

      digitais.add(instagram);
    }

    if (configuracao.facebook.trim().isNotEmpty) {
      digitais.add(configuracao.facebook.trim());
    }

    if (digitais.isNotEmpty) {
      linhas.add(digitais.join(' • '));
    }

    return linhas;
  }

  static String _nomeEmpresa(Configuracao configuracao) {
    final nome = configuracao.nomeFantasia.trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    return 'Imperium Detailing';
  }

  static bool _possuiWhatsApp(Configuracao configuracao) {
    return configuracao.whatsapp.trim().isNotEmpty ||
        configuracao.telefone.trim().isNotEmpty;
  }

  static String _numeroWhatsApp(Configuracao configuracao) {
    final telefone = configuracao.whatsapp.trim().isNotEmpty
        ? configuracao.whatsapp
        : configuracao.telefone;

    var numero = telefone.replaceAll(RegExp(r'[^0-9]'), '');

    if (numero.isEmpty) {
      return '';
    }

    if (numero.startsWith('00')) {
      numero = numero.substring(2);
    }

    if (!numero.startsWith('55')) {
      numero = '55$numero';
    }

    return numero;
  }

  static String _tituloDocumento({
    required String tipoDocumento,
    required String numeroDocumento,
  }) {
    final tipo = tipoDocumento.trim().isEmpty
        ? 'Documento'
        : tipoDocumento.trim();

    if (numeroDocumento.trim().isEmpty) {
      return tipo;
    }

    return '$tipo #${numeroDocumento.trim()}';
  }

  static PdfColor _corStatus(String status) {
    final valor = status.trim().toLowerCase();

    switch (valor) {
      case 'aprovado':
      case 'pago':
      case 'concluído':
      case 'concluido':
      case 'finalizado':
        return PdfColors.green700;

      case 'recusado':
      case 'cancelado':
      case 'vencido':
        return PdfColors.red700;

      case 'pendente':
      case 'aguardando':
      case 'em aberto':
        return PdfColors.orange700;

      case 'em andamento':
      case 'em execução':
      case 'em execucao':
        return PdfColors.blue700;

      default:
        return PdfColors.grey700;
    }
  }
}
