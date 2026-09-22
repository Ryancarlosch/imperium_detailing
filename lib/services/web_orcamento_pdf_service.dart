import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'web_configuracao_arquivo_service.dart';
import 'web_configuracao_empresa_service.dart';

class WebOrcamentoPdfService {
  WebOrcamentoPdfService._();

  static final WebOrcamentoPdfService instance = WebOrcamentoPdfService._();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  Future<Uint8List> gerar({
    required Map<String, dynamic> orcamento,
    required List<Map<String, dynamic>> itens,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> veiculo,
    bool recibo = false,
  }) async {
    final dados = await Future.wait<dynamic>([
      WebConfiguracaoEmpresaService.instance.carregar(),
      WebConfiguracaoArquivoService.instance.listarAtivos(),
    ]);
    final config = Map<String, dynamic>.from(dados[0] as Map);
    final arquivos = dados[1] as Map<String, WebConfiguracaoArquivo>;
    final logo = await _baixar(arquivos['logo']);

    final subtotal = itens.fold<double>(
      0,
      (total, item) =>
          total +
          (_numero(item['quantidade']) * _numero(item['valor_unitario'])),
    );
    final desconto = _numero(orcamento['desconto']);
    final totalBanco = _numero(orcamento['valor']);
    final total = totalBanco > 0
        ? totalBanco
        : (subtotal - desconto).clamp(0.0, double.infinity).toDouble();

    final documento = pw.Document(
      title: recibo ? 'Recibo de orçamento' : 'Orçamento',
      author: _nomeEmpresa(config),
    );

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 28),
        footer: (context) => _rodape(context, config),
        build: (_) => [
          _cabecalho(
            config: config,
            logo: logo,
            titulo: recibo ? 'RECIBO / PROPOSTA' : 'ORÇAMENTO',
            numero: _numeroDocumento(orcamento),
            status: _textoOu(orcamento['status'], 'Pendente'),
          ),
          pw.SizedBox(height: 12),
          _secao(
            'CLIENTE E VEÍCULO',
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _info({
                    'Cliente': _textoOu(cliente['nome'], '—'),
                    'Telefone': _textoOu(cliente['telefone'], '—'),
                    'E-mail': _textoOu(cliente['email'], '—'),
                  }),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _info({
                    'Veículo': [
                      _texto(veiculo['marca']),
                      _texto(veiculo['modelo']),
                    ].where((e) => e.isNotEmpty).join(' '),
                    'Placa': _textoOu(veiculo['placa'], '—'),
                    'Cor': _textoOu(veiculo['cor'], '—'),
                    'Ano': _textoOu(veiculo['ano'], '—'),
                  }),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _secao(
            'INFORMAÇÕES',
            pw.Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _campo('Emissão', _textoOu(orcamento['data_emissao'], '—')),
                _campo('Validade', _textoOu(orcamento['validade'], '—')),
                _campo(
                  'Perfil de preço',
                  _perfil(_texto(orcamento['perfil_preco'])),
                ),
                _campo('Status', _textoOu(orcamento['status'], 'Pendente')),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _secao('SERVIÇOS', _tabelaItens(itens)),
          pw.SizedBox(height: 10),
          _secao(
            'VALORES',
            pw.Column(
              children: [
                _linhaValor('Subtotal', _moeda.format(subtotal)),
                if (desconto > 0)
                  _linhaValor('Desconto', '- ${_moeda.format(desconto)}'),
                pw.Divider(),
                _linhaValor('Total', _moeda.format(total), destaque: true),
              ],
            ),
          ),
          if (_texto(orcamento['observacoes']).isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _secao('OBSERVAÇÕES', pw.Text(_texto(orcamento['observacoes']))),
          ],
          if (!recibo && _texto(config['termos_orcamento']).isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _secao(
              'TERMOS DO ORÇAMENTO',
              pw.Text(
                _texto(config['termos_orcamento']),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ],
      ),
    );

    return documento.save();
  }

  Future<void> visualizar({
    required Map<String, dynamic> orcamento,
    required List<Map<String, dynamic>> itens,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> veiculo,
    bool recibo = false,
  }) async {
    final bytes = await gerar(
      orcamento: orcamento,
      itens: itens,
      cliente: cliente,
      veiculo: veiculo,
      recibo: recibo,
    );
    await Printing.layoutPdf(
      name: recibo ? 'Recibo de orçamento' : 'Orçamento',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> compartilhar({
    required Map<String, dynamic> orcamento,
    required List<Map<String, dynamic>> itens,
    required Map<String, dynamic> cliente,
    required Map<String, dynamic> veiculo,
    bool recibo = false,
  }) async {
    final bytes = await gerar(
      orcamento: orcamento,
      itens: itens,
      cliente: cliente,
      veiculo: veiculo,
      recibo: recibo,
    );
    final numero = _arquivoSeguro(_numeroDocumento(orcamento));
    await Printing.sharePdf(
      bytes: bytes,
      filename: recibo
          ? 'recibo_orcamento_$numero.pdf'
          : 'orcamento_$numero.pdf',
    );
  }

  Future<Uint8List?> _baixar(WebConfiguracaoArquivo? arquivo) async {
    try {
      return await WebConfiguracaoArquivoService.instance.baixar(arquivo);
    } catch (_) {
      return null;
    }
  }

  pw.Widget _cabecalho({
    required Map<String, dynamic> config,
    required Uint8List? logo,
    required String titulo,
    required String numero,
    required String status,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null && logo.isNotEmpty) ...[
          pw.SizedBox(
            width: 62,
            height: 62,
            child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 14),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _nomeEmpresa(config),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (_texto(config['cnpj']).isNotEmpty)
                pw.Text(
                  'CNPJ: ${_texto(config['cnpj'])}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (_endereco(config).isNotEmpty)
                pw.Text(
                  _endereco(config),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (_contato(config).isNotEmpty)
                pw.Text(
                  _contato(config),
                  style: const pw.TextStyle(fontSize: 9),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(numero, style: const pw.TextStyle(fontSize: 10)),
            pw.Text(status, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
  }

  pw.Widget _secao(String titulo, pw.Widget conteudo) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 7),
          conteudo,
        ],
      ),
    );
  }

  pw.Widget _info(Map<String, String> dados) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: dados.entries.map((entry) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '${entry.key}: ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(
                  text: entry.value.trim().isEmpty ? '—' : entry.value,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _campo(String titulo, String valor) {
    return pw.SizedBox(
      width: 150,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _tabelaItens(List<Map<String, dynamic>> itens) {
    if (itens.isEmpty) return pw.Text('Nenhum serviço informado.');

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.5),
      },
      children: [
        _linhaTabela(const [
          'Serviço',
          'Qtd.',
          'Unitário',
          'Total',
        ], cabecalho: true),
        ...itens.map((item) {
          final qtd = _numero(item['quantidade']);
          final unitario = _numero(item['valor_unitario']);
          return _linhaTabela([
            _textoOu(item['servico'], 'Serviço'),
            _quantidade(qtd),
            _moeda.format(unitario),
            _moeda.format(qtd * unitario),
          ]);
        }),
      ],
    );
  }

  pw.TableRow _linhaTabela(List<String> valores, {bool cabecalho = false}) {
    return pw.TableRow(
      decoration: cabecalho
          ? const pw.BoxDecoration(color: PdfColors.grey200)
          : null,
      children: valores.map((valor) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: cabecalho ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _linhaValor(String titulo, String valor, {bool destaque = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(titulo),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: destaque ? 11 : 9,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _rodape(pw.Context context, Map<String, dynamic> config) {
    final personalizado = _texto(config['rodape_documentos']);
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                personalizado.isEmpty ? _nomeEmpresa(config) : personalizado,
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Text(
              'Página ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
      ],
    );
  }

  String _numeroDocumento(Map<String, dynamic> orcamento) {
    final local = _texto(orcamento['origem_local_id']);
    if (local.isNotEmpty) return 'Orçamento #$local';

    final id = _texto(orcamento['id']);
    return id.isEmpty
        ? 'Orçamento'
        : 'Orçamento ${id.substring(0, id.length.clamp(0, 8))}';
  }

  String _nomeEmpresa(Map<String, dynamic> config) {
    final fantasia = _texto(config['nome_fantasia']);
    if (fantasia.isNotEmpty) return fantasia;
    final razao = _texto(config['razao_social']);
    if (razao.isNotEmpty) return razao;
    return _textoOu(config['nome_aplicativo'], 'Imperium Detailing');
  }

  String _endereco(Map<String, dynamic> config) {
    return [
      _texto(config['endereco']),
      _texto(config['numero']),
      _texto(config['bairro']),
      _texto(config['cidade']),
      _texto(config['estado']),
      _texto(config['cep']),
    ].where((e) => e.isNotEmpty).join(' · ');
  }

  String _contato(Map<String, dynamic> config) {
    return [
      _texto(config['telefone']),
      _texto(config['whatsapp']),
      _texto(config['email']),
      _texto(config['site']),
    ].where((e) => e.isNotEmpty).join(' · ');
  }

  static String _perfil(String valor) {
    return switch (valor) {
      'cliente' => 'Cliente final',
      'parceiro_1_4' => 'Parceiro 1–4/mês',
      'parceiro_5_9' => 'Parceiro 5–9/mês',
      'parceiro_10_mais' => 'Parceiro 10+/mês',
      _ => 'Preço informado',
    };
  }

  static String _quantidade(double valor) {
    if (valor == valor.roundToDouble()) return valor.toInt().toString();
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _arquivoSeguro(String valor) {
    final normalizado = valor
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalizado.isEmpty ? 'orcamento' : normalizado;
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String _textoOu(dynamic valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }

  static double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(_texto(valor).replaceAll(',', '.')) ?? 0;
  }
}
