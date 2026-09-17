import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/ordem_servico_valor.dart';
import 'web_cloud_operacional_service.dart';
import 'web_os_arquivos_service.dart';
import 'web_os_v3_service.dart';

/// Gera a Ordem de Serviço no navegador sem depender de caminhos locais.
///
/// Todos os anexos entram no PDF como bytes vindos do Supabase Storage.
class WebOsPdfService {
  WebOsPdfService._();

  static final WebOsPdfService instance = WebOsPdfService._();

  final WebOsV3Service _osService = WebOsV3Service.instance;
  final WebCloudOperacionalService _operacional =
      WebCloudOperacionalService.instance;
  final WebOsArquivosService _arquivosService = WebOsArquivosService.instance;

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  Future<Uint8List> gerarPdf({required String ordemId}) async {
    final id = ordemId.trim();
    if (id.isEmpty) throw ArgumentError('Ordem de serviço inválida.');

    final resultados = await Future.wait<dynamic>([
      _osService.carregarEdicao(id),
      _operacional.listarClientes(),
      _operacional.listarVeiculos(),
      _arquivosService.carregar(id),
    ]);

    final edicao = Map<String, dynamic>.from(resultados[0] as Map);
    final clientes = (resultados[1] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final veiculos = (resultados[2] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pacoteArquivos = Map<String, dynamic>.from(resultados[3] as Map);

    final ordem = Map<String, dynamic>.from(edicao['ordem'] as Map);
    final itens = (edicao['itens'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final clienteId = _texto(ordem['cliente_id']);
    final veiculoId = _texto(ordem['veiculo_id']);
    final cliente = _porId(clientes, clienteId);
    final veiculo = _porId(veiculos, veiculoId);
    final imagens = await _carregarImagens(pacoteArquivos);

    final documento = pw.Document();
    final numero = _texto(ordem['numero']).isEmpty
        ? id
        : _texto(ordem['numero']);
    final negociado = OrdemServicoValor.valorNegociado(
      valorTotal: _double(ordem['valor_total']),
      desconto: _double(ordem['desconto']),
      descontoNegociacao: _double(ordem['desconto_negociacao']),
      acrescimoNegociacao: _double(ordem['acrescimo_negociacao']),
      jurosParcelamento: _double(ordem['juros_parcelamento']),
    );

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Imperium Manager · página ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => <pw.Widget>[
          _cabecalho(numero: numero, status: _texto(ordem['status'])),
          pw.SizedBox(height: 12),
          _dadosPrincipais(ordem, cliente, veiculo),
          pw.SizedBox(height: 12),
          _itens(itens),
          pw.SizedBox(height: 12),
          _totais(ordem, negociado),
          if (_texto(ordem['observacoes']).isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _caixaTexto('OBSERVAÇÕES', _texto(ordem['observacoes'])),
          ],
          if (imagens.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'FOTOS, AVARIAS E ASSINATURA',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            ...imagens.map(_imagem),
          ],
        ],
      ),
    );

    return documento.save();
  }

  Future<void> baixarPdf({required String ordemId, String numero = ''}) async {
    final bytes = await gerarPdf(ordemId: ordemId);
    final identificador = _arquivoSeguro(numero.isEmpty ? ordemId : numero);

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'ordem_servico_$identificador.pdf',
    );
  }

  pw.Widget _cabecalho({required String numero, required String status}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'IMPERIUM MANAGER',
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'ORDEM DE SERVIÇO',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'OS $numero',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (status.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(status, style: const pw.TextStyle(fontSize: 9)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _dadosPrincipais(
    Map<String, dynamic> ordem,
    Map<String, dynamic> cliente,
    Map<String, dynamic> veiculo,
  ) {
    final clienteNome = _texto(cliente['nome']);
    final veiculoDescricao = [
      _texto(veiculo['marca']),
      _texto(veiculo['modelo']),
    ].where((e) => e.isNotEmpty).join(' ');

    final linhas = <List<String>>[
      ['Cliente', clienteNome],
      ['Telefone', _texto(cliente['telefone'])],
      ['E-mail', _texto(cliente['email'])],
      ['Veículo', veiculoDescricao],
      ['Placa', _texto(veiculo['placa'])],
      ['Cor / Ano', _juntar(_texto(veiculo['cor']), _texto(veiculo['ano']))],
      ['Abertura', _texto(ordem['data_abertura'])],
      [
        'Entrada',
        _juntar(_texto(ordem['data_inicio']), _texto(ordem['hora_entrada'])),
      ],
      [
        'Saída',
        _juntar(_texto(ordem['data_finalizacao']), _texto(ordem['hora_saida'])),
      ],
      ['Responsável', _texto(ordem['funcionario_responsavel'])],
      ['Quilometragem', _texto(ordem['quilometragem_entrada'])],
      ['Combustível', _texto(ordem['combustivel_entrada'])],
    ].where((linha) => linha[1].isNotEmpty).toList();

    if (linhas.isEmpty) {
      return _caixaTexto('DADOS DA OS', 'Sem dados complementares.');
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DADOS DA OS',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          ...linhas.map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 88,
                    child: pw.Text(
                      '${linha[0]}:',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      linha[1],
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _itens(List<Map<String, dynamic>> itens) {
    final dados = itens.map((item) {
      final quantidade = _double(item['quantidade']);
      final unitario = _double(item['valor_unitario']);
      return <String>[
        _texto(item['servico']).isEmpty ? 'Serviço' : _texto(item['servico']),
        _quantidade(quantidade),
        _moeda.format(unitario),
        _moeda.format(quantidade * unitario),
      ];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SERVIÇOS',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (dados.isEmpty)
          pw.Text('Nenhum serviço informado.')
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Serviço', 'Qtd.', 'Unitário', 'Subtotal'],
            data: dados,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
          ),
      ],
    );
  }

  pw.Widget _totais(Map<String, dynamic> ordem, double negociado) {
    final totalBruto = _double(ordem['valor_total']);
    final desconto =
        _double(ordem['desconto']) + _double(ordem['desconto_negociacao']);
    final acrescimos =
        _double(ordem['acrescimo_negociacao']) +
        _double(ordem['juros_parcelamento']);

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 240,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            _linhaTotal('Valor dos serviços', totalBruto),
            if (desconto > 0) _linhaTotal('Descontos', -desconto),
            if (acrescimos > 0) _linhaTotal('Acréscimos/juros', acrescimos),
            pw.Divider(color: PdfColors.grey500),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _moeda.format(negociado),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _linhaTotal(String rotulo, double valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(rotulo, style: const pw.TextStyle(fontSize: 8.5)),
          pw.Text(
            _moeda.format(valor),
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _caixaTexto(String titulo, String texto) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(texto, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  pw.Widget _imagem(_WebOsPdfImagem imagem) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            imagem.titulo,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (imagem.descricao.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(imagem.descricao, style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Image(
              pw.MemoryImage(imagem.bytes),
              fit: pw.BoxFit.contain,
              height: imagem.tipo == 'assinatura' ? 100 : 250,
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_WebOsPdfImagem>> _carregarImagens(
    Map<String, dynamic> pacote,
  ) async {
    final arquivos = (pacote['arquivos'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final imagens = <_WebOsPdfImagem>[];

    for (final arquivo in arquivos) {
      final mime = _texto(arquivo['mime']).toLowerCase();
      if (mime.isNotEmpty && !mime.startsWith('image/')) continue;

      try {
        final bytes = await _arquivosService.baixar(arquivo);
        if (bytes.isEmpty) continue;
        imagens.add(
          _WebOsPdfImagem(
            tipo: _texto(arquivo['tipo']),
            titulo: _texto(arquivo['titulo']).isEmpty
                ? 'Arquivo da OS'
                : _texto(arquivo['titulo']),
            descricao: _texto(arquivo['descricao']),
            bytes: bytes,
          ),
        );
      } catch (_) {
        // Um anexo indisponível não pode impedir a geração do documento.
      }
    }

    return imagens;
  }

  static Map<String, dynamic> _porId(
    List<Map<String, dynamic>> itens,
    String id,
  ) {
    for (final item in itens) {
      if (_texto(item['id']) == id) return item;
    }
    return <String, dynamic>{};
  }

  static String _juntar(String a, String b) {
    return [a, b].where((e) => e.isNotEmpty).join(' · ');
  }

  static String _quantidade(double valor) {
    if (valor == valor.roundToDouble()) return valor.toInt().toString();
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _arquivoSeguro(String valor) {
    final normalizado = valor
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalizado.isEmpty ? 'os' : normalizado;
  }

  static String _texto(dynamic valor) => (valor ?? '').toString().trim();

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(_texto(valor).replaceAll(',', '.')) ?? 0;
  }
}

class _WebOsPdfImagem {
  const _WebOsPdfImagem({
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.bytes,
  });

  final String tipo;
  final String titulo;
  final String descricao;
  final Uint8List bytes;
}
