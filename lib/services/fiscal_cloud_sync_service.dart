import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincronizacao bidirecional do nucleo fiscal entre SQLite mobile e Cloud.
///
/// Mantem notas e itens fiscais compartilhados com a Web sem executar regras
/// de estoque/financeiro novamente. Essas integracoes continuam nos modulos
/// proprios, evitando dupla movimentacao.
class FiscalCloudSyncService {
  FiscalCloudSyncService._();

  static final FiscalCloudSyncService instance = FiscalCloudSyncService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_fiscal_notas',
      'imperium_sync_fiscal_itens',
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

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_fiscal_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        entidade TEXT NOT NULL,
        local_id INTEGER,
        remoto_id TEXT,
        motivo TEXT NOT NULL,
        local_json TEXT NOT NULL DEFAULT '{}',
        remoto_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'Pendente',
        criado_em TEXT NOT NULL,
        UNIQUE (empresa_id, entidade, local_id, remoto_id, status)
      )
    ''');
  }

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      // Primeiro incorpora alteracoes Web para evitar publicar por cima de uma
      // versao remota mais nova.
      await _baixarNotas(empresaId);
      await _baixarItens(empresaId);

      await _publicarNotas(empresaId);
      await _publicarItens(empresaId);
      await _publicarExclusoesLocais(empresaId);

      if (await possuiConflitosPendentes(empresaId)) {
        throw StateError(
          'Existem conflitos fiscais pendentes entre o mobile e a Web.',
        );
      }
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_fiscal_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [empresaId],
    );
    return _int(resultado.first['total']) > 0;
  }

  Future<void> _baixarNotas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotosRaw = await client
        .from('imperium_fiscal_notas_entrada')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final raw in remotosRaw) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;

      final mapa = await _mapaPorRemoto(
        tabela: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      if (mapa == null) {
        if (_texto(remoto['excluido_em']).isNotEmpty) continue;
        await _baixarNotaNovaOuReconciliar(empresaId, remoto);
        continue;
      }

      await _reconciliarNotaMapeada(empresaId, mapa, remoto);
    }
  }

  Future<void> _baixarNotaNovaOuReconciliar(
    String empresaId,
    Map<String, dynamic> remoto,
  ) async {
    final database = await _appDatabase.database;
    final remotoId = _texto(remoto['id']);
    final chave = _texto(remoto['chave_acesso']);

    if (chave.isEmpty) return;

    final existentePorOrigem = await _localDaMesmaOrigem(
      tabelaLocal: 'notas_fiscais_entrada',
      origemDispositivo: _texto(remoto['origem_dispositivo']),
      origemLocalId: _int(remoto['origem_local_id']),
    );

    Map<String, Object?>? existente = existentePorOrigem;
    existente ??= await _primeiroLocal(
      'notas_fiscais_entrada',
      where: 'chave_acesso = ?',
      whereArgs: [chave],
    );

    final fornecedorLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_financeiro_fornecedores',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['fornecedor_id']),
    );

    if (_texto(remoto['fornecedor_id']).isNotEmpty &&
        fornecedorLocalId == null) {
      return;
    }

    final dados = _dadosNotaRemota(
      remoto,
      fornecedorLocalId: fornecedorLocalId,
      preservarFornecedorLocal: existente?['fornecedor_id'],
    );

    final int localId;
    if (existente == null) {
      localId = await database.insert(
        'notas_fiscais_entrada',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      localId = _int(existente['id']);
      if (localId <= 0) return;
      await database.update(
        'notas_fiscais_entrada',
        dados,
        where: 'id = ?',
        whereArgs: [localId],
      );
    }

    final local = await _localPorId('notas_fiscais_entrada', localId);
    await _salvarMapa(
      tabela: 'imperium_sync_fiscal_notas',
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hashNota(local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _reconciliarNotaMapeada(
    String empresaId,
    Map<String, Object?> mapa,
    Map<String, dynamic> remoto,
  ) async {
    final localId = _int(mapa['local_id']);
    final remotoId = _texto(remoto['id']);
    if (localId <= 0) return;

    final local = await _localPorIdOuNulo('notas_fiscais_entrada', localId);
    if (local == null) {
      if (_texto(remoto['excluido_em']).isNotEmpty) {
        await _removerMapa(
          tabela: 'imperium_sync_fiscal_notas',
          empresaId: empresaId,
          localId: localId,
        );
        return;
      }
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'nota',
        localId: localId,
        remotoId: remotoId,
        motivo: 'registro_local_ausente',
        local: const {},
        remoto: remoto,
      );
      return;
    }

    final localHash = _hashNota(local);
    final localMudou = localHash != _texto(mapa['local_hash']);
    final remotoBase = _texto(mapa['remoto_atualizado_em']);
    final remotoAtual = _texto(remoto['atualizado_em']);
    final remotoMudou =
        remotoBase.isEmpty || remotoAtual.isEmpty || remotoBase != remotoAtual;
    final remotoExcluido = _texto(remoto['excluido_em']).isNotEmpty;

    if (remotoExcluido) {
      if (localMudou || await _notaLocalTemIntegracoes(localId)) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'nota',
          localId: localId,
          remotoId: remotoId,
          motivo: 'exclusao_remota_com_dependencia_ou_alteracao_local',
          local: local,
          remoto: remoto,
        );
        return;
      }

      final database = await _appDatabase.database;
      await database.transaction((tx) async {
        await tx.delete(
          'notas_fiscais_entrada_itens',
          where: 'nota_fiscal_id = ?',
          whereArgs: [localId],
        );
        await tx.delete(
          'notas_fiscais_entrada',
          where: 'id = ?',
          whereArgs: [localId],
        );
        await tx.delete(
          'imperium_sync_fiscal_itens',
          where: 'empresa_id = ? AND local_id NOT IN '
              '(SELECT id FROM notas_fiscais_entrada_itens)',
          whereArgs: [empresaId],
        );
      });
      await _removerMapa(
        tabela: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        localId: localId,
      );
      return;
    }

    if (!remotoMudou) return;

    if (localMudou) {
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'nota',
        localId: localId,
        remotoId: remotoId,
        motivo: 'alteracao_concorrente',
        local: local,
        remoto: remoto,
      );
      return;
    }

    final fornecedorLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_financeiro_fornecedores',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['fornecedor_id']),
    );
    if (_texto(remoto['fornecedor_id']).isNotEmpty &&
        fornecedorLocalId == null) {
      return;
    }

    final database = await _appDatabase.database;
    await database.update(
      'notas_fiscais_entrada',
      _dadosNotaRemota(
        remoto,
        fornecedorLocalId: fornecedorLocalId,
        preservarFornecedorLocal: local['fornecedor_id'],
      ),
      where: 'id = ?',
      whereArgs: [localId],
    );

    final localAtual = await _localPorId('notas_fiscais_entrada', localId);
    await _salvarMapa(
      tabela: 'imperium_sync_fiscal_notas',
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hashNota(localAtual),
      remotoAtualizadoEm: remotoAtual,
    );
  }

  Future<void> _baixarItens(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotosRaw = await client
        .from('imperium_fiscal_notas_itens')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final raw in remotosRaw) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;

      final mapa = await _mapaPorRemoto(
        tabela: 'imperium_sync_fiscal_itens',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      if (mapa == null) {
        if (_texto(remoto['excluido_em']).isNotEmpty) continue;
        await _baixarItemNovoOuReconciliar(empresaId, remoto);
        continue;
      }

      await _reconciliarItemMapeado(empresaId, mapa, remoto);
    }
  }

  Future<void> _baixarItemNovoOuReconciliar(
    String empresaId,
    Map<String, dynamic> remoto,
  ) async {
    final notaLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_fiscal_notas',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['nota_fiscal_id']),
    );
    if (notaLocalId == null) return;

    final estoqueLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['estoque_item_id']),
    );
    if (_texto(remoto['estoque_item_id']).isNotEmpty &&
        estoqueLocalId == null) {
      return;
    }

    final numero = _int(remoto['numero_item']);
    if (numero <= 0) return;

    Map<String, Object?>? existente;
    final origemItemId = _int(remoto['origem_local_item_id']);
    if (origemItemId > 0) {
      existente = await _localPorIdOuNulo(
        'notas_fiscais_entrada_itens',
        origemItemId,
      );
      if (existente != null &&
          _int(existente['nota_fiscal_id']) != notaLocalId) {
        existente = null;
      }
    }
    existente ??= await _primeiroLocal(
      'notas_fiscais_entrada_itens',
      where: 'nota_fiscal_id = ? AND numero_item = ?',
      whereArgs: [notaLocalId, numero],
    );

    final dados = _dadosItemRemoto(
      remoto,
      notaLocalId: notaLocalId,
      estoqueLocalId: estoqueLocalId,
      preservarEstoqueLocal: existente?['estoque_item_id'],
    );

    final database = await _appDatabase.database;
    final int localId;
    if (existente == null) {
      localId = await database.insert(
        'notas_fiscais_entrada_itens',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      localId = _int(existente['id']);
      if (localId <= 0) return;
      await database.update(
        'notas_fiscais_entrada_itens',
        dados,
        where: 'id = ?',
        whereArgs: [localId],
      );
    }

    final local = await _localPorId('notas_fiscais_entrada_itens', localId);
    await _salvarMapa(
      tabela: 'imperium_sync_fiscal_itens',
      empresaId: empresaId,
      localId: localId,
      remotoId: _texto(remoto['id']),
      localHash: _hashItem(local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _reconciliarItemMapeado(
    String empresaId,
    Map<String, Object?> mapa,
    Map<String, dynamic> remoto,
  ) async {
    final localId = _int(mapa['local_id']);
    final remotoId = _texto(remoto['id']);
    if (localId <= 0) return;

    final local = await _localPorIdOuNulo(
      'notas_fiscais_entrada_itens',
      localId,
    );
    if (local == null) {
      if (_texto(remoto['excluido_em']).isNotEmpty) {
        await _removerMapa(
          tabela: 'imperium_sync_fiscal_itens',
          empresaId: empresaId,
          localId: localId,
        );
        return;
      }
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'item',
        localId: localId,
        remotoId: remotoId,
        motivo: 'registro_local_ausente',
        local: const {},
        remoto: remoto,
      );
      return;
    }

    final localHash = _hashItem(local);
    final localMudou = localHash != _texto(mapa['local_hash']);
    final remotoBase = _texto(mapa['remoto_atualizado_em']);
    final remotoAtual = _texto(remoto['atualizado_em']);
    final remotoMudou =
        remotoBase.isEmpty || remotoAtual.isEmpty || remotoBase != remotoAtual;
    final remotoExcluido = _texto(remoto['excluido_em']).isNotEmpty;

    if (remotoExcluido) {
      if (localMudou || _int(local['estoque_item_id']) > 0) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'item',
          localId: localId,
          remotoId: remotoId,
          motivo: 'exclusao_remota_com_vinculo_ou_alteracao_local',
          local: local,
          remoto: remoto,
        );
        return;
      }
      final database = await _appDatabase.database;
      await database.delete(
        'notas_fiscais_entrada_itens',
        where: 'id = ?',
        whereArgs: [localId],
      );
      await _removerMapa(
        tabela: 'imperium_sync_fiscal_itens',
        empresaId: empresaId,
        localId: localId,
      );
      return;
    }

    if (!remotoMudou) return;

    if (localMudou) {
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'item',
        localId: localId,
        remotoId: remotoId,
        motivo: 'alteracao_concorrente',
        local: local,
        remoto: remoto,
      );
      return;
    }

    final notaLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_fiscal_notas',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['nota_fiscal_id']),
    );
    if (notaLocalId == null) return;

    final estoqueLocalId = await _localPorRemotoOuNulo(
      tabelaMapa: 'imperium_sync_estoque_itens',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['estoque_item_id']),
    );
    if (_texto(remoto['estoque_item_id']).isNotEmpty &&
        estoqueLocalId == null) {
      return;
    }

    final database = await _appDatabase.database;
    await database.update(
      'notas_fiscais_entrada_itens',
      _dadosItemRemoto(
        remoto,
        notaLocalId: notaLocalId,
        estoqueLocalId: estoqueLocalId,
        preservarEstoqueLocal: local['estoque_item_id'],
      ),
      where: 'id = ?',
      whereArgs: [localId],
    );

    final localAtual = await _localPorId(
      'notas_fiscais_entrada_itens',
      localId,
    );
    await _salvarMapa(
      tabela: 'imperium_sync_fiscal_itens',
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hashItem(localAtual),
      remotoAtualizadoEm: remotoAtual,
    );
  }

  Future<void> _publicarNotas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'notas_fiscais_entrada',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0 || await _temConflito(empresaId, 'nota', localId)) {
        continue;
      }

      final hash = _hashNota(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        localId: localId,
      );
      if (mapa != null && hash == _texto(mapa['local_hash'])) continue;

      final fornecedorRemotoId = await _remotoPorLocalOuNulo(
        tabelaMapa: 'imperium_sync_financeiro_fornecedores',
        empresaId: empresaId,
        localId: _intNulo(local['fornecedor_id']),
      );
      if (_int(local['fornecedor_id']) > 0 && fornecedorRemotoId == null) {
        continue;
      }

      final payload = _dadosNotaLocal(
        empresaId: empresaId,
        local: local,
        fornecedorRemotoId: fornecedorRemotoId,
      );

      if (mapa == null) {
        final existenteRaw = await client
            .from('imperium_fiscal_notas_entrada')
            .select()
            .eq('empresa_id', empresaId)
            .eq('chave_acesso', _texto(local['chave_acesso']))
            .maybeSingle();

        if (existenteRaw != null) {
          final remoto = Map<String, dynamic>.from(existenteRaw);
          await _salvarMapa(
            tabela: 'imperium_sync_fiscal_notas',
            empresaId: empresaId,
            localId: localId,
            remotoId: _texto(remoto['id']),
            localHash: hash,
            remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
          );
          continue;
        }

        payload['origem_dispositivo'] = await _dispositivoId();
        payload['origem_local_id'] = localId;

        final salvoRaw = await client
            .from('imperium_fiscal_notas_entrada')
            .insert(payload)
            .select('id,atualizado_em')
            .single();
        final salvo = Map<String, dynamic>.from(salvoRaw);

        await _salvarMapa(
          tabela: 'imperium_sync_fiscal_notas',
          empresaId: empresaId,
          localId: localId,
          remotoId: _texto(salvo['id']),
          localHash: hash,
          remotoAtualizadoEm: salvo['atualizado_em']?.toString(),
        );
        continue;
      }

      final remotoId = _texto(mapa['remoto_id']);
      final esperado = _texto(mapa['remoto_atualizado_em']);
      final remotoAtualRaw = await client
          .from('imperium_fiscal_notas_entrada')
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoAtualRaw == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'nota',
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_remoto_ausente',
          local: local,
          remoto: const {},
        );
        continue;
      }

      final remotoAtual = Map<String, dynamic>.from(remotoAtualRaw);
      if (esperado.isNotEmpty &&
          _texto(remotoAtual['atualizado_em']) != esperado) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'nota',
          localId: localId,
          remotoId: remotoId,
          motivo: 'cas_falhou_alteracao_concorrente',
          local: local,
          remoto: remotoAtual,
        );
        continue;
      }

      final resposta = esperado.isEmpty
          ? await client
                .from('imperium_fiscal_notas_entrada')
                .update(payload)
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .select('id,atualizado_em')
          : await client
                .from('imperium_fiscal_notas_entrada')
                .update(payload)
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .eq('atualizado_em', esperado)
                .select('id,atualizado_em');

      if (resposta.isEmpty) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'nota',
          localId: localId,
          remotoId: remotoId,
          motivo: 'cas_falhou_alteracao_concorrente',
          local: local,
          remoto: remotoAtual,
        );
        continue;
      }

      await _salvarMapa(
        tabela: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: hash,
        remotoAtualizadoEm: resposta.first['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarItens(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'notas_fiscais_entrada_itens',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0 || await _temConflito(empresaId, 'item', localId)) {
        continue;
      }

      final notaRemotaId = await _remotoPorLocalOuNulo(
        tabelaMapa: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        localId: _intNulo(local['nota_fiscal_id']),
      );
      if (notaRemotaId == null) continue;

      final estoqueRemotoId = await _remotoPorLocalOuNulo(
        tabelaMapa: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        localId: _intNulo(local['estoque_item_id']),
      );
      if (_int(local['estoque_item_id']) > 0 && estoqueRemotoId == null) {
        continue;
      }

      final hash = _hashItem(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_fiscal_itens',
        empresaId: empresaId,
        localId: localId,
      );
      if (mapa != null && hash == _texto(mapa['local_hash'])) continue;

      final payload = _dadosItemLocal(
        empresaId: empresaId,
        local: local,
        notaRemotaId: notaRemotaId,
        estoqueRemotoId: estoqueRemotoId,
      );

      if (mapa == null) {
        final existenteRaw = await client
            .from('imperium_fiscal_notas_itens')
            .select()
            .eq('empresa_id', empresaId)
            .eq('nota_fiscal_id', notaRemotaId)
            .eq('numero_item', _int(local['numero_item']))
            .maybeSingle();

        if (existenteRaw != null) {
          final remoto = Map<String, dynamic>.from(existenteRaw);
          await _salvarMapa(
            tabela: 'imperium_sync_fiscal_itens',
            empresaId: empresaId,
            localId: localId,
            remotoId: _texto(remoto['id']),
            localHash: hash,
            remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
          );
          continue;
        }

        final salvoRaw = await client
            .from('imperium_fiscal_notas_itens')
            .insert(payload)
            .select('id,atualizado_em')
            .single();
        final salvo = Map<String, dynamic>.from(salvoRaw);

        await _salvarMapa(
          tabela: 'imperium_sync_fiscal_itens',
          empresaId: empresaId,
          localId: localId,
          remotoId: _texto(salvo['id']),
          localHash: hash,
          remotoAtualizadoEm: salvo['atualizado_em']?.toString(),
        );
        continue;
      }

      final remotoId = _texto(mapa['remoto_id']);
      final esperado = _texto(mapa['remoto_atualizado_em']);
      final atualRaw = await client
          .from('imperium_fiscal_notas_itens')
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (atualRaw == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'item',
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_remoto_ausente',
          local: local,
          remoto: const {},
        );
        continue;
      }

      final remotoAtual = Map<String, dynamic>.from(atualRaw);
      if (esperado.isNotEmpty &&
          _texto(remotoAtual['atualizado_em']) != esperado) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'item',
          localId: localId,
          remotoId: remotoId,
          motivo: 'cas_falhou_alteracao_concorrente',
          local: local,
          remoto: remotoAtual,
        );
        continue;
      }

      final resposta = esperado.isEmpty
          ? await client
                .from('imperium_fiscal_notas_itens')
                .update(payload)
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .select('id,atualizado_em')
          : await client
                .from('imperium_fiscal_notas_itens')
                .update(payload)
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .eq('atualizado_em', esperado)
                .select('id,atualizado_em');

      if (resposta.isEmpty) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'item',
          localId: localId,
          remotoId: remotoId,
          motivo: 'cas_falhou_alteracao_concorrente',
          local: local,
          remoto: remotoAtual,
        );
        continue;
      }

      await _salvarMapa(
        tabela: 'imperium_sync_fiscal_itens',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: hash,
        remotoAtualizadoEm: resposta.first['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarExclusoesLocais(String empresaId) async {
    final client = _client;
    if (client == null) return;
    final database = await _appDatabase.database;

    final mapasItens = await database.query(
      'imperium_sync_fiscal_itens',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );
    for (final mapa in mapasItens) {
      final localId = _int(mapa['local_id']);
      if (await _localPorIdOuNulo('notas_fiscais_entrada_itens', localId) !=
          null) {
        continue;
      }
      await client
          .from('imperium_fiscal_notas_itens')
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', _texto(mapa['remoto_id']))
          .isFilter('excluido_em', null);
      await _removerMapa(
        tabela: 'imperium_sync_fiscal_itens',
        empresaId: empresaId,
        localId: localId,
      );
    }

    final mapasNotas = await database.query(
      'imperium_sync_fiscal_notas',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );
    for (final mapa in mapasNotas) {
      final localId = _int(mapa['local_id']);
      if (await _localPorIdOuNulo('notas_fiscais_entrada', localId) != null) {
        continue;
      }

      final remotoId = _texto(mapa['remoto_id']);
      final estoque = await client
          .from('imperium_estoque_movimentacoes')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('fiscal_nota_id', remotoId)
          .limit(1);
      final financeiro = await client
          .from('imperium_financeiro_movimentos')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('fiscal_nota_id', remotoId)
          .isFilter('excluido_em', null)
          .limit(1);

      if (estoque.isNotEmpty || financeiro.isNotEmpty) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'nota',
          localId: localId,
          remotoId: remotoId,
          motivo: 'exclusao_local_com_integracao_remota',
          local: const {},
          remoto: const {},
        );
        continue;
      }

      await client
          .from('imperium_fiscal_notas_entrada')
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .isFilter('excluido_em', null);
      await _removerMapa(
        tabela: 'imperium_sync_fiscal_notas',
        empresaId: empresaId,
        localId: localId,
      );
    }
  }

  Map<String, dynamic> _dadosNotaLocal({
    required String empresaId,
    required Map<String, Object?> local,
    required String? fornecedorRemotoId,
  }) {
    return <String, dynamic>{
      'empresa_id': empresaId,
      'chave_acesso': _texto(local['chave_acesso']),
      'modelo': _intNulo(local['modelo']),
      'numero': _intNulo(local['numero']),
      'serie': _intNulo(local['serie']),
      'data_emissao': _textoNulo(local['data_emissao']),
      'fornecedor_id': fornecedorRemotoId,
      'emitente_cnpj_cpf': _textoNulo(local['emitente_cnpj_cpf']),
      'emitente_nome': _textoNulo(local['emitente_nome']),
      'valor_produtos': _doubleNulo(local['valor_produtos']),
      'valor_frete': _double(local['valor_frete']),
      'valor_seguro': _double(local['valor_seguro']),
      'valor_desconto': _double(local['valor_desconto']),
      'valor_outras_despesas': _double(local['valor_outras_despesas']),
      'valor_ipi': _double(local['valor_ipi']),
      'valor_icms_st': _double(local['valor_icms_st']),
      'valor_total': _doubleNulo(local['valor_total']),
      'situacao_fiscal': _textoPadrao(local['situacao_fiscal'], 'desconhecida'),
      'status_importacao': _textoPadrao(local['status_importacao'], 'pendente'),
      'origem_importacao': _texto(local['origem_importacao']),
      'xml_original': _textoNulo(local['xml_original']),
      'xml_hash': _textoNulo(local['xml_hash']),
      'consulta_url': _textoNulo(local['consulta_url']),
      'tentativas_importacao': _int(local['tentativas_importacao']),
      'ultima_tentativa_em': _textoNulo(local['ultima_tentativa_em']),
      'ultimo_erro_codigo': _texto(local['ultimo_erro_codigo']),
      'ultimo_erro_mensagem': _texto(local['ultimo_erro_mensagem']),
      'importada_em': _texto(local['importada_em']),
      'observacoes': _texto(local['observacoes']),
      'excluido_em': null,
    };
  }

  Map<String, Object?> _dadosNotaRemota(
    Map<String, dynamic> remoto, {
    required int? fornecedorLocalId,
    Object? preservarFornecedorLocal,
  }) {
    return <String, Object?>{
      'chave_acesso': _texto(remoto['chave_acesso']),
      'modelo': _intNulo(remoto['modelo']),
      'numero': _intNulo(remoto['numero']),
      'serie': _intNulo(remoto['serie']),
      'data_emissao': _textoNulo(remoto['data_emissao']),
      'fornecedor_id':
          fornecedorLocalId ?? _intNulo(preservarFornecedorLocal),
      'emitente_cnpj_cpf': _textoNulo(remoto['emitente_cnpj_cpf']),
      'emitente_nome': _textoNulo(remoto['emitente_nome']),
      'valor_produtos': _doubleNulo(remoto['valor_produtos']),
      'valor_frete': _double(remoto['valor_frete']),
      'valor_seguro': _double(remoto['valor_seguro']),
      'valor_desconto': _double(remoto['valor_desconto']),
      'valor_outras_despesas': _double(remoto['valor_outras_despesas']),
      'valor_ipi': _double(remoto['valor_ipi']),
      'valor_icms_st': _double(remoto['valor_icms_st']),
      'valor_total': _doubleNulo(remoto['valor_total']),
      'situacao_fiscal': _textoPadrao(remoto['situacao_fiscal'], 'desconhecida'),
      'status_importacao': _textoPadrao(remoto['status_importacao'], 'pendente'),
      'origem_importacao': _texto(remoto['origem_importacao']),
      'xml_original': _textoNulo(remoto['xml_original']),
      'xml_hash': _textoNulo(remoto['xml_hash']),
      'consulta_url': _textoNulo(remoto['consulta_url']),
      'tentativas_importacao': _int(remoto['tentativas_importacao']),
      'ultima_tentativa_em': _textoNulo(remoto['ultima_tentativa_em']),
      'ultimo_erro_codigo': _texto(remoto['ultimo_erro_codigo']),
      'ultimo_erro_mensagem': _texto(remoto['ultimo_erro_mensagem']),
      'importada_em': _textoPreferido(
        remoto['importada_em'],
        remoto['criado_em'],
        DateTime.now().toIso8601String(),
      ),
      'observacoes': _texto(remoto['observacoes']),
    };
  }

  Map<String, dynamic> _dadosItemLocal({
    required String empresaId,
    required Map<String, Object?> local,
    required String notaRemotaId,
    required String? estoqueRemotoId,
  }) {
    return <String, dynamic>{
      'empresa_id': empresaId,
      'nota_fiscal_id': notaRemotaId,
      'numero_item': _int(local['numero_item']),
      'codigo_produto': _textoNulo(local['codigo_produto']),
      'ean': _textoNulo(local['ean']),
      'descricao': _texto(local['descricao']),
      'ncm': _textoNulo(local['ncm']),
      'cfop': _textoNulo(local['cfop']),
      'unidade': _texto(local['unidade']),
      'quantidade': _double(local['quantidade']),
      'valor_unitario': _double(local['valor_unitario']),
      'valor_total': _double(local['valor_total']),
      'valor_desconto': _double(local['valor_desconto']),
      'estoque_item_id': estoqueRemotoId,
      'observacoes': _texto(local['observacoes']),
      'origem_local_item_id': _int(local['id']),
      'excluido_em': null,
    };
  }

  Map<String, Object?> _dadosItemRemoto(
    Map<String, dynamic> remoto, {
    required int notaLocalId,
    required int? estoqueLocalId,
    Object? preservarEstoqueLocal,
  }) {
    return <String, Object?>{
      'nota_fiscal_id': notaLocalId,
      'numero_item': _int(remoto['numero_item']),
      'codigo_produto': _textoNulo(remoto['codigo_produto']),
      'ean': _textoNulo(remoto['ean']),
      'descricao': _texto(remoto['descricao']),
      'ncm': _textoNulo(remoto['ncm']),
      'cfop': _textoNulo(remoto['cfop']),
      'unidade': _texto(remoto['unidade']),
      'quantidade': _double(remoto['quantidade']),
      'valor_unitario': _double(remoto['valor_unitario']),
      'valor_total': _double(remoto['valor_total']),
      'valor_desconto': _double(remoto['valor_desconto']),
      'estoque_item_id': estoqueLocalId ?? _intNulo(preservarEstoqueLocal),
      'observacoes': _texto(remoto['observacoes']),
    };
  }

  Future<bool> _notaLocalTemIntegracoes(int notaLocalId) async {
    final database = await _appDatabase.database;

    final estoqueExiste = await _tabelaExiste(
      database,
      'movimentacoes_estoque',
    );
    if (estoqueExiste) {
      final estoque = await database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM movimentacoes_estoque
        WHERE nota_fiscal_id = ?
        ''',
        [notaLocalId],
      );
      if (_int(estoque.first['total']) > 0) return true;
    }

    final financeiroExiste = await _tabelaExiste(
      database,
      'movimentos_financeiros',
    );
    if (financeiroExiste) {
      final financeiro = await database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM movimentos_financeiros
        WHERE nota_fiscal_id = ?
          AND status != 'Cancelado'
        ''',
        [notaLocalId],
      );
      if (_int(financeiro.first['total']) > 0) return true;
    }

    return false;
  }

  Future<bool> _tabelaExiste(Database database, String tabela) async {
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tabela],
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>?> _localDaMesmaOrigem({
    required String tabelaLocal,
    required String origemDispositivo,
    required int origemLocalId,
  }) async {
    if (origemDispositivo.isEmpty || origemLocalId <= 0) return null;
    final atual = await _dispositivoId();
    if (origemDispositivo != atual) return null;
    return _localPorIdOuNulo(tabelaLocal, origemLocalId);
  }

  Future<bool> _temConflito(
    String empresaId,
    String entidade,
    int localId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_fiscal_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND entidade = ? AND local_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required Map local,
    required Map remoto,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_fiscal_conflitos',
      {
        'empresa_id': empresaId,
        'entidade': entidade,
        'local_id': localId,
        'remoto_id': remotoId,
        'motivo': motivo,
        'local_json': jsonEncode(local),
        'remoto_json': jsonEncode(remoto),
        'status': 'Pendente',
        'criado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
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
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _mapaPorRemoto({
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
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> _remotoPorLocalOuNulo({
    required String tabelaMapa,
    required String empresaId,
    required int? localId,
  }) async {
    if (localId == null || localId <= 0) return null;
    final mapa = await _mapaLocal(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
    final remoto = _texto(mapa?['remoto_id']);
    return remoto.isEmpty ? null : remoto;
  }

  Future<int?> _localPorRemotoOuNulo({
    required String tabelaMapa,
    required String empresaId,
    required String? remotoId,
  }) async {
    if (remotoId == null || remotoId.trim().isEmpty) return null;
    final mapa = await _mapaPorRemoto(
      tabela: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
    final localId = _int(mapa?['local_id']);
    return localId <= 0 ? null : localId;
  }

  Future<Map<String, Object?>?> _primeiroLocal(
    String tabela, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>> _localPorId(
    String tabela,
    int localId,
  ) async {
    final local = await _localPorIdOuNulo(tabela, localId);
    if (local == null) {
      throw StateError('Registro fiscal local nao encontrado.');
    }
    return local;
  }

  Future<Map<String, Object?>?> _localPorIdOuNulo(
    String tabela,
    int localId,
  ) async {
    if (localId <= 0) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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
    await database.insert(
      tabela,
      {
        'empresa_id': empresaId,
        'local_id': localId,
        'remoto_id': remotoId,
        'local_hash': localHash,
        'remoto_atualizado_em': remotoAtualizadoEm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _removerMapa({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    await database.delete(
      tabela,
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
      throw StateError('Dispositivo de sincronizacao nao inicializado.');
    }
    return id;
  }

  String _hashNota(Map<String, Object?> local) {
    return _hash([
      local['chave_acesso'],
      _intNulo(local['modelo']),
      _intNulo(local['numero']),
      _intNulo(local['serie']),
      local['data_emissao'],
      _intNulo(local['fornecedor_id']),
      local['emitente_cnpj_cpf'],
      local['emitente_nome'],
      _doubleNulo(local['valor_produtos']),
      _double(local['valor_frete']),
      _double(local['valor_seguro']),
      _double(local['valor_desconto']),
      _double(local['valor_outras_despesas']),
      _double(local['valor_ipi']),
      _double(local['valor_icms_st']),
      _doubleNulo(local['valor_total']),
      local['situacao_fiscal'],
      local['status_importacao'],
      local['origem_importacao'],
      local['xml_hash'],
      local['consulta_url'],
      _int(local['tentativas_importacao']),
      local['ultima_tentativa_em'],
      local['ultimo_erro_codigo'],
      local['ultimo_erro_mensagem'],
      local['importada_em'],
      local['observacoes'],
    ]);
  }

  String _hashItem(Map<String, Object?> local) {
    return _hash([
      _int(local['nota_fiscal_id']),
      _int(local['numero_item']),
      local['codigo_produto'],
      local['ean'],
      local['descricao'],
      local['ncm'],
      local['cfop'],
      local['unidade'],
      _double(local['quantidade']),
      _double(local['valor_unitario']),
      _double(local['valor_total']),
      _double(local['valor_desconto']),
      _intNulo(local['estoque_item_id']),
      local['observacoes'],
    ]);
  }

  String _hash(List<Object?> valores) {
    return sha256.convert(utf8.encode(jsonEncode(valores))).toString();
  }

  static String _texto(Object? valor) => valor?.toString().trim() ?? '';

  static String? _textoNulo(Object? valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }

  static String _textoPadrao(Object? valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }

  static String _textoPreferido(
    Object? primeiro,
    Object? segundo,
    String fallback,
  ) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;
    final b = _texto(segundo);
    return b.isNotEmpty ? b : fallback;
  }

  static int _int(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(_texto(valor)) ?? 0;
  }

  static int? _intNulo(Object? valor) {
    if (valor == null) return null;
    final resultado = _int(valor);
    return resultado <= 0 ? null : resultado;
  }

  static double _double(Object? valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(_texto(valor).replaceAll(',', '.')) ?? 0;
  }

  static double? _doubleNulo(Object? valor) {
    if (valor == null) return null;
    return _double(valor);
  }
}
