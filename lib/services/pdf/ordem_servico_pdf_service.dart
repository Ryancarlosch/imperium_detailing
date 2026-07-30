import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../repositories/foto_servico_repository.dart';
import '../../repositories/ordem_servico_repository.dart';

class OrdemServicoPdfService {
  final OrdemServicoRepository _repository =
  OrdemServicoRepository();

  final FotoServicoRepository _fotoRepository =
  FotoServicoRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  Future<Uint8List> gerarPdf({
    required int ordemServicoId,
  }) async {
    final dados = await _repository
        .buscarOrdemServicoCompletaPorId(
      ordemServicoId,
    );

    if (dados == null) {
      throw StateError(
        'Ordem de Serviço não encontrada.',
      );
    }

    final fotosPdf = await _carregarFotosParaPdf(
      dados,
    );

    final documento = pw.Document();

    final itens = _extrairItens(
      dados['itens'],
    );

    final numero = _texto(
      dados['numero'],
      padrao:
      'OS-${ordemServicoId.toString().padLeft(4, '0')}',
    );

    final status = _texto(
      dados['status'],
      padrao: 'Aberta',
    );

    final cliente = _texto(
      dados['cliente_nome'],
      padrao: 'Cliente não informado',
    );

    final telefone = _texto(
      dados['cliente_telefone'],
    );

    final email = _texto(
      dados['cliente_email'],
    );

    final endereco = _texto(
      dados['cliente_endereco'],
    );

    final veiculo = _montarVeiculo(dados);

    final placa = _texto(
      dados['veiculo_placa'],
    );

    final cor = _texto(
      dados['veiculo_cor'],
    );

    final ano = _texto(
      dados['veiculo_ano'],
    );

    final dataAbertura = _formatarData(
      dados['data_abertura'],
    );

    final dataInicio = _formatarData(
      dados['data_inicio'],
    );

    final dataFinalizacao = _formatarData(
      dados['data_finalizacao'],
    );

    final horaEntrada = _texto(
      dados['hora_entrada'],
    );

    final horaSaida = _texto(
      dados['hora_saida'],
    );

    final quilometragem = _texto(
      dados['quilometragem'],
    );

    final formaPagamento = _texto(
      dados['forma_pagamento'],
      padrao: 'Não informada',
    );

    final observacoes = _texto(
      dados['observacoes'],
    );

    final subtotalItens = itens.fold<double>(
      0,
          (total, item) {
        return total +
            (_numero(item['quantidade'], padrao: 1) *
                _numero(item['valor_unitario']));
      },
    );

    final valorTotalBanco = _numero(
      dados['valor_total'],
    );

    final desconto = _numero(
      dados['desconto'],
    );

    final valorTotal = valorTotalBanco > 0
        ? valorTotalBanco
        : (subtotalItens - desconto)
        .clamp(
      0.0,
      double.infinity,
    )
        .toDouble();


    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          34,
          34,
          34,
          40,
        ),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox();
          }

          return pw.Container(
            margin: const pw.EdgeInsets.only(
              bottom: 16,
            ),
            padding: const pw.EdgeInsets.only(
              bottom: 8,
            ),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColors.grey400,
                  width: 0.7,
                ),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'IMPERIUM DETAILING',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.Text(
                  'ORDEM DE SERVIÇO $numero',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(
              top: 16,
            ),
            padding: const pw.EdgeInsets.only(
              top: 8,
            ),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey400,
                  width: 0.6,
                ),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment:
              pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Imperium Detailing • Estética Automotiva',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de '
                      '${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            _cabecalho(
              numero: numero,
              status: status,
            ),
            pw.SizedBox(height: 18),
            _tituloSecao('DADOS DO CLIENTE'),
            _caixa(
              children: [
                _linhaInformacao(
                  titulo: 'Cliente',
                  valor: cliente,
                ),
                if (telefone.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Telefone',
                    valor: telefone,
                  ),
                if (email.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'E-mail',
                    valor: email,
                  ),
                if (endereco.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Endereço',
                    valor: endereco,
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            _tituloSecao('DADOS DO VEÍCULO'),
            _caixa(
              children: [
                _linhaInformacao(
                  titulo: 'Veículo',
                  valor: veiculo.isEmpty
                      ? 'Não informado'
                      : veiculo,
                ),
                if (placa.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Placa',
                    valor: placa,
                  ),
                if (cor.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Cor',
                    valor: cor,
                  ),
                if (ano.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Ano',
                    valor: ano,
                  ),
                if (quilometragem.isNotEmpty)
                  _linhaInformacao(
                    titulo: 'Quilometragem',
                    valor: quilometragem,
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            _tituloSecao('DATAS E HORÁRIOS'),
            _caixa(
              children: [
                _linhaInformacao(
                  titulo: 'Abertura',
                  valor: dataAbertura,
                ),
                if (dataInicio != '-')
                  _linhaInformacao(
                    titulo: 'Início',
                    valor: _juntarDataHora(
                      dataInicio,
                      horaEntrada,
                    ),
                  ),
                if (dataFinalizacao != '-')
                  _linhaInformacao(
                    titulo: 'Finalização',
                    valor: _juntarDataHora(
                      dataFinalizacao,
                      horaSaida,
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            _tituloSecao('SERVIÇOS'),
            _tabelaServicos(itens),
            pw.SizedBox(height: 14),
            _resumoFinanceiro(
              subtotal: subtotalItens,
              desconto: desconto,
              total: valorTotal,
              formaPagamento: formaPagamento,
            ),
            if (observacoes.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _tituloSecao('OBSERVAÇÕES'),
              _caixa(
                children: [
                  pw.Text(
                    observacoes,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      lineSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
            if (fotosPdf.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              _tituloSecao('REGISTRO FOTOGRÁFICO'),
              pw.SizedBox(height: 10),
              ...fotosPdf.map(
                    (foto) => _cartaoComparativoFoto(
                  foto,
                ),
              ),
            ],
            pw.SizedBox(height: 18),
            _declaracao(),
            pw.SizedBox(height: 42),
            _assinaturas(
              cliente: cliente,
            ),
          ];
        },
      ),
    );

    return documento.save();
  }

  Future<void> visualizarPdf({
    required int ordemServicoId,
  }) async {
    final bytes = await gerarPdf(
      ordemServicoId: ordemServicoId,
    );

    await Printing.layoutPdf(
      name: 'Ordem de Serviço',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> compartilharPdf({
    required int ordemServicoId,
  }) async {
    final bytes = await gerarPdf(
      ordemServicoId: ordemServicoId,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename:
      'ordem_servico_imperium_$ordemServicoId.pdf',
    );
  }

  pw.Widget _cabecalho({
    required String numero,
    required String status,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey900,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(
          color: PdfColors.amber700,
          width: 1,
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'IMPERIUM',
                  style: pw.TextStyle(
                    color: PdfColors.amber700,
                    fontSize: 23,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                pw.Text(
                  'DETAILING',
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'ESTÉTICA AUTOMOTIVA',
                  style: const pw.TextStyle(
                    color: PdfColors.grey400,
                    fontSize: 7,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment:
            pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'ORDEM DE SERVIÇO',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                numero,
                style: pw.TextStyle(
                  color: PdfColors.amber700,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius:
                  pw.BorderRadius.circular(20),
                ),
                child: pw.Text(
                  status.toUpperCase(),
                  style: pw.TextStyle(
                    color: PdfColors.grey900,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _tituloSecao(String titulo) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: const pw.BoxDecoration(
        color: PdfColors.amber700,
      ),
      child: pw.Text(
        titulo,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  pw.Widget _caixa({
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.7,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  pw.Widget _linhaInformacao({
    required String titulo,
    required String valor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        bottom: 5,
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 95,
            child: pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              valor,
              style: const pw.TextStyle(
                fontSize: 8.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tabelaServicos(
      List<Map<String, dynamic>> itens,
      ) {
    if (itens.isEmpty) {
      return _caixa(
        children: [
          pw.Text(
            'Nenhum serviço cadastrado.',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey300,
        width: 0.6,
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(25),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey200,
          ),
          children: [
            _celulaTabela(
              '#',
              cabecalho: true,
              alinhamento: pw.TextAlign.center,
            ),
            _celulaTabela(
              'Serviço',
              cabecalho: true,
            ),
            _celulaTabela(
              'Qtd.',
              cabecalho: true,
              alinhamento: pw.TextAlign.center,
            ),
            _celulaTabela(
              'Unitário',
              cabecalho: true,
              alinhamento: pw.TextAlign.right,
            ),
            _celulaTabela(
              'Total',
              cabecalho: true,
              alinhamento: pw.TextAlign.right,
            ),
          ],
        ),
        ...itens.asMap().entries.map(
              (entrada) {
            final indice = entrada.key;
            final item = entrada.value;

            final quantidade = _numero(
              item['quantidade'],
              padrao: 1,
            );

            final valorUnitario = _numero(
              item['valor_unitario'],
            );

            final total =
                quantidade * valorUnitario;

            final nome = _texto(
              item['servico'],
              padrao: _texto(
                item['nome'],
                padrao: 'Serviço',
              ),
            );

            final descricao = _texto(
              item['descricao'],
            );

            return pw.TableRow(
              children: [
                _celulaTabela(
                  '${indice + 1}',
                  alinhamento: pw.TextAlign.center,
                ),
                pw.Padding(
                  padding:
                  const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        nome,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight:
                          pw.FontWeight.bold,
                        ),
                      ),
                      if (descricao.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          descricao,
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _celulaTabela(
                  _formatarQuantidade(
                    quantidade,
                  ),
                  alinhamento: pw.TextAlign.center,
                ),
                _celulaTabela(
                  _moeda.format(valorUnitario),
                  alinhamento: pw.TextAlign.right,
                ),
                _celulaTabela(
                  _moeda.format(total),
                  alinhamento: pw.TextAlign.right,
                  negrito: true,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  pw.Widget _celulaTabela(
      String texto, {
        bool cabecalho = false,
        bool negrito = false,
        pw.TextAlign alinhamento =
            pw.TextAlign.left,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        texto,
        textAlign: alinhamento,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: cabecalho || negrito
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _resumoFinanceiro({
    required double subtotal,
    required double desconto,
    required double total,
    required String formaPagamento,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(
          color: PdfColors.amber700,
          width: 0.8,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment:
        pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'FORMA DE PAGAMENTO',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  formaPagamento,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 30),
          pw.SizedBox(
            width: 210,
            child: pw.Column(
              children: [
                _linhaValor(
                  titulo: 'Subtotal',
                  valor: _moeda.format(subtotal),
                ),
                if (desconto > 0) ...[
                  pw.SizedBox(height: 4),
                  _linhaValor(
                    titulo: 'Desconto',
                    valor: _moeda.format(desconto),
                  ),
                ],
                pw.SizedBox(height: 7),
                pw.Divider(
                  color: PdfColors.amber700,
                ),
                _linhaValor(
                  titulo: 'TOTAL',
                  valor: _moeda.format(total),
                  destaque: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _linhaValor({
    required String titulo,
    required String valor,
    bool destaque = false,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            titulo,
            style: pw.TextStyle(
              fontSize: destaque ? 10 : 8,
              fontWeight: destaque
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: destaque ? 13 : 8,
            fontWeight: destaque
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Future<List<_FotoPdfRegistro>>
  _carregarFotosParaPdf(
      Map<String, dynamic> dados,
      ) async {
    final clienteId = _inteiro(
      dados['cliente_id'],
    );

    final veiculoId = _inteiro(
      dados['veiculo_id'],
    );

    if (clienteId == null || veiculoId == null) {
      return [];
    }

    final registros = await _fotoRepository
        .listarFotosParaOrdemServico(
      clienteId: clienteId,
      veiculoId: veiculoId,
      limite: 6,
    );

    final fotos = <_FotoPdfRegistro>[];

    for (final registro in registros) {
      final caminhoAntes = _texto(
        registro['caminho_antes'],
      );

      final caminhoDepois = _texto(
        registro['caminho_depois'],
      );

      final bytesAntes = await _lerImagem(
        caminhoAntes,
      );

      final bytesDepois = await _lerImagem(
        caminhoDepois,
      );

      if (bytesAntes == null && bytesDepois == null) {
        continue;
      }

      fotos.add(
        _FotoPdfRegistro(
          antes: bytesAntes,
          depois: bytesDepois,
          descricao: _texto(
            registro['descricao'],
          ),
          data: _formatarData(
            registro['data'],
          ),
        ),
      );
    }

    return fotos;
  }

  Future<Uint8List?> _lerImagem(
      String caminho,
      ) async {
    if (caminho.isEmpty) {
      return null;
    }

    try {
      final arquivo = File(caminho);

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

  pw.Widget _cartaoComparativoFoto(
      _FotoPdfRegistro foto,
      ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(
        bottom: 12,
      ),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.grey300,
          width: 0.7,
        ),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          if (foto.descricao.isNotEmpty ||
              foto.data != '-')
            pw.Padding(
              padding: const pw.EdgeInsets.only(
                bottom: 8,
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      foto.descricao.isEmpty
                          ? 'Registro do serviço'
                          : foto.descricao,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  if (foto.data != '-')
                    pw.Text(
                      foto.data,
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey600,
                      ),
                    ),
                ],
              ),
            ),
          pw.Row(
            crossAxisAlignment:
            pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _imagemComLegenda(
                  titulo: 'ANTES',
                  bytes: foto.antes,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _imagemComLegenda(
                  titulo: 'DEPOIS',
                  bytes: foto.depois,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _imagemComLegenda({
    required String titulo,
    required Uint8List? bytes,
  }) {
    return pw.Column(
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
            vertical: 5,
          ),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey900,
          ),
          child: pw.Text(
            titulo,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: titulo == 'DEPOIS'
                  ? PdfColors.amber700
                  : PdfColors.white,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        pw.Container(
          width: double.infinity,
          height: 165,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(
              color: PdfColors.grey300,
              width: 0.5,
            ),
          ),
          child: bytes == null
              ? pw.Center(
            child: pw.Text(
              'Foto não disponível',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          )
              : pw.Image(
            pw.MemoryImage(bytes),
            fit: pw.BoxFit.cover,
          ),
        ),
      ],
    );
  }

  int? _inteiro(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(
      (valor ?? '').toString().trim(),
    );
  }

  pw.Widget _declaracao() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(
          color: PdfColors.grey300,
        ),
      ),
      child: pw.Text(
        'Declaro que as informações desta Ordem de Serviço '
            'estão corretas e autorizo a realização dos serviços '
            'descritos neste documento.',
        textAlign: pw.TextAlign.justify,
        style: const pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey700,
          lineSpacing: 2,
        ),
      ),
    );
  }

  pw.Widget _assinaturas({
    required String cliente,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _campoAssinatura(
            titulo: cliente,
            subtitulo: 'Assinatura do cliente',
          ),
        ),
        pw.SizedBox(width: 35),
        pw.Expanded(
          child: _campoAssinatura(
            titulo: 'Imperium Detailing',
            subtitulo:
            'Assinatura do responsável',
          ),
        ),
      ],
    );
  }

  pw.Widget _campoAssinatura({
    required String titulo,
    required String subtitulo,
  }) {
    return pw.Column(
      children: [
        pw.Container(
          height: 1,
          color: PdfColors.grey700,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          titulo,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          subtitulo,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _extrairItens(
      dynamic valor,
      ) {
    if (valor is! List) {
      return [];
    }

    return valor
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(
        item,
      ),
    )
        .toList();
  }

  String _montarVeiculo(
      Map<String, dynamic> dados,
      ) {
    return [
      _texto(dados['veiculo_marca']),
      _texto(dados['veiculo_modelo']),
    ].where(
          (valor) => valor.isNotEmpty,
    ).join(' ');
  }

  String _texto(
      dynamic valor, {
        String padrao = '',
      }) {
    final texto = (valor ?? '').toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  double _numero(
      dynamic valor, {
        double padrao = 0,
      }) {
    if (valor is num) {
      return valor.toDouble();
    }

    final texto = (valor ?? '')
        .toString()
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.contains(',') &&
        texto.contains('.')) {
      return double.tryParse(
        texto
            .replaceAll('.', '')
            .replaceAll(',', '.'),
      ) ??
          padrao;
    }

    return double.tryParse(
      texto.replaceAll(',', '.'),
    ) ??
        padrao;
  }

  String _formatarData(dynamic valor) {
    final texto = _texto(valor);

    if (texto.isEmpty) {
      return '-';
    }

    final data = DateTime.tryParse(texto);

    if (data == null) {
      return texto;
    }

    return _data.format(data);
  }

  String _juntarDataHora(
      String data,
      String hora,
      ) {
    if (hora.isEmpty) {
      return data;
    }

    return '$data às $hora';
  }

  String _formatarQuantidade(
      double quantidade,
      ) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',');
  }
}

class _FotoPdfRegistro {
  final Uint8List? antes;
  final Uint8List? depois;
  final String descricao;
  final String data;

  const _FotoPdfRegistro({
    required this.antes,
    required this.depois,
    required this.descricao,
    required this.data,
  });
}
