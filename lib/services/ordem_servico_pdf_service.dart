import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/produto_ordem_servico.dart';
import '../repositories/foto_servico_repository.dart';
import '../repositories/ordem_servico_checklist_repository.dart';
import '../repositories/ordem_servico_repository.dart';
import '../repositories/produto_ordem_servico_repository.dart';
import 'pdf/documento_pdf_service.dart';
import 'pdf/widgets/cabecalho_pdf.dart';

class OrdemServicoPdfService extends DocumentoPdfService {
  final OrdemServicoRepository _repository = OrdemServicoRepository();
  final OrdemServicoChecklistRepository _checklistRepository =
      OrdemServicoChecklistRepository();
  final ProdutoOrdemServicoRepository _produtoRepository =
      ProdutoOrdemServicoRepository();
  final FotoServicoRepository _fotoRepository = FotoServicoRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  Future<Uint8List> gerarPdf({required int ordemServicoId}) async {
    final contexto = await carregarContextoPdf();

    final dados = await _repository.buscarOrdemServicoCompletaPorId(
      ordemServicoId,
    );

    if (dados == null) {
      throw StateError('Ordem de Serviço não encontrada.');
    }

    final checklist = await _checklistRepository.listarChecklist(
      ordemServicoId,
    );
    final produtos = await _produtoRepository.listarProdutosPorOrdemServico(
      ordemServicoId,
    );
    final fotos = await _carregarFotosParaPdf(dados);

    final documento = pw.Document();

    final numero = _numeroDocumento(dados, ordemServicoId);
    final status = _texto(dados, 'status', padrao: 'Aberta');
    final emissao = _formatarData(_texto(dados, 'data_abertura'));

    final cliente = _mapaCliente(dados);
    final veiculo = _mapaVeiculo(dados);

    final itens = _itens(dados['itens']);
    final subtotalItens = _subtotal(itens);
    final desconto = _numero(dados, 'desconto');
    final totalBanco = _numero(dados, 'valor_total');
    final totalFallback = (subtotalItens - desconto).clamp(
      0.0,
      double.infinity,
    );
    final totalFinal = totalBanco > 0 ? totalBanco : totalFallback;

    final formaPagamento = _texto(dados, 'forma_pagamento');
    final observacoes = _texto(dados, 'observacoes');

    final assinaturaCliente = await _carregarImagemSegura(
      _texto(dados, 'assinatura_cliente'),
    );

    final assinaturaEmpresa = await _carregarImagemSegura(
      _primeiroValorTexto(dados, [
            'assinatura_empresa',
            'caminho_assinatura_empresa',
          ]).isNotEmpty
          ? _primeiroValorTexto(dados, [
              'assinatura_empresa',
              'caminho_assinatura_empresa',
            ])
          : (contexto.configuracao.caminhoAssinaturaEmpresa ?? ''),
    );

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 20, 26, 24),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox();
          }

          return CabecalhoPdf.criarCabecalhoPaginasSeguintes(
            contexto: contexto,
            tipoDocumento: 'ORDEM DE SERVIÇO',
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
              tipoDocumento: 'ORDEM DE SERVIÇO',
              numeroDocumento: numero,
              status: status,
              mostrarQrCode: false,
            ),
            pw.SizedBox(height: 9),
            _secaoInformacoesOs(dados: dados, emissao: emissao),
            pw.SizedBox(height: 8),
            _secaoClienteVeiculo(cliente: cliente, veiculo: veiculo),
            pw.SizedBox(height: 8),
            _secaoItens(itens),
            pw.SizedBox(height: 8),
            _secaoTotais(
              subtotal: subtotalItens,
              desconto: desconto,
              total: totalFinal,
              formaPagamento: formaPagamento,
            ),
            if (checklist.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _secaoChecklistResumo(checklist),
            ],
            if (produtos.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _secaoProdutos(produtos),
            ],
            if (observacoes.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _secaoObservacoes(observacoes),
            ],
            if (fotos.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              _secaoFotos(fotos),
            ],
            pw.SizedBox(height: 12),
            _secaoAssinaturas(
              contexto: contexto,
              nomeCliente: cliente['nome'] ?? '',
              assinaturaCliente: assinaturaCliente,
              assinaturaEmpresa: assinaturaEmpresa,
              data: _dataAssinatura(dados),
            ),
          ];
        },
      ),
    );

    return documento.save();
  }

  Future<void> visualizarPdf({required int ordemServicoId}) async {
    final bytes = await gerarPdf(ordemServicoId: ordemServicoId);

    await Printing.layoutPdf(
      name: 'Ordem de Serviço',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> compartilharPdf({required int ordemServicoId}) async {
    final bytes = await gerarPdf(ordemServicoId: ordemServicoId);

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'ordem_servico_imperium_$ordemServicoId.pdf',
    );
  }

  pw.Widget _secaoInformacoesOs({
    required Map<String, dynamic> dados,
    required String emissao,
  }) {
    final dataEntrada = _juntarDataHora(
      _formatarData(_texto(dados, 'data_inicio')),
      _texto(dados, 'hora_entrada'),
    );

    final dataSaida = _juntarDataHora(
      _formatarData(_texto(dados, 'data_finalizacao')),
      _texto(dados, 'hora_saida'),
    );

    final responsavel = _texto(dados, 'funcionario_responsavel');

    final quilometragem = _texto(dados, 'quilometragem');

    final campos = <_CampoPdf>[_CampoPdf('Data de emissão', emissao)];

    if (dataEntrada.isNotEmpty) {
      campos.add(_CampoPdf('Entrada', dataEntrada));
    }

    if (dataSaida.isNotEmpty) {
      campos.add(_CampoPdf('Saída', dataSaida));
    }

    if (responsavel.isNotEmpty) {
      campos.add(_CampoPdf('Responsável', responsavel));
    }

    if (quilometragem.isNotEmpty) {
      campos.add(_CampoPdf('Quilometragem', quilometragem));
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
          _tituloSecao('INFORMAÇÕES DA ORDEM'),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: _gridCampos(campos),
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

    if ((cliente['nome'] ?? '').isNotEmpty) {
      camposCliente.add(_CampoPdf('Nome', cliente['nome']!));
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
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (camposCliente.isEmpty)
                  _textoVazio('Dados do cliente não informados.')
                else
                  _gridCampos(camposCliente),
                if (camposVeiculo.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.6),
                  pw.SizedBox(height: 5),
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
              padding: const pw.EdgeInsets.all(10),
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
            padding: const pw.EdgeInsets.fromLTRB(7, 7, 7, 7),
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
                vertical: 5,
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
      padding: const pw.EdgeInsets.all(10),
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
                      pw.SizedBox(height: 2),
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
          pw.SizedBox(width: 12),
          pw.SizedBox(
            width: 210,
            child: pw.Column(
              children: [
                _linhaTotal('Subtotal', _moeda.format(subtotal)),
                if (desconto > 0) ...[
                  pw.SizedBox(height: 3),
                  _linhaTotal('Desconto', _moeda.format(desconto)),
                ],
                pw.SizedBox(height: 5),
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

  pw.Widget _secaoChecklistResumo(List<Map<String, dynamic>> checklist) {
    var total = 0;
    var ok = 0;
    var avaria = 0;

    final itensAvaria = <String>[];

    for (final item in checklist) {
      total++;

      final status = _paraInt(item['status']);

      if (status == OrdemServicoChecklistRepository.statusOk) {
        ok++;
      }

      if (status == OrdemServicoChecklistRepository.statusAvaria) {
        avaria++;

        final nomeItem = (item['item'] ?? '').toString().trim();
        final observacao = (item['observacao'] ?? '').toString().trim();
        final texto = observacao.isEmpty ? nomeItem : '$nomeItem: $observacao';

        if (texto.trim().isNotEmpty) {
          itensAvaria.add(texto.trim());
        }
      }
    }

    final naoVerificado = total - ok - avaria;

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
          _tituloSecao('CHECKLIST (RESUMO)'),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _chipResumo('Itens', total.toString()),
                    _chipResumo('OK', ok.toString()),
                    _chipResumo('Com avaria', avaria.toString()),
                    _chipResumo('Não verificado', naoVerificado.toString()),
                  ],
                ),
                if (itensAvaria.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Avarias registradas:',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey800,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  ...itensAvaria
                      .take(8)
                      .map(
                        (descricao) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '• ',
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                              pw.Expanded(
                                child: pw.Text(
                                  descricao,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey800,
                                    lineSpacing: 1.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _chipResumo(String titulo, String valor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        '$titulo: $valor',
        style: pw.TextStyle(
          fontSize: 7.5,
          color: PdfColors.grey800,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _secaoProdutos(List<ProdutoOrdemServico> produtos) {
    final linhas = produtos.map((produto) {
      final unidade = produto.unidade.trim();
      final qtd = _formatarQuantidade(produto.quantidade);
      final quantidadeComUnidade = unidade.isEmpty ? qtd : '$qtd $unidade';

      return <String>[
        produto.produtoNome.trim().isEmpty
            ? 'Produto'
            : produto.produtoNome.trim(),
        quantidadeComUnidade,
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
          _tituloSecao('PRODUTOS UTILIZADOS'),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(7, 7, 7, 7),
            child: pw.TableHelper.fromTextArray(
              headers: const ['Produto', 'Quantidade'],
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
              },
              columnWidths: const {
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(2),
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
            ),
          ),
        ],
      ),
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
            padding: const pw.EdgeInsets.all(10),
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

  pw.Widget _secaoFotos(List<_FotoPdfRegistro> fotos) {
    final cards = fotos.take(4).map(_cartaoComparativoFoto).toList();

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
          _tituloSecao('REGISTRO FOTOGRÁFICO'),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(children: cards),
          ),
        ],
      ),
    );
  }

  pw.Widget _cartaoComparativoFoto(_FotoPdfRegistro foto) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (foto.descricao.isNotEmpty || foto.data.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      foto.descricao.isEmpty
                          ? 'Registro do serviço'
                          : foto.descricao,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ),
                  if (foto.data.isNotEmpty)
                    pw.Text(
                      foto.data,
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                ],
              ),
            ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _imagemComLegenda('ANTES', foto.antes)),
              pw.SizedBox(width: 6),
              pw.Expanded(child: _imagemComLegenda('DEPOIS', foto.depois)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _imagemComLegenda(String titulo, Uint8List? bytes) {
    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          color: PdfColors.grey800,
          child: pw.Text(
            titulo,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Container(
          width: double.infinity,
          height: 120,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: bytes == null
              ? pw.Center(
                  child: pw.Text(
                    'Foto não disponível',
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                )
              : pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
        ),
      ],
    );
  }

  pw.Widget _secaoAssinaturas({
    required DocumentoPdfContexto contexto,
    required String nomeCliente,
    required Uint8List? assinaturaCliente,
    required Uint8List? assinaturaEmpresa,
    required String data,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (data.isNotEmpty)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Data: $data',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ),
        pw.SizedBox(height: 9),
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
            pw.SizedBox(width: 22),
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
          height: 42,
          width: double.infinity,
          alignment: pw.Alignment.bottomCenter,
          child: bytes == null
              ? pw.SizedBox()
              : pw.Image(
                  pw.MemoryImage(bytes),
                  height: 38,
                  fit: pw.BoxFit.contain,
                ),
        ),
        pw.Container(height: 1, color: PdfColors.grey700),
        pw.SizedBox(height: 3),
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
          pw.SizedBox(height: 1.5),
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    if (campos.isEmpty) {
      return pw.SizedBox();
    }

    final linhas = <pw.Widget>[];

    for (var i = 0; i < campos.length; i += 2) {
      final esquerda = campos[i];
      final direita = i + 1 < campos.length ? campos[i + 1] : null;

      linhas.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _campo(esquerda)),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: direita == null ? pw.SizedBox() : _campo(direita),
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

  List<_ItemDocumento> _itens(dynamic origem) {
    if (origem is! List) {
      return [];
    }

    final itens = <_ItemDocumento>[];

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

  Future<List<_FotoPdfRegistro>> _carregarFotosParaPdf(
    Map<String, dynamic> dados,
  ) async {
    final clienteId = _paraInt(dados['cliente_id']);
    final veiculoId = _paraInt(dados['veiculo_id']);

    if (clienteId == null || veiculoId == null) {
      return [];
    }

    final registros = await _fotoRepository.listarFotosParaOrdemServico(
      clienteId: clienteId,
      veiculoId: veiculoId,
      limite: 4,
    );

    final fotos = <_FotoPdfRegistro>[];

    for (final registro in registros) {
      final caminhoAntes = _texto(registro, 'caminho_antes');
      final caminhoDepois = _texto(registro, 'caminho_depois');

      final bytesAntes = await _carregarImagemSegura(caminhoAntes);
      final bytesDepois = await _carregarImagemSegura(caminhoDepois);

      if (bytesAntes == null && bytesDepois == null) {
        continue;
      }

      fotos.add(
        _FotoPdfRegistro(
          antes: bytesAntes,
          depois: bytesDepois,
          descricao: _texto(registro, 'descricao'),
          data: _formatarData(_texto(registro, 'data')),
        ),
      );
    }

    return fotos;
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

  String _dataAssinatura(Map<String, dynamic> dados) {
    final finalizacao = _formatarData(_texto(dados, 'data_finalizacao'));
    if (finalizacao != '-') {
      return finalizacao;
    }

    final emissao = _formatarData(_texto(dados, 'data_abertura'));
    if (emissao != '-') {
      return emissao;
    }

    return '';
  }

  String _juntarDataHora(String data, String hora) {
    if (data == '-' || data.isEmpty) {
      return '';
    }

    if (hora.trim().isEmpty) {
      return data;
    }

    return '$data às ${hora.trim()}';
  }

  String _numeroDocumento(Map<String, dynamic> dados, int ordemServicoId) {
    final numero = _texto(dados, 'numero');
    if (numero.isNotEmpty) {
      return numero;
    }

    return 'OS-${ordemServicoId.toString().padLeft(4, '0')}';
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

  String _texto(
    Map<dynamic, dynamic> dados,
    String chave, {
    String padrao = '',
  }) {
    final valor = (dados[chave] ?? '').toString().trim();

    if (valor.isEmpty || valor.toLowerCase() == 'null') {
      return padrao;
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

  double _numero(Map<dynamic, dynamic> dados, String chave) {
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

  int? _paraInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse((valor ?? '').toString().trim());
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

class _FotoPdfRegistro {
  const _FotoPdfRegistro({
    required this.antes,
    required this.depois,
    required this.descricao,
    required this.data,
  });

  final Uint8List? antes;
  final Uint8List? depois;
  final String descricao;
  final String data;
}
