import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class TabelaServicosPdf {
  const TabelaServicosPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    required List<dynamic> servicos,
    String titulo = 'SERVIÇOS',
    bool mostrarQuantidade = true,
    bool mostrarValorUnitario = true,
    bool mostrarDesconto = false,
    bool mostrarTotal = true,
  }) {
    final itens = _converterServicos(servicos);

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
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _criarTitulo(
            contexto: contexto,
            titulo: titulo,
          ),
          if (itens.isEmpty)
            _criarListaVazia()
          else
            _criarTabela(
              contexto: contexto,
              itens: itens,
              mostrarQuantidade: mostrarQuantidade,
              mostrarValorUnitario: mostrarValorUnitario,
              mostrarDesconto: mostrarDesconto,
              mostrarTotal: mostrarTotal,
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
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
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

  static pw.Widget _criarTabela({
    required DocumentoPdfContexto contexto,
    required List<_ServicoPdf> itens,
    required bool mostrarQuantidade,
    required bool mostrarValorUnitario,
    required bool mostrarDesconto,
    required bool mostrarTotal,
  }) {
    final larguras = <int, pw.TableColumnWidth>{};

    var indiceColuna = 0;

    larguras[indiceColuna] =
    const pw.FixedColumnWidth(24);
    indiceColuna++;

    larguras[indiceColuna] =
    const pw.FlexColumnWidth(4.2);
    indiceColuna++;

    if (mostrarQuantidade) {
      larguras[indiceColuna] =
      const pw.FlexColumnWidth(0.9);
      indiceColuna++;
    }

    if (mostrarValorUnitario) {
      larguras[indiceColuna] =
      const pw.FlexColumnWidth(1.4);
      indiceColuna++;
    }

    if (mostrarDesconto) {
      larguras[indiceColuna] =
      const pw.FlexColumnWidth(1.2);
      indiceColuna++;
    }

    if (mostrarTotal) {
      larguras[indiceColuna] =
      const pw.FlexColumnWidth(1.5);
    }

    return pw.Table(
      columnWidths: larguras,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.5,
        ),
      ),
      children: [
        _criarCabecalhoTabela(
          contexto: contexto,
          mostrarQuantidade: mostrarQuantidade,
          mostrarValorUnitario: mostrarValorUnitario,
          mostrarDesconto: mostrarDesconto,
          mostrarTotal: mostrarTotal,
        ),
        ...itens.asMap().entries.map(
              (entrada) {
            final indice = entrada.key;
            final servico = entrada.value;

            return _criarLinhaServico(
              indice: indice,
              servico: servico,
              mostrarQuantidade: mostrarQuantidade,
              mostrarValorUnitario:
              mostrarValorUnitario,
              mostrarDesconto: mostrarDesconto,
              mostrarTotal: mostrarTotal,
            );
          },
        ),
      ],
    );
  }

  static pw.TableRow _criarCabecalhoTabela({
    required DocumentoPdfContexto contexto,
    required bool mostrarQuantidade,
    required bool mostrarValorUnitario,
    required bool mostrarDesconto,
    required bool mostrarTotal,
  }) {
    final celulas = <pw.Widget>[
      _criarCelulaCabecalho(
        texto: '#',
        alinhamento: pw.TextAlign.center,
      ),
      _criarCelulaCabecalho(
        texto: 'DESCRIÇÃO',
      ),
    ];

    if (mostrarQuantidade) {
      celulas.add(
        _criarCelulaCabecalho(
          texto: 'QTD.',
          alinhamento: pw.TextAlign.center,
        ),
      );
    }

    if (mostrarValorUnitario) {
      celulas.add(
        _criarCelulaCabecalho(
          texto: 'UNITÁRIO',
          alinhamento: pw.TextAlign.right,
        ),
      );
    }

    if (mostrarDesconto) {
      celulas.add(
        _criarCelulaCabecalho(
          texto: 'DESCONTO',
          alinhamento: pw.TextAlign.right,
        ),
      );
    }

    if (mostrarTotal) {
      celulas.add(
        _criarCelulaCabecalho(
          texto: 'TOTAL',
          alinhamento: pw.TextAlign.right,
        ),
      );
    }

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: contexto.corSecundaria,
      ),
      children: celulas,
    );
  }

  static pw.Widget _criarCelulaCabecalho({
    required String texto,
    pw.TextAlign alinhamento =
        pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 7,
      ),
      child: pw.Text(
        texto,
        textAlign: alinhamento,
        style: pw.TextStyle(
          fontSize: 6.8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static pw.TableRow _criarLinhaServico({
    required int indice,
    required _ServicoPdf servico,
    required bool mostrarQuantidade,
    required bool mostrarValorUnitario,
    required bool mostrarDesconto,
    required bool mostrarTotal,
  }) {
    final celulas = <pw.Widget>[
      _criarCelula(
        texto: '${indice + 1}',
        alinhamento: pw.TextAlign.center,
      ),
      _criarDescricaoServico(
        servico,
      ),
    ];

    if (mostrarQuantidade) {
      celulas.add(
        _criarCelula(
          texto: _formatarQuantidade(
            servico.quantidade,
          ),
          alinhamento: pw.TextAlign.center,
        ),
      );
    }

    if (mostrarValorUnitario) {
      celulas.add(
        _criarCelula(
          texto: _formatarMoeda(
            servico.valorUnitario,
          ),
          alinhamento: pw.TextAlign.right,
        ),
      );
    }

    if (mostrarDesconto) {
      celulas.add(
        _criarCelula(
          texto: servico.desconto > 0
              ? _formatarMoeda(
            servico.desconto,
          )
              : '-',
          alinhamento: pw.TextAlign.right,
        ),
      );
    }

    if (mostrarTotal) {
      celulas.add(
        _criarCelula(
          texto: _formatarMoeda(
            servico.valorTotal,
          ),
          alinhamento: pw.TextAlign.right,
          destaque: true,
        ),
      );
    }

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: indice.isEven
            ? PdfColors.white
            : PdfColors.grey100,
      ),
      children: celulas,
    );
  }

  static pw.Widget _criarDescricaoServico(
      _ServicoPdf servico,
      ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 8,
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            servico.descricao,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey900,
            ),
          ),
          if (servico.observacao.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              servico.observacao,
              style: const pw.TextStyle(
                fontSize: 6.8,
                color: PdfColors.grey600,
                lineSpacing: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _criarCelula({
    required String texto,
    pw.TextAlign alinhamento =
        pw.TextAlign.left,
    bool destaque = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 8,
      ),
      child: pw.Text(
        texto,
        textAlign: alinhamento,
        style: pw.TextStyle(
          fontSize: 7.5,
          color: PdfColors.grey900,
          fontWeight: destaque
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _criarListaVazia() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 20,
      ),
      child: pw.Text(
        'Nenhum serviço informado.',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  static List<_ServicoPdf> _converterServicos(
      List<dynamic> servicos,
      ) {
    final resultado = <_ServicoPdf>[];

    for (final item in servicos) {
      if (item is Map) {
        final mapa = Map<dynamic, dynamic>.from(
          item,
        );

        final descricao = _primeiroTexto(
          mapa,
          [
            'descricao',
            'nome',
            'servico',
            'servico_nome',
            'descricao_servico',
            'produto_nome',
          ],
        );

        if (descricao.isEmpty) {
          continue;
        }

        var quantidade = _primeiroNumero(
          mapa,
          [
            'quantidade',
            'qtd',
            'qtde',
          ],
        );

        if (quantidade <= 0) {
          quantidade = 1;
        }

        final valorUnitario = _primeiroNumero(
          mapa,
          [
            'valor_unitario',
            'preco_unitario',
            'valor',
            'preco',
            'servico_valor',
          ],
        );

        final desconto = _primeiroNumero(
          mapa,
          [
            'desconto',
            'valor_desconto',
          ],
        );

        final totalInformado = _primeiroNumero(
          mapa,
          [
            'valor_total',
            'total',
            'subtotal',
          ],
        );

        final totalCalculado =
            (quantidade * valorUnitario) -
                desconto;

        final valorTotal = totalInformado > 0
            ? totalInformado
            : totalCalculado;

        final observacao = _primeiroTexto(
          mapa,
          [
            'observacao',
            'observacoes',
            'detalhes',
            'descricao_detalhada',
          ],
        );

        resultado.add(
          _ServicoPdf(
            descricao: descricao,
            observacao: observacao,
            quantidade: quantidade,
            valorUnitario: valorUnitario,
            desconto: desconto,
            valorTotal:
            valorTotal < 0 ? 0 : valorTotal,
          ),
        );
      } else {
        final descricao =
            item?.toString().trim() ?? '';

        if (descricao.isNotEmpty) {
          resultado.add(
            _ServicoPdf(
              descricao: descricao,
              observacao: '',
              quantidade: 1,
              valorUnitario: 0,
              desconto: 0,
              valorTotal: 0,
            ),
          );
        }
      }
    }

    return resultado;
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

    return 0;
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
        .replaceAll('%', '')
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

  static String _formatarQuantidade(
      double quantidade,
      ) {
    if (quantidade ==
        quantidade.truncateToDouble()) {
      return quantidade
          .toInt()
          .toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',');
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

    final sinal = negativo ? '-' : '';

    return '${sinal}R\$ ${buffer.toString()},$decimal';
  }
}

class _ServicoPdf {
  const _ServicoPdf({
    required this.descricao,
    required this.observacao,
    required this.quantidade,
    required this.valorUnitario,
    required this.desconto,
    required this.valorTotal,
  });

  final String descricao;
  final String observacao;
  final double quantidade;
  final double valorUnitario;
  final double desconto;
  final double valorTotal;
}