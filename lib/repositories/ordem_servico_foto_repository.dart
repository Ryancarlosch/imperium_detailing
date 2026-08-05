import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'foto_servico_repository.dart';
import 'ordem_servico_revisao_repository.dart';

class OrdemServicoFotoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final FotoServicoRepository _fotoServicoRepository = FotoServicoRepository();
  final OrdemServicoRevisaoRepository _revisaoRepository =
      OrdemServicoRevisaoRepository();

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

    return database.transaction((transaction) {
      return _inserirFotoComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        etapa: etapa,
        caminho: caminho,
        descricao: descricao,
      );
    });
  }

  Future<int> inserirFotoComRevisao({
    required int ordemServicoId,
    required String etapa,
    required String caminho,
    required String motivo,
    String descricao = '',
  }) async {
    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final etapaLimpa = etapa.trim();
      final quantidadeAntes = await _contarFotosComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        etapa: etapaLimpa,
      );

      final fotoId = await _inserirFotoComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        etapa: etapaLimpa,
        caminho: caminho,
        descricao: descricao,
      );

      await _revisaoRepository.registrarComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        tipo: 'Correcao de fotos',
        motivo: motivo,
        dadosAnteriores: {
          'acao': 'adicionar_foto',
          'etapa': etapaLimpa,
          'quantidade_fotos_etapa': quantidadeAntes,
        },
        dadosNovos: {
          'acao': 'foto_adicionada',
          'foto_id': fotoId,
          'etapa': etapaLimpa,
          'caminho': caminho.trim(),
          'descricao': descricao.trim(),
          'quantidade_fotos_etapa': quantidadeAntes + 1,
        },
      );

      return fotoId;
    });
  }

  Future<int> _inserirFotoComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String etapa,
    required String caminho,
    String descricao = '',
  }) async {
    final etapaLimpa = etapa.trim();
    final caminhoLimpo = caminho.trim();

    if (etapaLimpa != 'Antes' && etapaLimpa != 'Depois') {
      throw ArgumentError('A etapa da foto deve ser "Antes" ou "Depois".');
    }

    if (caminhoLimpo.isEmpty) {
      throw ArgumentError('O caminho da foto não pode estar vazio.');
    }

    final resultadoOrdem = await transaction.rawQuery(
      '''
      SELECT COALESCE(MAX(ordem), -1) + 1 AS proxima_ordem
      FROM ordem_servico_fotos
      WHERE ordem_servico_id = ?
        AND etapa = ?
      ''',
      [ordemServicoId, etapaLimpa],
    );

    final valorOrdem = resultadoOrdem.first['proxima_ordem'];
    final proximaOrdem = valorOrdem is num
        ? valorOrdem.toInt()
        : int.tryParse(valorOrdem?.toString() ?? '') ?? 0;

    return transaction.insert('ordem_servico_fotos', {
      'ordem_servico_id': ordemServicoId,
      'etapa': etapaLimpa,
      'caminho': caminhoLimpo,
      'descricao': descricao.trim(),
      'data': DateTime.now().toIso8601String(),
      'ordem': proximaOrdem,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> _contarFotosComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String etapa,
  }) async {
    final resultado = await transaction.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_fotos
      WHERE ordem_servico_id = ?
        AND etapa = ?
      ''',
      [ordemServicoId, etapa.trim()],
    );

    return (resultado.first['total'] as num?)?.toInt() ?? 0;
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

    final resultado = await database.transaction((transaction) {
      return _excluirFotoComTransacao(transaction, fotoId);
    });

    await _excluirArquivoAposRemocao(
      fotoId: fotoId,
      foto: resultado,
      excluirArquivo: excluirArquivo,
    );
  }

  Future<void> excluirFotoComRevisao({
    required int fotoId,
    required String motivo,
    bool excluirArquivo = true,
  }) async {
    final database = await _appDatabase.database;

    final resultado = await database.transaction((transaction) async {
      final foto = await _buscarFotoComTransacao(transaction, fotoId);

      if (foto == null) {
        throw StateError('Foto da Ordem de Serviço não encontrada.');
      }

      final ordemServicoId = (foto['ordem_servico_id'] as num?)?.toInt();

      if (ordemServicoId == null) {
        throw StateError('A foto não possui uma Ordem de Serviço válida.');
      }

      final etapa = (foto['etapa'] ?? '').toString().trim();
      final quantidadeAntes = await _contarFotosComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        etapa: etapa,
      );

      final removida = await _excluirFotoComTransacao(
        transaction,
        fotoId,
        fotoExistente: foto,
      );

      await _revisaoRepository.registrarComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        tipo: 'Correcao de fotos',
        motivo: motivo,
        dadosAnteriores: {
          'acao': 'excluir_foto',
          'foto': Map<String, dynamic>.from(foto),
          'quantidade_fotos_etapa': quantidadeAntes,
        },
        dadosNovos: {
          'acao': 'foto_excluida',
          'foto_id': fotoId,
          'etapa': etapa,
          'quantidade_fotos_etapa': quantidadeAntes > 0
              ? quantidadeAntes - 1
              : 0,
        },
      );

      return removida;
    });

    await _excluirArquivoAposRemocao(
      fotoId: fotoId,
      foto: resultado,
      excluirArquivo: excluirArquivo,
    );
  }

  Future<Map<String, dynamic>?> _buscarFotoComTransacao(
    Transaction transaction,
    int fotoId,
  ) async {
    final resultado = await transaction.query(
      'ordem_servico_fotos',
      where: 'id = ?',
      whereArgs: [fotoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<Map<String, dynamic>?> _excluirFotoComTransacao(
    Transaction transaction,
    int fotoId, {
    Map<String, dynamic>? fotoExistente,
  }) async {
    final foto =
        fotoExistente ?? await _buscarFotoComTransacao(transaction, fotoId);

    if (foto == null) {
      return null;
    }

    final removidos = await transaction.delete(
      'ordem_servico_fotos',
      where: 'id = ?',
      whereArgs: [fotoId],
    );

    if (removidos == 0) {
      throw StateError('A foto não pôde ser excluída.');
    }

    return foto;
  }

  Future<void> _excluirArquivoAposRemocao({
    required int fotoId,
    required Map<String, dynamic>? foto,
    required bool excluirArquivo,
  }) async {
    if (!excluirArquivo || foto == null) {
      return;
    }

    final caminho = (foto['caminho'] ?? '').toString().trim();

    if (caminho.isEmpty) {
      return;
    }

    try {
      await _fotoServicoRepository.excluirArquivoSeNaoReferenciado(
        caminho,
        ignorarOrdemServicoFotoId: fotoId,
      );
    } catch (_) {
      // A remoção do banco e a auditoria já foram concluídas.
    }
  }
}
