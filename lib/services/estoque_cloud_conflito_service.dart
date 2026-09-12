import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Etapa 5 - Estoque Cloud V2.1.
///
/// Reconciliacao antes do upload:
/// - local mudou, remoto igual ao baseline -> upload pode seguir;
/// - local igual, remoto mudou -> aplica remoto localmente;
/// - local mudou e remoto mudou -> registra conflito e nao sobrescreve;
/// - soft delete remoto segue a mesma regra.
/// Movimentacoes continuam append-only e nao entram em conflito de update.
class EstoqueCloudConflitoService {
  EstoqueCloudConflitoService._();

  static final EstoqueCloudConflitoService instance =
      EstoqueCloudConflitoService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // estoque-cloud-conflitos-v2-1
  Future<void> reconciliarAntesDoUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      await _reconciliarItens(empresaId);
      await _reconciliarLotes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_estoque_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        entidade TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_atualizado_base TEXT,
        remoto_atualizado_atual TEXT,
        local_json TEXT NOT NULL DEFAULT '',
        remoto_json TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Pendente',
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_imperium_sync_estoque_conflitos_pendentes
      ON imperium_sync_estoque_conflitos (
        empresa_id,
        entidade,
        status,
        local_id
      )
    ''');
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_estoque_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<void> _reconciliarItens(String empresaId) async {
    await _reconciliarEntidade(
      empresaId: empresaId,
      entidade: 'item',
      tabelaLocal: 'itens_estoque',
      tabelaMapa: 'imperium_sync_estoque_itens',
      tabelaRemota: 'imperium_estoque_itens',
      hashLocal: _hashItem,
      aplicarRemoto: _aplicarItemRemoto,
    );
  }

  Future<void> _reconciliarLotes(String empresaId) async {
    await _reconciliarEntidade(
      empresaId: empresaId,
      entidade: 'lote',
      tabelaLocal: 'estoque_lotes',
      tabelaMapa: 'imperium_sync_estoque_lotes',
      tabelaRemota: 'imperium_estoque_lotes',
      hashLocal: _hashLote,
      aplicarRemoto: _aplicarLoteRemoto,
    );
  }

  Future<void> _reconciliarEntidade({
    required String empresaId,
    required String entidade,
    required String tabelaLocal,
    required String tabelaMapa,
    required String tabelaRemota,
    required String Function(Map<String, Object?>) hashLocal,
    required Future<void> Function(
      String empresaId,
      int localId,
      Map<String, dynamic> remoto,
      Map<String, Object?> mapa,
    )
    aplicarRemoto,
  }) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      tabelaMapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      final remotoId = (mapa['remoto_id'] ?? '').toString().trim();

      if (localId <= 0 || remotoId.isEmpty) continue;
      if ((mapa['local_hash'] ?? '').toString() == '__excluido__') continue;

      if (await _possuiConflitoPendente(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final locais = await database.query(
        tabelaLocal,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (locais.isEmpty) continue;

      final local = locais.first;
      final localHashBase = (mapa['local_hash'] ?? '').toString();
      final localHashAtual = hashLocal(local);
      final localMudou = localHashBase != localHashAtual;

      final remotoRaw = await client
          .from(tabelaRemota)
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoRaw == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'remoto_ausente',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoBase = (mapa['remoto_atualizado_em'] ?? '').toString().trim();
      final remotoAtual = (remoto['atualizado_em'] ?? '').toString().trim();
      final remotoExcluido = (remoto['excluido_em'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

      final remotoMudou =
          remotoExcluido ||
          remotoBase.isEmpty ||
          remotoAtual.isEmpty ||
          remotoAtual != remotoBase;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: remotoExcluido
              ? 'alteracao_local_e_exclusao_remota'
              : 'alteracao_concorrente',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: remoto,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        await aplicarRemoto(empresaId, localId, remoto, mapa);
      }
    }
  }

  Future<void> _aplicarItemRemoto(
    String empresaId,
    int localId,
    Map<String, dynamic> remoto,
    Map<String, Object?> mapa,
  ) async {
    final database = await _appDatabase.database;
    final remotoExcluido = (remoto['excluido_em'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    final atualizadoEm = _textoPreferido(
      remoto['origem_atualizado_em'],
      remoto['atualizado_em'],
      DateTime.now().toIso8601String(),
    );

    await database.update(
      'itens_estoque',
      {
        'nome': (remoto['nome'] ?? '').toString(),
        'categoria': (remoto['categoria'] ?? '').toString(),
        'quantidade': _double(remoto['quantidade']),
        'quantidade_minima': _double(remoto['quantidade_minima']),
        'unidade': (remoto['unidade'] ?? 'un').toString(),
        'valor_total_pago': _double(remoto['valor_total_pago']),
        'quantidade_total': _double(remoto['quantidade_total']),
        'ean': (remoto['ean'] ?? '').toString(),
        'custo_unitario': _double(remoto['custo_unitario']),
        'custo_unitario_calculado': _double(remoto['custo_unitario_calculado']),
        'fornecedor': (remoto['fornecedor'] ?? '').toString(),
        'observacoes': (remoto['observacoes'] ?? '').toString(),
        'ativo': remotoExcluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
        'atualizado_em': atualizadoEm,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );

    final atualizado = await _localPorId(
      tabela: 'itens_estoque',
      localId: localId,
    );

    await _atualizarMapaAposDownload(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      localId: localId,
      localHash: _hashItem(atualizado),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _aplicarLoteRemoto(
    String empresaId,
    int localId,
    Map<String, dynamic> remoto,
    Map<String, Object?> mapa,
  ) async {
    final database = await _appDatabase.database;
    final remotoExcluido = (remoto['excluido_em'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    final itemRemotoId = (remoto['item_estoque_id'] ?? '').toString().trim();
    final itemLocalId = await _localPorRemoto(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      remotoId: itemRemotoId,
    );

    if (itemLocalId == null) {
      final local = await _localPorId(
        tabela: 'estoque_lotes',
        localId: localId,
      );
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'lote',
        localId: localId,
        remotoId: (mapa['remoto_id'] ?? '').toString(),
        motivo: 'dependencia_item_remoto_sem_mapa_local',
        mapa: mapa,
        localHashAtual: _hashLote(local),
        local: local,
        remoto: remoto,
      );
      return;
    }

    await database.update(
      'estoque_lotes',
      {
        'item_estoque_id': itemLocalId,
        'data_compra': (remoto['data_compra'] ?? '').toString(),
        'quantidade_original': _double(remoto['quantidade_original']),
        'quantidade_normalizada': _double(remoto['quantidade_normalizada']),
        'quantidade_disponivel': _double(remoto['quantidade_disponivel']),
        'unidade_original': (remoto['unidade_original'] ?? '').toString(),
        'unidade_base': (remoto['unidade_base'] ?? 'un').toString(),
        'valor_total_pago': _double(remoto['valor_total_pago']),
        'custo_unitario': _double(remoto['custo_unitario']),
        'fornecedor': (remoto['fornecedor'] ?? '').toString(),
        'observacao': (remoto['observacao'] ?? '').toString(),
        'ativo': remotoExcluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );

    final atualizado = await _localPorId(
      tabela: 'estoque_lotes',
      localId: localId,
    );

    await _atualizarMapaAposDownload(
      tabelaMapa: 'imperium_sync_estoque_lotes',
      empresaId: empresaId,
      localId: localId,
      localHash: _hashLote(atualizado),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<bool> _possuiConflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'imperium_sync_estoque_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );

    return resultado.isNotEmpty;
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required Map<String, Object?> mapa,
    required String localHashAtual,
    required Map<String, Object?> local,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    final existente = await database.query(
      'imperium_sync_estoque_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );

    final dados = <String, Object?>{
      'empresa_id': empresaId,
      'entidade': entidade,
      'local_id': localId,
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': (mapa['local_hash'] ?? '').toString(),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': (mapa['remoto_atualizado_em'] ?? '').toString(),
      'remoto_atualizado_atual': (remoto['atualizado_em'] ?? '').toString(),
      'local_json': jsonEncode(local),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'detectado_em': agora,
      'resolvido_em': null,
    };

    if (existente.isEmpty) {
      await database.insert(
        'imperium_sync_estoque_conflitos',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await database.update(
        'imperium_sync_estoque_conflitos',
        dados,
        where: 'id = ?',
        whereArgs: [existente.first['id']],
      );
    }
  }

  Future<void> _atualizarMapaAposDownload({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      tabelaMapa,
      {'local_hash': localHash, 'remoto_atualizado_em': remotoAtualizadoEm},
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
    );
  }

  Future<Map<String, Object?>> _localPorId({
    required String tabela,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabela,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Registro local nao encontrado durante reconciliacao.');
    }

    return resultado.first;
  }

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;

    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;

    final id = _int(resultado.first['local_id']);
    return id <= 0 ? null : id;
  }

  String _hashItem(Map<String, Object?> local) {
    return _hash(<Object?>[
      local['nome'],
      local['categoria'],
      _double(local['quantidade']),
      _double(local['quantidade_minima']),
      local['unidade'],
      _double(local['valor_total_pago']),
      _double(local['quantidade_total']),
      local['ean'],
      _double(local['custo_unitario']),
      _double(local['custo_unitario_calculado']),
      local['fornecedor'],
      local['observacoes'],
      _int(local['ativo']),
      local['atualizado_em'],
    ]);
  }

  String _hashLote(Map<String, Object?> local) {
    return _hash(<Object?>[
      _int(local['item_estoque_id']),
      local['data_compra'],
      _double(local['quantidade_original']),
      _double(local['quantidade_normalizada']),
      _double(local['quantidade_disponivel']),
      local['unidade_original'],
      local['unidade_base'],
      _double(local['valor_total_pago']),
      _double(local['custo_unitario']),
      local['fornecedor'],
      local['observacao'],
      _int(local['ativo']),
      local['criado_em'],
    ]);
  }

  String _hash(List<Object?> valores) {
    return sha256.convert(utf8.encode(jsonEncode(valores))).toString();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static String _textoPreferido(
    Object? primeiro,
    Object? segundo,
    String fallback,
  ) {
    final a = (primeiro ?? '').toString().trim();
    if (a.isNotEmpty) return a;

    final b = (segundo ?? '').toString().trim();
    if (b.isNotEmpty) return b;

    return fallback;
  }
}
