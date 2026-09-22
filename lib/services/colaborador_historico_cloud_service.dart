import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincroniza o histórico salarial e de situação dos funcionários.
///
/// O histórico é append-only. O cadastro atual continua sincronizado pelo
/// Precificação Cloud; este serviço apenas compartilha as ocorrências que o
/// Android já grava localmente e as ocorrências criadas pelo Web.
class ColaboradorHistoricoCloudService {
  ColaboradorHistoricoCloudService._();

  static final ColaboradorHistoricoCloudService instance =
      ColaboradorHistoricoCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_colaboradores_historico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        remuneracao_anterior REAL NOT NULL DEFAULT 0,
        remuneracao_nova REAL NOT NULL DEFAULT 0,
        encargos_anteriores REAL NOT NULL DEFAULT 0,
        encargos_novos REAL NOT NULL DEFAULT 0,
        outros_custos_anteriores REAL NOT NULL DEFAULT 0,
        outros_custos_novos REAL NOT NULL DEFAULT 0,
        ativo_anterior INTEGER,
        ativo_novo INTEGER,
        motivo TEXT NOT NULL DEFAULT '',
        vigencia_em TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS
      imperium_sync_precificacao_colaboradores_historico (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        criado_em TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      await _baixar(empresaId);
      await _publicar(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> _baixar(String empresaId) async {
    final client = _client;
    if (client == null) return;
    final remotos = await client
        .from('imperium_precificacao_colaboradores_historico')
        .select()
        .eq('empresa_id', empresaId)
        .order('vigencia_em');

    final database = await _appDatabase.database;
    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty ||
          await _mapaPorRemoto(empresaId, remotoId) != null) {
        continue;
      }

      final colaboradorLocal = await _localPorRemoto(
        empresaId,
        _texto(remoto['colaborador_id']),
      );
      if (colaboradorLocal == null) continue;

      final localId = await database.insert(
        'financeiro_colaboradores_historico',
        <String, Object?>{
          'colaborador_id': colaboradorLocal,
          'tipo': _texto(remoto['tipo']),
          'remuneracao_anterior': _double(remoto['remuneracao_anterior']),
          'remuneracao_nova': _double(remoto['remuneracao_nova']),
          'encargos_anteriores': _double(remoto['encargos_anteriores']),
          'encargos_novos': _double(remoto['encargos_novos']),
          'outros_custos_anteriores': _double(
            remoto['outros_custos_anteriores'],
          ),
          'outros_custos_novos': _double(remoto['outros_custos_novos']),
          'ativo_anterior': _boolNuloParaInt(remoto['ativo_anterior']),
          'ativo_novo': _boolNuloParaInt(remoto['ativo_novo']),
          'motivo': _texto(remoto['motivo']),
          'vigencia_em': _texto(remoto['vigencia_em']),
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _salvarMapa(
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        criadoEm: remoto['criado_em']?.toString(),
      );
    }
  }

  Future<void> _publicar(String empresaId) async {
    final client = _client;
    if (client == null) return;
    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_colaboradores_historico',
      orderBy: 'id ASC',
    );
    final dispositivoId = await _dispositivoId();

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0 || await _mapaLocal(empresaId, localId) != null) {
        continue;
      }

      final colaboradorRemoto = await _remotoPorLocal(
        empresaId,
        _int(local['colaborador_id']),
      );
      if (colaboradorRemoto == null) continue;

      final existente = await client
          .from('imperium_precificacao_colaboradores_historico')
          .select('id,criado_em')
          .eq('empresa_id', empresaId)
          .eq('origem_dispositivo', dispositivoId)
          .eq('origem_local_id', localId)
          .maybeSingle();

      if (existente != null) {
        await _salvarMapa(
          empresaId: empresaId,
          localId: localId,
          remotoId: _texto(existente['id']),
          criadoEm: existente['criado_em']?.toString(),
        );
        continue;
      }

      final raw = await client
          .from('imperium_precificacao_colaboradores_historico')
          .insert(<String, Object?>{
            'empresa_id': empresaId,
            'origem_dispositivo': dispositivoId,
            'origem_local_id': localId,
            'colaborador_id': colaboradorRemoto,
            'origem_colaborador_local_id': _int(local['colaborador_id']),
            'tipo': _texto(local['tipo']),
            'remuneracao_anterior': _double(local['remuneracao_anterior']),
            'remuneracao_nova': _double(local['remuneracao_nova']),
            'encargos_anteriores': _double(local['encargos_anteriores']),
            'encargos_novos': _double(local['encargos_novos']),
            'outros_custos_anteriores': _double(
              local['outros_custos_anteriores'],
            ),
            'outros_custos_novos': _double(local['outros_custos_novos']),
            'ativo_anterior': _intNuloParaBool(local['ativo_anterior']),
            'ativo_novo': _intNuloParaBool(local['ativo_novo']),
            'motivo': _texto(local['motivo']),
            'vigencia_em': _texto(local['vigencia_em']),
            'origem_criado_em': _texto(local['criado_em']),
          })
          .select('id,criado_em')
          .single();

      await _salvarMapa(
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(raw['id']),
        criadoEm: raw['criado_em']?.toString(),
      );
    }
  }

  Future<Map<String, Object?>?> _mapaLocal(
    String empresaId,
    int localId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_colaboradores_historico',
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _mapaPorRemoto(
    String empresaId,
    String remotoId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_colaboradores_historico',
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> _remotoPorLocal(String empresaId, int localId) async {
    if (localId <= 0) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_colaboradores',
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _texto(rows.first['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<int?> _localPorRemoto(String empresaId, String remotoId) async {
    if (remotoId.isEmpty) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_colaboradores',
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<void> _salvarMapa({
    required String empresaId,
    required int localId,
    required String remotoId,
    String? criadoEm,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_precificacao_colaboradores_historico',
      <String, Object?>{
        'empresa_id': empresaId,
        'local_id': localId,
        'remoto_id': remotoId,
        'criado_em': criadoEm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );
    final id = rows.isEmpty ? '' : _texto(rows.first['dispositivo_id']);
    if (id.isEmpty) {
      throw StateError('Dispositivo de sincronização não inicializado.');
    }
    return id;
  }

  static String _texto(Object? value) => value?.toString().trim() ?? '';

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;
    final b = _texto(segundo);
    return b.isNotEmpty ? b : DateTime.now().toIso8601String();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_texto(value)) ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_texto(value).replaceAll(',', '.')) ?? 0;
  }

  static int? _boolNuloParaInt(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    final text = _texto(value).toLowerCase();
    if (text == 'true' || text == '1') return 1;
    if (text == 'false' || text == '0') return 0;
    return null;
  }

  static bool? _intNuloParaBool(Object? value) {
    if (value == null) return null;
    final valor = _int(value);
    return valor == 1;
  }
}
