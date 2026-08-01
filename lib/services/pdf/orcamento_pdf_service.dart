import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'documento_pdf_service.dart';
import 'widgets/cabecalho_pdf.dart';

class OrcamentoPdfService extends DocumentoPdfService {
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  Future<Uint8List> gerarPdf(
    Map<String, dynamic> dados, {
    required bool recibo,
  }) async {
    final contexto = await carregarContextoPdf();
    final documento = pw.Document();

    final numero = _numeroDocumento(dados);
    final status = _texto(dados, 'status');
    final emissao = _formatarData(_texto(dados, 'data_emissao'));
    final validade = _formatarData(_texto(dados, 'validade'));

    final cliente = _mapaCliente(dados);
    final veiculo = _mapaVeiculo(dados);

    final itens = _itens(dados);
    final subtotalItens = _subtotal(itens);
    final subtotalBanco = _numero(dados, 'subtotal_itens');
    final subtotal = subtotalBanco > 0 ? subtotalBanco : subtotalItens;
    final desconto = _numero(dados, 'desconto');
    final totalBanco = _numero(dados, 'valor_total');
    final totalFallback = (subtotal - desconto).clamp(0.0, double.infinity);
    final total = totalBanco > 0 ? totalBanco : totalFallback;

    final formaPagamento = _texto(dados, 'forma_pagamento');
    final observacoes = _texto(dados, 'observacoes');

    final assinaturaClienteBytes = await _carregarImagemSegura(
      _primeiroValorTexto(dados, [
        'assinatura_cliente',
        'caminho_assinatura_cliente',
      ]),
    );

    final assinaturaEmpresaBytes = await _carregarImagemSegura(
      _primeiroValorTexto(dados, [
        'assinatura_empresa',
        'caminho_assinatura_empresa',
      ]),
    );

    final tipoDocumento = recibo ? 'RECIBO' : 'ORÇAMENTO';

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 30),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox();
          }

          return CabecalhoPdf.criarCabecalhoPaginasSeguintes(
            contexto: contexto,
            tipoDocumento: tipoDocumento,
            numeroDocumento: numero,
          );
        },
        footer: (context) {
          return criarRodapePagina(context: context, documento: contexto);
        },
        build: (context) {
          return [
            CabecalhoPdf.criar(
              contexto: contexto,
              tipoDocumento: tipoDocumento,
              numeroDocumento: numero,
              status: recibo ? '' : status,
              mostrarQrCode: false,
            ),
            pw.SizedBox(height: 12),
            _secaoInformacoesDocumento(
              emissao: emissao,
              validade: validade,
              recibo: recibo,
            ),
            pw.SizedBox(height: 10),
            _secaoClienteVeiculo(cliente: cliente, veiculo: veiculo),
            pw.SizedBox(height: 10),
            _secaoItens(itens),
            pw.SizedBox(height: 10),
            _secaoTotais(
              subtotal: subtotal,
              desconto: desconto,
              total: total,
              formaPagamento: formaPagamento,
            ),
            if (observacoes.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _secaoObservacoes(observacoes),
            ],
            pw.SizedBox(height: 18),
            _secaoAssinaturas(
              contexto: contexto,
              nomeCliente: cliente['nome'] ?? '',
              assinaturaCliente: assinaturaClienteBytes,
              assinaturaEmpresa: assinaturaEmpresaBytes,
              emissao: emissao,
            ),
          ];
        },
      ),
    );

    return documento.save();
  }

  Future<void> compartilhar(
    Map<String, dynamic> dados, {
    required bool recibo,
  }) async {
    final bytes = await gerarPdf(dados, recibo: recibo);

    final numero = _numeroDocumento(dados);

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
    final bytes = await gerarPdf(dados, recibo: recibo);

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: recibo ? 'Recibo Imperium' : 'Orçamento Imperium',
    );
  }

  pw.Widget _secaoInformacoesDocumento({
    required String emissao,
    required String validade,
    required bool recibo,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
      ),
      child: pw.Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          _campoInfoDocumento('Data de emissão', emissao),
          if (!recibo && validade != '-')
            _campoInfoDocumento('Validade', validade),
          if (recibo)
            _campoInfoDocumento('Data do recibo', _data.format(DateTime.now())),
        ],
      ),
    );
  }

  pw.Widget _campoInfoDocumento(String titulo, String valor) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$titulo: ',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.TextSpan(
            text: valor,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
          ),
        ],
      ),
    );
  }

  pw.Widget _secaoClienteVeiculo({
    required Map<String, String> cliente,
    required Map<String, String> veiculo,
  }) {
    final camposCliente = <_CampoPdf>[];
    final nomeCliente = cliente['nome'] ?? '';

    if (nomeCliente.isNotEmpty) {
      camposCliente.add(_CampoPdf('Nome', nomeCliente));
    }

    if ((cliente['telefone'] ?? '').isNotEmpty) {
      camposCliente.add(_CampoPdf('Telefone', cliente['telefone']!));
    }

    if ((cliente['email'] ?? '').isNotEmpty) {
      camposCliente.add(_CampoPdf('E-mail', cliente['email']!));
    }

    if ((cliente['endereco'] ?? '').isNotEmpty) {
      camposCliente.add(
        _CampoPdf('Endereço', cliente['endereco']!, maxLinhas: 3),
      );
    }

    final camposVeiculo = <_CampoPdf>[];
    if ((veiculo['descricao'] ?? '').isNotEmpty) {
      camposVeiculo.add(_CampoPdf('Veículo', veiculo['descricao']!));
    }

    if ((veiculo['placa'] ?? '').isNotEmpty) {
      camposVeiculo.add(_CampoPdf('Placa', veiculo['placa']!));
    }

    if ((veiculo['cor'] ?? '').isNotEmpty) {
      camposVeiculo.add(_CampoPdf('Cor', veiculo['cor']!));
    }

    if ((veiculo['ano'] ?? '').isNotEmpty) {
      camposVeiculo.add(_CampoPdf('Ano', veiculo['ano']!));
    }

    if ((veiculo['quilometragem'] ?? '').isNotEmpty) {
      camposVeiculo.add(_CampoPdf('Quilometragem', veiculo['quilometragem']!));
    }

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
          _tituloSecao('DADOS DO CLIENTE E VEÍCULO'),
          pw.Padding(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (camposCliente.isEmpty)
                  _textoVazio('Dados do cliente não informados.')
                else
                  _gridCampos(camposCliente),
                if (camposVeiculo.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.6),
                  pw.SizedBox(height: 7),
                  _gridCampos(camposVeiculo),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _secaoItens(List<_ItemDocumento> itens) {
    if (itens.isEmpty) {
      return pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _tituloSecao('ITENS E SERVIÇOS'),
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: _textoVazio('Nenhum item informado.'),
            ),
          ],
        ),
      );
    }

    final linhas = itens.map((item) {
      return <String>[
        item.descricao,
        _formatarQuantidade(item.quantidade),
        _moeda.format(item.valorUnitario),
        _moeda.format(item.subtotal),
      ];
    }).toList();

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tituloSecao('ITENS E SERVIÇOS'),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: pw.TableHelper.fromTextArray(
              headers: const ['Descrição', 'Qtd.', 'Unitário', 'Subtotal'],
              data: linhas,
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey800,
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey900,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              columnWidths: const {
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(1.8),
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _secaoTotais({
    required double subtotal,
    required double desconto,
    required double total,
    required String formaPagamento,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.amber700, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: formaPagamento.isEmpty
                ? pw.SizedBox()
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FORMA DE PAGAMENTO',
                        style: pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        formaPagamento,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey900,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
          pw.SizedBox(width: 14),
          pw.SizedBox(
            width: 210,
            child: pw.Column(
              children: [
                _linhaTotal('Subtotal', _moeda.format(subtotal)),
                if (desconto > 0) ...[
                  pw.SizedBox(height: 4),
                  _linhaTotal('Desconto', _moeda.format(desconto)),
                ],
                pw.SizedBox(height: 7),
                pw.Divider(color: PdfColors.grey500, thickness: 0.6),
                _linhaTotal('TOTAL', _moeda.format(total), destaque: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _linhaTotal(String titulo, String valor, {bool destaque = false}) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            titulo,
            style: pw.TextStyle(
              fontSize: destaque ? 9.5 : 8,
              fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: destaque ? 13 : 8,
            fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  pw.Widget _secaoObservacoes(String observacoes) {
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
          _tituloSecao('OBSERVAÇÕES'),
          pw.Padding(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Text(
              observacoes,
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey900,
                lineSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _secaoAssinaturas({
    required DocumentoPdfContexto contexto,
    required String nomeCliente,
    required Uint8List? assinaturaCliente,
    required Uint8List? assinaturaEmpresa,
    required String emissao,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            emissao == '-' ? '' : 'Data: $emissao',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: _blocoAssinatura(
                titulo: 'Assinatura do cliente',
                nome: nomeCliente,
                bytes: assinaturaCliente,
              ),
            ),
            pw.SizedBox(width: 26),
            pw.Expanded(
              child: _blocoAssinatura(
                titulo: 'Assinatura da empresa',
                nome: contexto.nomeEmpresa,
                bytes: assinaturaEmpresa,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _blocoAssinatura({
    required String titulo,
    required String nome,
    required Uint8List? bytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 48,
          width: double.infinity,
          alignment: pw.Alignment.bottomCenter,
          child: bytes == null
              ? pw.SizedBox()
              : pw.Image(
                  pw.MemoryImage(bytes),
                  height: 44,
                  fit: pw.BoxFit.contain,
                ),
        ),
        pw.Container(height: 1, color: PdfColors.grey700),
        pw.SizedBox(height: 4),
        pw.Text(
          titulo,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey700,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (nome.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            nome,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
          ),
        ],
      ],
    );
  }

  pw.Widget _tituloSecao(String titulo) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const pw.BoxDecoration(color: PdfColors.grey800),
      child: pw.Text(
        titulo,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  pw.Widget _gridCampos(List<_CampoPdf> campos) {
    final linhas = <pw.Widget>[];

    for (var i = 0; i < campos.length; i += 2) {
      final campoEsquerda = campos[i];
      final campoDireita = i + 1 < campos.length ? campos[i + 1] : null;

      linhas.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _campo(campoEsquerda)),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: campoDireita == null
                    ? pw.SizedBox()
                    : _campo(campoDireita),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: linhas,
    );
  }

  pw.Widget _campo(_CampoPdf campo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          campo.rotulo.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: PdfColors.grey600,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          campo.valor,
          maxLines: campo.maxLinhas,
          style: const pw.TextStyle(
            fontSize: 8.5,
            color: PdfColors.grey900,
            lineSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  pw.Widget _textoVazio(String texto) {
    return pw.Text(
      texto,
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    );
  }

  List<_ItemDocumento> _itens(Map<String, dynamic> dados) {
    final origem = dados['itens'];
    final itens = <_ItemDocumento>[];

    if (origem is List) {
      for (final item in origem) {
        if (item is! Map) {
          continue;
        }

        final mapa = Map<String, dynamic>.from(item);

        final servico = _primeiroValorTexto(mapa, ['servico', 'nome']);

        final descricao = _texto(mapa, 'descricao');
        final descricaoCompleta = [
          servico,
          descricao,
        ].where((valor) => valor.trim().isNotEmpty).join('\n');

        if (descricaoCompleta.trim().isEmpty) {
          continue;
        }

        var quantidade = _numero(mapa, 'quantidade');
        if (quantidade <= 0) {
          quantidade = 1;
        }

        final valorUnitario = _numero(mapa, 'valor_unitario');

        itens.add(
          _ItemDocumento(
            descricao: descricaoCompleta,
            quantidade: quantidade,
            valorUnitario: valorUnitario,
          ),
        );
      }
    }

    if (itens.isEmpty) {
      final servicoLegado = _texto(dados, 'servico');
      final descricaoLegado = _texto(dados, 'descricao');
      final descricaoCompleta = [
        servicoLegado,
        descricaoLegado,
      ].where((valor) => valor.trim().isNotEmpty).join('\n');

      if (descricaoCompleta.isNotEmpty) {
        final valor = _numero(dados, 'valor');

        itens.add(
          _ItemDocumento(
            descricao: descricaoCompleta,
            quantidade: 1,
            valorUnitario: valor,
          ),
        );
      }
    }

    return itens;
  }

  double _subtotal(List<_ItemDocumento> itens) {
    return itens.fold<double>(0, (total, item) => total + item.subtotal);
  }

  Map<String, String> _mapaCliente(Map<String, dynamic> dados) {
    return {
      'nome': _texto(dados, 'cliente_nome'),
      'telefone': _texto(dados, 'cliente_telefone'),
      'email': _texto(dados, 'cliente_email'),
      'endereco': _texto(dados, 'cliente_endereco'),
    };
  }

  Map<String, String> _mapaVeiculo(Map<String, dynamic> dados) {
    final marca = _texto(dados, 'veiculo_marca');
    final modelo = _texto(dados, 'veiculo_modelo');

    final descricao = [
      marca,
      modelo,
    ].where((item) => item.isNotEmpty).join(' ');

    return {
      'descricao': descricao,
      'placa': _texto(dados, 'veiculo_placa').toUpperCase(),
      'cor': _texto(dados, 'veiculo_cor'),
      'ano': _texto(dados, 'veiculo_ano'),
      'quilometragem': _texto(dados, 'quilometragem'),
    };
  }

  String _numeroDocumento(Map<String, dynamic> dados) {
    final numero = _texto(dados, 'numero');
    if (numero.isNotEmpty) {
      return numero;
    }

    final id = _texto(dados, 'id');
    if (id.isNotEmpty) {
      return id;
    }

    return '-';
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return '-';
    }

    final data = DateTime.tryParse(valor.trim());
    if (data == null) {
      return valor.trim();
    }

    return _data.format(data);
  }

  String _formatarQuantidade(double quantidade) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }

  String _texto(Map<String, dynamic> dados, String chave) {
    final valor = (dados[chave] ?? '').toString().trim();

    if (valor.toLowerCase() == 'null') {
      return '';
    }

    return valor;
  }

  String _primeiroValorTexto(Map<dynamic, dynamic> dados, List<String> chaves) {
    for (final chave in chaves) {
      final valor = (dados[chave] ?? '').toString().trim();
      if (valor.isNotEmpty && valor.toLowerCase() != 'null') {
        return valor;
      }
    }

    return '';
  }

  double _numero(Map<String, dynamic> dados, String chave) {
    final valor = dados[chave];

    if (valor is num) {
      return valor.toDouble();
    }

    var texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty || texto.toLowerCase() == 'null') {
      return 0;
    }

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else if (texto.contains(',')) {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  Future<Uint8List?> _carregarImagemSegura(String caminho) async {
    if (caminho.trim().isEmpty) {
      return null;
    }

    try {
      final arquivo = File(caminho.trim());

      if (!await arquivo.exists()) {
        return null;
      }

      final bytes = await arquivo.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }

      return bytes;
    } catch (_) {
      return null;
    }
  }
}

class _CampoPdf {
  const _CampoPdf(this.rotulo, this.valor, {this.maxLinhas = 2});

  final String rotulo;
  final String valor;
  final int maxLinhas;
}

class _ItemDocumento {
  const _ItemDocumento({
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
  });

  final String descricao;
  final double quantidade;
  final double valorUnitario;

  double get subtotal => quantidade * valorUnitario;
}
