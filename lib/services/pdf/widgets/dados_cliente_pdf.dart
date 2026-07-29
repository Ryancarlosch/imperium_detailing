import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class DadosClientePdf {
  const DadosClientePdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> cliente,
    Map<dynamic, dynamic>? veiculo,
    String titulo = 'DADOS DO CLIENTE',
    bool mostrarVeiculo = true,
  }) {
    final dadosCliente = _montarDadosCliente(
      cliente,
    );

    final dadosVeiculo = _montarDadosVeiculo(
      veiculo,
    );

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
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          _criarTitulo(
            contexto: contexto,
            titulo: titulo,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.start,
              children: [
                if (dadosCliente.isEmpty)
                  _criarMensagemVazia(
                    'Cliente não informado',
                  )
                else
                  _criarGradeDados(
                    dadosCliente,
                  ),
                if (mostrarVeiculo &&
                    dadosVeiculo.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Divider(
                    color: PdfColors.grey300,
                    thickness: 0.6,
                  ),
                  pw.SizedBox(height: 9),
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 4,
                        height: 13,
                        decoration: pw.BoxDecoration(
                          color: contexto.corPrincipal,
                          borderRadius:
                          pw.BorderRadius.circular(
                            2,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Text(
                        'VEÍCULO',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight:
                          pw.FontWeight.bold,
                          color: PdfColors.grey700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  _criarGradeDados(
                    dadosVeiculo,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget criarSomenteCliente({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> cliente,
    String titulo = 'DADOS DO CLIENTE',
  }) {
    return criar(
      contexto: contexto,
      cliente: cliente,
      mostrarVeiculo: false,
      titulo: titulo,
    );
  }

  static pw.Widget criarSomenteVeiculo({
    required DocumentoPdfContexto contexto,
    required Map<dynamic, dynamic> veiculo,
    String titulo = 'DADOS DO VEÍCULO',
  }) {
    final dadosVeiculo = _montarDadosVeiculo(
      veiculo,
    );

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
        crossAxisAlignment:
        pw.CrossAxisAlignment.start,
        children: [
          _criarTitulo(
            contexto: contexto,
            titulo: titulo,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: dadosVeiculo.isEmpty
                ? _criarMensagemVazia(
              'Veículo não informado',
            )
                : _criarGradeDados(
              dadosVeiculo,
            ),
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

  static pw.Widget _criarGradeDados(
      List<_CampoPdf> campos,
      ) {
    final linhas = <pw.Widget>[];

    for (var indice = 0;
    indice < campos.length;
    indice += 2) {
      final primeiro = campos[indice];

      final segundo =
      indice + 1 < campos.length
          ? campos[indice + 1]
          : null;

      linhas.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(
            bottom: 9,
          ),
          child: pw.Row(
            crossAxisAlignment:
            pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _criarCampo(
                  primeiro,
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: segundo == null
                    ? pw.SizedBox()
                    : _criarCampo(
                  segundo,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      children: linhas,
    );
  }

  static pw.Widget _criarCampo(
      _CampoPdf campo,
      ) {
    return pw.Column(
      crossAxisAlignment:
      pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          campo.rotulo.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 6.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey600,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          campo.valor,
          maxLines: campo.maximoLinhas,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey900,
            fontWeight: campo.destaque
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
            lineSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  static pw.Widget _criarMensagemVazia(
      String mensagem,
      ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: pw.Text(
        mensagem,
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  static List<_CampoPdf> _montarDadosCliente(
      Map<dynamic, dynamic> cliente,
      ) {
    final campos = <_CampoPdf>[];

    final nome = _primeiroTexto(
      cliente,
      [
        'nome',
        'cliente_nome',
        'nome_cliente',
        'razao_social',
      ],
    );

    final cpfCnpj = _primeiroTexto(
      cliente,
      [
        'cpf_cnpj',
        'cpf',
        'cnpj',
        'cliente_cpf_cnpj',
        'documento',
      ],
    );

    final telefone = _primeiroTexto(
      cliente,
      [
        'telefone',
        'celular',
        'whatsapp',
        'cliente_telefone',
      ],
    );

    final email = _primeiroTexto(
      cliente,
      [
        'email',
        'cliente_email',
      ],
    );

    final endereco = _montarEndereco(
      cliente,
    );

    if (nome.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Nome',
          valor: nome,
          destaque: true,
        ),
      );
    }

    if (cpfCnpj.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: _rotuloDocumento(
            cpfCnpj,
          ),
          valor: cpfCnpj,
        ),
      );
    }

    if (telefone.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Telefone / WhatsApp',
          valor: telefone,
        ),
      );
    }

    if (email.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'E-mail',
          valor: email,
        ),
      );
    }

    if (endereco.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Endereço',
          valor: endereco,
          maximoLinhas: 3,
        ),
      );
    }

    return campos;
  }

  static List<_CampoPdf> _montarDadosVeiculo(
      Map<dynamic, dynamic>? veiculo,
      ) {
    if (veiculo == null) {
      return [];
    }

    final campos = <_CampoPdf>[];

    final marca = _primeiroTexto(
      veiculo,
      [
        'marca',
        'veiculo_marca',
      ],
    );

    final modelo = _primeiroTexto(
      veiculo,
      [
        'modelo',
        'veiculo_modelo',
      ],
    );

    final nomeVeiculo = [
      marca,
      modelo,
    ].where(
          (valor) => valor.isNotEmpty,
    ).join(' ');

    final placa = _primeiroTexto(
      veiculo,
      [
        'placa',
        'veiculo_placa',
      ],
    );

    final ano = _primeiroTexto(
      veiculo,
      [
        'ano',
        'ano_modelo',
        'veiculo_ano',
      ],
    );

    final cor = _primeiroTexto(
      veiculo,
      [
        'cor',
        'veiculo_cor',
      ],
    );

    final quilometragem = _primeiroTexto(
      veiculo,
      [
        'quilometragem',
        'km',
        'veiculo_quilometragem',
      ],
    );

    final chassi = _primeiroTexto(
      veiculo,
      [
        'chassi',
        'veiculo_chassi',
      ],
    );

    if (nomeVeiculo.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Veículo',
          valor: nomeVeiculo,
          destaque: true,
        ),
      );
    }

    if (placa.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Placa',
          valor: placa.toUpperCase(),
          destaque: true,
        ),
      );
    }

    if (ano.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Ano',
          valor: ano,
        ),
      );
    }

    if (cor.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Cor',
          valor: cor,
        ),
      );
    }

    if (quilometragem.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Quilometragem',
          valor: _formatarQuilometragem(
            quilometragem,
          ),
        ),
      );
    }

    if (chassi.isNotEmpty) {
      campos.add(
        _CampoPdf(
          rotulo: 'Chassi',
          valor: chassi.toUpperCase(),
        ),
      );
    }

    return campos;
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

  static String _montarEndereco(
      Map<dynamic, dynamic> mapa,
      ) {
    final enderecoCompleto = _primeiroTexto(
      mapa,
      [
        'endereco_completo',
        'cliente_endereco_completo',
      ],
    );

    if (enderecoCompleto.isNotEmpty) {
      return enderecoCompleto;
    }

    final rua = _primeiroTexto(
      mapa,
      [
        'endereco',
        'logradouro',
        'rua',
        'cliente_endereco',
      ],
    );

    final numero = _primeiroTexto(
      mapa,
      [
        'numero',
        'endereco_numero',
      ],
    );

    final complemento = _primeiroTexto(
      mapa,
      [
        'complemento',
        'endereco_complemento',
      ],
    );

    final bairro = _primeiroTexto(
      mapa,
      [
        'bairro',
        'endereco_bairro',
      ],
    );

    final cidade = _primeiroTexto(
      mapa,
      [
        'cidade',
        'endereco_cidade',
      ],
    );

    final estado = _primeiroTexto(
      mapa,
      [
        'estado',
        'uf',
        'endereco_estado',
      ],
    );

    final cep = _primeiroTexto(
      mapa,
      [
        'cep',
        'endereco_cep',
      ],
    );

    final primeiraLinha = <String>[];

    if (rua.isNotEmpty) {
      primeiraLinha.add(rua);
    }

    if (numero.isNotEmpty) {
      primeiraLinha.add(numero);
    }

    if (complemento.isNotEmpty) {
      primeiraLinha.add(complemento);
    }

    final segundaLinha = <String>[];

    if (bairro.isNotEmpty) {
      segundaLinha.add(bairro);
    }

    final cidadeEstado = <String>[];

    if (cidade.isNotEmpty) {
      cidadeEstado.add(cidade);
    }

    if (estado.isNotEmpty) {
      cidadeEstado.add(
        estado.toUpperCase(),
      );
    }

    if (cidadeEstado.isNotEmpty) {
      segundaLinha.add(
        cidadeEstado.join(' - '),
      );
    }

    if (cep.isNotEmpty) {
      segundaLinha.add(
        'CEP: $cep',
      );
    }

    final linhas = <String>[];

    if (primeiraLinha.isNotEmpty) {
      linhas.add(
        primeiraLinha.join(', '),
      );
    }

    if (segundaLinha.isNotEmpty) {
      linhas.add(
        segundaLinha.join(' • '),
      );
    }

    return linhas.join('\n');
  }

  static String _rotuloDocumento(
      String documento,
      ) {
    final numeros = documento.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (numeros.length == 11) {
      return 'CPF';
    }

    if (numeros.length == 14) {
      return 'CNPJ';
    }

    return 'CPF / CNPJ';
  }

  static String _formatarQuilometragem(
      String valor,
      ) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return '';
    }

    if (texto.toLowerCase().contains('km')) {
      return texto;
    }

    return '$texto km';
  }
}

class _CampoPdf {
  const _CampoPdf({
    required this.rotulo,
    required this.valor,
    this.destaque = false,
    this.maximoLinhas = 2,
  });

  final String rotulo;
  final String valor;
  final bool destaque;
  final int maximoLinhas;
}