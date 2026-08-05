import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class ObservacoesPdf {
  const ObservacoesPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    String observacoes = '',
    String termos = '',
    String mensagemAgradecimento = '',
    String tituloObservacoes = 'OBSERVAÇÕES',
    String tituloTermos = 'TERMOS E CONDIÇÕES',
    bool mostrarMesmoVazio = false,
  }) {
    final possuiObservacoes = observacoes.trim().isNotEmpty;

    final possuiTermos = termos.trim().isNotEmpty;

    final possuiAgradecimento = mensagemAgradecimento.trim().isNotEmpty;

    if (!mostrarMesmoVazio &&
        !possuiObservacoes &&
        !possuiTermos &&
        !possuiAgradecimento) {
      return pw.SizedBox();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (possuiObservacoes || mostrarMesmoVazio)
          _criarBloco(
            contexto: contexto,
            titulo: tituloObservacoes,
            texto: possuiObservacoes
                ? observacoes.trim()
                : 'Nenhuma observação informada.',
          ),
        if ((possuiObservacoes || mostrarMesmoVazio) && possuiTermos)
          pw.SizedBox(height: 12),
        if (possuiTermos)
          _criarBloco(
            contexto: contexto,
            titulo: tituloTermos,
            texto: termos.trim(),
            estiloTermos: true,
          ),
        if ((possuiObservacoes || possuiTermos || mostrarMesmoVazio) &&
            possuiAgradecimento)
          pw.SizedBox(height: 12),
        if (possuiAgradecimento)
          _criarAgradecimento(
            contexto: contexto,
            mensagem: mensagemAgradecimento.trim(),
          ),
      ],
    );
  }

  static pw.Widget criarObservacoes({
    required DocumentoPdfContexto contexto,
    required String observacoes,
    String titulo = 'OBSERVAÇÕES',
    bool mostrarMesmoVazio = false,
  }) {
    return criar(
      contexto: contexto,
      observacoes: observacoes,
      tituloObservacoes: titulo,
      mostrarMesmoVazio: mostrarMesmoVazio,
    );
  }

  static pw.Widget criarTermos({
    required DocumentoPdfContexto contexto,
    required String termos,
    String titulo = 'TERMOS E CONDIÇÕES',
  }) {
    return criar(contexto: contexto, termos: termos, tituloTermos: titulo);
  }

  static pw.Widget criarAgradecimento({
    required DocumentoPdfContexto contexto,
    required String mensagem,
  }) {
    if (mensagem.trim().isEmpty) {
      return pw.SizedBox();
    }

    return _criarAgradecimento(contexto: contexto, mensagem: mensagem.trim());
  }

  static pw.Widget criarPorMapa({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> dados,
    String termosPadrao = '',
    String agradecimentoPadrao = '',
    bool mostrarMesmoVazio = false,
  }) {
    final observacoes = _primeiroTexto(dados, [
      'observacoes',
      'observacao',
      'descricao_observacao',
      'anotacoes',
      'detalhes',
    ]);

    final termos = _primeiroTexto(dados, [
      'termos',
      'termos_condicoes',
      'condicoes',
      'condicoes_gerais',
    ], padrao: termosPadrao);

    final agradecimento = _primeiroTexto(dados, [
      'mensagem_agradecimento',
      'agradecimento',
      'mensagem_final',
    ], padrao: agradecimentoPadrao);

    return criar(
      contexto: contexto,
      observacoes: observacoes,
      termos: termos,
      mensagemAgradecimento: agradecimento,
      mostrarMesmoVazio: mostrarMesmoVazio,
    );
  }

  static pw.Widget _criarBloco({
    required DocumentoPdfContexto contexto,
    required String titulo,
    required String texto,
    bool estiloTermos = false,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _criarTitulo(contexto: contexto, titulo: titulo),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: estiloTermos
                ? _criarTextoTermos(texto)
                : _criarTextoNormal(texto),
          ),
        ],
      ),
    );
  }

  static pw.Widget _criarTitulo({
    required DocumentoPdfContexto contexto,
    required String titulo,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: pw.BoxDecoration(
        color: contexto.corPrincipal,
        borderRadius: const pw.BorderRadius.only(
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

  static pw.Widget _criarTextoNormal(String texto) {
    final paragrafos = _separarParagrafos(texto);

    if (paragrafos.isEmpty) {
      return pw.Text(
        'Nenhuma informação cadastrada.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: paragrafos.map((paragrafo) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            paragrafo,
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey800,
              lineSpacing: 2,
            ),
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _criarTextoTermos(String texto) {
    final linhas = texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();

    if (linhas.isEmpty) {
      return pw.Text(
        'Nenhum termo cadastrado.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      );
    }

    final possuiMarcadores = linhas.any(
      (linha) =>
          linha.startsWith('-') ||
          linha.startsWith('•') ||
          RegExp(r'^\d+[\.\)]').hasMatch(linha),
    );

    if (!possuiMarcadores) {
      return _criarTextoNormal(texto);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: linhas.map((linha) {
        final textoLimpo = linha
            .replaceFirst(RegExp(r'^[-•]\s*'), '')
            .replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '')
            .trim();

        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 3),
                width: 4,
                height: 4,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey700,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 7),
              pw.Expanded(
                child: pw.Text(
                  textoLimpo,
                  textAlign: pw.TextAlign.justify,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey800,
                    lineSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _criarAgradecimento({
    required DocumentoPdfContexto contexto,
    required String mensagem,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: pw.BoxDecoration(
        color: contexto.corSecundaria,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: contexto.corPrincipal, width: 0.9),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 5,
            height: 42,
            decoration: pw.BoxDecoration(
              color: contexto.corPrincipal,
              borderRadius: pw.BorderRadius.circular(3),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'AGRADECIMENTO',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: contexto.corPrincipal,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  mensagem,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _separarParagrafos(String texto) {
    return texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n+'))
        .map((paragrafo) => paragrafo.trim())
        .where((paragrafo) => paragrafo.isNotEmpty)
        .toList();
  }

  static String _primeiroTexto(
    Map<dynamic, dynamic> mapa,
    List<String> chaves, {
    String padrao = '',
  }) {
    for (final chave in chaves) {
      final valor = (mapa[chave] ?? '').toString().trim();

      if (valor.isNotEmpty && valor.toLowerCase() != 'null') {
        return valor;
      }
    }

    return padrao.trim();
  }
}
