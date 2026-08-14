import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

class PontoOfflineSyncService {
  PontoOfflineSyncService._();

  static final PontoOfflineSyncService instance = PontoOfflineSyncService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final PontoNuvemService _nuvem = PontoNuvemService.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  bool _sincronizando = false;

  Future<void> garantirEstrutura() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_ponto_batidas_pendentes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_local_id INTEGER NOT NULL,
        chave TEXT NOT NULL UNIQUE,
        ocorrido_em TEXT NOT NULL,
        local_resultado_json TEXT,
        tentativas INTEGER NOT NULL DEFAULT 0,
        ultimo_erro TEXT,
        criado_em TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_imperium_ponto_pendentes_colaborador
      ON imperium_ponto_batidas_pendentes (
        colaborador_local_id,
        id
      )
    ''');
  }

  Future<bool> pontoNuvemEsperadoLocal(int colaboradorLocalId) async {
    await garantirEstrutura();
    final database = await _appDatabase.database;

    final tabela = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = 'imperium_dispositivo_acesso'
      LIMIT 1
    ''');

    if (tabela.isEmpty) return false;

    final colunas = await database.rawQuery(
      'PRAGMA table_info(imperium_dispositivo_acesso)',
    );

    final nomes = colunas
        .map((item) => (item['name'] ?? '').toString())
        .toSet();

    if (!nomes.contains('ponto_nuvem_ativo')) return false;

    final dispositivo = await database.query(
      'imperium_dispositivo_acesso',
      columns: ['modo', 'colaborador_local_id', 'ponto_nuvem_ativo'],
      where: 'id = 1',
      limit: 1,
    );

    if (dispositivo.isEmpty) return false;

    final item = dispositivo.first;

    return (item['modo'] ?? '').toString() == 'funcionario' &&
        _int(item['colaborador_local_id']) == colaboradorLocalId &&
        _int(item['ponto_nuvem_ativo']) == 1;
  }

  String novaChave({
    required int colaboradorLocalId,
    required DateTime ocorridoEm,
  }) {
    final random = Random.secure();
    final aleatorio = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    return 'ponto-$colaboradorLocalId-'
        '${ocorridoEm.microsecondsSinceEpoch}-$aleatorio';
  }

  Future<Map<String, dynamic>> registrarRemotoIdempotente({
    required int colaboradorLocalId,
    required DateTime ocorridoEm,
    required String chave,
  }) async {
    final client = _client;

    if (client == null || client.auth.currentUser == null) {
      throw StateError('Sessão da nuvem indisponível.');
    }

    final empresaId = await _nuvem.empresaAtualId();

    if (empresaId == null || empresaId.isEmpty) {
      throw StateError('Empresa da nuvem não identificada.');
    }

    final colaboradorRemotoId = await _nuvem.remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (colaboradorRemotoId == null || colaboradorRemotoId.isEmpty) {
      throw StateError(
        'Funcionário ainda não está vinculado ao Ponto na nuvem.',
      );
    }

    final resposta = await client.rpc(
      'ponto_registrar_batida_offline',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorRemotoId,
        'p_ocorrido_em': ocorridoEm.toUtc().toIso8601String(),
        'p_chave': chave,
      },
    );

    return _mapa(resposta);
  }

  Future<void> enfileirar({
    required int colaboradorLocalId,
    required DateTime ocorridoEm,
    required String chave,
    required Map<String, dynamic> resultadoLocal,
  }) async {
    await garantirEstrutura();
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_ponto_batidas_pendentes',
      {
        'colaborador_local_id': colaboradorLocalId,
        'chave': chave,
        'ocorrido_em': ocorridoEm.toUtc().toIso8601String(),
        'local_resultado_json': jsonEncode(resultadoLocal),
        'tentativas': 0,
        'ultimo_erro': null,
        'criado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> contarPendentes({int? colaboradorLocalId}) async {
    await garantirEstrutura();
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      colaboradorLocalId == null
          ? 'SELECT COUNT(*) AS total FROM imperium_ponto_batidas_pendentes'
          : '''
              SELECT COUNT(*) AS total
              FROM imperium_ponto_batidas_pendentes
              WHERE colaborador_local_id = ?
            ''',
      colaboradorLocalId == null ? const [] : [colaboradorLocalId],
    );

    if (resultado.isEmpty) return 0;
    return _int(resultado.first['total']);
  }

  Future<int> sincronizarPendentes({int? colaboradorLocalId}) async {
    if (_sincronizando) return 0;

    final client = _client;
    if (client == null || client.auth.currentUser == null) return 0;

    _sincronizando = true;

    try {
      await garantirEstrutura();
      final database = await _appDatabase.database;

      final pendentes = await database.query(
        'imperium_ponto_batidas_pendentes',
        where: colaboradorLocalId == null ? null : 'colaborador_local_id = ?',
        whereArgs: colaboradorLocalId == null ? null : [colaboradorLocalId],
        orderBy: 'id ASC',
      );

      var enviados = 0;

      for (final item in pendentes) {
        final id = _int(item['id']);
        final localId = _int(item['colaborador_local_id']);
        final chave = (item['chave'] ?? '').toString().trim();
        final ocorridoEm = DateTime.tryParse(
          (item['ocorrido_em'] ?? '').toString(),
        );

        if (id <= 0 || localId <= 0 || chave.isEmpty || ocorridoEm == null) {
          if (id > 0) {
            await database.delete(
              'imperium_ponto_batidas_pendentes',
              where: 'id = ?',
              whereArgs: [id],
            );
          }
          continue;
        }

        try {
          await registrarRemotoIdempotente(
            colaboradorLocalId: localId,
            ocorridoEm: ocorridoEm,
            chave: chave,
          );

          await database.delete(
            'imperium_ponto_batidas_pendentes',
            where: 'id = ?',
            whereArgs: [id],
          );

          await _nuvem.sincronizarDia(
            colaboradorLocalId: localId,
            data: ocorridoEm.toLocal(),
          );

          enviados++;
        } catch (erro) {
          await database.update(
            'imperium_ponto_batidas_pendentes',
            {
              'tentativas': _int(item['tentativas']) + 1,
              'ultimo_erro': _textoErro(erro),
            },
            where: 'id = ?',
            whereArgs: [id],
          );

          // Mantém a ordem: não tenta a saída antes de uma entrada pendente.
          break;
        }
      }

      return enviados;
    } finally {
      _sincronizando = false;
    }
  }

  bool ehErroConexao(Object erro) {
    if (erro is SocketException ||
        erro is TimeoutException ||
        erro is http.ClientException) {
      return true;
    }

    final texto = erro.toString().toLowerCase();

    return texto.contains('socketexception') ||
        texto.contains('clientexception') ||
        texto.contains('failed host lookup') ||
        texto.contains('network is unreachable') ||
        texto.contains('network request failed') ||
        texto.contains('connection refused') ||
        texto.contains('connection reset') ||
        texto.contains('connection closed') ||
        texto.contains('connection timed out') ||
        texto.contains('timed out') ||
        texto.contains('failed to fetch') ||
        texto.contains('xmlhttprequest');
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.length > 500 ? texto.substring(0, 500) : texto;
  }

  static Map<String, dynamic> _mapa(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is Map) {
      return valor.map<String, dynamic>(
        (chave, item) => MapEntry(chave.toString(), item),
      );
    }

    return <String, dynamic>{};
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
