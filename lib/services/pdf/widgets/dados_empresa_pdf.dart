import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../documento_pdf_service.dart';

class DadosEmpresaPdf {
  const DadosEmpresaPdf._();

  static pw.Widget criar({
    required DocumentoPdfContexto contexto,
    Map<dynamic, dynamic>? empresa,
    String titulo = 'DADOS DA EMPRESA',
    bool mostrarTitulo = true,
    bool mostrarResponsavel = true,
    bool mostrarEndereco = true,
    bool mostrarContato = true,
    bool mostrarDocumento = true,
  }) {
    final dados = empresa ?? const <dynamic, dynamic>{};

    final nomeEmpresa = _primeiroTexto(dados, [
      'nome_empresa',
      'empresa_nome',
      'nome_fantasia',
      'razao_social',
    ], padrao: contexto.nomeEmpresa);

    final razaoSocial = _primeiroTexto(dados, [
      'razao_social',
      'empresa_razao_social',
    ]);

    final cnpj = _primeiroTexto(dados, [
      'cnpj',
      'empresa_cnpj',
      'cpf_cnpj',
      'documento',
    ]);

    final responsavel = _primeiroTexto(dados, [
      'responsavel',
      'nome_responsavel',
      'proprietario',
      'nome_proprietario',
      'empresa_responsavel',
    ]);

    final telefone = _primeiroTexto(dados, [
      'telefone',
      'celular',
      'whatsapp',
      'empresa_telefone',
      'empresa_whatsapp',
    ]);

    final email = _primeiroTexto(dados, ['email', 'empresa_email']);

    final site = _primeiroTexto(dados, ['site', 'website', 'empresa_site']);

    final instagram = _primeiroTexto(dados, [
      'instagram',
      'empresa_instagram',
      'rede_social',
    ]);

    final endereco = _montarEndereco(dados);

    final campos = <_CampoEmpresaPdf>[];

    if (nomeEmpresa.isNotEmpty) {
      campos.add(
        _CampoEmpresaPdf(
          rotulo: 'Nome da empresa',
          valor: nomeEmpresa,
          destaque: true,
        ),
      );
    }

    if (razaoSocial.isNotEmpty &&
        razaoSocial.toLowerCase() != nomeEmpresa.toLowerCase()) {
      campos.add(_CampoEmpresaPdf(rotulo: 'Razão social', valor: razaoSocial));
    }

    if (mostrarDocumento && cnpj.isNotEmpty) {
      campos.add(
        _CampoEmpresaPdf(
          rotulo: _rotuloDocumento(cnpj),
          valor: _formatarDocumento(cnpj),
        ),
      );
    }

    if (mostrarResponsavel && responsavel.isNotEmpty) {
      campos.add(_CampoEmpresaPdf(rotulo: 'Responsável', valor: responsavel));
    }

    if (mostrarContato && telefone.isNotEmpty) {
      campos.add(
        _CampoEmpresaPdf(rotulo: 'Telefone / WhatsApp', valor: telefone),
      );
    }

    if (mostrarContato && email.isNotEmpty) {
      campos.add(_CampoEmpresaPdf(rotulo: 'E-mail', valor: email));
    }

    if (mostrarContato && site.isNotEmpty) {
      campos.add(_CampoEmpresaPdf(rotulo: 'Site', valor: site));
    }

    if (mostrarContato && instagram.isNotEmpty) {
      campos.add(
        _CampoEmpresaPdf(
          rotulo: 'Instagram',
          valor: _formatarInstagram(instagram),
        ),
      );
    }

    if (mostrarEndereco && endereco.isNotEmpty) {
      campos.add(
        _CampoEmpresaPdf(rotulo: 'Endereço', valor: endereco, maximoLinhas: 3),
      );
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
          if (mostrarTitulo) _criarTitulo(contexto: contexto, titulo: titulo),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: campos.isEmpty ? _criarMensagemVazia() : _criarGrade(campos),
          ),
        ],
      ),
    );
  }

  static pw.Widget criarCompacto({
    required DocumentoPdfContexto contexto,
    Map<dynamic, dynamic>? empresa,
  }) {
    final dados = empresa ?? const <dynamic, dynamic>{};

    final nomeEmpresa = _primeiroTexto(dados, [
      'nome_empresa',
      'empresa_nome',
      'nome_fantasia',
      'razao_social',
    ], padrao: contexto.nomeEmpresa);

    final telefone = _primeiroTexto(dados, [
      'telefone',
      'celular',
      'whatsapp',
      'empresa_telefone',
      'empresa_whatsapp',
    ]);

    final email = _primeiroTexto(dados, ['email', 'empresa_email']);

    final endereco = _montarEndereco(dados);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: contexto.corSecundaria,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: contexto.corPrincipal, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            nomeEmpresa.isEmpty ? 'EMPRESA' : nomeEmpresa.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: contexto.corPrincipal,
              letterSpacing: 0.6,
            ),
          ),
          if (telefone.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            _criarLinhaCompacta(rotulo: 'Telefone', valor: telefone),
          ],
          if (email.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            _criarLinhaCompacta(rotulo: 'E-mail', valor: email),
          ],
          if (endereco.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            _criarLinhaCompacta(rotulo: 'Endereço', valor: endereco),
          ],
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

  static pw.Widget _criarGrade(List<_CampoEmpresaPdf> campos) {
    final linhas = <pw.Widget>[];

    for (var indice = 0; indice < campos.length; indice += 2) {
      final primeiro = campos[indice];

      final segundo = indice + 1 < campos.length ? campos[indice + 1] : null;

      linhas.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _criarCampo(primeiro)),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: segundo == null ? pw.SizedBox() : _criarCampo(segundo),
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

  static pw.Widget _criarCampo(_CampoEmpresaPdf campo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
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

  static pw.Widget _criarLinhaCompacta({
    required String rotulo,
    required String valor,
  }) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$rotulo: ',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey300,
            ),
          ),
          pw.TextSpan(
            text: valor,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  static pw.Widget _criarMensagemVazia() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Text(
        'Dados da empresa não informados.',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
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

  static String _montarEndereco(Map<dynamic, dynamic> mapa) {
    final enderecoCompleto = _primeiroTexto(mapa, [
      'endereco_completo',
      'empresa_endereco_completo',
    ]);

    if (enderecoCompleto.isNotEmpty) {
      return enderecoCompleto;
    }

    final rua = _primeiroTexto(mapa, [
      'endereco',
      'logradouro',
      'rua',
      'empresa_endereco',
    ]);

    final numero = _primeiroTexto(mapa, ['numero', 'endereco_numero']);

    final complemento = _primeiroTexto(mapa, [
      'complemento',
      'endereco_complemento',
    ]);

    final bairro = _primeiroTexto(mapa, ['bairro', 'endereco_bairro']);

    final cidade = _primeiroTexto(mapa, ['cidade', 'endereco_cidade']);

    final estado = _primeiroTexto(mapa, ['estado', 'uf', 'endereco_estado']);

    final cep = _primeiroTexto(mapa, ['cep', 'endereco_cep']);

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
      cidadeEstado.add(estado.toUpperCase());
    }

    if (cidadeEstado.isNotEmpty) {
      segundaLinha.add(cidadeEstado.join(' - '));
    }

    if (cep.isNotEmpty) {
      segundaLinha.add('CEP: $cep');
    }

    final linhas = <String>[];

    if (primeiraLinha.isNotEmpty) {
      linhas.add(primeiraLinha.join(', '));
    }

    if (segundaLinha.isNotEmpty) {
      linhas.add(segundaLinha.join(' • '));
    }

    return linhas.join('\n');
  }

  static String _rotuloDocumento(String documento) {
    final numeros = documento.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 11) {
      return 'CPF';
    }

    if (numeros.length == 14) {
      return 'CNPJ';
    }

    return 'CPF / CNPJ';
  }

  static String _formatarDocumento(String documento) {
    final texto = documento.trim();

    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 11) {
      return '${numeros.substring(0, 3)}.'
          '${numeros.substring(3, 6)}.'
          '${numeros.substring(6, 9)}-'
          '${numeros.substring(9, 11)}';
    }

    if (numeros.length == 14) {
      return '${numeros.substring(0, 2)}.'
          '${numeros.substring(2, 5)}.'
          '${numeros.substring(5, 8)}/'
          '${numeros.substring(8, 12)}-'
          '${numeros.substring(12, 14)}';
    }

    return texto;
  }

  static String _formatarInstagram(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return '';
    }

    if (texto.startsWith('@')) {
      return texto;
    }

    if (texto.contains('instagram.com')) {
      return texto;
    }

    return '@$texto';
  }
}

class _CampoEmpresaPdf {
  const _CampoEmpresaPdf({
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
