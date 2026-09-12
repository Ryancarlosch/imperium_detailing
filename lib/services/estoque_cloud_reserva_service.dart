import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'estoque_cloud_conflito_service.dart';
import 'supabase_bootstrap.dart';

class EstoqueCloudReservaService {
  EstoqueCloudReservaService._();

  static final EstoqueCloudReservaService instance =
      EstoqueCloudReservaService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // estoque-cloud-reserva-v3
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_estoque_reservas_os (
        empresa_id TEXT NOT NULL,
        ordem_servico_local_id INTEGER NOT NULL,
        ordem_servico_remoto_id TEXT NOT NULL,
        fingerprint TEXT,
        status TEXT NOT NULL,
        mensagem TEXT,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (empresa_id, ordem_servico_local_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_estoque_alertas (
        empresa_id TEXT NOT NULL,
        remoto_id TEXT NOT NULL,
        item_remoto_id TEXT NOT NULL,
        item_local_id INTEGER,
        tipo TEXT NOT NULL,
        status TEXT NOT NULL,
        mensagem TEXT NOT NULL,
        saldo_atual REAL NOT NULL DEFAULT 0,
        limite REAL NOT NULL DEFAULT 0,
        atualizado_em TEXT,
        PRIMARY KEY (empresa_id, remoto_id)
      )
    ''');

    await EstoqueCloudConflitoService.instance.garantirEstruturaLocal();
  }

  Future<void> sincronizarReservas(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    await garantirEstruturaLocal();

    final database = await _appDatabase.database;
    final ordens = await database.rawQuery(
      '''
      SELECT
        os.id AS local_id,
        os.numero,
        os.status,
        mapa.remoto_id
      FROM ordens_servico os
      INNER JOIN imperium_sync_ordens_servico mapa
        ON mapa.local_id = os.id
       AND mapa.empresa_id = ?
      ORDER BY os.id ASC
      ''',
      [empresaId],
    );

    for (final ordem in ordens) {
      try {
        await _sincronizarOrdem(
          empresaId: empresaId,
          ordem: Map<String, Object?>.from(ordem),
        );
      } on PostgrestException catch (error) {
        if (error.code == '42501') return;

        final localId = _int(ordem['local_id']);
        final remotoId = (ordem['remoto_id'] ?? '').toString();

        await _salvarEstado(
          empresaId: empresaId,
          ordemLocalId: localId,
          ordemRemotaId: remotoId,
          status: 'Erro',
          mensagem: error.message,
        );

        if (error.code == 'P0001') {
          final produtos = await _reservasDaOrdem(
            empresaId: empresaId,
            ordemLocalId: localId,
            incluirBaixados: true,
          );
          await _registrarConflitosReserva(
            empresaId: empresaId,
            produtos: produtos,
            mensagem: error.message,
          );
          continue;
        }

        rethrow;
      } catch (error) {
        final localId = _int(ordem['local_id']);
        final remotoId = (ordem['remoto_id'] ?? '').toString();

        await _salvarEstado(
          empresaId: empresaId,
          ordemLocalId: localId,
          ordemRemotaId: remotoId,
          status: 'Erro',
          mensagem: error.toString(),
        );
      }
    }
  }

  Future<void> sincronizarAlertas(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      final remotos = await client
          .from('imperium_estoque_alertas')
          .select()
          .eq('empresa_id', empresaId)
          .order('atualizado_em', ascending: false);

      final database = await _appDatabase.database;

      for (final remotoRaw in remotos) {
        final remoto = Map<String, dynamic>.from(remotoRaw);
        final remotoId = (remoto['id'] ?? '').toString().trim();
        final itemRemotoId = (remoto['item_estoque_id'] ?? '')
            .toString()
            .trim();

        if (remotoId.isEmpty || itemRemotoId.isEmpty) continue;

        final itemLocalId = await _localPorRemoto(
          empresaId: empresaId,
          itemRemotoId: itemRemotoId,
        );

        await database.insert(
          'imperium_sync_estoque_alertas',
          {
            'empresa_id': empresaId,
            'remoto_id': remotoId,
            'item_remoto_id': itemRemotoId,
            'item_local_id': itemLocalId,
            'tipo': (remoto['tipo'] ?? 'Estoque baixo').toString(),
            'status': (remoto['status'] ?? 'Ativo').toString(),
            'mensagem': (remoto['mensagem'] ?? '').toString(),
            'saldo_atual': _double(remoto['saldo_atual']),
            'limite': _double(remoto['limite']),
            'atualizado_em': remoto['atualizado_em']?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> listarAlertasAtivos({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_estoque_alertas',
      where: empresaId == null
          ? "status = 'Ativo'"
          : "empresa_id = ? AND status = 'Ativo'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'saldo_atual ASC, atualizado_em DESC',
    );
  }

  Future<void> _sincronizarOrdem({
    required String empresaId,
    required Map<String, Object?> ordem,
  }) async {
    final client = _client;
    if (client == null) return;

    final ordemLocalId = _int(ordem['local_id']);
    final ordemRemotaId = (ordem['remoto_id'] ?? '').toString().trim();
    final status = (ordem['status'] ?? '').toString().trim();

    if (ordemLocalId <= 0 || ordemRemotaId.isEmpty) return;

    final estado = await _estadoDaOrdem(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
    );

    if (status == 'Cancelada') {
      await client.rpc(
        'imperium_estoque_liberar_reserva_os',
        params: {
          'p_empresa_id': empresaId,
          'p_ordem_servico_id': ordemRemotaId,
        },
      );

      await _salvarEstado(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotaId: ordemRemotaId,
        status: 'Liberada',
      );
      return;
    }

    if (status != 'Aberta' &&
        status != 'Em andamento' &&
        status != 'Finalizada') {
      return;
    }

    if (status == 'Finalizada' &&
        (estado?['status'] ?? '').toString() == 'Consumida') {
      return;
    }

    final produtos = await _reservasDaOrdem(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
      incluirBaixados: status == 'Finalizada',
    );

    if (produtos.isEmpty) {
      await client.rpc(
        'imperium_estoque_liberar_reserva_os',
        params: {
          'p_empresa_id': empresaId,
          'p_ordem_servico_id': ordemRemotaId,
        },
      );

      await _salvarEstado(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotaId: ordemRemotaId,
        status: 'SemProdutos',
      );
      return;
    }

    final fingerprint = _fingerprint(produtos);

    if (status != 'Finalizada' &&
        (estado?['status'] ?? '').toString() == 'Ativa' &&
        (estado?['fingerprint'] ?? '').toString() == fingerprint) {
      return;
    }

    final dispositivoId = await _dispositivoId();

    final reservaRaw = await client.rpc(
      'imperium_estoque_reservar_os',
      params: {
        'p_empresa_id': empresaId,
        'p_ordem_servico_id': ordemRemotaId,
        'p_reservas': produtos
            .map(
              (item) => {
                'item_estoque_id': item['item_remoto_id'],
                'quantidade': item['quantidade'],
              },
            )
            .toList(),
        'p_origem_dispositivo': dispositivoId,
        'p_origem_os_local_id': ordemLocalId,
      },
    );

    final reserva = _mapResposta(reservaRaw);
    final statusReserva = (reserva['status'] ?? '').toString();

    if (statusReserva == 'ja_consumida') {
      await _salvarEstado(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotaId: ordemRemotaId,
        status: 'Consumida',
        fingerprint: fingerprint,
      );
      await _resolverConflitosReserva(empresaId: empresaId, produtos: produtos);
      return;
    }

    if (status != 'Finalizada') {
      await _salvarEstado(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotaId: ordemRemotaId,
        status: 'Ativa',
        fingerprint: fingerprint,
      );
      await _resolverConflitosReserva(empresaId: empresaId, produtos: produtos);
      return;
    }

    final consumoRaw = await client.rpc(
      'imperium_estoque_consumir_reserva_os',
      params: {'p_empresa_id': empresaId, 'p_ordem_servico_id': ordemRemotaId},
    );

    final consumo = _mapResposta(consumoRaw);
    final statusConsumo = (consumo['status'] ?? '').toString();

    if (statusConsumo == 'consumida') {
      await _atualizarBaselinesAposConsumo(
        empresaId: empresaId,
        itens: _listaMapas(consumo['itens']),
      );
    } else if (statusConsumo != 'ja_consumida') {
      throw StateError(
        'A reserva da OS nao foi consumida. Status remoto: $statusConsumo',
      );
    }

    await _salvarEstado(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
      ordemRemotaId: ordemRemotaId,
      status: 'Consumida',
      fingerprint: fingerprint,
    );

    await _resolverConflitosReserva(empresaId: empresaId, produtos: produtos);
  }

  Future<List<Map<String, Object?>>> _reservasDaOrdem({
    required String empresaId,
    required int ordemLocalId,
    required bool incluirBaixados,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'ordem_servico_produtos',
      columns: ['produto_id', 'quantidade', 'baixado_estoque'],
      where: incluirBaixados
          ? 'ordem_servico_id = ?'
          : 'ordem_servico_id = ? AND baixado_estoque = 0',
      whereArgs: [ordemLocalId],
    );

    final agregadas = <int, double>{};

    for (final row in rows) {
      final produtoId = _int(row['produto_id']);
      final quantidade = _double(row['quantidade']);

      if (produtoId <= 0 || quantidade <= 0) continue;
      agregadas[produtoId] = (agregadas[produtoId] ?? 0) + quantidade;
    }

    final resultado = <Map<String, Object?>>[];

    final ids = agregadas.keys.toList()..sort();

    for (final produtoId in ids) {
      final mapa = await database.query(
        'imperium_sync_estoque_itens',
        columns: ['remoto_id'],
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, produtoId],
        limit: 1,
      );

      if (mapa.isEmpty) {
        throw StateError(
          'Produto local #$produtoId ainda nao possui mapa remoto de estoque.',
        );
      }

      final remotoId = (mapa.first['remoto_id'] ?? '').toString().trim();

      if (remotoId.isEmpty) {
        throw StateError(
          'Produto local #$produtoId possui mapa remoto invalido.',
        );
      }

      resultado.add({
        'item_local_id': produtoId,
        'item_remoto_id': remotoId,
        'quantidade': agregadas[produtoId]!,
      });
    }

    return resultado;
  }

  Future<void> _atualizarBaselinesAposConsumo({
    required String empresaId,
    required List<Map<String, dynamic>> itens,
  }) async {
    final database = await _appDatabase.database;

    for (final item in itens) {
      final remotoId = (item['item_estoque_id'] ?? '').toString().trim();
      final atualizadoEm = (item['atualizado_em'] ?? '').toString().trim();

      if (remotoId.isEmpty || atualizadoEm.isEmpty) continue;

      await database.update(
        'imperium_sync_estoque_itens',
        {'remoto_atualizado_em': atualizadoEm},
        where: 'empresa_id = ? AND remoto_id = ?',
        whereArgs: [empresaId, remotoId],
      );
    }
  }

  Future<void> _registrarConflitosReserva({
    required String empresaId,
    required List<Map<String, Object?>> produtos,
    required String mensagem,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    for (final produto in produtos) {
      final localId = _int(produto['item_local_id']);
      final remotoId = (produto['item_remoto_id'] ?? '').toString().trim();

      if (localId <= 0 || remotoId.isEmpty) continue;

      final existente = await database.query(
        'imperium_sync_estoque_conflitos',
        columns: ['id'],
        where:
            "empresa_id = ? AND entidade = 'item' AND local_id = ? "
            "AND remoto_id = ? AND status = 'Pendente'",
        whereArgs: [empresaId, localId, remotoId],
        limit: 1,
      );

      if (existente.isNotEmpty) continue;

      final mapa = await database.query(
        'imperium_sync_estoque_itens',
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
        limit: 1,
      );

      final local = await database.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      await database.insert(
        'imperium_sync_estoque_conflitos',
        {
          'empresa_id': empresaId,
          'entidade': 'item',
          'local_id': localId,
          'remoto_id': remotoId,
          'motivo': 'reserva_remota_insuficiente',
          'local_hash_base': mapa.isEmpty
              ? null
              : mapa.first['local_hash']?.toString(),
          'local_hash_atual': null,
          'remoto_atualizado_base': mapa.isEmpty
              ? null
              : mapa.first['remoto_atualizado_em']?.toString(),
          'remoto_atualizado_atual': null,
          'local_json': local.isEmpty ? '' : jsonEncode(local.first),
          'remoto_json': jsonEncode({'erro_reserva': mensagem}),
          'status': 'Pendente',
          'detectado_em': agora,
          'resolvido_em': null,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<void> _resolverConflitosReserva({
    required String empresaId,
    required List<Map<String, Object?>> produtos,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    for (final produto in produtos) {
      final localId = _int(produto['item_local_id']);
      if (localId <= 0) continue;

      await database.update(
        'imperium_sync_estoque_conflitos',
        {'status': 'Resolvido', 'resolvido_em': agora},
        where:
            "empresa_id = ? AND entidade = 'item' AND local_id = ? "
            "AND motivo = 'reserva_remota_insuficiente' "
            "AND status = 'Pendente'",
        whereArgs: [empresaId, localId],
      );
    }
  }

  Future<Map<String, Object?>?> _estadoDaOrdem({
    required String empresaId,
    required int ordemLocalId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_estoque_reservas_os',
      where: 'empresa_id = ? AND ordem_servico_local_id = ?',
      whereArgs: [empresaId, ordemLocalId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _salvarEstado({
    required String empresaId,
    required int ordemLocalId,
    required String ordemRemotaId,
    required String status,
    String? fingerprint,
    String? mensagem,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_sync_estoque_reservas_os',
      {
        'empresa_id': empresaId,
        'ordem_servico_local_id': ordemLocalId,
        'ordem_servico_remoto_id': ordemRemotaId,
        'fingerprint': fingerprint,
        'status': status,
        'mensagem': mensagem,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> _localPorRemoto({
    required String empresaId,
    required String itemRemotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_estoque_itens',
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, itemRemotoId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<String?> _dispositivoId() async {
    final database = await _appDatabase.database;

    final existe = await database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'imperium_sync_config' LIMIT 1",
    );
    if (existe.isEmpty) return null;

    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final id = (rows.first['dispositivo_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  String _fingerprint(List<Map<String, Object?>> produtos) {
    final dados =
        produtos
            .map(
              (item) => <String, Object?>{
                'item_remoto_id': item['item_remoto_id'],
                'quantidade': _double(item['quantidade']),
              },
            )
            .toList()
          ..sort(
            (a, b) => a['item_remoto_id'].toString().compareTo(
              b['item_remoto_id'].toString(),
            ),
          );

    return sha256.convert(utf8.encode(jsonEncode(dados))).toString();
  }

  Map<String, dynamic> _mapResposta(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _listaMapas(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];

    return value
        .whereType<Map>()
        .map((item) => item.map((key, data) => MapEntry(key.toString(), data)))
        .toList();
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
}
