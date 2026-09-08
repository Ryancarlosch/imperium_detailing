import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import 'chave_fiscal_service.dart';

class NotaFiscalEntradaParseada {
  const NotaFiscalEntradaParseada({required this.nota, required this.itens});

  final NotaFiscalEntrada nota;
  final List<NotaFiscalEntradaItem> itens;
}

class NotaFiscalEntradaXmlService {
  NotaFiscalEntradaXmlService({this._repository});

  final NotaFiscalEntradaRepository? _repository;

  NotaFiscalEntradaParseada parsear(
    String xml, {
    String origemImportacao = 'xml',
    String? importadaEm,
  }) {
    if (xml.trim().isEmpty) {
      throw FormatException('XML fiscal vazio.');
    }
    if (origemImportacao != 'xml') {
      throw ArgumentError('Importação XML deve usar origem xml.');
    }

    final XmlDocument documento;
    try {
      documento = XmlDocument.parse(xml);
    } on XmlParserException catch (error) {
      throw FormatException('XML fiscal inválido: ${error.message}');
    } catch (error) {
      throw FormatException('XML fiscal inválido: $error');
    }

    final infNfe = _descendente(documento, 'infNFe');
    if (infNfe == null) {
      throw FormatException('XML fiscal não contém infNFe.');
    }

    final chaveInformada = _atributo(infNfe, 'Id');
    final chaveInfNfe = _normalizarChave(chaveInformada);
    _validarChave(chaveInfNfe, 'infNFe/@Id');

    final ide = _filho(infNfe, 'ide');
    if (ide == null) throw FormatException('XML fiscal não contém ide.');

    final modelo = _int(_textoFilho(ide, 'mod'));
    if (modelo != 55 && modelo != 65) {
      throw FormatException('Modelo fiscal não suportado: $modelo.');
    }

    final protocolo = _descendente(documento, 'protNFe');
    final infProt = protocolo == null ? null : _filho(protocolo, 'infProt');
    final chaveProtocolo = _normalizarChave(
      infProt == null ? '' : _textoFilho(infProt, 'chNFe'),
    );
    if (chaveProtocolo.isNotEmpty) {
      _validarChave(chaveProtocolo, 'protNFe/infProt/chNFe');
      if (chaveProtocolo != chaveInfNfe) {
        throw FormatException('Chaves fiscais divergentes no XML.');
      }
    }

    final emit = _filho(infNfe, 'emit');
    final total = _filho(_filho(infNfe, 'total'), 'ICMSTot');
    final emitenteNome = _textoFilho(emit, 'xNome');
    final emitenteCnpjCpf = _primeiroTexto(emit, const ['CNPJ', 'CPF']);
    final valorTotalTexto = _textoFilho(total, 'vNF');
    if (valorTotalTexto.isEmpty) {
      throw FormatException('XML fiscal não contém valor total vNF.');
    }
    final valorTotal = _doubleTexto(valorTotalTexto);

    final itens = <NotaFiscalEntradaItem>[];
    for (final det in _filhos(infNfe, 'det')) {
      final prod = _filho(det, 'prod');
      if (prod == null) {
        throw FormatException('Item fiscal sem grupo prod.');
      }

      final numeroItem = _int(_atributo(det, 'nItem'));
      if (numeroItem == null || numeroItem <= 0) {
        throw FormatException('Item fiscal sem numeroItem válido.');
      }

      itens.add(
        NotaFiscalEntradaItem(
          notaFiscalId: 0,
          numeroItem: numeroItem,
          codigoProduto: _textoNulo(_textoFilho(prod, 'cProd')),
          ean: _textoNulo(_primeiroTexto(prod, const ['cEAN', 'cEANTrib'])),
          descricao: _textoFilho(prod, 'xProd'),
          ncm: _textoNulo(_textoFilho(prod, 'NCM')),
          cfop: _textoNulo(_textoFilho(prod, 'CFOP')),
          unidade: _textoFilho(prod, 'uCom'),
          quantidade: _doubleTexto(_textoFilho(prod, 'qCom')),
          valorUnitario: _doubleTexto(_textoFilho(prod, 'vUnCom')),
          valorTotal: _doubleTexto(_textoFilho(prod, 'vProd')),
          valorDesconto: _doubleTexto(_textoFilho(prod, 'vDesc')),
        ),
      );
    }

    final dataEmissao = _textoNulo(
      _textoFilho(ide, 'dhEmi').isNotEmpty
          ? _textoFilho(ide, 'dhEmi')
          : _textoFilho(ide, 'dEmi'),
    );
    final numero = _int(_textoFilho(ide, 'nNF'));
    final serie = _int(_textoFilho(ide, 'serie'));
    if (numero == null || serie == null || dataEmissao == null) {
      throw FormatException(
        'XML fiscal não contém número, série ou data de emissão válidos.',
      );
    }
    if (emitenteNome.isEmpty || emitenteCnpjCpf.isEmpty) {
      throw FormatException('XML fiscal não contém emitente completo.');
    }
    final situacaoFiscal = _situacaoFiscal(infProt);

    final nota = NotaFiscalEntrada(
      chaveAcesso: chaveInfNfe,
      modelo: modelo,
      numero: numero,
      serie: serie,
      dataEmissao: dataEmissao,
      emitenteCnpjCpf: _textoNulo(emitenteCnpjCpf),
      emitenteNome: _textoNulo(emitenteNome),
      valorProdutos: _doubleTexto(_textoFilho(total, 'vProd')),
      valorFrete: _doubleTexto(_textoFilho(total, 'vFrete')),
      valorSeguro: _doubleTexto(_textoFilho(total, 'vSeg')),
      valorDesconto: _doubleTexto(_textoFilho(total, 'vDesc')),
      valorOutrasDespesas: _doubleTexto(_textoFilho(total, 'vOutro')),
      valorIpi: _doubleDescendente(total, const ['vIPI']),
      valorIcmsSt: _doubleTexto(_textoFilho(total, 'vST')),
      valorTotal: valorTotal,
      situacaoFiscal: situacaoFiscal,
      statusImportacao: 'pendente',
      origemImportacao: 'xml',
      xmlOriginal: xml,
      xmlHash: sha256.convert(utf8.encode(xml)).toString(),
      importadaEm: importadaEm ?? DateTime.now().toIso8601String(),
    );

    return NotaFiscalEntradaParseada(nota: nota, itens: itens);
  }

  Future<NotaFiscalEntrada> importarXml(
    String xml, {
    String? importadaEm,
  }) async {
    final parsed = parsear(xml, importadaEm: importadaEm);
    final repository = _repository;
    if (repository == null) {
      throw StateError('Repository fiscal não configurado para importação.');
    }
    return repository.salvarNotaCompleta(
      nota: parsed.nota,
      itens: parsed.itens,
      removerItensAusentes: true,
    );
  }

  String _situacaoFiscal(XmlElement? infProt) {
    if (infProt == null) return 'desconhecida';
    final cStat = _textoFilho(infProt, 'cStat');
    return cStat == '100' || cStat == '150' ? 'autorizada' : 'desconhecida';
  }

  static XmlElement? _descendente(XmlNode node, String nome) {
    for (final elemento in node.descendants.whereType<XmlElement>()) {
      if (elemento.localName == nome) return elemento;
    }
    return null;
  }

  static XmlElement? _filho(XmlElement? pai, String nome) {
    if (pai == null) return null;
    for (final filho in pai.children.whereType<XmlElement>()) {
      if (filho.localName == nome) return filho;
    }
    return null;
  }

  static List<XmlElement> _filhos(XmlElement pai, String nome) {
    return pai.children
        .whereType<XmlElement>()
        .where((filho) => filho.localName == nome)
        .toList();
  }

  static String _textoFilho(XmlElement? pai, String nome) {
    return _filho(pai, nome)?.innerText.trim() ?? '';
  }

  static String _primeiroTexto(XmlElement? pai, List<String> nomes) {
    for (final nome in nomes) {
      final valor = _textoFilho(pai, nome);
      if (valor.isNotEmpty) return valor;
    }
    return '';
  }

  static String _atributo(XmlElement elemento, String nome) {
    return elemento.getAttribute(nome)?.trim() ?? '';
  }

  static String _normalizarChave(String valor) {
    final chave = valor.trim();
    return chave.startsWith('NFe') ? chave.substring(3) : chave;
  }

  static void _validarChave(String chave, String origem) {
    if (!ChaveFiscalService.chaveValida(chave)) {
      throw FormatException('Chave fiscal inválida em $origem.');
    }
  }

  static int? _int(String valor) {
    if (valor.trim().isEmpty) return null;
    return int.tryParse(valor.trim());
  }

  static double _doubleTexto(String valor) {
    if (valor.trim().isEmpty) return 0;
    final resultado = double.tryParse(valor.trim().replaceAll(',', '.'));
    if (resultado == null) {
      throw FormatException('Valor numérico inválido: $valor.');
    }
    return resultado;
  }

  static double _doubleDescendente(XmlElement? pai, List<String> nomes) {
    if (pai == null) return 0;
    for (final nome in nomes) {
      final elemento = _descendente(pai, nome);
      if (elemento != null) return _doubleTexto(elemento.innerText);
    }
    return 0;
  }

  static String? _textoNulo(String valor) =>
      valor.trim().isEmpty ? null : valor.trim();
}
