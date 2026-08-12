import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class PontoNuvemImportacaoResumo {
  const PontoNuvemImportacaoResumo({
    required this.totalLocal,
    required this.importados,
    required this.atualizados,
    required this.falhas,
  });

  final int totalLocal;
  final int importados;
  final int atualizados;
  final List<String> falhas;

  int get sucesso => importados + atualizados;
}

class PontoNuvemImportacaoService {
  PontoNuvemImportacaoService._();

  static final PontoNuvemImportacaoService instance =
      PontoNuvemImportacaoService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sincronizacao_ponto_colaboradores (
        local_id INTEGER PRIMARY KEY,
        empresa_id TEXT NOT NULL,
        remoto_id TEXT NOT NULL,
        sincronizado_em TEXT NOT NULL,
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<Map<String, dynamic>> obterResumo({required String empresaId}) async {
    final database = await _appDatabase.database;
    await garantirEstruturaLocal();

    final totalLocal =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM financeiro_colaboradores_custo',
          ),
        ) ??
        0;

    final vinculados =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM sincronizacao_ponto_colaboradores
            WHERE empresa_id = ?
            ''',
            [empresaId],
          ),
        ) ??
        0;

    var remoto = 0;
    final client = SupabaseBootstrap.client;

    if (client != null && client.auth.currentUser != null) {
      final dados = await client
          .from('ponto_colaboradores')
          .select('id')
          .eq('empresa_id', empresaId);

      remoto = dados.length;
    }

    return {
      'total_local': totalLocal,
      'vinculados': vinculados,
      'remoto': remoto,
    };
  }

  Future<PontoNuvemImportacaoResumo> importarColaboradores({
    required String empresaId,
  }) async {
    final client = SupabaseBootstrap.client;

    if (client == null || client.auth.currentUser == null) {
      throw StateError('Conecte a conta da nuvem antes de importar.');
    }

    final database = await _appDatabase.database;
    await garantirEstruturaLocal();

    final locais = await database.query(
      'financeiro_colaboradores_custo',
      columns: ['id', 'nome', 'funcao', 'ativo'],
      orderBy: 'id ASC',
    );

    var importados = 0;
    var atualizados = 0;
    final falhas = <String>[];

    for (final item in locais) {
      final localId = _int(item['id']);
      final nome = (item['nome'] ?? '').toString().trim();
      final funcao = (item['funcao'] ?? '').toString().trim();
      final ativo = _int(item['ativo']) == 1;

      if (localId <= 0 || nome.length < 2) {
        falhas.add(
          nome.isEmpty
              ? 'Registro local #$localId inválido.'
              : '$nome: registro local inválido.',
        );
        continue;
      }

      final vinculoAnterior = await database.query(
        'sincronizacao_ponto_colaboradores',
        columns: ['remoto_id'],
        where: 'local_id = ? AND empresa_id = ?',
        whereArgs: [localId, empresaId],
        limit: 1,
      );

      try {
        final resultado = await client.rpc(
          'ponto_importar_colaborador',
          params: {
            'p_empresa_id': empresaId,
            'p_origem_local_id': localId,
            'p_nome': nome,
            'p_funcao': funcao,
            'p_ativo': ativo,
          },
        );

        final remotoId = resultado?.toString().trim() ?? '';

        if (remotoId.isEmpty) {
          throw StateError(
            'A nuvem não retornou o identificador do funcionário.',
          );
        }

        await database.insert(
          'sincronizacao_ponto_colaboradores',
          {
            'local_id': localId,
            'empresa_id': empresaId,
            'remoto_id': remotoId,
            'sincronizado_em': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (vinculoAnterior.isEmpty) {
          importados++;
        } else {
          atualizados++;
        }
      } catch (erro) {
        falhas.add('$nome: ${_textoErro(erro)}');
      }
    }

    return PontoNuvemImportacaoResumo(
      totalLocal: locais.length,
      importados: importados,
      atualizados: atualizados,
      falhas: falhas,
    );
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const <String>[
      'PostgrestException: ',
      'Exception: ',
      'StateError: ',
      'Bad state: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida.' : texto;
  }
}
