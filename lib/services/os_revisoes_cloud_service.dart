import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Histórico append-only das correções administrativas de Ordens de Serviço.
class OsRevisoesCloudService {
  OsRevisoesCloudService._();

  static final OsRevisoesCloudService instance = OsRevisoesCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (client == null || empresaId.trim().isEmpty) return;

    final database = await _appDatabase.database;
    await _garantirMapa(database);

    await _publicarLocais(database, client, empresaId);
    await _baixarRemotas(database, client, empresaId);
  }

  Future<void> _garantirMapa(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_revisoes (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<void> _publicarLocais(
    DatabaseExecutor database,
    SupabaseClient client,
    String empresaId,
  ) async {
    final dispositivoId = await _dispositivoId(database);
    final locais = await database.query(
      'ordem_servico_revisoes',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      final ordemLocalId = _int(local['ordem_servico_id']);
      final numeroRevisao = _int(local['numero_revisao']);

      if (localId <= 0 || ordemLocalId <= 0 || numeroRevisao <= 0) continue;

      final mapa = await _mapaLocal(
        database,
        empresaId: empresaId,
        localId: localId,
      );
      if (mapa != null) continue;

      final ordemRemotaId = await _ordemRemotaPorLocal(
        database,
        empresaId: empresaId,
        localId: ordemLocalId,
      );
      if (ordemRemotaId == null) continue;

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'ordem_servico_id': ordemRemotaId,
        'origem_dispositivo': dispositivoId,
        'origem_local_id': localId,
        'numero_revisao': numeroRevisao,
        'tipo': _texto(local['tipo']).isEmpty
            ? 'Correcao administrativa'
            : _texto(local['tipo']),
        'motivo': _texto(local['motivo']),
        'dados_anteriores': _jsonObjeto(local['dados_anteriores_json']),
        'dados_novos': _jsonObjeto(local['dados_novos_json']),
        'criado_em': _texto(local['criado_em']).isEmpty
            ? DateTime.now().toUtc().toIso8601String()
            : _texto(local['criado_em']),
      };

      Map<String, dynamic>? remoto;

      try {
        remoto = Map<String, dynamic>.from(
          await client
              .from('imperium_ordem_servico_revisoes')
              .insert(payload)
              .select()
              .single(),
        );
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;

        final existente = await client
            .from('imperium_ordem_servico_revisoes')
            .select()
            .eq('empresa_id', empresaId)
            .eq('ordem_servico_id', ordemRemotaId)
            .eq('numero_revisao', numeroRevisao)
            .maybeSingle();

        if (existente == null) rethrow;
        remoto = Map<String, dynamic>.from(existente);
      }

      await _salvarMapa(
        database,
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
      );
    }
  }

  Future<void> _baixarRemotas(
    DatabaseExecutor database,
    SupabaseClient client,
    String empresaId,
  ) async {
    final remotas = await client
        .from('imperium_ordem_servico_revisoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final raw in remotas as List) {
      final remoto = Map<String, dynamic>.from(raw as Map);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;

      final mapa = await _mapaRemoto(
        database,
        empresaId: empresaId,
        remotoId: remotoId,
      );
      if (mapa != null) continue;

      final ordemLocalId = await _ordemLocalPorRemoto(
        database,
        empresaId: empresaId,
        remotoId: _texto(remoto['ordem_servico_id']),
      );
      if (ordemLocalId == null) continue;

      final numeroRevisao = _int(remoto['numero_revisao']);
      if (numeroRevisao <= 0) continue;

      final existente = await database.query(
        'ordem_servico_revisoes',
        columns: ['id'],
        where: 'ordem_servico_id = ? AND numero_revisao = ?',
        whereArgs: [ordemLocalId, numeroRevisao],
        limit: 1,
      );

      int localId;
      if (existente.isNotEmpty) {
        localId = _int(existente.first['id']);
      } else {
        localId = await database
            .insert('ordem_servico_revisoes', <String, Object?>{
              'ordem_servico_id': ordemLocalId,
              'numero_revisao': numeroRevisao,
              'tipo': _texto(remoto['tipo']),
              'motivo': _texto(remoto['motivo']),
              'dados_anteriores_json': jsonEncode(
                _mapJson(remoto['dados_anteriores']),
              ),
              'dados_novos_json': jsonEncode(_mapJson(remoto['dados_novos'])),
              'criado_em': _texto(remoto['criado_em']),
            }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      if (localId <= 0) continue;

      await _salvarMapa(
        database,
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
      );
    }
  }

  Future<String> _dispositivoId(DatabaseExecutor database) async {
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );
    final valor = rows.isEmpty ? '' : _texto(rows.first['dispositivo_id']);
    if (valor.isEmpty) {
      throw StateError('Dispositivo de sincronização não configurado.');
    }
    return valor;
  }

  Future<String?> _ordemRemotaPorLocal(
    DatabaseExecutor database, {
    required String empresaId,
    required int localId,
  }) async {
    final rows = await database.query(
      'imperium_sync_ordens_servico',
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final remotoId = _texto(rows.first['remoto_id']);
    return remotoId.isEmpty ? null : remotoId;
  }

  Future<int?> _ordemLocalPorRemoto(
    DatabaseExecutor database, {
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;

    final rows = await database.query(
      'imperium_sync_ordens_servico',
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final localId = _int(rows.first['local_id']);
    return localId <= 0 ? null : localId;
  }

  Future<Map<String, Object?>?> _mapaLocal(
    DatabaseExecutor database, {
    required String empresaId,
    required int localId,
  }) async {
    final rows = await database.query(
      'imperium_sync_os_revisoes',
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _mapaRemoto(
    DatabaseExecutor database, {
    required String empresaId,
    required String remotoId,
  }) async {
    final rows = await database.query(
      'imperium_sync_os_revisoes',
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> _salvarMapa(
    DatabaseExecutor database, {
    required String empresaId,
    required int localId,
    required String remotoId,
  }) async {
    if (localId <= 0 || remotoId.isEmpty) return;

    await database.insert('imperium_sync_os_revisoes', <String, Object?>{
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Map<String, dynamic> _jsonObjeto(dynamic valor) {
    if (valor is Map) return Map<String, dynamic>.from(valor);

    final texto = _texto(valor);
    if (texto.isEmpty) return <String, dynamic>{};

    try {
      final decodificado = jsonDecode(texto);
      return _mapJson(decodificado);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _mapJson(dynamic valor) {
    if (valor is Map) return Map<String, dynamic>.from(valor);
    return <String, dynamic>{};
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';
}
