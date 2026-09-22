import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincroniza os pagamentos de funcionários entre o SQLite e o Cloud.
///
/// O movimento financeiro é sincronizado pelo Financeiro V2. Este serviço
/// sincroniza apenas o vínculo do pagamento com funcionário/conta/movimento,
/// evitando criar uma segunda saída financeira.
class PagamentoColaboradorCloudService {
  PagamentoColaboradorCloudService._();

  static final PagamentoColaboradorCloudService instance =
      PagamentoColaboradorCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_pagamentos_colaboradores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        movimento_financeiro_id INTEGER,
        valor REAL NOT NULL,
        conta_id INTEGER NOT NULL,
        data_pagamento TEXT NOT NULL,
        forma_pagamento TEXT NOT NULL DEFAULT '',
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE RESTRICT,
        FOREIGN KEY (movimento_financeiro_id)
          REFERENCES movimentos_financeiros (id)
          ON DELETE SET NULL,
        FOREIGN KEY (conta_id)
          REFERENCES financeiro_contas (id)
          ON DELETE RESTRICT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_fin_pag_colaborador_data
      ON financeiro_pagamentos_colaboradores (
        colaborador_id,
        data_pagamento
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS
      imperium_sync_financeiro_pagamentos_colaboradores (
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
      await _baixarRemotos(empresaId);
      await _publicarLocais(empresaId);
      await _publicarExclusoesLocais(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> _baixarRemotos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_pagamentos_colaboradores')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;

      final mapa = await _mapaPorRemoto(
        empresaId: empresaId,
        remotoId: remotoId,
      );

      final excluido = _texto(remoto['excluido_em']).isNotEmpty;
      if (mapa != null) {
        if (excluido) {
          final localId = _int(mapa['local_id']);
          if (localId > 0) {
            final database = await _appDatabase.database;
            await database.delete(
              'financeiro_pagamentos_colaboradores',
              where: 'id = ?',
              whereArgs: [localId],
            );
            await _removerMapa(empresaId: empresaId, localId: localId);
          }
        }
        continue;
      }

      if (excluido) continue;

      final colaboradorLocal = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_precificacao_colaboradores',
        empresaId: empresaId,
        remotoId: _texto(remoto['colaborador_id']),
      );
      final contaLocal = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        remotoId: _texto(remoto['conta_id']),
      );
      final movimentoLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_financeiro_movimentos',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['movimento_financeiro_id']),
      );

      if (colaboradorLocal == null || contaLocal == null) continue;
      if (_texto(remoto['movimento_financeiro_id']).isNotEmpty &&
          movimentoLocal == null) {
        continue;
      }

      final database = await _appDatabase.database;
      final localId = await database.insert(
        'financeiro_pagamentos_colaboradores',
        {
          'colaborador_id': colaboradorLocal,
          'movimento_financeiro_id': movimentoLocal,
          'valor': _double(remoto['valor']),
          'conta_id': contaLocal,
          'data_pagamento': _texto(remoto['data_pagamento']),
          'forma_pagamento': _texto(remoto['forma_pagamento']),
          'observacoes': _texto(remoto['observacoes']),
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

  Future<void> _publicarLocais(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_pagamentos_colaboradores',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final existente = await _mapaLocal(
        empresaId: empresaId,
        localId: localId,
      );
      if (existente != null) continue;

      final colaboradorRemoto = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_precificacao_colaboradores',
        empresaId: empresaId,
        localId: _int(local['colaborador_id']),
      );
      final contaRemota = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: _int(local['conta_id']),
      );
      final movimentoRemoto = await _remotoPorLocalOpcional(
        tabelaMapa: 'imperium_sync_financeiro_movimentos',
        empresaId: empresaId,
        localId: _intNulo(local['movimento_financeiro_id']),
      );

      if (colaboradorRemoto == null || contaRemota == null) continue;
      if (_int(local['movimento_financeiro_id']) > 0 &&
          movimentoRemoto == null) {
        continue;
      }

      final dispositivoId = await _dispositivoId();
      final existenteRemoto = await client
          .from('imperium_financeiro_pagamentos_colaboradores')
          .select('id,criado_em')
          .eq('empresa_id', empresaId)
          .eq('origem_dispositivo', dispositivoId)
          .eq('origem_local_id', localId)
          .maybeSingle();

      if (existenteRemoto != null) {
        await _salvarMapa(
          empresaId: empresaId,
          localId: localId,
          remotoId: _texto(existenteRemoto['id']),
          criadoEm: existenteRemoto['criado_em']?.toString(),
        );
        continue;
      }

      final raw = await client
          .from('imperium_financeiro_pagamentos_colaboradores')
          .insert({
            'empresa_id': empresaId,
            'origem_dispositivo': dispositivoId,
            'origem_local_id': localId,
            'colaborador_id': colaboradorRemoto,
            'origem_colaborador_local_id': _int(local['colaborador_id']),
            'movimento_financeiro_id': movimentoRemoto,
            'origem_movimento_local_id': _intNulo(
              local['movimento_financeiro_id'],
            ),
            'valor': _double(local['valor']),
            'conta_id': contaRemota,
            'origem_conta_local_id': _int(local['conta_id']),
            'data_pagamento': _texto(local['data_pagamento']),
            'forma_pagamento': _texto(local['forma_pagamento']),
            'observacoes': _texto(local['observacoes']),
            'origem_criado_em': _textoNulo(local['criado_em']),
            'excluido_em': null,
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

  Future<void> _publicarExclusoesLocais(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      'imperium_sync_financeiro_pagamentos_colaboradores',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      if (localId <= 0) continue;

      final local = await database.query(
        'financeiro_pagamentos_colaboradores',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (local.isNotEmpty) continue;

      await client
          .from('imperium_financeiro_pagamentos_colaboradores')
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', _texto(mapa['remoto_id']))
          .isFilter('excluido_em', null);

      await _removerMapa(empresaId: empresaId, localId: localId);
    }
  }

  Future<Map<String, Object?>?> _mapaLocal({
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_pagamentos_colaboradores',
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _mapaPorRemoto({
    required String empresaId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_pagamentos_colaboradores',
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> _remotoPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _texto(rows.first['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<String?> _remotoPorLocalOpcional({
    required String tabelaMapa,
    required String empresaId,
    required int? localId,
  }) async {
    if (localId == null || localId <= 0) return null;
    return _remotoPorLocal(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
  }

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.trim().isEmpty) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<int?> _localPorRemotoOpcional({
    required String tabelaMapa,
    required String empresaId,
    required String? remotoId,
  }) async {
    if (remotoId == null || remotoId.trim().isEmpty) return null;
    return _localPorRemoto(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
  }

  Future<void> _salvarMapa({
    required String empresaId,
    required int localId,
    required String remotoId,
    String? criadoEm,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_financeiro_pagamentos_colaboradores',
      {
        'empresa_id': empresaId,
        'local_id': localId,
        'remoto_id': remotoId,
        'criado_em': criadoEm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _removerMapa({
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    await database.delete(
      'imperium_sync_financeiro_pagamentos_colaboradores',
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
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

  static String? _textoNulo(Object? value) {
    final texto = _texto(value);
    return texto.isEmpty ? null : texto;
  }

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

  static int? _intNulo(Object? value) {
    if (value == null) return null;
    final valor = _int(value);
    return valor <= 0 ? null : valor;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_texto(value).replaceAll(',', '.')) ?? 0;
  }
}
