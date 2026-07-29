import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class OrcamentoPdfService {
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _data =
  DateFormat('dd/MM/yyyy');

  Future<Uint8List> gerarPdf(
      Map<String, dynamic> dados, {
        required bool recibo,
      }) async {
    final documento = pw.Document();

    final emissao = DateTime.tryParse(
      (dados['data_emissao'] ?? '').toString(),
    );

    final validade = DateTime.tryParse(
      (dados['validade'] ?? '').toString(),
    );

    final valor =
        (dados['valor'] as num?)?.toDouble() ?? 0;

    final veiculo = [
      dados['veiculo_marca'],
      dados['veiculo_modelo'],
      dados['veiculo_placa'],
    ]
        .where(
          (valor) =>
      valor != null &&
          valor.toString().trim().isNotEmpty,
    )
        .join(' • ');

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey900,
                borderRadius:
                pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'IMPERIUM',
                        style: pw.TextStyle(
                          color: PdfColors.amber700,
                          fontSize: 24,
                          fontWeight:
                          pw.FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      pw.Text(
                        'DETAILING',
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    recibo ? 'RECIBO' : 'ORÇAMENTO',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              recibo
                  ? 'Recebemos de'
                  : 'Cliente',
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey700,
              ),
            ),
            pw.Text(
              (dados['cliente_nome'] ?? '')
                  .toString(),
              style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if ((dados['cliente_telefone'] ?? '')
                .toString()
                .isNotEmpty)
              pw.Text(
                'Telefone: ${dados['cliente_telefone']}',
              ),
            if (veiculo.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'Veículo',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Text(veiculo),
            ],
            pw.SizedBox(height: 24),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey400,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  children: [
                    _celula(
                      recibo
                          ? 'Serviço realizado'
                          : 'Serviço proposto',
                      cabecalho: true,
                    ),
                    _celula(
                      'Valor',
                      cabecalho: true,
                      alinhamento:
                      pw.TextAlign.right,
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _celula(
                      (dados['servico'] ?? '')
                          .toString(),
                    ),
                    _celula(
                      _moeda.format(valor),
                      alinhamento:
                      pw.TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
            if ((dados['descricao'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Descrição',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                dados['descricao'].toString(),
              ),
            ],
            if ((dados['observacoes'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Observações',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                dados['observacoes'].toString(),
              ),
            ],
            pw.SizedBox(height: 26),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColors.amber50,
                border: pw.Border.all(
                  color: PdfColors.amber700,
                ),
              ),
              child: pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    recibo
                        ? 'VALOR RECEBIDO'
                        : 'VALOR TOTAL',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _moeda.format(valor),
                    style: pw.TextStyle(
                      fontSize: 19,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              recibo
                  ? 'Data do recibo: ${_data.format(DateTime.now())}'
                  : 'Emissão: ${emissao == null ? '-' : _data.format(emissao)}'
                  '   •   Validade: ${validade == null ? '-' : _data.format(validade)}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            if (recibo) ...[
              pw.SizedBox(height: 55),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: 230,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Imperium Detailing',
                      style: const pw.TextStyle(
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            pw.Spacer(),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                'Imperium Detailing • Estética Automotiva',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return documento.save();
  }

  pw.Widget _celula(
      String texto, {
        bool cabecalho = false,
        pw.TextAlign alinhamento =
            pw.TextAlign.left,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Text(
        texto,
        textAlign: alinhamento,
        style: pw.TextStyle(
          fontWeight: cabecalho
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> compartilhar(
      Map<String, dynamic> dados, {
        required bool recibo,
      }) async {
    final bytes = await gerarPdf(
      dados,
      recibo: recibo,
    );

    final numero =
    (dados['id'] ?? '').toString();

    await Printing.sharePdf(
      bytes: bytes,
      filename: recibo
          ? 'recibo_imperium_$numero.pdf'
          : 'orcamento_imperium_$numero.pdf',
    );
  }

  Future<void> visualizar(
      Map<String, dynamic> dados, {
        required bool recibo,
      }) async {
    final bytes = await gerarPdf(
      dados,
      recibo: recibo,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: recibo
          ? 'Recibo Imperium'
          : 'Orçamento Imperium',
    );
  }
}
