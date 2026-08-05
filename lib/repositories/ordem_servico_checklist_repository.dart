import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'ordem_servico_revisao_repository.dart';

class OrdemServicoChecklistRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final OrdemServicoRevisaoRepository _revisaoRepository =
      OrdemServicoRevisaoRepository();

  static const int statusNaoVerificado = 0;
  static const int statusOk = 1;
  static const int statusAvaria = 2;

  static const List<Map<String, dynamic>> _itensPadrao = [
    {'categoria': 'Pintura e carroceria', 'item': 'Pintura'},
    {'categoria': 'Pintura e carroceria', 'item': 'Carroceria'},
    {'categoria': 'Pintura e carroceria', 'item': 'Para-choque dianteiro'},
    {'categoria': 'Pintura e carroceria', 'item': 'Para-choque traseiro'},
    {'categoria': 'Pintura e carroceria', 'item': 'Capô'},
    {'categoria': 'Pintura e carroceria', 'item': 'Teto'},
    {'categoria': 'Pintura e carroceria', 'item': 'Portas'},
    {'categoria': 'Pintura e carroceria', 'item': 'Retrovisores'},
    {'categoria': 'Vidros e iluminação', 'item': 'Para-brisa'},
    {'categoria': 'Vidros e iluminação', 'item': 'Vidro traseiro'},
    {'categoria': 'Vidros laterais', 'item': 'Vidros laterais'},
    {'categoria': 'Vidros e iluminação', 'item': 'Faróis'},
    {'categoria': 'Vidros e iluminação', 'item': 'Lanternas'},
    {'categoria': 'Rodas e pneus', 'item': 'Roda dianteira esquerda'},
    {'categoria': 'Rodas e pneus', 'item': 'Roda dianteira direita'},
    {'categoria': 'Rodas e pneus', 'item': 'Roda traseira esquerda'},
    {'categoria': 'Rodas e pneus', 'item': 'Roda traseira direita'},
    {'categoria': 'Rodas e pneus', 'item': 'Pneus'},
    {'categoria': 'Itens do veículo', 'item': 'Estepe'},
    {'categoria': 'Itens do veículo', 'item': 'Macaco'},
    {'categoria': 'Itens do veículo', 'item': 'Chave de roda'},
    {
      'categoria': 'Itens do veículo',
      'item': 'Documentos ou objetos deixados no veículo',
    },
    {'categoria': 'Interior', 'item': 'Bancos'},
    {'categoria': 'Interior', 'item': 'Painel'},
    {'categoria': 'Interior', 'item': 'Volante'},
    {'categoria': 'Interior', 'item': 'Carpete'},
    {'categoria': 'Interior', 'item': 'Porta-malas'},
  ];

  Future<List<Map<String, dynamic>>> listarChecklist(int ordemServicoId) async {
    await garantirChecklistPadrao(ordemServicoId);

    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_checklist',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'ordem ASC, id ASC',
    );

    return resultado.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> garantirChecklistPadrao(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final quantidade = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_checklist
      WHERE ordem_servico_id = ?
      ''',
      [ordemServicoId],
    );

    final total = (quantidade.first['total'] as num?)?.toInt() ?? 0;

    if (total > 0) {
      return;
    }

    await database.transaction((transaction) async {
      for (var indice = 0; indice < _itensPadrao.length; indice++) {
        final item = _itensPadrao[indice];

        await transaction.insert('ordem_servico_checklist', {
          'ordem_servico_id': ordemServicoId,
          'categoria': (item['categoria'] ?? 'Geral').toString().trim(),
          'item': (item['item'] ?? 'Item').toString().trim(),
          'marcado': 0,
          'status': statusNaoVerificado,
          'observacao': '',
          'foto_avaria': null,
          'ordem': indice,
        });
      }
    });
  }

  Future<void> salvarChecklist(List<Map<String, dynamic>> itens) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _salvarChecklistComTransacao(transaction, itens);
    });
  }

  Future<void> salvarChecklistCompleto({
    required int ordemServicoId,
    required String quilometragem,
    required String combustivel,
    required List<Map<String, dynamic>> itens,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _salvarDadosEntradaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        quilometragem: quilometragem,
        combustivel: combustivel,
      );

      await _salvarChecklistComTransacao(
        transaction,
        itens,
        ordemServicoId: ordemServicoId,
      );
    });
  }

  Future<int> corrigirChecklistFinalizado({
    required int ordemServicoId,
    required String motivo,
    required String quilometragem,
    required String combustivel,
    required List<Map<String, dynamic>> itens,
  }) async {
    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final dadosAnteriores = await _buscarSnapshotComTransacao(
        transaction,
        ordemServicoId,
      );

      final dadosNovos = <String, dynamic>{
        'dados_entrada': {
          'quilometragem': quilometragem.trim(),
          'combustivel': combustivel.trim(),
        },
        'itens': _normalizarItensParaSnapshot(itens),
      };

      if (jsonEncode(dadosAnteriores) == jsonEncode(dadosNovos)) {
        throw StateError('Nenhuma alteração foi identificada no checklist.');
      }

      await _salvarDadosEntradaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        quilometragem: quilometragem,
        combustivel: combustivel,
      );

      await _salvarChecklistComTransacao(
        transaction,
        itens,
        ordemServicoId: ordemServicoId,
      );

      return _revisaoRepository.registrarComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        tipo: 'Correcao de checklist',
        motivo: motivo,
        dadosAnteriores: dadosAnteriores,
        dadosNovos: dadosNovos,
      );
    });
  }

  Future<void> _salvarChecklistComTransacao(
    Transaction transaction,
    List<Map<String, dynamic>> itens, {
    int? ordemServicoId,
  }) async {
    for (final item in itens) {
      final id = _converterInt(item['id']);

      if (id == null) {
        continue;
      }

      final dados = _normalizarItemParaPersistencia(item);

      final linhasAlteradas = await transaction.update(
        'ordem_servico_checklist',
        dados,
        where: ordemServicoId == null
            ? 'id = ?'
            : 'id = ? AND ordem_servico_id = ?',
        whereArgs: ordemServicoId == null ? [id] : [id, ordemServicoId],
      );

      if (linhasAlteradas == 0) {
        throw StateError(
          'Um item do checklist não foi encontrado durante o salvamento.',
        );
      }
    }
  }

  Future<void> _salvarDadosEntradaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String quilometragem,
    required String combustivel,
  }) async {
    final linhasAlteradas = await transaction.update(
      'ordens_servico',
      {
        'quilometragem_entrada': quilometragem.trim(),
        'combustivel_entrada': combustivel.trim(),
      },
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );

    if (linhasAlteradas == 0) {
      throw StateError('Ordem de Serviço não encontrada.');
    }
  }

  Future<Map<String, dynamic>> _buscarSnapshotComTransacao(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final resultadoOrdem = await transaction.query(
      'ordens_servico',
      columns: ['quilometragem_entrada', 'combustivel_entrada'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultadoOrdem.isEmpty) {
      throw StateError('Ordem de Serviço não encontrada.');
    }

    final resultadoItens = await transaction.query(
      'ordem_servico_checklist',
      columns: [
        'id',
        'status',
        'marcado',
        'observacao',
        'foto_avaria',
        'avaria_localizacao',
        'avaria_data_registro',
      ],
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'ordem ASC, id ASC',
    );

    return {
      'dados_entrada': {
        'quilometragem': (resultadoOrdem.first['quilometragem_entrada'] ?? '')
            .toString()
            .trim(),
        'combustivel': (resultadoOrdem.first['combustivel_entrada'] ?? '')
            .toString()
            .trim(),
      },
      'itens': _normalizarItensParaSnapshot(
        resultadoItens.map((item) => Map<String, dynamic>.from(item)).toList(),
      ),
    };
  }

  List<Map<String, dynamic>> _normalizarItensParaSnapshot(
    List<Map<String, dynamic>> itens,
  ) {
    final normalizados = itens
        .map((item) => _normalizarItemParaSnapshot(item))
        .toList();

    normalizados.sort((a, b) {
      final primeiro = _converterInt(a['id']) ?? 0;
      final segundo = _converterInt(b['id']) ?? 0;
      return primeiro.compareTo(segundo);
    });

    return normalizados;
  }

  Map<String, dynamic> _normalizarItemParaSnapshot(Map<String, dynamic> item) {
    final id = _converterInt(item['id']);
    final dados = _normalizarItemParaPersistencia(item);

    return {'id': id, ...dados};
  }

  Map<String, dynamic> _normalizarItemParaPersistencia(
    Map<String, dynamic> item,
  ) {
    final status = _obterStatus(item);
    final conferido = status != statusNaoVerificado;
    final fotoAvaria = _normalizarCaminhoFoto(item['foto_avaria']);

    return {
      'marcado': conferido ? 1 : 0,
      'status': status,
      'observacao': (item['observacao'] ?? '').toString().trim(),
      'foto_avaria': status == statusAvaria ? fotoAvaria : null,
      'avaria_localizacao': status == statusAvaria
          ? (item['avaria_localizacao'] ?? '').toString().trim()
          : '',
      'avaria_data_registro': status == statusAvaria
          ? _normalizarTextoOpcional(item['avaria_data_registro'])
          : null,
    };
  }

  Future<void> atualizarStatus({
    required int checklistId,
    required int status,
  }) async {
    final statusNormalizado = _normalizarStatus(status);

    final database = await _appDatabase.database;

    final dados = <String, dynamic>{
      'status': statusNormalizado,
      'marcado': statusNormalizado != statusNaoVerificado ? 1 : 0,
    };

    if (statusNormalizado != statusAvaria) {
      dados['foto_avaria'] = null;
      dados['avaria_localizacao'] = '';
      dados['avaria_data_registro'] = null;
    }

    await database.update(
      'ordem_servico_checklist',
      dados,
      where: 'id = ?',
      whereArgs: [checklistId],
    );
  }

  Future<void> atualizarObservacao({
    required int checklistId,
    required String observacao,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_checklist',
      {'observacao': observacao.trim()},
      where: 'id = ?',
      whereArgs: [checklistId],
    );
  }

  Future<void> salvarFotoAvaria({
    required int checklistId,
    required String caminho,
  }) async {
    final caminhoLimpo = caminho.trim();

    if (caminhoLimpo.isEmpty) {
      throw ArgumentError('O caminho da foto da avaria não pode estar vazio.');
    }

    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_checklist',
      {
        'status': statusAvaria,
        'marcado': 1,
        'foto_avaria': caminhoLimpo,
        'avaria_data_registro': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [checklistId],
    );
  }

  Future<void> removerFotoAvaria({required int checklistId}) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_checklist',
      {'foto_avaria': null},
      where: 'id = ?',
      whereArgs: [checklistId],
    );
  }

  Future<Map<String, String>> buscarDadosEntrada(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordens_servico',
      columns: ['quilometragem_entrada', 'combustivel_entrada'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return {'quilometragem': '', 'combustivel': ''};
    }

    return {
      'quilometragem': (resultado.first['quilometragem_entrada'] ?? '')
          .toString()
          .trim(),
      'combustivel': (resultado.first['combustivel_entrada'] ?? '')
          .toString()
          .trim(),
    };
  }

  Future<void> salvarDadosEntrada({
    required int ordemServicoId,
    required String quilometragem,
    required String combustivel,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _salvarDadosEntradaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        quilometragem: quilometragem,
        combustivel: combustivel,
      );
    });
  }

  Future<Map<String, dynamic>?> buscarItemPorId(int checklistId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_checklist',
      where: 'id = ?',
      whereArgs: [checklistId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<List<Map<String, dynamic>>> listarAvarias(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_checklist',
      where: '''
        ordem_servico_id = ?
        AND status = ?
      ''',
      whereArgs: [ordemServicoId, statusAvaria],
      orderBy: 'ordem ASC, id ASC',
    );

    return resultado.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<int> contarConferidos(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_checklist
      WHERE ordem_servico_id = ?
        AND status != ?
      ''',
      [ordemServicoId, statusNaoVerificado],
    );

    return (resultado.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> contarAvarias(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_checklist
      WHERE ordem_servico_id = ?
        AND status = ?
      ''',
      [ordemServicoId, statusAvaria],
    );

    return (resultado.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> contarTotal(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordem_servico_checklist
      WHERE ordem_servico_id = ?
      ''',
      [ordemServicoId],
    );

    return (resultado.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<bool> checklistConcluido(int ordemServicoId) async {
    final total = await contarTotal(ordemServicoId);

    if (total == 0) {
      return false;
    }

    final conferidos = await contarConferidos(ordemServicoId);

    return conferidos >= total;
  }

  Future<void> limparChecklist(int ordemServicoId) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_checklist',
      {
        'marcado': 0,
        'status': statusNaoVerificado,
        'observacao': '',
        'foto_avaria': null,
        'avaria_localizacao': '',
        'avaria_data_registro': null,
      },
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  int _obterStatus(Map<String, dynamic> item) {
    final statusInformado = _converterInt(item['status']);

    if (statusInformado != null) {
      return _normalizarStatus(statusInformado);
    }

    final marcado = _converterBool(item['marcado']);

    return marcado ? statusOk : statusNaoVerificado;
  }

  int _normalizarStatus(int status) {
    if (status == statusOk) {
      return statusOk;
    }

    if (status == statusAvaria) {
      return statusAvaria;
    }

    return statusNaoVerificado;
  }

  String? _normalizarCaminhoFoto(dynamic valor) {
    final caminho = valor?.toString().trim() ?? '';

    if (caminho.isEmpty) {
      return null;
    }

    return caminho;
  }

  String? _normalizarTextoOpcional(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    return texto;
  }

  int? _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  bool _converterBool(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
