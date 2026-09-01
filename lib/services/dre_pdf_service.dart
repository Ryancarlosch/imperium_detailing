import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../database/app_database.dart';
import '../repositories/dre_repository.dart';

/// dre-pdf-detalhado-v1
///
/// Exporta exatamente o resultado produzido pelo DreRepository.
/// Este serviço não recalcula faturamento, custo ou caixa por conta própria.
class DrePdfService {
  final DreRepository _repository = DreRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  Future<Uint8List> gerarPdf({
    required DateTime inicio,
    required DateTime fim,
    required DreRegime regime,
  }) async {
    final resultado = await _repository.calcular(
      inicio: inicio,
      fim: fim,
      regime: regime,
    );

    final empresa = await _carregarEmpresa();
    final detalhamentos = <_DreDetalhamentoPdf>[];

    for (final detalhe in resultado.detalhes) {
      List<DreOrigemDetalhe> origens = const <DreOrigemDetalhe>[];

      try {
        origens = await _repository.listarOrigens(
          detalhe: detalhe,
          inicio: inicio,
          fim: fim,
          regime: regime,
        );
      } catch (_) {
        // O PDF principal continua disponível mesmo se um detalhamento
        // específico não puder ser carregado.
      }

      detalhamentos.add(
        _DreDetalhamentoPdf(detalhe: detalhe, origens: origens),
      );
    }

    final documento = pw.Document();

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 30),
        header: (context) => _cabecalho(
          empresa: empresa,
          inicio: inicio,
          fim: fim,
          regime: regime,
        ),
        footer: (context) => _rodape(context),
        build: (context) {
          final widgets = <pw.Widget>[
            _tituloRelatorio(regime),
            pw.SizedBox(height: 12),
            _resumoExecutivo(resultado),
            pw.SizedBox(height: 16),
            _notaRegime(regime),
            pw.SizedBox(height: 18),
            _tituloSecao('DRE POR CATEGORIA / CONTA'),
            pw.SizedBox(height: 7),
            _tabelaContas(resultado.detalhes),
            pw.SizedBox(height: 18),
            _tituloSecao('DETALHAMENTO DOS LANÇAMENTOS'),
            pw.SizedBox(height: 5),
            pw.Text(
              'Abaixo estão as origens que formam cada linha da DRE. '
              'Recebimentos, Ordens de Serviço, descontos, taxas e custos '
              'seguem a mesma regra usada na tela do aplicativo.',
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 10),
          ];

          for (final item in detalhamentos) {
            widgets.add(_cabecalhoDetalhe(item.detalhe));

            if (item.origens.isEmpty) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 10),
                  child: pw.Text(
                    'Nenhum lançamento individual disponível para esta linha.',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              );
            } else {
              widgets.add(_tabelaOrigens(item.origens));
              widgets.add(pw.SizedBox(height: 10));
            }
          }

          return widgets;
        },
      ),
    );

    return documento.save();
  }

  Future<void> visualizar({
    required DateTime inicio,
    required DateTime fim,
    required DreRegime regime,
  }) async {
    final bytes = await gerarPdf(inicio: inicio, fim: fim, regime: regime);

    await Printing.layoutPdf(
      name: 'DRE Gerencial',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> compartilhar({
    required DateTime inicio,
    required DateTime fim,
    required DreRegime regime,
  }) async {
    final bytes = await gerarPdf(inicio: inicio, fim: fim, regime: regime);

    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'dre_gerencial_${_arquivoData(inicio)}_${_arquivoData(fim)}_${regime.name}.pdf',
    );
  }

  Future<Map<String, dynamic>> _carregarEmpresa() async {
    try {
      final database = await AppDatabase.instance.database;
      final rows = await database.query('configuracoes', limit: 1);

      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
    } catch (_) {
      // Cabeçalho cai para o nome padrão.
    }

    return const <String, dynamic>{};
  }

  pw.Widget _cabecalho({
    required Map<String, dynamic> empresa,
    required DateTime inicio,
    required DateTime fim,
    required DreRegime regime,
  }) {
    final nomeFantasia = _texto(
      empresa['nome_fantasia'],
      padrao: 'Imperium Detailing',
    );
    final razaoSocial = _texto(empresa['razao_social']);
    final cnpj = _texto(empresa['cnpj']);
    final cidade = _texto(empresa['cidade']);
    final estado = _texto(empresa['estado']);

    final identificacao = <String>[
      if (razaoSocial.isNotEmpty && razaoSocial != nomeFantasia) razaoSocial,
      if (cnpj.isNotEmpty) 'CNPJ $cnpj',
      if (cidade.isNotEmpty || estado.isNotEmpty)
        [cidade, estado].where((item) => item.isNotEmpty).join(' / '),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.7),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nomeFantasia,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (identificacao.isNotEmpty)
                  pw.Text(
                    identificacao.join(' • '),
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),
          pw.Text(
            '${_data.format(inicio)} a ${_data.format(fim)}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _tituloRelatorio(DreRegime regime) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey900,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DRE GERENCIAL',
            style: pw.TextStyle(
              fontSize: 18,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            regime == DreRegime.competencia
                ? 'Regime de competência'
                : 'Regime de caixa',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey300),
          ),
        ],
      ),
    );
  }

  pw.Widget _resumoExecutivo(DreResultado r) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          _linhaResumo('Receita bruta', r.receitaBruta),
          _linhaResumo('(-) Deduções', -r.deducoes),
          _linhaResumo('= Receita líquida', r.receitaLiquida, destaque: true),
          _linhaResumo('(-) Custos variáveis', -r.custosVariaveis),
          _linhaResumo(
            '= Margem de contribuição',
            r.margemContribuicao,
            destaque: true,
          ),
          _linhaResumo('(-) Despesas operacionais', -r.despesasOperacionais),
          _linhaResumo('Resultado financeiro', r.resultadoFinanceiro),
          _linhaResumo('Outras receitas', r.outrasReceitas),
          _linhaResumo('(-) Outras despesas', -r.outrasDespesas),
          _linhaResumo(
            '= RESULTADO GERENCIAL',
            r.resultadoGerencial,
            destaque: true,
            forte: true,
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 7),
            color: PdfColors.grey100,
            child: pw.Text(
              'Margem do período: ${_percentual(r.margemPercentual)}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _linhaResumo(
    String titulo,
    double valor, {
    bool destaque = false,
    bool forte = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: forte ? 10 : 8.5,
                fontWeight: destaque
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            _moeda.format(valor),
            style: pw.TextStyle(
              fontSize: forte ? 10 : 8.5,
              fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _notaRegime(DreRegime regime) {
    final texto = regime == DreRegime.competencia
        ? 'Competência: a receita da Ordem de Serviço é reconhecida no '
              'período econômico da venda. O recebimento posterior não cria '
              'uma segunda receita. Despesas usam a data de competência.'
        : 'Caixa: receitas e despesas aparecem quando o dinheiro '
              'efetivamente entra ou sai. Esta visão é útil para acompanhar '
              'liquidez, mas não substitui a DRE por competência para análise '
              'de desempenho.';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Text(
        texto,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
      ),
    );
  }

  pw.Widget _tituloSecao(String titulo) {
    return pw.Text(
      titulo,
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    );
  }

  pw.Widget _tabelaContas(List<DreDetalhe> detalhes) {
    if (detalhes.isEmpty) {
      return pw.Text(
        'Nenhuma linha de DRE no período.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: const ['Grupo', 'Código', 'Conta / categoria', 'Valor'],
      data: detalhes
          .map(
            (item) => <String>[
              item.grupo,
              item.codigo,
              item.nome,
              _moeda.format(item.valor),
            ],
          )
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.2),
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
      },
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.1),
        2: pw.FlexColumnWidth(3.4),
        3: pw.FlexColumnWidth(1.8),
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.35),
    );
  }

  pw.Widget _cabecalhoDetalhe(DreDetalhe detalhe) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
      margin: const pw.EdgeInsets.only(top: 4),
      color: PdfColors.grey200,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${detalhe.codigo} • ${detalhe.nome}',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            _moeda.format(detalhe.valor),
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _tabelaOrigens(List<DreOrigemDetalhe> origens) {
    return pw.TableHelper.fromTextArray(
      headers: const [
        'Data',
        'Tipo',
        'Descrição / origem',
        'Referência',
        'Valor',
      ],
      data: origens.map((origem) {
        final referencia = <String>[
          if (origem.ordemServicoId != null) 'OS #${origem.ordemServicoId}',
          if (origem.pagamentoId != null) 'Pgto #${origem.pagamentoId}',
          if (origem.movimentoId != null) 'Mov #${origem.movimentoId}',
        ].join(' / ');

        final descricao = origem.subtitulo.trim().isEmpty
            ? origem.titulo
            : '${origem.titulo} — ${origem.subtitulo}';

        return <String>[
          _formatarDataTexto(origem.data),
          origem.tipo,
          descricao,
          referencia,
          _moeda.format(origem.valor),
        ];
      }).toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 6.8,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerRight,
      },
      columnWidths: const {
        0: pw.FlexColumnWidth(1.25),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(3.7),
        3: pw.FlexColumnWidth(1.6),
        4: pw.FlexColumnWidth(1.55),
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
    );
  }

  pw.Widget _rodape(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Imperium Manager • DRE Gerencial',
              style: const pw.TextStyle(
                fontSize: 6.8,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  String _formatarDataTexto(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return '';

    final data = DateTime.tryParse(texto);
    return data == null ? texto : _data.format(data);
  }

  String _percentual(double valor) {
    return '${valor.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  String _arquivoData(DateTime valor) {
    return '${valor.year.toString().padLeft(4, '0')}'
        '${valor.month.toString().padLeft(2, '0')}'
        '${valor.day.toString().padLeft(2, '0')}';
  }

  static String _texto(dynamic valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? padrao : texto;
  }
}

class _DreDetalhamentoPdf {
  const _DreDetalhamentoPdf({required this.detalhe, required this.origens});

  final DreDetalhe detalhe;
  final List<DreOrigemDetalhe> origens;
}
