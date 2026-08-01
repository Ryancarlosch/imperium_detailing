import '../database/app_database.dart';
import 'foto_servico_repository.dart';

class OrdemServicoFotoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final FotoServicoRepository _fotoServicoRepository = FotoServicoRepository();

  Future<List<Map<String, dynamic>>> listarFotos(
    int ordemServicoId, {
    String? etapa,
  }) async {
    final database = await _appDatabase.database;

    final etapaLimpa = etapa?.trim() ?? '';

    final resultado = await database.query(
      'ordem_servico_fotos',
      where: etapaLimpa.isEmpty
          ? 'ordem_servico_id = ?'
          : 'ordem_servico_id = ? AND etapa = ?',
      whereArgs: etapaLimpa.isEmpty
          ? [ordemServicoId]
          : [ordemServicoId, etapaLimpa],
      orderBy: 'ordem DESC, id DESC',
    );

    return resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList();
  }

  Future<int> contarFotos(int ordemServicoId, {required String etapa}) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_fotos
      WHERE ordem_servico_id = ?
        AND etapa = ?
      ''',
      [ordemServicoId, etapa.trim()],
    );

    final valor = resultado.first['total'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Future<int> inserirFoto({
    required int ordemServicoId,
    required String etapa,
    required String caminho,
    String descricao = '',
  }) async {
    final database = await _appDatabase.database;

    final resultadoOrdem = await database.rawQuery(
      '''
      SELECT COALESCE(MAX(ordem), -1) + 1 AS proxima_ordem
      FROM ordem_servico_fotos
      WHERE ordem_servico_id = ?
        AND etapa = ?
      ''',
      [ordemServicoId, etapa.trim()],
    );

    final valorOrdem = resultadoOrdem.first['proxima_ordem'];
    final proximaOrdem = valorOrdem is num
        ? valorOrdem.toInt()
        : int.tryParse(valorOrdem?.toString() ?? '') ?? 0;

    return database.insert('ordem_servico_fotos', {
      'ordem_servico_id': ordemServicoId,
      'etapa': etapa.trim(),
      'caminho': caminho.trim(),
      'descricao': descricao.trim(),
      'data': DateTime.now().toIso8601String(),
      'ordem': proximaOrdem,
    });
  }

  Future<void> atualizarDescricao({
    required int fotoId,
    required String descricao,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_fotos',
      {'descricao': descricao.trim()},
      where: 'id = ?',
      whereArgs: [fotoId],
    );
  }

  Future<void> excluirFoto(int fotoId, {bool excluirArquivo = true}) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_fotos',
      columns: ['caminho'],
      where: 'id = ?',
      whereArgs: [fotoId],
      limit: 1,
    );

    final removidos = await database.delete(
      'ordem_servico_fotos',
      where: 'id = ?',
      whereArgs: [fotoId],
    );

    if (!excluirArquivo || resultado.isEmpty || removidos <= 0) {
      return;
    }

    final caminho = resultado.first['caminho']?.toString().trim() ?? '';

    if (caminho.isEmpty) {
      return;
    }

    try {
      await _fotoServicoRepository.excluirArquivoSeNaoReferenciado(
        caminho,
        ignorarOrdemServicoFotoId: fotoId,
      );
    } catch (_) {
      // Erros de arquivo não devem impedir a limpeza do banco.
    }
  }
}
