import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'estoque_cloud_upload_service.dart';
import 'supabase_bootstrap.dart';

/// Etapa 5 - Estoque Cloud V2.
///
/// Download controlado:
/// - baixa somente registros remotos ainda sem mapa local;
/// - reconstrói mapas após interrupção quando a origem é o próprio aparelho;
/// - itens chegam com o snapshot atual do saldo remoto;
/// - lotes chegam com o snapshot atual de disponibilidade;
/// - movimentações são importadas diretamente como histórico e NÃO recalculam
///   novamente o saldo do item;
/// - registros já mapeados não são sobrescritos nesta versão.
/// Isso evita last-write-wins silencioso até existir resolução de conflitos V2.1.
class EstoqueCloudDownloadService {
  EstoqueCloudDownloadService._();

  static final EstoqueCloudDownloadService instance =
      EstoqueCloudDownloadService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // estoque-cloud-download-v2
  Future<void> sincronizarDownloadNovos(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await EstoqueCloudUploadService.instance.garantirEstruturaLocal();
      await _baixarItensNovos(empresaId);
      await _baixarLotesNovos(empresaId);
      await _baixarMovimentacoesNovas(empresaId);
    } on PostgrestException catch (error) {
      // Usuário sem permissão de Estoque não deve impedir os outros módulos.
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> _baixarItensNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_estoque_itens')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    for (final remotoRaw in remotos) {
      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoId = (remoto['id'] ?? '').toString().trim();
      if (remotoId.isEmpty) continue;

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_estoque_itens',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      final reconstruido = await _tentarReconstruirMapaDaOrigem(
        empresaId: empresaId,
        remoto: remoto,
        tabelaLocal: 'itens_estoque',
        tabelaMapa: 'imperium_sync_estoque_itens',
        hashLocal: _hashItem,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );

      if (reconstruido) continue;

      final database = await _appDatabase.database;
      final criadoEm = _textoPreferido(
        remoto['origem_criado_em'],
        remoto['criado_em'],
        DateTime.now().toIso8601String(),
      );
      final atualizadoEm = _textoPreferido(
        remoto['origem_atualizado_em'],
        remoto['atualizado_em'],
        criadoEm,
      );

      final localId = await database.insert('itens_estoque', {
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
        'ativo': remoto['ativo'] == true ? 1 : 0,
        'criado_em': criadoEm,
        'atualizado_em': atualizadoEm,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final inserido = await _localPorId(
        tabela: 'itens_estoque',
        localId: localId,
      );

      await _salvarMapa(
        tabela: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashItem(inserido),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarLotesNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_estoque_lotes')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    for (final remotoRaw in remotos) {
      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoId = (remoto['id'] ?? '').toString().trim();
      if (remotoId.isEmpty) continue;

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_estoque_lotes',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      final reconstruido = await _tentarReconstruirMapaDaOrigem(
        empresaId: empresaId,
        remoto: remoto,
        tabelaLocal: 'estoque_lotes',
        tabelaMapa: 'imperium_sync_estoque_lotes',
        hashLocal: _hashLote,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );

      if (reconstruido) continue;

      final itemRemotoId = (remoto['item_estoque_id'] ?? '').toString().trim();
      final itemLocalId = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        remotoId: itemRemotoId,
      );

      if (itemLocalId == null) {
        // Dependência ainda não disponível: tenta novamente no próximo sync.
        continue;
      }

      final database = await _appDatabase.database;
      final criadoEm = _textoPreferido(
        remoto['origem_criado_em'],
        remoto['criado_em'],
        DateTime.now().toIso8601String(),
      );

      final localId = await database.insert('estoque_lotes', {
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
        'ativo': remoto['ativo'] == true ? 1 : 0,
        'criado_em': criadoEm,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final inserido = await _localPorId(
        tabela: 'estoque_lotes',
        localId: localId,
      );

      await _salvarMapa(
        tabela: 'imperium_sync_estoque_lotes',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashLote(inserido),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarMovimentacoesNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_estoque_movimentacoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final remotoRaw in remotos) {
      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoId = (remoto['id'] ?? '').toString().trim();
      if (remotoId.isEmpty) continue;

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_estoque_movimentacoes',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      final reconstruido = await _tentarReconstruirMapaDaOrigem(
        empresaId: empresaId,
        remoto: remoto,
        tabelaLocal: 'movimentacoes_estoque',
        tabelaMapa: 'imperium_sync_estoque_movimentacoes',
        hashLocal: _hashMovimentacao,
        remotoAtualizadoEm: remoto['criado_em']?.toString(),
      );

      if (reconstruido) continue;

      final itemRemotoId = (remoto['item_estoque_id'] ?? '').toString().trim();
      final itemLocalId = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        remotoId: itemRemotoId,
      );

      if (itemLocalId == null) continue;

      int? loteLocalId;
      final loteRemotoId = (remoto['lote_id'] ?? '').toString().trim();
      if (loteRemotoId.isNotEmpty) {
        loteLocalId = await _localPorRemoto(
          tabelaMapa: 'imperium_sync_estoque_lotes',
          empresaId: empresaId,
          remotoId: loteRemotoId,
        );

        if (loteLocalId == null) continue;
      }

      int? ordemLocalId;
      final ordemRemotoId = (remoto['ordem_servico_id'] ?? '')
          .toString()
          .trim();
      if (ordemRemotoId.isNotEmpty) {
        ordemLocalId = await _localPorRemoto(
          tabelaMapa: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          remotoId: ordemRemotoId,
        );
        // OS é metadado opcional para histórico de estoque.
        // Se ainda não existir localmente, a movimentação continua importável.
      }

      final database = await _appDatabase.database;

      // IMPORTANTE: inserção direta do histórico.
      // Não usa EstoqueRepository.registrarMovimentacao e portanto não altera
      // novamente itens_estoque.quantidade.
      final localId = await database.insert('movimentacoes_estoque', {
        'item_estoque_id': itemLocalId,
        'tipo': (remoto['tipo'] ?? '').toString(),
        'quantidade': _double(remoto['quantidade']),
        'quantidade_anterior': _double(remoto['quantidade_anterior']),
        'quantidade_posterior': _double(remoto['quantidade_posterior']),
        'custo_unitario': _double(remoto['custo_unitario']),
        'observacoes': (remoto['observacoes'] ?? '').toString(),
        'motivo': (remoto['motivo'] ?? '').toString(),
        'origem': (remoto['origem'] ?? 'Cloud').toString(),
        'ordem_servico_id': ordemLocalId,
        'lote_id': loteLocalId,
        'nota_fiscal_id': null,
        'nota_fiscal_item_id': null,
        'data': (remoto['data'] ?? '').toString(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final inserido = await _localPorId(
        tabela: 'movimentacoes_estoque',
        localId: localId,
      );

      await _salvarMapa(
        tabela: 'imperium_sync_estoque_movimentacoes',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashMovimentacao(inserido),
        remotoAtualizadoEm: remoto['criado_em']?.toString(),
      );
    }
  }

  Future<bool> _tentarReconstruirMapaDaOrigem({
    required String empresaId,
    required Map<String, dynamic> remoto,
    required String tabelaLocal,
    required String tabelaMapa,
    required String Function(Map<String, Object?>) hashLocal,
    required String? remotoAtualizadoEm,
  }) async {
    final dispositivoId = await _dispositivoId();
    final origemDispositivo = (remoto['origem_dispositivo'] ?? '')
        .toString()
        .trim();
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo != dispositivoId || origemLocalId <= 0) {
      return false;
    }

    final database = await _appDatabase.database;
    final local = await database.query(
      tabelaLocal,
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    if (local.isEmpty) return false;

    await _salvarMapa(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: origemLocalId,
      remotoId: remoto['id'].toString(),
      localHash: hashLocal(local.first),
      remotoAtualizadoEm: remotoAtualizadoEm,
    );

    return true;
  }

  Future<Map<String, Object?>?> _mapaPorRemoto({
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      tabela,
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );

    return resultado.isEmpty ? null : resultado.first;
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
      throw StateError('Registro local recém-criado não foi encontrado.');
    }

    return resultado.first;
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
      throw StateError('Dispositivo de sincronização não inicializado.');
    }

    return id;
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
