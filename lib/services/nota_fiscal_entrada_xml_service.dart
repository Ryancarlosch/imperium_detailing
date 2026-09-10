import 'dart:convert';
import 'dart:math' as math;

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
      throw const FormatException('XML fiscal vazio.');
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
      throw const FormatException('XML fiscal não contém infNFe.');
    }

    final chaveInformada = _atributo(infNfe, 'Id');
    final chaveInfNfe = _normalizarChave(chaveInformada);
    _validarChave(chaveInfNfe, 'infNFe/@Id');
    final metadadosChave = ChaveFiscalService.metadados(chaveInfNfe);

    final ide = _filho(infNfe, 'ide');
    if (ide == null) throw const FormatException('XML fiscal não contém ide.');

    final modelo = _int(_textoFilho(ide, 'mod'));
    if (modelo != 55 && modelo != 65) {
      throw FormatException('Modelo fiscal não suportado: $modelo.');
    }
    if (modelo != metadadosChave.modelo) {
      throw const FormatException(
        'O modelo informado no XML diverge do modelo presente na chave de acesso.',
      );
    }

    final protocolo = _descendente(documento, 'protNFe');
    final infProt = protocolo == null ? null : _filho(protocolo, 'infProt');
    final chaveProtocolo = _normalizarChave(
      infProt == null ? '' : _textoFilho(infProt, 'chNFe'),
    );
    if (chaveProtocolo.isNotEmpty) {
      _validarChave(chaveProtocolo, 'protNFe/infProt/chNFe');
      if (chaveProtocolo != chaveInfNfe) {
        throw const FormatException('Chaves fiscais divergentes no XML.');
      }
    }

    final emit = _filho(infNfe, 'emit');
    final total = _filho(_filho(infNfe, 'total'), 'ICMSTot');
    if (emit == null || total == null) {
      throw const FormatException('XML fiscal não contém emitente ou totais.');
    }

    final emitenteNome = _textoFilho(emit, 'xNome');
    final emitenteCnpjCpf = _primeiroTexto(emit, const ['CNPJ', 'CPF']);
    if (emitenteNome.isEmpty || emitenteCnpjCpf.isEmpty) {
      throw const FormatException('XML fiscal não contém emitente completo.');
    }

    final cnpjXml = _somenteDigitos(_textoFilho(emit, 'CNPJ'));
    if (cnpjXml.isNotEmpty && cnpjXml != metadadosChave.cnpjEmitente) {
      throw const FormatException(
        'O CNPJ do emitente no XML diverge do CNPJ presente na chave de acesso.',
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
      throw const FormatException(
        'XML fiscal não contém número, série ou data de emissão válidos.',
      );
    }
    if (numero != metadadosChave.numero || serie != metadadosChave.serie) {
      throw const FormatException(
        'Número ou série do XML divergem da chave de acesso.',
      );
    }
    if (DateTime.tryParse(dataEmissao) == null) {
      throw const FormatException('Data de emissão do XML fiscal é inválida.');
    }

    final valorTotalTexto = _textoFilho(total, 'vNF');
    if (valorTotalTexto.isEmpty) {
      throw const FormatException('XML fiscal não contém valor total vNF.');
    }
    final valorTotal = _doubleTexto(valorTotalTexto);
    if (valorTotal < 0) {
      throw const FormatException('Valor total da nota não pode ser negativo.');
    }

    final itens = <NotaFiscalEntradaItem>[];
    for (final det in _filhos(infNfe, 'det')) {
      final prod = _filho(det, 'prod');
      if (prod == null) {
        throw const FormatException('Item fiscal sem grupo prod.');
      }

      final numeroItem = _int(_atributo(det, 'nItem'));
      if (numeroItem == null || numeroItem <= 0) {
        throw const FormatException('Item fiscal sem numeroItem válido.');
      }

      final descricao = _textoFilho(prod, 'xProd');
      final unidade = _textoFilho(prod, 'uCom');
      final quantidade = _doubleObrigatorio(prod, 'qCom', numeroItem);
      final valorUnitario = _doubleObrigatorio(prod, 'vUnCom', numeroItem);
      final valorProduto = _doubleObrigatorio(prod, 'vProd', numeroItem);
      if (descricao.isEmpty || unidade.isEmpty) {
        throw FormatException(
          'Item $numeroItem sem descrição ou unidade comercial.',
        );
      }
      if (quantidade <= 0 || valorUnitario < 0 || valorProduto < 0) {
        throw FormatException('Valores inválidos no item fiscal $numeroItem.');
      }

      itens.add(
        NotaFiscalEntradaItem(
          notaFiscalId: 0,
          numeroItem: numeroItem,
          codigoProduto: _textoNulo(_textoFilho(prod, 'cProd')),
          ean: _normalizarGtin(
            _primeiroTexto(prod, const ['cEAN', 'cEANTrib']),
          ),
          descricao: descricao,
          ncm: _textoNulo(_textoFilho(prod, 'NCM')),
          cfop: _textoNulo(_textoFilho(prod, 'CFOP')),
          unidade: unidade,
          quantidade: quantidade,
          valorUnitario: valorUnitario,
          valorTotal: valorProduto,
          valorDesconto: _doubleTexto(_textoFilho(prod, 'vDesc')),
        ),
      );
    }
    if (itens.isEmpty) {
      throw const FormatException('XML fiscal não contém itens de produto.');
    }

    final valorProdutos = _doubleTexto(_textoFilho(total, 'vProd'));
    final somaProdutos = itens.fold<double>(
      0,
      (soma, item) => soma + item.valorTotal,
    );
    final tolerancia = math.max(0.05, valorProdutos.abs() * 0.0001);
    if ((somaProdutos - valorProdutos).abs() > tolerancia) {
      throw FormatException(
        'A soma dos itens (${somaProdutos.toStringAsFixed(2)}) diverge do '
        'total de produtos do XML (${valorProdutos.toStringAsFixed(2)}).',
      );
    }

    final nota = NotaFiscalEntrada(
      chaveAcesso: chaveInfNfe,
      modelo: modelo,
      numero: numero,
      serie: serie,
      dataEmissao: dataEmissao,
      emitenteCnpjCpf: _textoNulo(emitenteCnpjCpf),
      emitenteNome: _textoNulo(emitenteNome),
      valorProdutos: valorProdutos,
      valorFrete: _doubleTexto(_textoFilho(total, 'vFrete')),
      valorSeguro: _doubleTexto(_textoFilho(total, 'vSeg')),
      valorDesconto: _doubleTexto(_textoFilho(total, 'vDesc')),
      valorOutrasDespesas: _doubleTexto(_textoFilho(total, 'vOutro')),
      valorIpi: _doubleDescendente(total, const ['vIPI']),
      valorIcmsSt: _doubleTexto(_textoFilho(total, 'vST')),
      valorTotal: valorTotal,
      situacaoFiscal: _situacaoFiscal(infProt),
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

  static String _situacaoFiscal(XmlElement? infProt) {
    if (infProt == null) return 'desconhecida';
    final cStat = _textoFilho(infProt, 'cStat');
    switch (cStat) {
      case '100':
      case '150':
        return 'autorizada';
      case '101':
      case '151':
        return 'cancelada';
      case '110':
      case '301':
      case '302':
        return 'denegada';
      default:
        return 'desconhecida';
    }
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

  static double _doubleObrigatorio(
    XmlElement prod,
    String campo,
    int numeroItem,
  ) {
    final texto = _textoFilho(prod, campo);
    if (texto.isEmpty) {
      throw FormatException('Item $numeroItem sem campo $campo.');
    }
    return _doubleTexto(texto);
  }

  static double _doubleTexto(String valor) {
    if (valor.trim().isEmpty) return 0;
    final resultado = double.tryParse(valor.trim().replaceAll(',', '.'));
    if (resultado == null || !resultado.isFinite) {
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

  static String? _normalizarGtin(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return null;
    final superior = texto.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (superior == 'SEM GTIN' ||
        superior == 'SEM EAN' ||
        superior == 'NO GTIN') {
      return null;
    }
    final digitos = _somenteDigitos(texto);
    return digitos.isEmpty ? null : digitos;
  }

  static String _somenteDigitos(String valor) =>
      valor.replaceAll(RegExp(r'\D'), '');

  static String? _textoNulo(String valor) =>
      valor.trim().isEmpty ? null : valor.trim();
}
