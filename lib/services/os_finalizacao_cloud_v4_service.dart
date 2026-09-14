import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// OS Cloud V4.
///
/// Sincroniza o contrato de produtos usado para finalizar a OS, os snapshots
/// FIFO, a mao de obra automatica e os ajustes financeiros gerados por taxa.
///
/// As tabelas auxiliares locais sao dinamicas para preservar schema v33.
class OsFinalizacaoCloudV4Service {
  OsFinalizacaoCloudV4Service._();

  static final OsFinalizacaoCloudV4Service instance =
      OsFinalizacaoCloudV4Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_produtos_estado (
        empresa_id TEXT NOT NULL,
        ordem_local_id INTEGER NOT NULL,
        ordem_remoto_id TEXT NOT NULL,
        local_hash TEXT NOT NULL DEFAULT '',
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, ordem_local_id),
        UNIQUE (empresa_id, ordem_remoto_id)
      )
    ''');

    for (final tabela in <String>[
      'imperium_sync_os_produtos',
      'imperium_sync_os_produto_lotes',
      'imperium_sync_os_mao_obra',
      'imperium_sync_os_ajustes_financeiros',
    ]) {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS $tabela (
          empresa_id TEXT NOT NULL,
          local_id INTEGER NOT NULL,
          remoto_id TEXT NOT NULL,
          remoto_atualizado_em TEXT,
          PRIMARY KEY (empresa_id, local_id),
          UNIQUE (empresa_id, remoto_id)
        )
      ''');
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_produtos_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        ordem_local_id INTEGER NOT NULL,
        ordem_remoto_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_atualizado_base TEXT,
        remoto_atualizado_atual TEXT,
        status TEXT NOT NULL DEFAULT 'Pendente',
        resolucao TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_os_prod_conflito_pendente
      ON imperium_sync_os_produtos_conflitos (
        empresa_id,
        ordem_local_id
      )
      WHERE status = 'Pendente'
    ''');
  }

  /// Retorna false quando existe conflito de contrato de produtos.
  Future<bool> sincronizarProdutos(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return true;

    try {
      await garantirEstruturaLocal();

      if (await possuiConflitosProdutosPendentes(empresaId)) {
        return false;
      }

      final database = await _appDatabase.database;
      final ordens = await database.rawQuery(
        '''
        SELECT
          mapa.local_id AS ordem_local_id,
          mapa.remoto_id AS ordem_remoto_id,
          os.status
        FROM imperium_sync_ordens_servico mapa
        INNER JOIN ordens_servico os ON os.id = mapa.local_id
        WHERE mapa.empresa_id = ?
          AND os.status != 'Cancelada'
        ORDER BY mapa.local_id ASC
        ''',
        [empresaId],
      );

      for (final raw in ordens) {
        final ordem = Map<String, Object?>.from(raw);
        final ordemLocalId = _int(ordem['ordem_local_id']);
        final ordemRemotoId = _texto(ordem['ordem_remoto_id']);

        if (ordemLocalId <= 0 || ordemRemotoId.isEmpty) continue;

        final ok = await _sincronizarProdutosDaOrdem(
          empresaId: empresaId,
          ordemLocalId: ordemLocalId,
          ordemRemotoId: ordemRemotoId,
        );

        if (!ok) return false;
      }

      return !await possuiConflitosProdutosPendentes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return true;
      rethrow;
    }
  }

  Future<void> sincronizarPosFinanceiro(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      await _publicarMaoObra(empresaId);
      await _baixarMaoObra(empresaId);
      await _publicarAjustes(empresaId);
      await _baixarAjustes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitosProdutosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_os_produtos_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listarConflitosProdutosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_os_produtos_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    Future<int> contar(
      String tabela, {
      String? where,
      List<Object?>? whereArgs,
    }) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela'
        '${where == null ? '' : ' WHERE $where'}',
        whereArgs,
      );
      return _int(rows.first['total']);
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'contratos_produtos': await contar(
        'imperium_sync_os_produtos_estado',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'produtos_mapeados': await contar(
        'imperium_sync_os_produtos',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'mao_obra_mapeada': await contar(
        'imperium_sync_os_mao_obra',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'ajustes_mapeados': await contar(
        'imperium_sync_os_ajustes_financeiros',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'conflitos_produtos': await contar(
        'imperium_sync_os_produtos_conflitos',
        where: "empresa_id = ? AND status = 'Pendente'",
        whereArgs: [empresaId],
      ),
    };
  }

  Future<void> resolverProdutosUsandoLocal(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final ordemLocalId = _int(conflito['ordem_local_id']);
    final ordemRemotoId = _texto(conflito['ordem_remoto_id']);

    final estado = await _estadoRemoto(
      empresaId: empresaId,
      ordemRemotoId: ordemRemotoId,
    );

    if (estado == null) {
      throw StateError('O contrato remoto de produtos não existe mais.');
    }

    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_os_produtos_estado',
      {'remoto_atualizado_em': estado['atualizado_em']?.toString()},
      where: 'empresa_id = ? AND ordem_local_id = ?',
      whereArgs: [empresaId, ordemLocalId],
    );

    await _resolverConflito(conflitoId, 'local');
  }

  Future<void> resolverProdutosUsandoNuvem(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final ordemLocalId = _int(conflito['ordem_local_id']);
    final ordemRemotoId = _texto(conflito['ordem_remoto_id']);

    final estado = await _estadoRemoto(
      empresaId: empresaId,
      ordemRemotoId: ordemRemotoId,
    );

    if (estado == null || estado['pronto'] != true) {
      throw StateError('O contrato remoto de produtos não está pronto.');
    }

    await _aplicarProdutosRemotos(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
      ordemRemotoId: ordemRemotoId,
      estado: estado,
    );

    await _resolverConflito(conflitoId, 'nuvem');
  }

  Future<bool> _sincronizarProdutosDaOrdem({
    required String empresaId,
    required int ordemLocalId,
    required String ordemRemotoId,
  }) async {
    final database = await _appDatabase.database;
    final local = await _contratoLocal(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
    );

    final estado = await _estadoRemoto(
      empresaId: empresaId,
      ordemRemotoId: ordemRemotoId,
    );

    final mapaRows = await database.query(
      'imperium_sync_os_produtos_estado',
      where: 'empresa_id = ? AND ordem_local_id = ?',
      whereArgs: [empresaId, ordemLocalId],
      limit: 1,
    );

    final mapa = mapaRows.isEmpty
        ? null
        : Map<String, Object?>.from(mapaRows.first);

    if (estado == null) {
      if (mapa != null) {
        await _registrarConflito(
          empresaId: empresaId,
          ordemLocalId: ordemLocalId,
          ordemRemotoId: ordemRemotoId,
          motivo: 'contrato_remoto_ausente',
          localHashBase: _texto(mapa['local_hash']),
          localHashAtual: local.hash,
          remotoBase: _textoNulo(mapa['remoto_atualizado_em']),
          remotoAtual: null,
        );
        return false;
      }

      await _publicarContrato(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotoId: ordemRemotoId,
        estadoAtualizadoEm: null,
        local: local,
      );
      return true;
    }

    if (estado['pronto'] != true) return true;

    if (mapa == null) {
      await _aplicarProdutosRemotos(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotoId: ordemRemotoId,
        estado: estado,
      );
      return true;
    }

    final localMudou = local.hash != _texto(mapa['local_hash']);
    final remotoBase = _textoNulo(mapa['remoto_atualizado_em']);
    final remotoAtual = _textoNulo(estado['atualizado_em']);
    final remotoMudou = !_mesmoTimestamp(remotoBase, remotoAtual);

    if (localMudou && remotoMudou) {
      await _registrarConflito(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotoId: ordemRemotoId,
        motivo: 'alteracao_concorrente',
        localHashBase: _texto(mapa['local_hash']),
        localHashAtual: local.hash,
        remotoBase: remotoBase,
        remotoAtual: remotoAtual,
      );
      return false;
    }

    if (localMudou) {
      await _publicarContrato(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotoId: ordemRemotoId,
        estadoAtualizadoEm: remotoAtual,
        local: local,
      );
      return true;
    }

    if (remotoMudou) {
      await _aplicarProdutosRemotos(
        empresaId: empresaId,
        ordemLocalId: ordemLocalId,
        ordemRemotoId: ordemRemotoId,
        estado: estado,
      );
    }

    return true;
  }

  Future<_ContratoLocal> _contratoLocal({
    required String empresaId,
    required int ordemLocalId,
  }) async {
    final database = await _appDatabase.database;
    final dispositivoId = await _dispositivoId();

    final produtos = await database.query(
      'ordem_servico_produtos',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemLocalId],
      orderBy: 'id ASC',
    );

    final payload = <Map<String, Object?>>[];
    final lotesPayload = <Map<String, Object?>>[];
    final canonicos = <String>[];

    for (final produto in produtos) {
      final localId = _int(produto['id']);
      final itemLocalId = _int(produto['produto_id']);

      String? itemRemotoId;
      if (itemLocalId > 0) {
        itemRemotoId = await _remotoPorLocal(
          tabela: 'imperium_sync_estoque_itens',
          empresaId: empresaId,
          localId: itemLocalId,
        );
        if (itemRemotoId == null) {
          throw StateError(
            'Produto local #$itemLocalId ainda não possui mapa remoto.',
          );
        }
      }

      final mapaProduto = await _mapaLocal(
        tabela: 'imperium_sync_os_produtos',
        empresaId: empresaId,
        localId: localId,
      );

      final remotoId = _textoNulo(mapaProduto?['remoto_id']);
      final composicoes = <Map<String, Object?>>[];
      final lotes = await database.query(
        'ordem_servico_produto_lotes',
        where: 'ordem_servico_produto_id = ?',
        whereArgs: [localId],
        orderBy: 'id ASC',
      );

      for (final lote in lotes) {
        final loteLocalId = _int(lote['lote_id']);
        final loteRemotoId = await _remotoPorLocal(
          tabela: 'imperium_sync_estoque_lotes',
          empresaId: empresaId,
          localId: loteLocalId,
        );

        if (loteRemotoId == null) {
          throw StateError(
            'Lote local #$loteLocalId ainda não possui mapa remoto.',
          );
        }

        final composicao = <String, Object?>{
          'lote_id': loteRemotoId,
          'quantidade': _double(lote['quantidade']),
          'custo_unitario': _double(lote['custo_unitario']),
          'custo_total': _double(lote['custo_total']),
        };
        composicoes.add(composicao);

        lotesPayload.add(<String, Object?>{
          'produto_id': remotoId,
          'produto_origem_local_id': localId,
          'item_estoque_id': itemRemotoId,
          'lote_id': loteRemotoId,
          'origem_local_id': _int(lote['id']),
          'quantidade': _double(lote['quantidade']),
          'custo_unitario': _double(lote['custo_unitario']),
          'custo_total': _double(lote['custo_total']),
        });
      }

      composicoes.sort(
        (a, b) => _texto(a['lote_id']).compareTo(_texto(b['lote_id'])),
      );

      final item = <String, Object?>{
        'origem_local_id': localId,
        'item_estoque_id': itemRemotoId,
        'produto_nome': _texto(produto['produto_nome']),
        'quantidade': _double(produto['quantidade']),
        'unidade': _texto(produto['unidade']),
        'custo_unitario': _double(produto['custo_unitario']),
        'custo_unitario_no_momento': _double(
          produto['custo_unitario_no_momento'],
        ),
        'custo_total_no_momento': _double(produto['custo_total_no_momento']),
        'composicao_lotes_json': composicoes,
        'baixado_estoque': _int(produto['baixado_estoque']) != 0,
      };
      if (remotoId != null) {
        item['id'] = remotoId;
      }
      payload.add(item);

      canonicos.add(
        jsonEncode(<String, Object?>{
          'item': itemRemotoId,
          'nome': _texto(produto['produto_nome']),
          'quantidade': _double(produto['quantidade']),
          'unidade': _texto(produto['unidade']),
          'custo_unitario': _double(produto['custo_unitario']),
          'custo_unitario_no_momento': _double(
            produto['custo_unitario_no_momento'],
          ),
          'custo_total_no_momento': _double(produto['custo_total_no_momento']),
          'baixado': _int(produto['baixado_estoque']) != 0,
          'lotes': composicoes,
        }),
      );
    }

    canonicos.sort();

    return _ContratoLocal(
      hash: sha256.convert(utf8.encode(jsonEncode(canonicos))).toString(),
      produtos: payload,
      lotes: lotesPayload,
      dispositivoId: dispositivoId,
    );
  }

  Future<void> _publicarContrato({
    required String empresaId,
    required int ordemLocalId,
    required String ordemRemotoId,
    required String? estadoAtualizadoEm,
    required _ContratoLocal local,
  }) async {
    final client = _client;
    if (client == null) return;

    final raw = await client.rpc(
      'imperium_os_produtos_publicar_v4',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_ordem_servico_id': ordemRemotoId,
        'p_estado_atualizado_em': estadoAtualizadoEm,
        'p_contrato_hash': local.hash,
        'p_produtos': local.produtos,
        'p_lotes': local.lotes,
        'p_origem_dispositivo': local.dispositivoId,
        'p_origem_os_local_id': ordemLocalId,
      },
    );

    final resposta = Map<String, dynamic>.from(raw as Map);
    final estado = Map<String, dynamic>.from(resposta['estado'] as Map);
    final produtos = (resposta['produtos'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final database = await _appDatabase.database;

    for (final remoto in produtos) {
      if (_texto(remoto['origem_dispositivo']) != local.dispositivoId) {
        continue;
      }

      final localId = _int(remoto['origem_local_id']);
      if (localId <= 0) continue;

      await _salvarMapa(
        tabela: 'imperium_sync_os_produtos',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        remotoAtualizadoEm: _textoNulo(remoto['atualizado_em']),
      );
    }

    await database.insert(
      'imperium_sync_os_produtos_estado',
      <String, Object?>{
        'empresa_id': empresaId,
        'ordem_local_id': ordemLocalId,
        'ordem_remoto_id': ordemRemotoId,
        'local_hash': local.hash,
        'remoto_atualizado_em': estado['atualizado_em']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _aplicarProdutosRemotos({
    required String empresaId,
    required int ordemLocalId,
    required String ordemRemotoId,
    required Map<String, dynamic> estado,
  }) async {
    final client = _client;
    if (client == null) return;

    final produtosRaw = await client
        .from('imperium_ordem_servico_produtos')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemRemotoId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final lotesRaw = await client
        .from('imperium_ordem_servico_produto_lotes')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemRemotoId)
        .order('criado_em');

    final produtos = (produtosRaw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final lotes = (lotesRaw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final itemLocal = <String, int>{};
    final loteLocal = <String, int>{};

    for (final produto in produtos) {
      final remoto = _textoNulo(produto['item_estoque_id']);
      if (remoto == null) continue;

      final local = await _localPorRemoto(
        tabela: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        remotoId: remoto,
      );
      if (local == null) {
        throw StateError(
          'Item remoto $remoto da OS ainda não possui mapa local.',
        );
      }
      itemLocal[remoto] = local;
    }

    for (final lote in lotes) {
      final remoto = _texto(lote['lote_id']);
      if (remoto.isEmpty || loteLocal.containsKey(remoto)) continue;

      final local = await _localPorRemoto(
        tabela: 'imperium_sync_estoque_lotes',
        empresaId: empresaId,
        remotoId: remoto,
      );
      if (local == null) {
        throw StateError(
          'Lote remoto $remoto da OS ainda não possui mapa local.',
        );
      }
      loteLocal[remoto] = local;
    }

    final database = await _appDatabase.database;

    await database.transaction((tx) async {
      final antigos = await tx.query(
        'ordem_servico_produtos',
        columns: ['id'],
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemLocalId],
      );
      final idsProdutos = antigos
          .map((e) => _int(e['id']))
          .where((e) => e > 0)
          .toList();

      final antigosLotes = <int>[];
      if (idsProdutos.isNotEmpty) {
        final marks = List.filled(idsProdutos.length, '?').join(',');
        final rows = await tx.rawQuery(
          'SELECT id FROM ordem_servico_produto_lotes '
          'WHERE ordem_servico_produto_id IN ($marks)',
          idsProdutos,
        );
        antigosLotes.addAll(rows.map((e) => _int(e['id'])).where((e) => e > 0));
        await tx.rawDelete(
          'DELETE FROM ordem_servico_produto_lotes '
          'WHERE ordem_servico_produto_id IN ($marks)',
          idsProdutos,
        );
      }

      await tx.delete(
        'ordem_servico_produtos',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemLocalId],
      );

      for (final id in idsProdutos) {
        await tx.delete(
          'imperium_sync_os_produtos',
          where: 'empresa_id = ? AND local_id = ?',
          whereArgs: [empresaId, id],
        );
      }
      for (final id in antigosLotes) {
        await tx.delete(
          'imperium_sync_os_produto_lotes',
          where: 'empresa_id = ? AND local_id = ?',
          whereArgs: [empresaId, id],
        );
      }

      final produtoLocalPorRemoto = <String, int>{};

      for (final remoto in produtos) {
        final itemRemoto = _textoNulo(remoto['item_estoque_id']);
        final localId = await tx.insert(
          'ordem_servico_produtos',
          <String, Object?>{
            'ordem_servico_id': ordemLocalId,
            'produto_id': itemRemoto == null ? null : itemLocal[itemRemoto],
            'produto_nome': _texto(remoto['produto_nome']),
            'quantidade': _double(remoto['quantidade']),
            'unidade': _texto(remoto['unidade']),
            'custo_unitario': _double(remoto['custo_unitario']),
            'custo_unitario_no_momento': _double(
              remoto['custo_unitario_no_momento'],
            ),
            'custo_total_no_momento': _double(remoto['custo_total_no_momento']),
            'composicao_lotes_json': '[]',
            'baixado_estoque': remoto['baixado_estoque'] == true ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final remotoId = _texto(remoto['id']);
        produtoLocalPorRemoto[remotoId] = localId;

        await tx.insert(
          'imperium_sync_os_produtos',
          <String, Object?>{
            'empresa_id': empresaId,
            'local_id': localId,
            'remoto_id': remotoId,
            'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final composicoes = <int, List<Map<String, Object?>>>{};

      for (final remoto in lotes) {
        final produtoLocalId =
            produtoLocalPorRemoto[_texto(remoto['ordem_servico_produto_id'])];
        if (produtoLocalId == null) continue;

        final loteRemotoId = _texto(remoto['lote_id']);
        final loteLocalId = loteLocal[loteRemotoId];
        if (loteLocalId == null) continue;

        final localId = await tx.insert(
          'ordem_servico_produto_lotes',
          <String, Object?>{
            'ordem_servico_produto_id': produtoLocalId,
            'lote_id': loteLocalId,
            'quantidade': _double(remoto['quantidade']),
            'custo_unitario': _double(remoto['custo_unitario']),
            'custo_total': _double(remoto['custo_total']),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        await tx.insert(
          'imperium_sync_os_produto_lotes',
          <String, Object?>{
            'empresa_id': empresaId,
            'local_id': localId,
            'remoto_id': _texto(remoto['id']),
            'remoto_atualizado_em': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        (composicoes[produtoLocalId] ??= <Map<String, Object?>>[])
            .add(<String, Object?>{
              'lote_id': loteLocalId,
              'quantidade': _double(remoto['quantidade']),
              'custo_unitario': _double(remoto['custo_unitario']),
              'custo_total': _double(remoto['custo_total']),
            });
      }

      for (final entry in composicoes.entries) {
        await tx.update(
          'ordem_servico_produtos',
          {'composicao_lotes_json': jsonEncode(entry.value)},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });

    final novoLocal = await _contratoLocal(
      empresaId: empresaId,
      ordemLocalId: ordemLocalId,
    );

    await database.insert(
      'imperium_sync_os_produtos_estado',
      <String, Object?>{
        'empresa_id': empresaId,
        'ordem_local_id': ordemLocalId,
        'ordem_remoto_id': ordemRemotoId,
        'local_hash': novoLocal.hash,
        'remoto_atualizado_em': estado['atualizado_em']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> _estadoRemoto({
    required String empresaId,
    required String ordemRemotoId,
  }) async {
    final client = _client;
    if (client == null) return null;

    final raw = await client
        .from('imperium_ordem_servico_produtos_estado')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemRemotoId)
        .maybeSingle();

    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<void> _publicarMaoObra(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final dispositivoId = await _dispositivoId();
    final rows = await database.query(
      'financeiro_os_mao_obra',
      orderBy: 'id ASC',
    );

    for (final local in rows) {
      final localId = _int(local['id']);
      final ordemRemota = await _remotoPorLocal(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: _int(local['ordem_servico_id']),
      );
      if (localId <= 0 || ordemRemota == null) continue;

      String? colaboradorRemoto;
      final colaboradorLocal = _int(local['colaborador_custo_id']);
      if (colaboradorLocal > 0) {
        colaboradorRemoto = await _remotoPorLocal(
          tabela: 'imperium_sync_precificacao_colaboradores',
          empresaId: empresaId,
          localId: colaboradorLocal,
        );
      }

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'ordem_servico_id': ordemRemota,
        'colaborador_custo_id': colaboradorRemoto,
        'descricao': _texto(local['descricao']),
        'horas': _double(local['horas']),
        'custo_hora_snapshot': _double(local['custo_hora_snapshot']),
        'custo_total': _double(local['custo_total']),
        'data': _texto(local['data']),
        'observacoes': _texto(local['observacoes']),
        'ativo': _int(local['ativo']) != 0,
        'cancelado_em': _textoNulo(local['cancelado_em']),
        'origem_atualizado_em': DateTime.now().toIso8601String(),
      };

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_os_mao_obra',
        empresaId: empresaId,
        localId: localId,
      );

      Map<String, dynamic> remoto;

      if (mapa == null) {
        payload['origem_dispositivo'] = dispositivoId;
        payload['origem_local_id'] = localId;
        payload['origem_criado_em'] = _textoNulo(local['data']);

        remoto = Map<String, dynamic>.from(
          await client
              .from('imperium_financeiro_os_mao_obra')
              .insert(payload)
              .select()
              .single(),
        );
      } else {
        remoto = Map<String, dynamic>.from(
          await client
              .from('imperium_financeiro_os_mao_obra')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', mapa['remoto_id']!)
              .select()
              .single(),
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_os_mao_obra',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        remotoAtualizadoEm: _textoNulo(remoto['atualizado_em']),
      );
    }
  }

  Future<void> _baixarMaoObra(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_os_mao_obra')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos as List) {
      final remoto = Map<String, dynamic>.from(raw as Map);
      final remotoId = _texto(remoto['id']);

      final ordemLocal = await _localPorRemoto(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: _texto(remoto['ordem_servico_id']),
      );
      if (ordemLocal == null) continue;

      int? colaboradorLocal;
      final colaboradorRemoto = _textoNulo(remoto['colaborador_custo_id']);
      if (colaboradorRemoto != null) {
        colaboradorLocal = await _localPorRemoto(
          tabela: 'imperium_sync_precificacao_colaboradores',
          empresaId: empresaId,
          remotoId: colaboradorRemoto,
        );
      }

      final mapa = await _mapaRemoto(
        tabela: 'imperium_sync_os_mao_obra',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      final values = <String, Object?>{
        'ordem_servico_id': ordemLocal,
        'colaborador_custo_id': colaboradorLocal,
        'descricao': _texto(remoto['descricao']),
        'horas': _double(remoto['horas']),
        'custo_hora_snapshot': _double(remoto['custo_hora_snapshot']),
        'custo_total': _double(remoto['custo_total']),
        'data': _texto(remoto['data']),
        'observacoes': _texto(remoto['observacoes']),
        'ativo': remoto['ativo'] == true ? 1 : 0,
        'cancelado_em': _textoNulo(remoto['cancelado_em']),
      };

      int localId;
      if (mapa == null) {
        localId = await database.insert(
          'financeiro_os_mao_obra',
          values,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        localId = _int(mapa['local_id']);
        await database.update(
          'financeiro_os_mao_obra',
          values,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_os_mao_obra',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        remotoAtualizadoEm: _textoNulo(remoto['atualizado_em']),
      );
    }
  }

  Future<void> _publicarAjustes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final dispositivoId = await _dispositivoId();
    final rows = await database.query(
      'ordem_servico_ajustes_financeiros',
      orderBy: 'id ASC',
    );

    for (final local in rows) {
      final localId = _int(local['id']);
      final ordemRemota = await _remotoPorLocal(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: _int(local['ordem_servico_id']),
      );
      if (localId <= 0 || ordemRemota == null) continue;

      String? regraRemota;
      final regraLocal = _int(local['regra_taxa_id']);
      if (regraLocal > 0) {
        regraRemota = await _remotoPorLocal(
          tabela: 'imperium_sync_financeiro_regras_taxa',
          empresaId: empresaId,
          localId: regraLocal,
        );
      }

      String? pagamentoRemoto;
      final pagamentoLocal = _int(local['pagamento_id']);
      if (pagamentoLocal > 0) {
        pagamentoRemoto = await _remotoPorLocal(
          tabela: 'imperium_sync_financeiro_pagamentos',
          empresaId: empresaId,
          localId: pagamentoLocal,
        );
      }

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'ordem_servico_id': ordemRemota,
        'regra_taxa_id': regraRemota,
        'pagamento_id': pagamentoRemoto,
        'tipo': _texto(local['tipo']),
        'valor': _double(local['valor']),
        'motivo': _texto(local['motivo']),
        'status': _texto(local['status']),
        'origem': _texto(local['origem']).isEmpty
            ? 'Manual'
            : _texto(local['origem']),
        'cancelado_em': _textoNulo(local['cancelado_em']),
        'motivo_cancelamento': _texto(local['motivo_cancelamento']),
      };

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_os_ajustes_financeiros',
        empresaId: empresaId,
        localId: localId,
      );

      Map<String, dynamic> remoto;

      if (mapa == null) {
        payload['origem_dispositivo'] = dispositivoId;
        payload['origem_local_id'] = localId;
        payload['origem_criado_em'] = _textoNulo(local['criado_em']);

        remoto = Map<String, dynamic>.from(
          await client
              .from('imperium_ordem_servico_ajustes_financeiros')
              .insert(payload)
              .select()
              .single(),
        );
      } else {
        remoto = Map<String, dynamic>.from(
          await client
              .from('imperium_ordem_servico_ajustes_financeiros')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', mapa['remoto_id']!)
              .select()
              .single(),
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_os_ajustes_financeiros',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        remotoAtualizadoEm: _textoNulo(remoto['atualizado_em']),
      );
    }
  }

  Future<void> _baixarAjustes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_ordem_servico_ajustes_financeiros')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos as List) {
      final remoto = Map<String, dynamic>.from(raw as Map);
      final remotoId = _texto(remoto['id']);

      final ordemLocal = await _localPorRemoto(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: _texto(remoto['ordem_servico_id']),
      );
      if (ordemLocal == null) continue;

      int? regraLocal;
      final regraRemota = _textoNulo(remoto['regra_taxa_id']);
      if (regraRemota != null) {
        regraLocal = await _localPorRemoto(
          tabela: 'imperium_sync_financeiro_regras_taxa',
          empresaId: empresaId,
          remotoId: regraRemota,
        );
      }

      int? pagamentoLocal;
      final pagamentoRemoto = _textoNulo(remoto['pagamento_id']);
      if (pagamentoRemoto != null) {
        pagamentoLocal = await _localPorRemoto(
          tabela: 'imperium_sync_financeiro_pagamentos',
          empresaId: empresaId,
          remotoId: pagamentoRemoto,
        );
      }

      final mapa = await _mapaRemoto(
        tabela: 'imperium_sync_os_ajustes_financeiros',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      final values = <String, Object?>{
        'ordem_servico_id': ordemLocal,
        'tipo': _texto(remoto['tipo']),
        'valor': _double(remoto['valor']),
        'motivo': _texto(remoto['motivo']),
        'status': _texto(remoto['status']),
        'criado_em':
            _textoNulo(remoto['origem_criado_em']) ??
            _texto(remoto['criado_em']),
        'cancelado_em': _textoNulo(remoto['cancelado_em']),
        'motivo_cancelamento': _texto(remoto['motivo_cancelamento']),
        'origem': _texto(remoto['origem']),
        'regra_taxa_id': regraLocal,
        'pagamento_id': pagamentoLocal,
      };

      int localId;
      if (mapa == null) {
        localId = await database.insert(
          'ordem_servico_ajustes_financeiros',
          values,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        localId = _int(mapa['local_id']);
        await database.update(
          'ordem_servico_ajustes_financeiros',
          values,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_os_ajustes_financeiros',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        remotoAtualizadoEm: _textoNulo(remoto['atualizado_em']),
      );
    }
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required int ordemLocalId,
    required String ordemRemotoId,
    required String motivo,
    required String localHashBase,
    required String localHashAtual,
    required String? remotoBase,
    required String? remotoAtual,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_sync_os_produtos_conflitos',
      <String, Object?>{
        'empresa_id': empresaId,
        'ordem_local_id': ordemLocalId,
        'ordem_remoto_id': ordemRemotoId,
        'motivo': motivo,
        'local_hash_base': localHashBase,
        'local_hash_atual': localHashAtual,
        'remoto_atualizado_base': remotoBase,
        'remoto_atualizado_atual': remotoAtual,
        'status': 'Pendente',
        'detectado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Map<String, Object?>> _conflitoPendente(int id) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_os_produtos_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito de produtos não encontrado.');
    }

    return Map<String, Object?>.from(rows.first);
  }

  Future<void> _resolverConflito(int id, String resolucao) async {
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_os_produtos_conflitos',
      <String, Object?>{
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>?> _mapaLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _mapaRemoto({
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> _salvarMapa({
    required String tabela,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(tabela, <String, Object?>{
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _remotoPorLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;
    final mapa = await _mapaLocal(
      tabela: tabela,
      empresaId: empresaId,
      localId: localId,
    );
    final id = _texto(mapa?['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<int?> _localPorRemoto({
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.trim().isEmpty) return null;
    final mapa = await _mapaRemoto(
      tabela: tabela,
      empresaId: empresaId,
      remotoId: remotoId,
    );
    final id = _int(mapa?['local_id']);
    return id > 0 ? id : null;
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final atual = _texto(rows.first['dispositivo_id']);
      if (atual.isNotEmpty) return atual;
    }

    final novo = 'android-${DateTime.now().microsecondsSinceEpoch}';

    if (rows.isEmpty) {
      await database.insert('imperium_sync_config', <String, Object?>{
        'id': 1,
        'dispositivo_id': novo,
        'empresa_id': null,
        'ultimo_sync_em': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await database.update('imperium_sync_config', {
        'dispositivo_id': novo,
      }, where: 'id = 1');
    }

    return novo;
  }

  static bool _mesmoTimestamp(String? a, String? b) {
    final aa = a?.trim() ?? '';
    final bb = b?.trim() ?? '';

    if (aa.isEmpty || bb.isEmpty) return aa == bb;

    final da = DateTime.tryParse(aa);
    final db = DateTime.tryParse(bb);

    if (da == null || db == null) return aa == bb;

    return da.toUtc().microsecondsSinceEpoch ==
        db.toUtc().microsecondsSinceEpoch;
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String? _textoNulo(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ContratoLocal {
  const _ContratoLocal({
    required this.hash,
    required this.produtos,
    required this.lotes,
    required this.dispositivoId,
  });

  final String hash;
  final List<Map<String, Object?>> produtos;
  final List<Map<String, Object?>> lotes;
  final String dispositivoId;
}
