import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import 'chave_fiscal_service.dart';
import 'nota_fiscal_entrada_xml_service.dart';

class ConsultaPublicaFiscalException implements Exception {
  const ConsultaPublicaFiscalException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class ConsultaPublicaHttpResponse {
  const ConsultaPublicaHttpResponse({
    required this.statusCode,
    required this.body,
    required this.finalUri,
  });

  final int statusCode;
  final String body;
  final Uri finalUri;
}

typedef ConsultaPublicaFetcher =
    Future<ConsultaPublicaHttpResponse> Function(Uri uri);

class NotaFiscalConsultaPublicaService {
  NotaFiscalConsultaPublicaService({
    NotaFiscalEntradaRepository? repository,
    ConsultaPublicaFetcher? fetcher,
    Duration timeout = const Duration(seconds: 20),
  }) : _repository = repository ?? NotaFiscalEntradaRepository(),
       // Mantém os parâmetros públicos `fetcher` e `timeout` para injeção em testes.
       // ignore: prefer_initializing_formals
       _fetcher = fetcher,
       // ignore: prefer_initializing_formals
       _timeout = timeout;

  final NotaFiscalEntradaRepository _repository;
  final ConsultaPublicaFetcher? _fetcher;
  final Duration _timeout;

  Future<NotaFiscalEntrada> consultarEImportar(
    String conteudo, {
    required String origem,
  }) async {
    final capturada = ChaveFiscalService().extrair(conteudo, origem: origem);
    final modelo = modeloDaChave(capturada.chave);

    if (modelo != 65) {
      throw const ConsultaPublicaFiscalException(
        'A consulta automática sem XML está disponível para NFC-e (modelo 65) '
        'quando o QR Code fornece a URL pública. Para NF-e modelo 55, a chave '
        'sozinha não contém os itens e exige consulta DF-e autorizada.',
      );
    }

    final uri = extrairUrlConsulta(conteudo);
    if (uri == null) {
      throw const ConsultaPublicaFiscalException(
        'A chave da NFC-e foi lida, mas o conteúdo não trouxe a URL do QR Code. '
        'Escaneie o QR Code do cupom para importar fornecedor, itens e valores.',
      );
    }

    _validarUrlOficial(uri);
    final segura = urlSegura(uri);
    final resposta = await (_fetcher ?? _buscar)(segura).timeout(_timeout);
    _validarUrlOficial(resposta.finalUri);

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw ConsultaPublicaFiscalException(
        'O portal fiscal respondeu HTTP ${resposta.statusCode}. '
        'A chave foi reconhecida, mas os dados completos não puderam ser obtidos.',
      );
    }

    final parsed = parsearHtml(
      resposta.body,
      chaveAcesso: capturada.chave,
      origemImportacao: origem,
    );

    return _repository.salvarNotaCompleta(
      nota: parsed.nota,
      itens: parsed.itens,
      removerItensAusentes: true,
    );
  }

  Future<NotaFiscalEntrada> importarHtmlLiberado(
    String html, {
    required String chaveAcesso,
    String origemImportacao = 'qrCode',
  }) async {
    final parsed = parsearHtml(
      html,
      chaveAcesso: chaveAcesso,
      origemImportacao: origemImportacao,
    );
    return _repository.salvarNotaCompleta(
      nota: parsed.nota,
      itens: parsed.itens,
      removerItensAusentes: true,
    );
  }

  NotaFiscalEntradaParseada parsearHtml(
    String html, {
    required String chaveAcesso,
    String origemImportacao = 'qrCode',
    String? importadaEm,
  }) {
    final chave = ChaveFiscalService.normalizar(chaveAcesso);
    if (modeloDaChave(chave) != 65) {
      throw const ConsultaPublicaFiscalException(
        'A página pública informada não corresponde a uma NFC-e modelo 65.',
      );
    }
    if (html.trim().isEmpty) {
      throw const ConsultaPublicaFiscalException(
        'O portal retornou uma página vazia.',
      );
    }

    final documento = html_parser.parse(html);
    final linhas = _linhasVisiveis(documento);
    final texto = linhas.join('\n');
    final textoMaiusculo = _semAcentos(texto).toUpperCase();

    if (textoMaiusculo.contains('AMBIENTE DE HOMOLOGACAO') ||
        textoMaiusculo.contains('SEM VALOR FISCAL')) {
      throw const ConsultaPublicaFiscalException(
        'Esta NFC-e é de homologação/sem valor fiscal e não será importada como compra.',
      );
    }

    final todosDigitos = texto.replaceAll(RegExp(r'\D'), '');
    if (!todosDigitos.contains(chave)) {
      throw const ConsultaPublicaFiscalException(
        'A chave exibida pelo portal é diferente da chave lida no QR Code.',
      );
    }

    final itens = _extrairItens(documento, texto);
    if (itens.isEmpty) {
      if (textoMaiusculo.contains('RECAPTCHA') ||
          textoMaiusculo.contains('CAPTCHA')) {
        throw const ConsultaPublicaFiscalException(
          'O portal fiscal está aguardando a validação do CAPTCHA.',
        );
      }
      throw const ConsultaPublicaFiscalException(
        'O portal abriu a NFC-e, mas não entregou os itens em HTML utilizável. '
        'Use a consulta assistida para carregar a página e importar os dados exibidos.',
      );
    }

    final cnpj = cnpjEmitenteDaChave(chave);
    final emitente = _extrairEmitente(linhas, cnpj);
    if (emitente == null || emitente.trim().length < 2) {
      throw const ConsultaPublicaFiscalException(
        'Não foi possível identificar o nome do fornecedor na consulta pública.',
      );
    }

    final dataEmissao = _extrairDataEmissao(texto);
    if (dataEmissao == null) {
      throw const ConsultaPublicaFiscalException(
        'Não foi possível identificar a data de emissão da NFC-e.',
      );
    }

    final valorTotal = _extrairValorRotulo(texto, const [
      r'Valor\s+a\s+pagar\s*R\$\s*:?\s*',
      r'Valor\s+total\s*R\$\s*:?\s*',
    ]);
    if (valorTotal == null) {
      throw const ConsultaPublicaFiscalException(
        'Não foi possível identificar o valor total da NFC-e.',
      );
    }

    final valorProdutos = itens.fold<double>(
      0,
      (total, item) => total + item.valorTotal,
    );
    final valorDesconto =
        _extrairValorRotulo(texto, const [r'Descontos?\s*R\$\s*:?\s*']) ?? 0;
    final valorFrete =
        _extrairValorRotulo(texto, const [r'Frete\s*R\$\s*:?\s*']) ?? 0;

    final situacao = _situacaoFiscal(textoMaiusculo);
    final nota = NotaFiscalEntrada(
      chaveAcesso: chave,
      modelo: 65,
      numero: numeroDaChave(chave),
      serie: serieDaChave(chave),
      dataEmissao: dataEmissao,
      emitenteCnpjCpf: cnpj,
      emitenteNome: emitente.trim(),
      valorProdutos: valorProdutos,
      valorFrete: valorFrete,
      valorDesconto: valorDesconto,
      valorTotal: valorTotal,
      situacaoFiscal: situacao,
      statusImportacao: 'pendente',
      origemImportacao: origemImportacao,
      importadaEm: importadaEm ?? DateTime.now().toIso8601String(),
      observacoes: 'Dados obtidos da consulta pública da NFC-e via QR Code.',
    );

    return NotaFiscalEntradaParseada(nota: nota, itens: itens);
  }

  static Uri? extrairUrlConsulta(String conteudo) {
    final texto = conteudo.trim();
    final match = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    ).firstMatch(texto);
    if (match == null) return null;

    var url = match.group(0)!.trim();
    while (url.endsWith('.') || url.endsWith(',') || url.endsWith(';')) {
      url = url.substring(0, url.length - 1);
    }
    try {
      return Uri.parse(url);
    } catch (_) {
      return null;
    }
  }

  static int modeloDaChave(String chave) =>
      ChaveFiscalService.metadados(chave).modelo;

  static String cnpjEmitenteDaChave(String chave) =>
      ChaveFiscalService.metadados(chave).cnpjEmitente;

  static int serieDaChave(String chave) =>
      ChaveFiscalService.metadados(chave).serie;

  static int numeroDaChave(String chave) =>
      ChaveFiscalService.metadados(chave).numero;

  Future<ConsultaPublicaHttpResponse> _buscar(Uri uri) async {
    final client = http.Client();
    try {
      final resposta = await client.get(
        uri,
        headers: const {
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'pt-BR,pt;q=0.9',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              'Chrome/124 Mobile Safari/537.36 ImperiumManager/1.0',
        },
      );
      return ConsultaPublicaHttpResponse(
        statusCode: resposta.statusCode,
        body: resposta.body,
        finalUri: resposta.request?.url ?? uri,
      );
    } finally {
      client.close();
    }
  }

  static bool urlOficial(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final oficial = host == 'gov.br' || host.endsWith('.gov.br');
    return (scheme == 'https' || scheme == 'http') && oficial;
  }

  static Uri urlSegura(Uri uri) =>
      uri.scheme.toLowerCase() == 'http' ? uri.replace(scheme: 'https') : uri;

  static void _validarUrlOficial(Uri uri) {
    if (!urlOficial(uri)) {
      throw const ConsultaPublicaFiscalException(
        'Por segurança, o Imperium só consulta URLs fiscais oficiais em domínio gov.br.',
      );
    }
  }

  static List<String> _linhasVisiveis(dom.Document documento) {
    final buffer = StringBuffer();
    final blocos = <String>{
      'address',
      'article',
      'br',
      'div',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'header',
      'li',
      'p',
      'section',
      'table',
      'td',
      'th',
      'tr',
    };

    void visitar(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
      if (blocos.contains(tag)) buffer.write('\n');
      for (final filho in node.nodes) {
        visitar(filho);
      }
      if (blocos.contains(tag)) buffer.write('\n');
    }

    final raiz = documento.body ?? documento.documentElement;
    if (raiz != null) visitar(raiz);

    return buffer
        .toString()
        .replaceAll('\u00A0', ' ')
        .split(RegExp(r'[\r\n]+'))
        .map((linha) => linha.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((linha) => linha.isNotEmpty)
        .toList();
  }

  static String? _extrairEmitente(List<String> linhas, String cnpj) {
    final cnpjDigitos = cnpj.replaceAll(RegExp(r'\D'), '');
    for (var indice = 0; indice < linhas.length; indice++) {
      final linha = linhas[indice];
      final digitos = linha.replaceAll(RegExp(r'\D'), '');
      if (!linha.toUpperCase().contains('CNPJ') ||
          !digitos.contains(cnpjDigitos)) {
        continue;
      }

      final posicaoCnpj = linha.toUpperCase().indexOf('CNPJ');
      if (posicaoCnpj > 1) {
        final antes = linha.substring(0, posicaoCnpj).trim();
        if (_pareceNomeEmitente(antes)) return antes;
      }

      for (
        var anterior = indice - 1;
        anterior >= 0 && anterior >= indice - 5;
        anterior--
      ) {
        final candidato = linhas[anterior].trim();
        if (_pareceNomeEmitente(candidato)) return candidato;
      }
    }
    return null;
  }

  static bool _pareceNomeEmitente(String texto) {
    if (texto.length < 2 || RegExp(r'^\d+$').hasMatch(texto)) return false;
    final normalizado = _semAcentos(texto).toUpperCase();
    const bloqueados = [
      'DOCUMENTO AUXILIAR',
      'NOTA FISCAL DE CONSUMIDOR',
      'NFC-E',
      'CONSULTA',
      'SECRETARIA',
      'GOVERNO DO ESTADO',
      'CHAVE DE ACESSO',
    ];
    return !bloqueados.any(normalizado.contains);
  }

  static List<NotaFiscalEntradaItem> _extrairItens(
    dom.Document documento,
    String texto,
  ) {
    final cards = _extrairItensPorCards(texto);
    if (cards.isNotEmpty) return cards;
    return _extrairItensPorTabela(documento);
  }

  static List<NotaFiscalEntradaItem> _extrairItensPorCards(String texto) {
    final marcador = RegExp(
      r'^([^\n]{2,}?)\s*\(C[oó]digo:\s*([^)]+?)\s*\)',
      caseSensitive: false,
      multiLine: true,
    );
    final marcadores = marcador.allMatches(texto).toList();
    final itens = <NotaFiscalEntradaItem>[];

    for (var indice = 0; indice < marcadores.length; indice++) {
      final atual = marcadores[indice];
      final limiteNatural = texto.indexOf('Qtd. total', atual.end);
      final fim = indice + 1 < marcadores.length
          ? marcadores[indice + 1].start
          : limiteNatural >= 0
          ? limiteNatural
          : texto.length;
      final bloco = texto.substring(atual.start, fim);
      final quantidade = _capturarNumero(
        bloco,
        RegExp(r'Qtd(?:e)?\.?\s*:\s*([0-9.,]+)', caseSensitive: false),
      );
      final unidade = RegExp(
        r'\bUN\s*:\s*([^\s|]+)',
        caseSensitive: false,
      ).firstMatch(bloco)?.group(1)?.trim();
      final unitario = _capturarNumero(
        bloco,
        RegExp(
          r'V[lI]\.?\s*Unit\.?\s*:\s*(?:R\$\s*)?([0-9.,]+)',
          caseSensitive: false,
        ),
      );
      final totalMatches = RegExp(
        r'V[lI]\.?\s*Total\s*(?:R\$\s*)?[:]?\s*([0-9.,]+)',
        caseSensitive: false,
      ).allMatches(bloco).toList();
      final valorTotal = totalMatches.isEmpty
          ? null
          : _numeroBr(totalMatches.last.group(1)!);

      if (quantidade == null ||
          quantidade <= 0 ||
          unidade == null ||
          unidade.isEmpty ||
          unitario == null ||
          valorTotal == null) {
        continue;
      }

      itens.add(
        NotaFiscalEntradaItem(
          notaFiscalId: 0,
          numeroItem: itens.length + 1,
          codigoProduto: atual.group(2)?.trim(),
          descricao: atual.group(1)!.trim(),
          unidade: unidade,
          quantidade: quantidade,
          valorUnitario: unitario,
          valorTotal: valorTotal,
        ),
      );
    }
    return itens;
  }

  static List<NotaFiscalEntradaItem> _extrairItensPorTabela(
    dom.Document documento,
  ) {
    final itens = <NotaFiscalEntradaItem>[];
    for (final linha in documento.querySelectorAll('tr')) {
      final celulas = linha
          .querySelectorAll('td')
          .map((item) => item.text.replaceAll('\u00A0', ' ').trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (celulas.length < 6) continue;

      final quantidade = _numeroBr(celulas[2]);
      final unitario = _numeroBr(celulas[4]);
      final total = _numeroBr(celulas[5]);
      if (quantidade == null ||
          quantidade <= 0 ||
          unitario == null ||
          total == null ||
          celulas[1].length < 2) {
        continue;
      }

      itens.add(
        NotaFiscalEntradaItem(
          notaFiscalId: 0,
          numeroItem: itens.length + 1,
          codigoProduto: celulas[0],
          descricao: celulas[1],
          unidade: celulas[3],
          quantidade: quantidade,
          valorUnitario: unitario,
          valorTotal: total,
        ),
      );
    }
    return itens;
  }

  static double? _capturarNumero(String texto, RegExp regex) {
    final match = regex.firstMatch(texto);
    if (match == null) return null;
    return _numeroBr(match.group(1)!);
  }

  static double? _extrairValorRotulo(String texto, List<String> rotulos) {
    for (final rotulo in rotulos) {
      final match = RegExp(
        '$rotulo([0-9][0-9.,]*)',
        caseSensitive: false,
      ).firstMatch(texto);
      if (match != null) return _numeroBr(match.group(1)!);
    }
    return null;
  }

  static double? _numeroBr(String valor) {
    var texto = valor
        .replaceAll('R\$', '')
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .trim();
    if (texto.isEmpty) return null;

    if (texto.contains(',')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^-?\d{1,3}(?:\.\d{3})+$').hasMatch(texto)) {
      texto = texto.replaceAll('.', '');
    }
    return double.tryParse(texto);
  }

  static String? _extrairDataEmissao(String texto) {
    final match = RegExp(
      r'Emiss[aã]o\s*:\s*(\d{2})/(\d{2})/(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
      caseSensitive: false,
    ).firstMatch(texto);
    if (match == null) return null;

    final dia = int.parse(match.group(1)!);
    final mes = int.parse(match.group(2)!);
    final ano = int.parse(match.group(3)!);
    final hora = int.parse(match.group(4)!);
    final minuto = int.parse(match.group(5)!);
    final segundo = int.tryParse(match.group(6) ?? '') ?? 0;
    return DateTime(ano, mes, dia, hora, minuto, segundo).toIso8601String();
  }

  static String _situacaoFiscal(String textoMaiusculo) {
    if (textoMaiusculo.contains('CANCELAD')) return 'cancelada';
    if (textoMaiusculo.contains('DENEGAD')) return 'denegada';
    if (textoMaiusculo.contains('INUTILIZAD')) return 'inutilizada';
    return 'autorizada';
  }

  static String _semAcentos(String texto) => texto
      .replaceAll(RegExp('[ÁÀÂÃÄáàâãä]'), 'a')
      .replaceAll(RegExp('[ÉÈÊËéèêë]'), 'e')
      .replaceAll(RegExp('[ÍÌÎÏíìîï]'), 'i')
      .replaceAll(RegExp('[ÓÒÔÕÖóòôõö]'), 'o')
      .replaceAll(RegExp('[ÚÙÛÜúùûü]'), 'u')
      .replaceAll(RegExp('[Çç]'), 'c');
}
