import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/configuracao.dart';
import '../../repositories/configuracao_repository.dart';

abstract class DocumentoPdfService {
  final ConfiguracaoRepository configuracaoRepository =
      ConfiguracaoRepository();

  Future<DocumentoPdfContexto> carregarContextoPdf() async {
    final configuracao = await configuracaoRepository.obterConfiguracao();

    final logo = await _carregarLogo(configuracao.caminhoLogo);

    return DocumentoPdfContexto(
      configuracao: configuracao,
      logo: logo,
      corPrincipal: converterCor(configuracao.corPrincipal),
      corSecundaria: converterCor(configuracao.corSecundaria),
    );
  }

  Future<pw.MemoryImage?> _carregarLogo(String? caminho) async {
    if (caminho == null || caminho.trim().isEmpty) {
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

      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  PdfColor converterCor(int valor) {
    final alpha = (valor >> 24) & 0xFF;
    final vermelho = (valor >> 16) & 0xFF;
    final verde = (valor >> 8) & 0xFF;
    final azul = valor & 0xFF;

    return PdfColor(vermelho / 255, verde / 255, azul / 255, alpha / 255);
  }

  String textoDoMapa(
    Map<dynamic, dynamic> mapa,
    String chave, {
    String padrao = '',
  }) {
    final valor = (mapa[chave] ?? '').toString().trim();

    if (valor.isEmpty) {
      return padrao;
    }

    return valor;
  }

  double numeroDoMapa(Map<dynamic, dynamic> mapa, String chave) {
    final valor = mapa[chave];

    if (valor is num) {
      return valor.toDouble();
    }

    var texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return 0;
    }

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '');

    if (texto.contains(',')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  String somenteNumeros(String texto) {
    return texto.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String montarNumeroWhatsApp(String telefone) {
    var numero = somenteNumeros(telefone);

    if (numero.isEmpty) {
      return '';
    }

    if (numero.startsWith('00')) {
      numero = numero.substring(2);
    }

    if (!numero.startsWith('55')) {
      numero = '55$numero';
    }

    return numero;
  }

  String montarLinkWhatsApp(Configuracao configuracao) {
    final numero = montarNumeroWhatsApp(
      configuracao.whatsapp.isNotEmpty
          ? configuracao.whatsapp
          : configuracao.telefone,
    );

    if (numero.isEmpty) {
      return '';
    }

    return 'https://wa.me/$numero';
  }

  String nomeEmpresa(Configuracao configuracao) {
    final nome = configuracao.nomeFantasia.trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    return 'Imperium Detailing';
  }

  List<String> montarDadosEmpresa(Configuracao configuracao) {
    final dados = <String>[];

    if (configuracao.razaoSocial.trim().isNotEmpty) {
      dados.add(configuracao.razaoSocial.trim());
    }

    if (configuracao.cnpj.trim().isNotEmpty) {
      dados.add('CNPJ: ${configuracao.cnpj.trim()}');
    }

    if (configuracao.inscricaoEstadual.trim().isNotEmpty) {
      dados.add(
        'Inscrição Estadual: '
        '${configuracao.inscricaoEstadual.trim()}',
      );
    }

    if (configuracao.enderecoCompleto.trim().isNotEmpty) {
      dados.add(configuracao.enderecoCompleto.trim());
    }

    final contatos = <String>[];

    if (configuracao.telefone.trim().isNotEmpty) {
      contatos.add(
        'Telefone: '
        '${configuracao.telefone.trim()}',
      );
    }

    if (configuracao.whatsapp.trim().isNotEmpty &&
        configuracao.whatsapp.trim() != configuracao.telefone.trim()) {
      contatos.add(
        'WhatsApp: '
        '${configuracao.whatsapp.trim()}',
      );
    }

    if (contatos.isNotEmpty) {
      dados.add(contatos.join(' • '));
    }

    final internet = <String>[];

    if (configuracao.email.trim().isNotEmpty) {
      internet.add(configuracao.email.trim());
    }

    if (configuracao.site.trim().isNotEmpty) {
      internet.add(configuracao.site.trim());
    }

    if (configuracao.instagram.trim().isNotEmpty) {
      var instagram = configuracao.instagram.trim();

      if (!instagram.startsWith('@')) {
        instagram = '@$instagram';
      }

      internet.add(instagram);
    }

    if (configuracao.facebook.trim().isNotEmpty) {
      internet.add(configuracao.facebook.trim());
    }

    if (internet.isNotEmpty) {
      dados.add(internet.join(' • '));
    }

    return dados;
  }

  String montarRodape(Configuracao configuracao) {
    final rodapePersonalizado = configuracao.rodapeDocumentos.trim();

    if (rodapePersonalizado.isNotEmpty) {
      return rodapePersonalizado;
    }

    final partes = <String>[nomeEmpresa(configuracao)];

    if (configuracao.telefonePrincipal.trim().isNotEmpty) {
      partes.add(configuracao.telefonePrincipal.trim());
    }

    if (configuracao.instagram.trim().isNotEmpty) {
      var instagram = configuracao.instagram.trim();

      if (!instagram.startsWith('@')) {
        instagram = '@$instagram';
      }

      partes.add(instagram);
    }

    return partes.join(' • ');
  }

  pw.Widget criarCodigoQrWhatsApp({
    required DocumentoPdfContexto contexto,
    double tamanho = 58,
  }) {
    final link = montarLinkWhatsApp(contexto.configuracao);

    if (link.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: link,
          width: tamanho,
          height: tamanho,
          color: PdfColors.black,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'WhatsApp',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget criarRodapePagina({
    required pw.Context context,
    required DocumentoPdfContexto documento,
  }) {
    final textoRodape = montarRodape(documento.configuracao);

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: PdfColors.grey400, thickness: 0.6),
        pw.SizedBox(height: 3),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Text(
                textoRodape,
                maxLines: 2,
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey600,
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Página ${context.pageNumber} '
              'de ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Uint8List? bytesDaLogo(DocumentoPdfContexto contexto) {
    return contexto.logo?.bytes;
  }
}

class DocumentoPdfContexto {
  const DocumentoPdfContexto({
    required this.configuracao,
    required this.logo,
    required this.corPrincipal,
    required this.corSecundaria,
  });

  final Configuracao configuracao;
  final pw.MemoryImage? logo;
  final PdfColor corPrincipal;
  final PdfColor corSecundaria;

  bool get possuiLogo {
    return logo != null;
  }

  String get nomeEmpresa {
    final nome = configuracao.nomeFantasia.trim();

    if (nome.isNotEmpty) {
      return nome;
    }

    return 'Imperium Detailing';
  }
}
