import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

/// Pastas persistentes isoladas por empresa.
///
/// Arquivos legados continuam válidos onde já estiverem. Novos arquivos
/// persistentes passam a ser gravados em:
/// `Documentos/empresas/<empresa_id>/<pasta>/...`
class TenantLocalStorageService {
  TenantLocalStorageService._();

  static final TenantLocalStorageService instance =
      TenantLocalStorageService._();

  Future<Directory> pasta(
    String nome, {
    List<String> segmentos = const <String>[],
  }) async {
    final documentos = await getApplicationDocumentsDirectory();
    final empresaId = await AppDatabase.instance.empresaAtivaId;

    final partes = <String>[documentos.path];

    if (empresaId != null && empresaId.isNotEmpty) {
      partes
        ..add('empresas')
        ..add(_seguro(empresaId));
    }

    partes
      ..add(nome)
      ..addAll(segmentos.map(_seguro));

    final diretorio = Directory(path.joinAll(partes));

    if (!await diretorio.exists()) {
      await diretorio.create(recursive: true);
    }

    return diretorio;
  }

  String _seguro(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return '_';
    return texto.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  }
}
