import 'dart:typed_data';

import 'orcamento_pdf_service.dart';

class ReciboPdfService {
  final OrcamentoPdfService _orcamentoPdfService =
  OrcamentoPdfService();

  Future<Uint8List> gerarPdf(
      Map<String, dynamic> dados,
      ) async {
    return _orcamentoPdfService.gerarPdf(
      dados,
      recibo: true,
    );
  }

  Future<void> visualizar(
      Map<String, dynamic> dados,
      ) async {
    await _orcamentoPdfService.visualizar(
      dados,
      recibo: true,
    );
  }

  Future<void> compartilhar(
      Map<String, dynamic> dados,
      ) async {
    await _orcamentoPdfService.compartilhar(
      dados,
      recibo: true,
    );
  }
}