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
  const ConsultaPublicaFiscalException(
    this.mensagem, {
    this.codigo = 'consulta_publica_erro',
  });

  final String mensagem;
  final String codigo;

  bool get pendente => const {
    'captcha_required',
    'portal_content_unavailable',
    'portal_http_error',
    'portal_timeout',
  }.contains(codigo);

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
    late final ConsultaPublicaHttpResponse resposta;
    try {
      resposta = await (_fetcher ?? _buscar)(segura).timeout(_timeout);
    } on TimeoutException {
      throw const ConsultaPublicaFiscalException(
        'O portal fiscal demorou demais para responder. Use a consulta assistida ou tente novamente.',
        codigo: 'portal_timeout',
      );
    }
    _validarUrlOficial(resposta.finalUri);

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw ConsultaPublicaFiscalException(
        'O portal fiscal respondeu HTTP ${resposta.statusCode}. '
        'A chave foi reconhecida, mas os dados completos não puderam ser obtidos.',
        codigo: 'portal_http_error',
      );
    }

    final parsed = parsearHtml(
      resposta.body,
      chaveAcesso: capturada.chave,
      origemImportacao: origem,
    );

    return _repository.salvarNotaCompleta(
      nota: parsed.nota.copyWith(consultaUrl: segura.toString()),
      itens: parsed.itens,
      removerItensAusentes: true,
    );
  }

  Future<NotaFiscalEntrada> importarHtmlLiberado(
    String html, {
    required String chaveAcesso,
    String origemImportacao = 'qrCode',
    String? textoVisivel,
    String? consultaUrl,
  }) async {
    final parsed = parsearHtml(
      html,
      chaveAcesso: chaveAcesso,
      origemImportacao: origemImportacao,
      textoVisivel: textoVisivel,
    );
    return _repository.salvarNotaCompleta(
      nota: parsed.nota.copyWith(consultaUrl: consultaUrl),
      itens: parsed.itens,
      removerItensAusentes: true,
    );
  }

  NotaFiscalEntradaParseada parsearHtml(
    String html, {
    required String chaveAcesso,
    String origemImportacao = 'qrCode',
    String? importadaEm,
    String? textoVisivel,
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
    final linhasHtml = _linhasVisiveis(documento);
    final linhasRenderizadas =
        textoVisivel == null || textoVisivel.trim().isEmpty
        ? const <String>[]
        : _linhasDoTexto(textoVisivel);
    final linhas = linhasRenderizadas.isNotEmpty
        ? linhasRenderizadas
        : linhasHtml;
    final texto = linhas.join('\n');
    // A chave pode existir no DOM mas não estar na área atualmente renderizada.
    // Usamos ambos apenas para validação; itens e valores vêm do texto visível
    // quando o WebView consegue fornecê-lo.
    final textoValidacao = [
      texto,
      if (linhasRenderizadas.isNotEmpty) linhasHtml.join('\n'),
    ].join('\n');
    final textoMaiusculo = _semAcentos(textoValidacao).toUpperCase();

    if (textoMaiusculo.contains('AMBIENTE DE HOMOLOGACAO') ||
        textoMaiusculo.contains('SEM VALOR FISCAL')) {
      throw const ConsultaPublicaFiscalException(
        'Esta NFC-e é de homologação/sem valor fiscal e não será importada como compra.',
      );
    }

    final todosDigitos = textoValidacao.replaceAll(RegExp(r'\D'), '');
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
          codigo: 'captcha_required',
        );
      }
      throw const ConsultaPublicaFiscalException(
        'O portal abriu a NFC-e, mas não entregou os itens em HTML utilizável. '
        'Use a consulta assistida para carregar a página e importar os dados exibidos.',
        codigo: 'portal_content_unavailable',
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

  static Uri? resolverUrlPortal(Uri base, String valor) {
    final bruto = valor.trim();
    if (bruto.isEmpty ||
        bruto == 'about:blank' ||
        bruto.startsWith('javascript:')) {
      return null;
    }
    try {
      final parsed = Uri.parse(bruto);
      final resolvida = parsed.hasScheme ? parsed : base.resolveUri(parsed);
      final segura = urlSegura(resolvida);
      return urlOficial(segura) ? segura : null;
    } catch (_) {
      return null;
    }
  }

  static void _validarUrlOficial(Uri uri) {
    if (!urlOficial(uri)) {
      throw const ConsultaPublicaFiscalException(
        'Por segurança, o Imperium só consulta URLs fiscais oficiais em domínio gov.br.',
      );
    }
  }

  static List<String> _linhasDoTexto(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll('\t', ' ')
        .split(RegExp(r'[\r\n]+'))
        .map((linha) => linha.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((linha) => linha.isNotEmpty)
        .toList();
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

  static bool _linhaContemCnpjEmitente(String linha, String cnpjDigitos) {
    if (cnpjDigitos.length != 14) {
      return false;
    }

    final g1 = cnpjDigitos.substring(0, 2);
    final g2 = cnpjDigitos.substring(2, 5);
    final g3 = cnpjDigitos.substring(5, 8);
    final g4 = cnpjDigitos.substring(8, 12);
    final g5 = cnpjDigitos.substring(12, 14);

    // Exige o CNPJ como um identificador isolado. Isso impede que os 14
    // dígitos internos da chave de acesso (44 dígitos) sejam confundidos com
    // a linha do emitente.
    return RegExp(
      '(^|\\D)$g1[.\\s]*$g2[.\\s]*$g3[/\\s]*$g4[-\\s]*$g5(\\D|\$)',
    ).hasMatch(linha);
  }

  static String? _extrairEmitente(List<String> linhas, String cnpj) {
    final cnpjDigitos = cnpj.replaceAll(RegExp(r'\D'), '');
    final candidatos = <({String texto, int pontos})>[];

    void adicionar(String texto, int pontos) {
      final limpo = _limparNomeEmitente(texto);
      if (!_pareceNomeEmitente(limpo)) return;
      candidatos.add((texto: limpo, pontos: pontos));
    }

    for (var indice = 0; indice < linhas.length; indice++) {
      final linha = linhas[indice].trim();
      if (!_linhaContemCnpjEmitente(linha, cnpjDigitos)) continue;

      final cnpjMatch = RegExp(
        r'\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}',
      ).firstMatch(linha);

      if (cnpjMatch != null) {
        adicionar(linha.substring(0, cnpjMatch.start), 120);
        adicionar(linha.substring(cnpjMatch.end), 110);
      } else {
        adicionar(
          linha.replaceAll(RegExp(r'CNPJ\s*:?', caseSensitive: false), ''),
          90,
        );
      }

      for (var deslocamento = 1; deslocamento <= 6; deslocamento++) {
        final anterior = indice - deslocamento;
        final proximo = indice + deslocamento;
        if (anterior >= 0) {
          adicionar(linhas[anterior], 100 - deslocamento * 5);
        }
        if (proximo < linhas.length) {
          adicionar(linhas[proximo], 95 - deslocamento * 5);
        }
      }
    }

    for (var indice = 0; indice < linhas.length; indice++) {
      final normalizada = _semAcentos(linhas[indice]).toUpperCase();
      if (!normalizada.contains('NOME / RAZAO SOCIAL') &&
          !normalizada.contains('NOME/RAZAO SOCIAL')) {
        continue;
      }
      for (
        var proximo = indice + 1;
        proximo < linhas.length && proximo <= indice + 4;
        proximo++
      ) {
        final linha = linhas[proximo];
        if (_linhaContemCnpjEmitente(linha, cnpjDigitos)) {
          final match = RegExp(
            r'\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}',
          ).firstMatch(linha);
          if (match != null) adicionar(linha.substring(match.end), 115);
        } else {
          adicionar(linha, 80);
        }
      }
    }

    if (candidatos.isEmpty) return null;
    candidatos.sort((a, b) => b.pontos.compareTo(a.pontos));
    return candidatos.first.texto;
  }

  static String _limparNomeEmitente(String texto) {
    var valor = texto
        .replaceAll(RegExp(r'CNPJ\s*:?', caseSensitive: false), '')
        .replaceAll(RegExp(r'^[\s:;|\-]+|[\s:;|\-]+$'), '')
        .trim();

    final cortes = <RegExp>[
      RegExp(
        r'\s+(?:I\.?E\.?|INSCRI[CÇ][AÃ]O\s+ESTADUAL)\s*[:\-]?',
        caseSensitive: false,
      ),
      RegExp(r'\s+UF\s*[:\-]?', caseSensitive: false),
      RegExp(r'\s+ENDERE[CÇ]O\s*[:\-]?', caseSensitive: false),
      RegExp(r'\s+\d{6,}\s+(?:SC|[A-Z]{2})\s*$', caseSensitive: false),
    ];
    for (final corte in cortes) {
      final match = corte.firstMatch(valor);
      if (match != null && match.start > 1) {
        valor = valor.substring(0, match.start).trim();
      }
    }
    return valor;
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
      'FILTRAR ITENS',
      'NOME / RAZAO SOCIAL',
      'NOME/RAZAO SOCIAL',
      'INSCRICAO ESTADUAL',
      'INFORMACOES GERAIS',
      'EMISSAO NORMAL',
    ];
    if (bloqueados.any(normalizado.contains)) return false;

    const prefixosMetadados = [
      'EMISSAO',
      'PROTOCOLO',
      'VALOR ',
      'QTDE',
      'QUANTIDADE',
      'VL. UNIT',
      'VL UNIT',
      'FORMA DE PAGAMENTO',
      'AMBIENTE DE ',
      'CODIGO:',
      'CODIGO ',
    ];
    if (prefixosMetadados.any(normalizado.startsWith)) return false;

    const prefixosEndereco = [
      'RUA ',
      'AV ',
      'AV. ',
      'AVENIDA ',
      'RODOVIA ',
      'ESTRADA ',
      'CEP ',
      'BAIRRO ',
      'MUNICIPIO ',
    ];
    if (prefixosEndereco.any(normalizado.startsWith)) return false;
    return RegExp(r'[A-ZÀ-Ü]{2,}', caseSensitive: false).hasMatch(texto);
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
    // Portais estaduais quebram cada item em elementos visuais diferentes.
    // Trabalhamos sobre o texto renderizado e aceitamos as formas mais comuns:
    // "(Código: 123)", "Código: 123" e "Cod. 123".
    final codigoRegex = RegExp(
      r'(?:\(\s*)?(?:C[oó]digo|C[oó]d\.?)[\s.:]*([A-Z0-9._/\-]+)\s*\)?',
      caseSensitive: false,
    );
    final codigos = codigoRegex.allMatches(texto).where((match) {
      final codigo = match.group(1)?.trim() ?? '';
      return codigo.isNotEmpty && codigo.length <= 80;
    }).toList();
    final itens = <NotaFiscalEntradaItem>[];

    for (var indice = 0; indice < codigos.length; indice++) {
      final atual = codigos[indice];
      final inicioLinha = texto.lastIndexOf('\n', atual.start - 1) + 1;
      final proximoInicio = indice + 1 < codigos.length
          ? texto.lastIndexOf('\n', codigos[indice + 1].start - 1) + 1
          : -1;
      final limiteResumo = texto.indexOf(
        RegExp(
          r'(?:Qtd\.?|Qtde\.?|Quantidade)\s+total\s+de\s+itens',
          caseSensitive: false,
        ),
        atual.end,
      );
      final fim = proximoInicio >= 0
          ? proximoInicio
          : limiteResumo >= 0
          ? limiteResumo
          : texto.length;

      final bloco = texto.substring(inicioLinha, fim);
      final descricao = _descricaoDoItem(texto, atual.start);
      if (descricao == null) continue;

      final quantidade = _primeiroNumero(bloco, const [
        r'(?:Qtd(?:e)?|Qtde|Quantidade)\.?\s*:?\s*([0-9.,]+)',
        r'([0-9.,]+)\s*(?:x|X)\s*(?:R\$\s*)?[0-9.,]+',
      ]);

      String? unidade;
      for (final padrao in const [
        r'\bUN(?:ID(?:ADE)?)?\s*:?\s*([A-Z0-9]{1,12}?)(?=\s*(?:V[lI]\.?|Valor)|\s{2,}|\n|$)',
        r'\b(?:Unidade|UN)\s*:?\s*([A-Z]{1,12})\b',
      ]) {
        final match = RegExp(padrao, caseSensitive: false).firstMatch(bloco);
        final valor = match?.group(1)?.trim();
        if (valor != null && valor.isNotEmpty) {
          unidade = valor;
          break;
        }
      }

      final unitarioMatch = RegExp(
        r'(?:V[lI]\.?|Valor)\s*(?:Unit\.?|Unit[aá]rio)\s*:?\s*(?:R\$\s*)?([0-9.,]+)',
        caseSensitive: false,
      ).firstMatch(bloco);
      final unitario = unitarioMatch == null
          ? null
          : _numeroBr(unitarioMatch.group(1)!);

      double? valorTotal;
      final totalRotulado = RegExp(
        r'(?:V[lI]\.?|Valor)\s*Total\s*(?:R\$\s*)?[:=]?\s*([0-9.,]+)',
        caseSensitive: false,
      ).allMatches(bloco).toList();
      if (totalRotulado.isNotEmpty) {
        valorTotal = _numeroBr(totalRotulado.last.group(1)!);
      }

      // S@T/SEF-SC: o rótulo "Vl. Total" pode estar antes da linha de
      // quantidade e o valor aparece isolado depois do unitário.
      if (valorTotal == null && unitarioMatch != null) {
        final depoisUnitario = bloco.substring(unitarioMatch.end);
        final isolado = RegExp(
          r'(?:^|\n|\s{2,})([0-9]+(?:[.,][0-9]{1,4})?)(?=\s*(?:\n|$))',
        ).firstMatch(depoisUnitario);
        if (isolado != null) valorTotal = _numeroBr(isolado.group(1)!);
      }

      if (quantidade == null || quantidade <= 0 || unitario == null) continue;
      unidade ??= 'UN';
      valorTotal ??= quantidade * unitario;
      if (!valorTotal.isFinite || valorTotal < 0) continue;

      itens.add(
        NotaFiscalEntradaItem(
          notaFiscalId: 0,
          numeroItem: itens.length + 1,
          codigoProduto: atual.group(1)?.trim(),
          descricao: descricao,
          unidade: unidade.toUpperCase(),
          quantidade: quantidade,
          valorUnitario: unitario,
          valorTotal: valorTotal,
        ),
      );
    }
    return itens;
  }

  static double? _primeiroNumero(String texto, List<String> padroes) {
    for (final padrao in padroes) {
      final match = RegExp(padrao, caseSensitive: false).firstMatch(texto);
      if (match != null) {
        final numero = _numeroBr(match.group(1)!);
        if (numero != null) return numero;
      }
    }
    return null;
  }

  static String? _descricaoDoItem(String texto, int inicioCodigo) {
    final inicioLinha = texto.lastIndexOf('\n', inicioCodigo - 1) + 1;
    var mesmaLinha = texto.substring(inicioLinha, inicioCodigo).trim();
    mesmaLinha = mesmaLinha
        .replaceFirst(
          RegExp(r'^\s*V[lI]\.?\s*Total\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(r'\s*V[lI]\.?\s*Total\s*$', caseSensitive: false),
          '',
        )
        .trim();
    if (_pareceDescricaoItem(mesmaLinha)) return mesmaLinha;

    final anteriores = texto.substring(0, inicioLinha).split('\n');
    for (
      var i = anteriores.length - 1;
      i >= 0 && i >= anteriores.length - 5;
      i--
    ) {
      var candidato = anteriores[i].trim();
      candidato = candidato
          .replaceFirst(
            RegExp(r'^\s*V[lI]\.?\s*Total\s*', caseSensitive: false),
            '',
          )
          .trim();
      if (_pareceDescricaoItem(candidato)) return candidato;
    }
    return null;
  }

  static bool _pareceDescricaoItem(String texto) {
    if (texto.length < 2) return false;
    final normalizado = _semAcentos(texto).toUpperCase();
    const bloqueados = [
      'VL. TOTAL',
      'VL TOTAL',
      'QTDE.',
      'QTDE:',
      'QTD.',
      'UN:',
      'VL. UNIT',
      'FILTRAR ITENS',
      'VALOR TOTAL',
      'VALOR A PAGAR',
      'DESCONTOS',
    ];
    if (bloqueados.any(
      (item) => normalizado == item || normalizado.startsWith(item),
    )) {
      return false;
    }
    return !RegExp(r'^[0-9., R$]+$').hasMatch(texto);
  }

  static List<NotaFiscalEntradaItem> _extrairItensPorTabela(
    dom.Document documento,
  ) {
    final itens = <NotaFiscalEntradaItem>[];
    for (final tabela in documento.querySelectorAll('table')) {
      final linhas = tabela.querySelectorAll('tr');
      if (linhas.isEmpty) continue;

      Map<String, int>? mapa;
      for (final linha in linhas) {
        final celulasElementos = linha.querySelectorAll('th,td');
        final celulas = celulasElementos
            .map((item) => item.text.replaceAll('\u00A0', ' ').trim())
            .toList();
        if (celulas.isEmpty) continue;

        if (mapa == null) {
          final candidato = _mapearCabecalhoTabela(celulas);
          if (candidato.length >= 5 && candidato.containsKey('descricao')) {
            mapa = candidato;
            continue;
          }
        }
        if (mapa == null) continue;

        String campo(String chave) {
          final indice = mapa![chave];
          if (indice == null || indice < 0 || indice >= celulas.length) {
            return '';
          }
          return celulas[indice].trim();
        }

        final descricao = campo('descricao');
        final quantidade = _numeroBr(campo('quantidade'));
        final unitario = _numeroBr(campo('unitario'));
        final total = _numeroBr(campo('total'));
        if (descricao.length < 2 ||
            quantidade == null ||
            quantidade <= 0 ||
            unitario == null ||
            total == null) {
          continue;
        }

        itens.add(
          NotaFiscalEntradaItem(
            notaFiscalId: 0,
            numeroItem: itens.length + 1,
            codigoProduto: _textoNulo(campo('codigo')),
            descricao: descricao,
            unidade: campo('unidade').isEmpty ? 'UN' : campo('unidade'),
            quantidade: quantidade,
            valorUnitario: unitario,
            valorTotal: total,
          ),
        );
      }
    }
    return itens;
  }

  static Map<String, int> _mapearCabecalhoTabela(List<String> celulas) {
    final mapa = <String, int>{};
    for (var i = 0; i < celulas.length; i++) {
      final texto = _semAcentos(celulas[i]).toUpperCase();
      if (texto.contains('COD')) mapa.putIfAbsent('codigo', () => i);
      if (texto.contains('DESCR') || texto.contains('PRODUTO')) {
        mapa.putIfAbsent('descricao', () => i);
      }
      if (texto.contains('QTD') ||
          texto.contains('QTDE') ||
          texto.contains('QUANT')) {
        mapa.putIfAbsent('quantidade', () => i);
      }
      if (texto == 'UN' || texto.contains('UNIDADE')) {
        mapa.putIfAbsent('unidade', () => i);
      }
      if (texto.contains('UNIT')) mapa.putIfAbsent('unitario', () => i);
      if (texto.contains('TOTAL')) mapa.putIfAbsent('total', () => i);
    }
    return mapa;
  }

  static String? _textoNulo(String valor) =>
      valor.trim().isEmpty ? null : valor.trim();

  static double? _extrairValorRotulo(String texto, List<String> rotulos) {
    for (final rotulo in rotulos) {
      final match = RegExp(
        '$rotulo\\s*(?:R'
        r'\$\s*)?[:=]?\s*([0-9][0-9.,]*)',
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
