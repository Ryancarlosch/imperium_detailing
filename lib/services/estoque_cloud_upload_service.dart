import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Etapa 5 - Estoque Cloud.
///
/// V1 propositalmente upload-only:
/// - publica itens e lotes mutáveis;
/// - publica movimentações como append-only;
/// - não baixa estoque para outro dispositivo;
/// - não altera o motor local de FIFO/saldo;
/// - não publica nem altera movimentos financeiros.
class EstoqueCloudUploadService {
  EstoqueCloudUploadService._();

  static final EstoqueCloudUploadService instance =
      EstoqueCloudUploadService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // estoque-cloud-upload-service-v1
  Future<void> sincronizarUpload(String empresaId) async {
    if (empresaId.trim().isEmpty || _client == null) return;

    try {
      await garantirEstruturaLocal();
      await _publicarItensLocais(empresaId);
      await _publicarLotesLocais(empresaId);
      await _publicarMovimentacoesLocais(empresaId);
    } on PostgrestException catch (error) {
      // Funcionário sem permissão de Estoque não deve impedir a
      // sincronização de Clientes/Agenda/OS/Ponto.
      if (_semPermissaoEstoque(error)) return;
      rethrow;
    }
  }

  // estoque-cloud-upload-mapas-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_estoque_itens',
      'imperium_sync_estoque_lotes',
      'imperium_sync_estoque_movimentacoes',
    ]) {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS $tabela (
          empresa_id TEXT NOT NULL,
          local_id INTEGER NOT NULL,
          remoto_id TEXT NOT NULL,
          local_hash TEXT,
          remoto_atualizado_em TEXT,
          PRIMARY KEY (empresa_id, local_id),
          UNIQUE (empresa_id, remoto_id)
        )
      ''');
    }
  }

  Future<void> _publicarItensLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('itens_estoque');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashItem(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarItem(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }

    await _marcarAusentesComoExcluidos(
      empresaId: empresaId,
      tabelaLocal: 'itens_estoque',
      tabelaMapa: 'imperium_sync_estoque_itens',
      tabelaRemota: 'imperium_estoque_itens',
    );
  }

  Future<void> _publicarItem({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
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
      'origem_atualizado_em': _nuloTexto(local['atualizado_em']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_estoque_itens')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_estoque_itens')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarLotesLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('estoque_lotes');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashLote(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_estoque_lotes',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarLote(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }

    await _marcarAusentesComoExcluidos(
      empresaId: empresaId,
      tabelaLocal: 'estoque_lotes',
      tabelaMapa: 'imperium_sync_estoque_lotes',
      tabelaRemota: 'imperium_estoque_lotes',
    );
  }

  Future<void> _publicarLote({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final itemLocalId = _int(local['item_estoque_id']);
    final itemRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      localId: itemLocalId,
    );

    if (itemRemotoId == null) {
      throw StateError(
        'Item de estoque do lote #$localId ainda não foi sincronizado.',
      );
    }

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
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
      'origem_criado_em': _nuloTexto(local['criado_em']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_estoque_lotes')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_estoque_lotes')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_estoque_lotes',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarMovimentacoesLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'movimentacoes_estoque',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_estoque_movimentacoes',
        empresaId: empresaId,
        localId: localId,
      );

      // Append-only: uma movimentação já mapeada nunca é alterada na nuvem.
      if (mapa != null) continue;

      await _publicarMovimentacao(
        empresaId: empresaId,
        localId: localId,
        local: local,
        hash: _hashMovimentacao(local),
      );
    }
  }

  Future<void> _publicarMovimentacao({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final itemLocalId = _int(local['item_estoque_id']);
    final itemRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      localId: itemLocalId,
    );

    if (itemRemotoId == null) {
      throw StateError(
        'Item da movimentação de estoque #$localId ainda não foi sincronizado.',
      );
    }

    String? loteRemotoId;
    final loteLocalId = _int(local['lote_id']);
    if (loteLocalId > 0) {
      loteRemotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_estoque_lotes',
        empresaId: empresaId,
        localId: loteLocalId,
      );

      if (loteRemotoId == null) {
        throw StateError(
          'Lote da movimentação de estoque #$localId ainda não foi sincronizado.',
        );
      }
    }

    String? ordemRemotaId;
    final ordemLocalId = _int(local['ordem_servico_id']);
    if (ordemLocalId > 0) {
      ordemRemotaId = await _remotoPorLocal(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: ordemLocalId,
      );

      if (ordemRemotaId == null) {
        throw StateError(
          'OS da movimentação de estoque #$localId ainda não foi sincronizada.',
        );
      }
    }

    final dispositivoId = await _dispositivoId();

    // Recupera idempotentemente uma inserção que tenha chegado ao servidor
    // caso o app tenha fechado antes de salvar o mapa local.
    final existente = await client
        .from('imperium_estoque_movimentacoes')
        .select('id,criado_em')
        .eq('empresa_id', empresaId)
        .eq('origem_dispositivo', dispositivoId)
        .eq('origem_local_id', localId)
        .maybeSingle();

    if (existente != null) {
      await _salvarMapa(
        tabela: 'imperium_sync_estoque_movimentacoes',
        empresaId: empresaId,
        localId: localId,
        remotoId: existente['id'].toString(),
        localHash: hash,
        remotoAtualizadoEm: existente['criado_em']?.toString(),
      );
      return;
    }

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'item_estoque_id': itemRemotoId,
      'lote_id': loteRemotoId,
      'ordem_servico_id': ordemRemotaId,
      'origem_dispositivo': dispositivoId,
      'origem_local_id': localId,
      'tipo': (local['tipo'] ?? '').toString(),
      'quantidade': _double(local['quantidade']),
      'quantidade_anterior': _double(local['quantidade_anterior']),
      'quantidade_posterior': _double(local['quantidade_posterior']),
      'custo_unitario': _double(local['custo_unitario']),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'motivo': (local['motivo'] ?? '').toString(),
      'origem': (local['origem'] ?? 'Manual').toString(),
      'origem_ordem_servico_local_id': ordemLocalId > 0 ? ordemLocalId : null,
      'origem_nota_fiscal_local_id': _int(local['nota_fiscal_id']) > 0
          ? _int(local['nota_fiscal_id'])
          : null,
      'origem_nota_fiscal_item_local_id': _int(local['nota_fiscal_item_id']) > 0
          ? _int(local['nota_fiscal_item_id'])
          : null,
      'data': (local['data'] ?? '').toString(),
    };

    Map<String, dynamic> remoto;

    try {
      final resposta = await client
          .from('imperium_estoque_movimentacoes')
          .insert(payload)
          .select('id,criado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;

      final recuperado = await client
          .from('imperium_estoque_movimentacoes')
          .select('id,criado_em')
          .eq('empresa_id', empresaId)
          .eq('origem_dispositivo', dispositivoId)
          .eq('origem_local_id', localId)
          .single();

      remoto = Map<String, dynamic>.from(recuperado);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_estoque_movimentacoes',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['criado_em']?.toString(),
    );
  }

  Future<void> _marcarAusentesComoExcluidos({
    required String empresaId,
    required String tabelaLocal,
    required String tabelaMapa,
    required String tabelaRemota,
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
      if ((mapa['local_hash'] ?? '').toString() == '__excluido__') continue;

      final localId = _int(mapa['local_id']);
      final remotoId = (mapa['remoto_id'] ?? '').toString().trim();
      if (localId <= 0 || remotoId.isEmpty) continue;

      final local = await database.query(
        tabelaLocal,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (local.isNotEmpty) continue;

      await client
          .from(tabelaRemota)
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId);

      await database.update(
        tabelaMapa,
        {'local_hash': '__excluido__'},
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
    }
  }

  Future<Map<String, Object?>?> _mapaLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabela,
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    return resultado.isEmpty ? null : resultado.first;
  }

  Future<String?> _remotoPorLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;

    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabela,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;

    final id = (resultado.first['remoto_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<void> _salvarMapa({
    required String tabela,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(tabela, {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final config = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    final id = config.isEmpty
        ? ''
        : (config.first['dispositivo_id'] ?? '').toString().trim();

    if (id.isEmpty) {
      throw StateError(
        'Dispositivo de sincronização ainda não foi inicializado.',
      );
    }

    return id;
  }

  bool _semPermissaoEstoque(PostgrestException error) {
    return error.code == '42501';
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

  String _hashMovimentacao(Map<String, Object?> local) {
    return _hash(<Object?>[
      _int(local['item_estoque_id']),
      local['tipo'],
      _double(local['quantidade']),
      _double(local['quantidade_anterior']),
      _double(local['quantidade_posterior']),
      _double(local['custo_unitario']),
      local['observacoes'],
      local['motivo'],
      local['origem'],
      _int(local['ordem_servico_id']),
      _int(local['lote_id']),
      _int(local['nota_fiscal_id']),
      _int(local['nota_fiscal_item_id']),
      local['data'],
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

  static String? _nuloTexto(Object? value) {
    final texto = (value ?? '').toString().trim();
    return texto.isEmpty ? null : texto;
  }
}
