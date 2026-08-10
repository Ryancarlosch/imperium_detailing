import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ComprovantePagamentoService {
  const ComprovantePagamentoService();

  Future<String?> selecionarESalvar({required int ordemServicoId}) async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      dialogTitle: 'Selecionar comprovante de pagamento',
    );

    final origem = resultado?.files.single.path?.trim() ?? '';
    if (origem.isEmpty) {
      return null;
    }

    final arquivoOrigem = File(origem);
    if (!await arquivoOrigem.exists()) {
      throw StateError('O comprovante selecionado não foi encontrado.');
    }

    final documentos = await getApplicationDocumentsDirectory();
    final pasta = Directory(
      path.join(
        documentos.path,
        'comprovantes_pagamentos',
        'os_$ordemServicoId',
      ),
    );

    await pasta.create(recursive: true);

    final extensao = path.extension(origem).toLowerCase();
    final destino = path.join(
      pasta.path,
      'comprovante_${DateTime.now().millisecondsSinceEpoch}$extensao',
    );

    final copia = await arquivoOrigem.copy(destino);
    return copia.path;
  }

  Future<void> excluirBestEffort(String? caminho) async {
    final valor = caminho?.trim() ?? '';
    if (valor.isEmpty) {
      return;
    }

    try {
      final arquivo = File(valor);
      if (await arquivo.exists()) {
        await arquivo.delete();
      }
    } catch (_) {
      // O histórico financeiro não deve falhar por problema de limpeza física.
    }
  }
}
