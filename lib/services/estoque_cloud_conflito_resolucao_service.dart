import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Estoque Cloud V2.2.
///
/// Resolve conflitos V2.1 de forma explicita:
/// - usar local: aplica o estado local na nuvem;
/// - usar nuvem: aplica o estado remoto no SQLite;
/// - registra auditoria e encerra o conflito somente depois da aplicacao.
class EstoqueCloudConflitoResolucaoService {
  EstoqueCloudConflitoResolucaoService._();

  static final EstoqueCloudConflitoResolucaoService instance =
      EstoqueCloudConflitoResolucaoService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // estoque-cloud-resolucao-v2-2
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    final tabela = await database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'imperium_sync_estoque_conflitos' "
      "LIMIT 1",
    );

    if (tabela.isEmpty) {
      throw StateError(
        'Tabela de conflitos do Estoque V2.1 ainda nao foi criada.',
      );
    }

    await _garantirColuna(database, coluna: 'resolucao', tipo: 'TEXT');
    await _garantirColuna(database, coluna: 'resolucao_detalhe', tipo: 'TEXT');
  }

  Future<List<Map<String, Object?>>> listarPendentes({
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

  Future<List<Map<String, Object?>>> listarHistorico({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_estoque_conflitos',
      where: empresaId == null ? null : 'empresa_id = ?',
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponivel para resolver o conflito.');
    }

    final conflito = await _buscarConflitoPendente(conflitoId);
    final empresaId = (conflito['empresa_id'] ?? '').toString().trim();
    final entidade = (conflito['entidade'] ?? '').toString().trim();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString().trim();

    final config = _config(entidade);
    final local = await _localPorId(
      tabela: config.tabelaLocal,
      localId: localId,
    );

    final Map<String, dynamic> payload;
    final String localHash;

    if (entidade == 'item') {
      payload = _payloadItem(local);
      localHash = _hashItem(local);
    } else {
      payload = await _payloadLote(empresaId: empresaId, local: local);
      localHash = _hashLote(local);
    }

    final existente = await client
        .from(config.tabelaRemota)
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (existente == null) {
      throw StateError(
        'Registro remoto nao existe mais; resolucao usando local interrompida.',
      );
    }

    final remoto = await client
        .from(config.tabelaRemota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em')
        .single();

    await _atualizarMapa(
      tabelaMapa: config.tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      localHash: localHash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrar(
      conflitoId: conflitoId,
      resolucao: 'local',
      detalhe: 'Versao local aplicada na nuvem.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponivel para resolver o conflito.');
    }

    final conflito = await _buscarConflitoPendente(conflitoId);
    final empresaId = (conflito['empresa_id'] ?? '').toString().trim();
    final entidade = (conflito['entidade'] ?? '').toString().trim();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString().trim();

    final config = _config(entidade);

    final remotoRaw = await client
        .from(config.tabelaRemota)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError(
        'Registro remoto nao existe mais; nao ha versao da nuvem para aplicar.',
      );
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);

    if (entidade == 'item') {
      await _aplicarItemRemoto(localId: localId, remoto: remoto);
    } else {
      await _aplicarLoteRemoto(
        empresaId: empresaId,
        localId: localId,
        remoto: remoto,
      );
    }

    final localAtual = await _localPorId(
      tabela: config.tabelaLocal,
      localId: localId,
    );

    await _atualizarMapa(
      tabelaMapa: config.tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      localHash: entidade == 'item'
          ? _hashItem(localAtual)
          : _hashLote(localAtual),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrar(
      conflitoId: conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versao da nuvem aplicada no SQLite.',
    );
  }

  Future<void> _aplicarItemRemoto({
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final excluido = (remoto['excluido_em'] ?? '').toString().trim().isNotEmpty;

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
        'ativo': excluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
        'atualizado_em': atualizadoEm,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> _aplicarLoteRemoto({
    required String empresaId,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final itemRemotoId = (remoto['item_estoque_id'] ?? '').toString().trim();
    final itemLocalId = await _localPorRemoto(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      remotoId: itemRemotoId,
    );

    if (itemLocalId == null) {
      throw StateError('Item remoto do lote ainda nao possui mapa local.');
    }

    final database = await _appDatabase.database;
    final excluido = (remoto['excluido_em'] ?? '').toString().trim().isNotEmpty;

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
        'ativo': excluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Map<String, dynamic> _payloadItem(Map<String, Object?> local) {
    return <String, dynamic>{
      'nome': (local['nome'] ?? '').toString(),
      'categoria': (local['categoria'] ?? '').toString(),
      'quantidade': _double(local['quantidade']),
      'quantidade_minima': _double(local['quantidade_minima']),
      'unidade': (local['unidade'] ?? 'un').toString(),
      'valor_total_pago': _double(local['valor_total_pago']),
      'quantidade_total': _double(local['quantidade_total']),
      'ean': (local['ean'] ?? '').toString(),
      'custo_unitario': _double(local['custo_unitario']),
      'custo_unitario_calculado': _double(local['custo_unitario_calculado']),
      'fornecedor': (local['fornecedor'] ?? '').toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'ativo': _int(local['ativo']) != 0,
      'origem_atualizado_em': local['atualizado_em']?.toString(),
      'excluido_em': null,
    };
  }

  Future<Map<String, dynamic>> _payloadLote({
    required String empresaId,
    required Map<String, Object?> local,
  }) async {
    final itemLocalId = _int(local['item_estoque_id']);
    final itemRemotoId = await _remotoPorLocal(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      localId: itemLocalId,
    );

    if (itemRemotoId == null) {
      throw StateError('Item local do lote ainda nao possui mapa remoto.');
    }

    return <String, dynamic>{
      'item_estoque_id': itemRemotoId,
      'data_compra': (local['data_compra'] ?? '').toString(),
      'quantidade_original': _double(local['quantidade_original']),
      'quantidade_normalizada': _double(local['quantidade_normalizada']),
      'quantidade_disponivel': _double(local['quantidade_disponivel']),
      'unidade_original': (local['unidade_original'] ?? '').toString(),
      'unidade_base': (local['unidade_base'] ?? 'un').toString(),
      'valor_total_pago': _double(local['valor_total_pago']),
      'custo_unitario': _double(local['custo_unitario']),
      'fornecedor': (local['fornecedor'] ?? '').toString(),
      'observacao': (local['observacao'] ?? '').toString(),
      'ativo': _int(local['ativo']) != 0,
      'excluido_em': null,
    };
  }

  Future<Map<String, Object?>> _buscarConflitoPendente(int id) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'imperium_sync_estoque_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError('Conflito pendente nao encontrado.');
    }

    return resultado.first;
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
      throw StateError('Registro local nao encontrado.');
    }

    return resultado.first;
  }

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
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

  Future<String?> _remotoPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;

    final id = (resultado.first['remoto_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<void> _atualizarMapa({
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

  Future<void> _encerrar({
    required int conflitoId,
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;

    final atualizados = await database.update(
      'imperium_sync_estoque_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [conflitoId],
    );

    if (atualizados != 1) {
      throw StateError('Conflito nao foi encerrado porque seu estado mudou.');
    }
  }

  Future<void> _garantirColuna(
    Database database, {
    required String coluna,
    required String tipo,
  }) async {
    final colunas = await database.rawQuery(
      'PRAGMA table_info(imperium_sync_estoque_conflitos)',
    );

    final existe = colunas.any(
      (item) => (item['name'] ?? '').toString() == coluna,
    );

    if (!existe) {
      await database.execute(
        'ALTER TABLE imperium_sync_estoque_conflitos '
        'ADD COLUMN $coluna $tipo',
      );
    }
  }

  _ConfigConflito _config(String entidade) {
    switch (entidade) {
      case 'item':
        return const _ConfigConflito(
          tabelaLocal: 'itens_estoque',
          tabelaMapa: 'imperium_sync_estoque_itens',
          tabelaRemota: 'imperium_estoque_itens',
        );
      case 'lote':
        return const _ConfigConflito(
          tabelaLocal: 'estoque_lotes',
          tabelaMapa: 'imperium_sync_estoque_lotes',
          tabelaRemota: 'imperium_estoque_lotes',
        );
      default:
        throw StateError('Entidade de conflito de estoque invalida: $entidade');
    }
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

class _ConfigConflito {
  const _ConfigConflito({
    required this.tabelaLocal,
    required this.tabelaMapa,
    required this.tabelaRemota,
  });

  final String tabelaLocal;
  final String tabelaMapa;
  final String tabelaRemota;
}
