import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';

class ChaveFiscalCapturada {
  const ChaveFiscalCapturada({required this.chave, required this.origem});

  final String chave;
  final String origem;
}

class ChaveFiscalService {
  ChaveFiscalService({this._repository});

  final NotaFiscalEntradaRepository? _repository;

  ChaveFiscalCapturada extrair(String conteudo, {required String origem}) {
    if (!_origens.contains(origem)) {
      throw ArgumentError('Origem inválida para captura de chave fiscal.');
    }

    final texto = conteudo.trim();
    if (texto.isEmpty) {
      throw const FormatException('Conteúdo sem chave fiscal.');
    }

    final candidatos = <String>[];
    final parametroP = RegExp(
      r'(?:[?&]|^)p=([^&#\s]+)',
      caseSensitive: false,
    ).firstMatch(texto);
    if (parametroP != null) {
      candidatos.addAll(_extrairCandidatos(parametroP.group(1)!));
    }
    candidatos.addAll(_extrairCandidatos(texto));

    for (final candidato in candidatos) {
      if (_validarDv(candidato)) {
        return ChaveFiscalCapturada(chave: candidato, origem: origem);
      }
    }

    throw const FormatException('Conteúdo não contém chave fiscal válida.');
  }

  Future<NotaFiscalEntrada> registrarPreliminar(
    String conteudo, {
    required String origem,
    String? importadaEm,
  }) async {
    final repository = _repository;
    if (repository == null) {
      throw StateError('Repository fiscal não configurado.');
    }

    final capturada = extrair(conteudo, origem: origem);
    return repository.registrarPreliminar(
      chaveAcesso: capturada.chave,
      origemImportacao: capturada.origem,
      importadaEm: importadaEm ?? DateTime.now().toIso8601String(),
    );
  }

  static bool chaveValida(String chave) {
    final normalizada = _normalizar(chave);
    return _validarDv(normalizada);
  }

  static String normalizar(String conteudo) {
    final candidatos = _extrairCandidatos(conteudo);
    for (final candidato in candidatos) {
      if (_validarDv(candidato)) return candidato;
    }
    throw const FormatException('Chave fiscal inválida.');
  }

  static const _origens = {'qrCode', 'codigoBarras', 'chaveManual'};

  static List<String> _extrairCandidatos(String texto) {
    final resultados = <String>[];
    final sequencias = RegExp(r'\d{44}').allMatches(texto);
    for (final sequencia in sequencias) {
      resultados.add(sequencia.group(0)!);
    }

    final apenasDigitos = texto.replaceAll(RegExp(r'\D'), '');
    if (apenasDigitos.length == 44) resultados.add(apenasDigitos);
    return resultados.toSet().toList();
  }

  static String _normalizar(String texto) {
    final candidatos = _extrairCandidatos(texto);
    if (candidatos.length == 1) return candidatos.single;
    return texto.replaceAll(RegExp(r'\D'), '');
  }

  static bool _validarDv(String chave) {
    if (!RegExp(r'^\d{44}$').hasMatch(chave)) return false;

    var soma = 0;
    var peso = 2;
    for (var indice = 42; indice >= 0; indice--) {
      soma += int.parse(chave[indice]) * peso;
      peso = peso == 9 ? 2 : peso + 1;
    }

    final resto = soma % 11;
    final esperado = resto == 0 || resto == 1 ? 0 : 11 - resto;
    return esperado == int.parse(chave[43]);
  }
}
