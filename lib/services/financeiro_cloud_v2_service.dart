import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Financeiro Cloud V2.
///
/// Complementa o upload V1 com:
/// - conflitos antes do upload;
/// - fornecedores, regras de taxa e transferencias;
/// - download controlado sem efeitos colaterais;
/// - resolucao tecnica local/nuvem;
/// - protecao contra dupla contabilizacao.
///
/// Pagamentos e movimentos baixados sao gravados diretamente no SQLite.
/// Este service nunca chama PagamentoRepository/FinanceiroRepository para
/// importar dados remotos.
class FinanceiroCloudV2Service {
  FinanceiroCloudV2Service._();

  static final FinanceiroCloudV2Service instance = FinanceiroCloudV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // financeiro-cloud-v2
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_financeiro_plano_contas',
      'imperium_sync_financeiro_contas',
      'imperium_sync_financeiro_pagamentos',
      'imperium_sync_financeiro_movimentos',
      'imperium_sync_financeiro_fornecedores',
      'imperium_sync_financeiro_regras_taxa',
      'imperium_sync_financeiro_transferencias',
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
      CREATE TABLE IF NOT EXISTS imperium_sync_financeiro_conflitos (
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
        resolucao TEXT,
        resolucao_detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_fin_conflitos_pendentes
      ON imperium_sync_financeiro_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');
  }

  /// Retorna false quando o Financeiro deve ficar bloqueado para upload.
  Future<bool> prepararUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return false;

    try {
      await garantirEstruturaLocal();

      if (await possuiConflitosPendentes(empresaId)) return false;

      for (final entidade in _entidadesMutaveis) {
        await _reconciliarEntidade(empresaId: empresaId, entidade: entidade);
      }

      return !await possuiConflitosPendentes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return false;
      rethrow;
    }
  }

  /// Executar depois do FinanceiroCloudUploadService V1.
  Future<void> completarUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      if (await possuiConflitosPendentes(empresaId)) return;

      await _publicarFornecedores(empresaId);
      await _publicarRegrasTaxa(empresaId);
      await _publicarTransferencias(empresaId);
      await _vincularRegrasNosPagamentos(empresaId);
      await _vincularComplementosNosMovimentos(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> sincronizarDownload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      await _baixarPlanosNovos(empresaId);
      await _baixarContasNovas(empresaId);
      await _baixarFornecedoresNovos(empresaId);
      await _baixarRegrasNovas(empresaId);
      await _baixarTransferenciasNovas(empresaId);
      await _baixarPagamentosNovos(empresaId);
      await _baixarMovimentosNovos(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_financeiro_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_financeiro_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  // financeiro-cloud-v2-resolucao
  Future<void> resolverUsandoLocal(int conflitoId) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponivel para resolver o conflito.');
    }

    final conflito = await _buscarConflitoPendente(conflitoId);
    final empresaId = (conflito['empresa_id'] ?? '').toString();
    final entidade = (conflito['entidade'] ?? '').toString();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString();

    final config = _config(entidade);
    final local = await _localPorId(config.local, localId);
    final payload = await _payloadLocal(
      empresaId: empresaId,
      entidade: entidade,
      local: local,
    );

    final remoto = await client
        .from(config.remota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em')
        .single();

    await _salvarMapa(
      tabela: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hash(entidade, local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
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
    final empresaId = (conflito['empresa_id'] ?? '').toString();
    final entidade = (conflito['entidade'] ?? '').toString();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString();

    final config = _config(entidade);
    final remotoRaw = await client
        .from(config.remota)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError('Registro remoto nao encontrado.');
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);

    if (_texto(remoto['excluido_em']).isNotEmpty) {
      throw StateError(
        'Registro remoto foi excluido. Exclusao financeira exige revisao manual.',
      );
    }

    await _aplicarRemoto(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remoto: remoto,
    );

    final localAtual = await _localPorId(config.local, localId);

    await _salvarMapa(
      tabela: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hash(entidade, localAtual),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId: conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versao da nuvem aplicada diretamente no SQLite.',
    );
  }

  static const List<String> _entidadesMutaveis = <String>[
    'plano',
    'conta',
    'fornecedor',
    'regra_taxa',
    'pagamento',
    'movimento',
  ];

  _ConfigFinanceiro _config(String entidade) {
    switch (entidade) {
      case 'plano':
        return const _ConfigFinanceiro(
          local: 'financeiro_plano_contas',
          remota: 'imperium_financeiro_plano_contas',
          mapa: 'imperium_sync_financeiro_plano_contas',
        );
      case 'conta':
        return const _ConfigFinanceiro(
          local: 'financeiro_contas',
          remota: 'imperium_financeiro_contas',
          mapa: 'imperium_sync_financeiro_contas',
        );
      case 'fornecedor':
        return const _ConfigFinanceiro(
          local: 'fornecedores',
          remota: 'imperium_financeiro_fornecedores',
          mapa: 'imperium_sync_financeiro_fornecedores',
        );
      case 'regra_taxa':
        return const _ConfigFinanceiro(
          local: 'financeiro_regras_taxa',
          remota: 'imperium_financeiro_regras_taxa',
          mapa: 'imperium_sync_financeiro_regras_taxa',
        );
      case 'transferencia':
        return const _ConfigFinanceiro(
          local: 'financeiro_transferencias',
          remota: 'imperium_financeiro_transferencias',
          mapa: 'imperium_sync_financeiro_transferencias',
        );
      case 'pagamento':
        return const _ConfigFinanceiro(
          local: 'ordem_servico_pagamentos',
          remota: 'imperium_financeiro_pagamentos_os',
          mapa: 'imperium_sync_financeiro_pagamentos',
        );
      case 'movimento':
        return const _ConfigFinanceiro(
          local: 'movimentos_financeiros',
          remota: 'imperium_financeiro_movimentos',
          mapa: 'imperium_sync_financeiro_movimentos',
        );
      default:
        throw StateError('Entidade financeira invalida: $entidade');
    }
  }

  Future<void> _reconciliarEntidade({
    required String empresaId,
    required String entidade,
  }) async {
    final client = _client;
    if (client == null) return;

    final config = _config(entidade);
    final database = await _appDatabase.database;

    final mapas = await database.query(
      config.mapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      final remotoId = _texto(mapa['remoto_id']);
      if (localId <= 0 || remotoId.isEmpty) continue;

      if (await _conflitoPendente(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final locais = await database.query(
        config.local,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (locais.isEmpty) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_local_ausente',
          mapa: mapa,
          local: const <String, Object?>{},
          localHashAtual: '',
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final local = locais.first;
      final localHashAtual = _hash(entidade, local);
      final localHashBase = _texto(mapa['local_hash']);
      final localMudou = localHashAtual != localHashBase;

      final remotoRaw = await client
          .from(config.remota)
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
          motivo: 'registro_remoto_ausente',
          mapa: mapa,
          local: local,
          localHashAtual: localHashAtual,
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoBase = _texto(mapa['remoto_atualizado_em']);
      final remotoAtual = _texto(remoto['atualizado_em']);
      final remotoExcluido = _texto(remoto['excluido_em']).isNotEmpty;
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
          local: local,
          localHashAtual: localHashAtual,
          remoto: remoto,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        if (remotoExcluido) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'exclusao_remota_financeira_requer_revisao',
            mapa: mapa,
            local: local,
            localHashAtual: localHashAtual,
            remoto: remoto,
          );
          continue;
        }

        try {
          await _aplicarRemoto(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remoto: remoto,
          );
        } on _DependenciaFinanceiraV2Pendente {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'dependencia_remota_pendente',
            mapa: mapa,
            local: local,
            localHashAtual: localHashAtual,
            remoto: remoto,
          );
          continue;
        }

        final atualizado = await _localPorId(config.local, localId);

        await _salvarMapa(
          tabela: config.mapa,
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: _hash(entidade, atualizado),
          remotoAtualizadoEm: remotoAtual,
        );
      }
    }
  }

  Future<void> _publicarFornecedores(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('fornecedores', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_fornecedores',
        empresaId: empresaId,
        localId: localId,
      );
      final hash = _hash('fornecedor', local);

      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      await _publicarComplemento(
        empresaId: empresaId,
        entidade: 'fornecedor',
        localId: localId,
        local: local,
        mapa: mapa,
        hash: hash,
      );
    }
  }

  Future<void> _publicarRegrasTaxa(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_regras_taxa',
      orderBy: 'prioridade ASC, id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final contaLocalId = _int(local['conta_id']);
      if (contaLocalId > 0) {
        final contaRemota = await _remotoPorLocal(
          tabela: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          localId: contaLocalId,
        );
        if (contaRemota == null) continue;
      }

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_regras_taxa',
        empresaId: empresaId,
        localId: localId,
      );
      final hash = _hash('regra_taxa', local);

      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      await _publicarComplemento(
        empresaId: empresaId,
        entidade: 'regra_taxa',
        localId: localId,
        local: local,
        mapa: mapa,
        hash: hash,
      );
    }
  }

  Future<void> _publicarTransferencias(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_transferencias',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final origemRemota = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: _int(local['conta_origem_id']),
      );
      final destinoRemoto = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: _int(local['conta_destino_id']),
      );

      if (origemRemota == null || destinoRemoto == null) continue;

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_transferencias',
        empresaId: empresaId,
        localId: localId,
      );
      final hash = _hash('transferencia', local);

      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      await _publicarComplemento(
        empresaId: empresaId,
        entidade: 'transferencia',
        localId: localId,
        local: local,
        mapa: mapa,
        hash: hash,
      );
    }
  }

  Future<void> _publicarComplemento({
    required String empresaId,
    required String entidade,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final config = _config(entidade);
    final payload = await _payloadLocal(
      empresaId: empresaId,
      entidade: entidade,
      local: local,
    );

    final remotoId = _texto(mapa?['remoto_id']);
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from(config.remota)
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from(config.remota)
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _vincularRegrasNosPagamentos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final pagamentos = await database.query(
      'ordem_servico_pagamentos',
      columns: ['id', 'regra_taxa_id'],
      orderBy: 'id ASC',
    );

    for (final pagamento in pagamentos) {
      final localId = _int(pagamento['id']);
      if (localId <= 0) continue;

      final pagamentoRemoto = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_pagamentos',
        empresaId: empresaId,
        localId: localId,
      );
      if (pagamentoRemoto == null) continue;

      final regraLocalId = _int(pagamento['regra_taxa_id']);
      final regraRemota = regraLocalId <= 0
          ? null
          : await _remotoPorLocal(
              tabela: 'imperium_sync_financeiro_regras_taxa',
              empresaId: empresaId,
              localId: regraLocalId,
            );

      if (regraLocalId > 0 && regraRemota == null) continue;

      final resposta = await client
          .from('imperium_financeiro_pagamentos_os')
          .update({'regra_taxa_id': regraRemota})
          .eq('empresa_id', empresaId)
          .eq('id', pagamentoRemoto)
          .select('atualizado_em')
          .single();

      await _atualizarTimestampMapa(
        tabela: 'imperium_sync_financeiro_pagamentos',
        empresaId: empresaId,
        localId: localId,
        remotoAtualizadoEm: resposta['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _vincularComplementosNosMovimentos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final movimentos = await database.query(
      'movimentos_financeiros',
      columns: ['id', 'fornecedor_id', 'transferencia_id'],
      orderBy: 'id ASC',
    );

    for (final movimento in movimentos) {
      final localId = _int(movimento['id']);
      if (localId <= 0) continue;

      final movimentoRemoto = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_movimentos',
        empresaId: empresaId,
        localId: localId,
      );
      if (movimentoRemoto == null) continue;

      final fornecedorLocalId = _int(movimento['fornecedor_id']);
      final transferenciaLocalId = _int(movimento['transferencia_id']);

      final fornecedorRemoto = fornecedorLocalId <= 0
          ? null
          : await _remotoPorLocal(
              tabela: 'imperium_sync_financeiro_fornecedores',
              empresaId: empresaId,
              localId: fornecedorLocalId,
            );

      final transferenciaRemota = transferenciaLocalId <= 0
          ? null
          : await _remotoPorLocal(
              tabela: 'imperium_sync_financeiro_transferencias',
              empresaId: empresaId,
              localId: transferenciaLocalId,
            );

      if (fornecedorLocalId > 0 && fornecedorRemoto == null) continue;
      if (transferenciaLocalId > 0 && transferenciaRemota == null) continue;

      final resposta = await client
          .from('imperium_financeiro_movimentos')
          .update({
            'fornecedor_id': fornecedorRemoto,
            'transferencia_id': transferenciaRemota,
          })
          .eq('empresa_id', empresaId)
          .eq('id', movimentoRemoto)
          .select('atualizado_em')
          .single();

      await _atualizarTimestampMapa(
        tabela: 'imperium_sync_financeiro_movimentos',
        empresaId: empresaId,
        localId: localId,
        remotoAtualizadoEm: resposta['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarPlanosNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_plano_contas')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('ordem')
        .order('codigo');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_financeiro_plano_contas',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      if (await _reconstruirMapaOrigem(
        empresaId: empresaId,
        entidade: 'plano',
        remoto: remoto,
      )) {
        continue;
      }

      final codigo = _texto(remoto['codigo']);
      final existente = await database.query(
        'financeiro_plano_contas',
        where: 'codigo = ?',
        whereArgs: [codigo],
        limit: 1,
      );

      int localId;

      if (existente.isNotEmpty) {
        localId = _int(existente.first['id']);
      } else {
        int? parentId;
        final parentCodigo = _texto(remoto['parent_codigo']);
        if (parentCodigo.isNotEmpty) {
          final parent = await database.query(
            'financeiro_plano_contas',
            columns: ['id'],
            where: 'codigo = ?',
            whereArgs: [parentCodigo],
            limit: 1,
          );
          if (parent.isNotEmpty) parentId = _int(parent.first['id']);
        }

        localId = await database.insert('financeiro_plano_contas', {
          'codigo': codigo,
          'nome': _texto(remoto['nome']),
          'tipo': _texto(remoto['tipo']),
          'natureza': _texto(remoto['natureza']),
          'grupo_dre': _textoPadrao(remoto['grupo_dre'], 'Não DRE'),
          'parent_id': parentId,
          'ativo': remoto['ativo'] == true ? 1 : 0,
          'ordem': _int(remoto['ordem']),
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
          'atualizado_em': _textoPreferido(
            remoto['origem_atualizado_em'],
            remoto['atualizado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final local = await _localPorId('financeiro_plano_contas', localId);
      await _salvarMapa(
        tabela: 'imperium_sync_financeiro_plano_contas',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hash('plano', local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarContasNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_contas')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_financeiro_contas',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      if (await _reconstruirMapaOrigem(
        empresaId: empresaId,
        entidade: 'conta',
        remoto: remoto,
      )) {
        continue;
      }

      final nome = _texto(remoto['nome']);
      final existente = await database.query(
        'financeiro_contas',
        where: 'nome = ?',
        whereArgs: [nome],
        limit: 1,
      );

      int localId;

      if (existente.isNotEmpty) {
        localId = _int(existente.first['id']);
      } else {
        localId = await database.insert('financeiro_contas', {
          'nome': nome,
          'tipo': _textoPadrao(remoto['tipo'], 'Conta bancária'),
          'instituicao': _texto(remoto['instituicao']),
          'saldo_inicial': _double(remoto['saldo_inicial']),
          'data_saldo_inicial': _textoNulo(remoto['data_saldo_inicial']),
          'observacoes': _texto(remoto['observacoes']),
          'ativo': remoto['ativo'] == true ? 1 : 0,
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
          'atualizado_em': _textoPreferido(
            remoto['origem_atualizado_em'],
            remoto['atualizado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final local = await _localPorId('financeiro_contas', localId);
      await _salvarMapa(
        tabela: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hash('conta', local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarFornecedoresNovos(String empresaId) async {
    await _baixarEntidadeSimples(empresaId: empresaId, entidade: 'fornecedor');
  }

  Future<void> _baixarRegrasNovas(String empresaId) async {
    await _baixarEntidadeSimples(empresaId: empresaId, entidade: 'regra_taxa');
  }

  Future<void> _baixarTransferenciasNovas(String empresaId) async {
    await _baixarEntidadeSimples(
      empresaId: empresaId,
      entidade: 'transferencia',
    );
  }

  Future<void> _baixarPagamentosNovos(String empresaId) async {
    await _baixarEntidadeSimples(empresaId: empresaId, entidade: 'pagamento');
  }

  Future<void> _baixarMovimentosNovos(String empresaId) async {
    await _baixarEntidadeSimples(empresaId: empresaId, entidade: 'movimento');
  }

  Future<void> _baixarEntidadeSimples({
    required String empresaId,
    required String entidade,
  }) async {
    final client = _client;
    if (client == null) return;

    final config = _config(entidade);
    final remotos = await client
        .from(config.remota)
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: config.mapa,
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      if (await _reconstruirMapaOrigem(
        empresaId: empresaId,
        entidade: entidade,
        remoto: remoto,
      )) {
        continue;
      }

      try {
        final localId = await _inserirRemotoNovo(
          empresaId: empresaId,
          entidade: entidade,
          remoto: remoto,
        );

        if (localId == null || localId <= 0) continue;

        final local = await _localPorId(config.local, localId);

        await _salvarMapa(
          tabela: config.mapa,
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: _hash(entidade, local),
          remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        );
      } on _DependenciaFinanceiraV2Pendente {
        // Dependencia chega em outro passo/sync; nao cria registro parcial.
        continue;
      }
    }
  }

  Future<int?> _inserirRemotoNovo({
    required String empresaId,
    required String entidade,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;

    switch (entidade) {
      case 'fornecedor':
        return database.insert('fornecedores', {
          'nome': _texto(remoto['nome']),
          'documento': _texto(remoto['documento']),
          'telefone': _texto(remoto['telefone']),
          'email': _texto(remoto['email']),
          'endereco': _texto(remoto['endereco']),
          'cidade': _texto(remoto['cidade']),
          'estado': _texto(remoto['estado']),
          'categoria': _texto(remoto['categoria']),
          'observacoes': _texto(remoto['observacoes']),
          'ativo': remoto['ativo'] == true ? 1 : 0,
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
          'atualizado_em': _textoPreferido(
            remoto['origem_atualizado_em'],
            remoto['atualizado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);

      case 'regra_taxa':
        final contaLocalId = await _localPorRemotoObrigatorioOuNulo(
          tabelaMapa: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['conta_id']),
        );

        return database.insert('financeiro_regras_taxa', {
          'nome': _texto(remoto['nome']),
          'forma_pagamento': _texto(remoto['forma_pagamento']),
          'parcelas': _int(remoto['parcelas']) <= 0
              ? 1
              : _int(remoto['parcelas']),
          'conta_id': contaLocalId,
          'taxa_percentual': _double(remoto['taxa_percentual']),
          'taxa_fixa': _double(remoto['taxa_fixa']),
          'prazo_recebimento_dias': _int(remoto['prazo_recebimento_dias']),
          'prioridade': _int(remoto['prioridade']),
          'repassar_cliente': remoto['repassar_cliente'] == true ? 1 : 0,
          'observacoes': _texto(remoto['observacoes']),
          'ativo': remoto['ativo'] == true ? 1 : 0,
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
          'atualizado_em': _textoPreferido(
            remoto['origem_atualizado_em'],
            remoto['atualizado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);

      case 'transferencia':
        final origemLocal = await _localPorRemotoObrigatorio(
          tabelaMapa: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          remotoId: _texto(remoto['conta_origem_id']),
        );
        final destinoLocal = await _localPorRemotoObrigatorio(
          tabelaMapa: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          remotoId: _texto(remoto['conta_destino_id']),
        );

        return database.insert('financeiro_transferencias', {
          'conta_origem_id': origemLocal,
          'conta_destino_id': destinoLocal,
          'valor': _double(remoto['valor']),
          'data': _texto(remoto['data']),
          'descricao': _texto(remoto['descricao']),
          'observacoes': _texto(remoto['observacoes']),
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);

      case 'pagamento':
        final ordemLocal = await _localPorRemotoObrigatorio(
          tabelaMapa: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          remotoId: _texto(remoto['ordem_servico_id']),
        );
        final regraLocal = await _localPorRemotoObrigatorioOuNulo(
          tabelaMapa: 'imperium_sync_financeiro_regras_taxa',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['regra_taxa_id']),
        );

        // IMPORTANTE: insert direto, sem PagamentoRepository.
        return database.insert('ordem_servico_pagamentos', {
          'ordem_servico_id': ordemLocal,
          'status': _textoPadrao(remoto['status'], 'Pago'),
          'valor': _double(remoto['valor']),
          'forma_pagamento': _texto(remoto['forma_pagamento']),
          'data_pagamento': _textoNulo(remoto['data_pagamento']),
          'parcela_numero': _intNulo(remoto['parcela_numero']),
          'total_parcelas': _intNulo(remoto['total_parcelas']),
          'vencimento': _textoNulo(remoto['vencimento']),
          'comprovante_caminho': null,
          'observacoes': _texto(remoto['observacoes']),
          'taxa_percentual': _doubleNulo(remoto['taxa_percentual']),
          'taxa_operacao': _double(remoto['taxa_operacao']),
          'valor_liquido': _double(remoto['valor_liquido']),
          'regra_taxa_id': regraLocal,
          'parcelas_taxa': _int(remoto['parcelas_taxa']) <= 0
              ? 1
              : _int(remoto['parcelas_taxa']),
          'estornado_em': _textoNulo(remoto['estornado_em']),
          'motivo_estorno': _texto(remoto['motivo_estorno']),
          'criado_em': _textoPreferido(
            remoto['origem_criado_em'],
            remoto['criado_em'],
          ),
          'atualizado_em': _textoPreferido(
            remoto['origem_atualizado_em'],
            remoto['atualizado_em'],
          ),
        }, conflictAlgorithm: ConflictAlgorithm.abort);

      case 'movimento':
        final refs = await _refsMovimentoRemoto(
          empresaId: empresaId,
          remoto: remoto,
        );

        // IMPORTANTE: insert direto, sem FinanceiroRepository.
        return database.insert('movimentos_financeiros', {
          'tipo': _texto(remoto['tipo']),
          'descricao': _texto(remoto['descricao']),
          'valor': _double(remoto['valor']),
          'forma_pagamento': _textoNulo(remoto['forma_pagamento']),
          'data': _texto(remoto['data']),
          ...refs,
          'nota_fiscal_id': null,
          'parcela_numero': _intNulo(remoto['parcela_numero']),
          'total_parcelas': _int(remoto['total_parcelas']) <= 0
              ? 1
              : _int(remoto['total_parcelas']),
          'natureza': _textoPadrao(remoto['natureza'], 'Não classificado'),
          'origem': _textoPadrao(remoto['origem'], 'Manual'),
          'status': _textoPadrao(remoto['status'], 'Realizado'),
          'data_competencia': _textoNulo(remoto['data_competencia']),
          'data_vencimento': _textoNulo(remoto['data_vencimento']),
          'data_pagamento': _textoNulo(remoto['data_pagamento']),
          'numero_documento': _texto(remoto['numero_documento']),
          'observacoes': _texto(remoto['observacoes']),
          'impacta_dre': remoto['impacta_dre'] == true ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

      default:
        throw StateError('Download nao implementado para $entidade');
    }
  }

  Future<Map<String, Object?>> _payloadLocal({
    required String empresaId,
    required String entidade,
    required Map<String, Object?> local,
  }) async {
    switch (entidade) {
      case 'plano':
        String? parentCodigo;
        final parentId = _int(local['parent_id']);

        if (parentId > 0) {
          final database = await _appDatabase.database;
          final parent = await database.query(
            'financeiro_plano_contas',
            columns: ['codigo'],
            where: 'id = ?',
            whereArgs: [parentId],
            limit: 1,
          );
          if (parent.isNotEmpty) {
            parentCodigo = _textoNulo(parent.first['codigo']);
          }
        }

        return <String, Object?>{
          'empresa_id': empresaId,
          'codigo': _texto(local['codigo']),
          'nome': _texto(local['nome']),
          'tipo': _texto(local['tipo']),
          'natureza': _texto(local['natureza']),
          'grupo_dre': _textoPadrao(local['grupo_dre'], 'Não DRE'),
          'parent_codigo': parentCodigo,
          'ativo': _int(local['ativo']) != 0,
          'ordem': _int(local['ordem']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'conta':
        return <String, Object?>{
          'empresa_id': empresaId,
          'nome': _texto(local['nome']),
          'tipo': _textoPadrao(local['tipo'], 'Conta bancária'),
          'instituicao': _texto(local['instituicao']),
          'saldo_inicial': _double(local['saldo_inicial']),
          'data_saldo_inicial': _textoNulo(local['data_saldo_inicial']),
          'observacoes': _texto(local['observacoes']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'fornecedor':
        return <String, Object?>{
          'empresa_id': empresaId,
          'nome': _texto(local['nome']),
          'documento': _texto(local['documento']),
          'telefone': _texto(local['telefone']),
          'email': _texto(local['email']),
          'endereco': _texto(local['endereco']),
          'cidade': _texto(local['cidade']),
          'estado': _texto(local['estado']),
          'categoria': _texto(local['categoria']),
          'observacoes': _texto(local['observacoes']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'regra_taxa':
        final contaLocalId = _int(local['conta_id']);
        final contaRemota = contaLocalId <= 0
            ? null
            : await _remotoPorLocalObrigatorio(
                tabela: 'imperium_sync_financeiro_contas',
                empresaId: empresaId,
                localId: contaLocalId,
              );

        return <String, Object?>{
          'empresa_id': empresaId,
          'nome': _texto(local['nome']),
          'forma_pagamento': _texto(local['forma_pagamento']),
          'parcelas': _int(local['parcelas']) <= 0
              ? 1
              : _int(local['parcelas']),
          'conta_id': contaRemota,
          'origem_conta_local_id': _intNulo(local['conta_id']),
          'taxa_percentual': _double(local['taxa_percentual']),
          'taxa_fixa': _double(local['taxa_fixa']),
          'prazo_recebimento_dias': _int(local['prazo_recebimento_dias']),
          'prioridade': _int(local['prioridade']),
          'repassar_cliente': _int(local['repassar_cliente']) != 0,
          'observacoes': _texto(local['observacoes']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'transferencia':
        final origemRemota = await _remotoPorLocalObrigatorio(
          tabela: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          localId: _int(local['conta_origem_id']),
        );
        final destinoRemota = await _remotoPorLocalObrigatorio(
          tabela: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          localId: _int(local['conta_destino_id']),
        );

        return <String, Object?>{
          'empresa_id': empresaId,
          'conta_origem_id': origemRemota,
          'conta_destino_id': destinoRemota,
          'valor': _double(local['valor']),
          'data': _texto(local['data']),
          'descricao': _texto(local['descricao']),
          'observacoes': _texto(local['observacoes']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'excluido_em': null,
        };

      case 'pagamento':
        final ordemRemota = await _remotoPorLocalObrigatorio(
          tabela: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          localId: _int(local['ordem_servico_id']),
        );

        final regraLocalId = _int(local['regra_taxa_id']);
        final regraRemota = regraLocalId <= 0
            ? null
            : await _remotoPorLocalObrigatorio(
                tabela: 'imperium_sync_financeiro_regras_taxa',
                empresaId: empresaId,
                localId: regraLocalId,
              );

        return <String, Object?>{
          'empresa_id': empresaId,
          'ordem_servico_id': ordemRemota,
          'status': _textoPadrao(local['status'], 'Pago'),
          'valor': _double(local['valor']),
          'forma_pagamento': _texto(local['forma_pagamento']),
          'data_pagamento': _textoNulo(local['data_pagamento']),
          'parcela_numero': _intNulo(local['parcela_numero']),
          'total_parcelas': _intNulo(local['total_parcelas']),
          'vencimento': _textoNulo(local['vencimento']),
          'comprovante_origem_caminho': _textoNulo(
            local['comprovante_caminho'],
          ),
          'observacoes': _texto(local['observacoes']),
          'taxa_percentual': _doubleNulo(local['taxa_percentual']),
          'taxa_operacao': _double(local['taxa_operacao']),
          'valor_liquido': _double(local['valor_liquido']),
          'origem_regra_taxa_local_id': _intNulo(local['regra_taxa_id']),
          'regra_taxa_id': regraRemota,
          'parcelas_taxa': _int(local['parcelas_taxa']) <= 0
              ? 1
              : _int(local['parcelas_taxa']),
          'estornado_em': _textoNulo(local['estornado_em']),
          'motivo_estorno': _texto(local['motivo_estorno']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'movimento':
        final refs = await _refsMovimentoLocal(
          empresaId: empresaId,
          local: local,
        );

        return <String, Object?>{
          'empresa_id': empresaId,
          'tipo': _texto(local['tipo']),
          'descricao': _texto(local['descricao']),
          'valor': _double(local['valor']),
          'forma_pagamento': _textoNulo(local['forma_pagamento']),
          'data': _texto(local['data']),
          ...refs,
          'origem_cliente_local_id': _intNulo(local['cliente_id']),
          'origem_agendamento_local_id': _intNulo(local['agendamento_id']),
          'origem_ordem_servico_local_id': _intNulo(local['ordem_servico_id']),
          'origem_pagamento_local_id': _intNulo(local['pagamento_id']),
          'origem_plano_conta_local_id': _intNulo(local['plano_conta_id']),
          'origem_conta_local_id': _intNulo(local['conta_id']),
          'origem_fornecedor_local_id': _intNulo(local['fornecedor_id']),
          'origem_transferencia_local_id': _intNulo(local['transferencia_id']),
          'origem_nota_fiscal_local_id': _intNulo(local['nota_fiscal_id']),
          'parcela_numero': _intNulo(local['parcela_numero']),
          'total_parcelas': _int(local['total_parcelas']) <= 0
              ? 1
              : _int(local['total_parcelas']),
          'natureza': _textoPadrao(local['natureza'], 'Não classificado'),
          'origem': _textoPadrao(local['origem'], 'Manual'),
          'status': _textoPadrao(local['status'], 'Realizado'),
          'data_competencia': _textoNulo(local['data_competencia']),
          'data_vencimento': _textoNulo(local['data_vencimento']),
          'data_pagamento': _textoNulo(local['data_pagamento']),
          'numero_documento': _texto(local['numero_documento']),
          'observacoes': _texto(local['observacoes']),
          'impacta_dre': _int(local['impacta_dre']) != 0,
          'excluido_em': null,
        };

      default:
        throw StateError('Payload nao implementado para $entidade');
    }
  }

  Future<void> _aplicarRemoto({
    required String empresaId,
    required String entidade,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;

    switch (entidade) {
      case 'plano':
        int? parentId;
        final parentCodigo = _texto(remoto['parent_codigo']);
        if (parentCodigo.isNotEmpty) {
          final parent = await database.query(
            'financeiro_plano_contas',
            columns: ['id'],
            where: 'codigo = ?',
            whereArgs: [parentCodigo],
            limit: 1,
          );
          if (parent.isNotEmpty) parentId = _int(parent.first['id']);
        }

        await database.update(
          'financeiro_plano_contas',
          {
            'codigo': _texto(remoto['codigo']),
            'nome': _texto(remoto['nome']),
            'tipo': _texto(remoto['tipo']),
            'natureza': _texto(remoto['natureza']),
            'grupo_dre': _textoPadrao(remoto['grupo_dre'], 'Não DRE'),
            'parent_id': parentId,
            'ativo': remoto['ativo'] == true ? 1 : 0,
            'ordem': _int(remoto['ordem']),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'conta':
        await database.update(
          'financeiro_contas',
          {
            'nome': _texto(remoto['nome']),
            'tipo': _textoPadrao(remoto['tipo'], 'Conta bancária'),
            'instituicao': _texto(remoto['instituicao']),
            'saldo_inicial': _double(remoto['saldo_inicial']),
            'data_saldo_inicial': _textoNulo(remoto['data_saldo_inicial']),
            'observacoes': _texto(remoto['observacoes']),
            'ativo': remoto['ativo'] == true ? 1 : 0,
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'fornecedor':
        await database.update(
          'fornecedores',
          {
            'nome': _texto(remoto['nome']),
            'documento': _texto(remoto['documento']),
            'telefone': _texto(remoto['telefone']),
            'email': _texto(remoto['email']),
            'endereco': _texto(remoto['endereco']),
            'cidade': _texto(remoto['cidade']),
            'estado': _texto(remoto['estado']),
            'categoria': _texto(remoto['categoria']),
            'observacoes': _texto(remoto['observacoes']),
            'ativo': remoto['ativo'] == true ? 1 : 0,
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'regra_taxa':
        final contaLocal = await _localPorRemotoObrigatorioOuNulo(
          tabelaMapa: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['conta_id']),
        );

        await database.update(
          'financeiro_regras_taxa',
          {
            'nome': _texto(remoto['nome']),
            'forma_pagamento': _texto(remoto['forma_pagamento']),
            'parcelas': _int(remoto['parcelas']) <= 0
                ? 1
                : _int(remoto['parcelas']),
            'conta_id': contaLocal,
            'taxa_percentual': _double(remoto['taxa_percentual']),
            'taxa_fixa': _double(remoto['taxa_fixa']),
            'prazo_recebimento_dias': _int(remoto['prazo_recebimento_dias']),
            'prioridade': _int(remoto['prioridade']),
            'repassar_cliente': remoto['repassar_cliente'] == true ? 1 : 0,
            'observacoes': _texto(remoto['observacoes']),
            'ativo': remoto['ativo'] == true ? 1 : 0,
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'pagamento':
        final ordemLocal = await _localPorRemotoObrigatorio(
          tabelaMapa: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          remotoId: _texto(remoto['ordem_servico_id']),
        );
        final regraLocal = await _localPorRemotoObrigatorioOuNulo(
          tabelaMapa: 'imperium_sync_financeiro_regras_taxa',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['regra_taxa_id']),
        );

        await database.update(
          'ordem_servico_pagamentos',
          {
            'ordem_servico_id': ordemLocal,
            'status': _textoPadrao(remoto['status'], 'Pago'),
            'valor': _double(remoto['valor']),
            'forma_pagamento': _texto(remoto['forma_pagamento']),
            'data_pagamento': _textoNulo(remoto['data_pagamento']),
            'parcela_numero': _intNulo(remoto['parcela_numero']),
            'total_parcelas': _intNulo(remoto['total_parcelas']),
            'vencimento': _textoNulo(remoto['vencimento']),
            'observacoes': _texto(remoto['observacoes']),
            'taxa_percentual': _doubleNulo(remoto['taxa_percentual']),
            'taxa_operacao': _double(remoto['taxa_operacao']),
            'valor_liquido': _double(remoto['valor_liquido']),
            'regra_taxa_id': regraLocal,
            'parcelas_taxa': _int(remoto['parcelas_taxa']) <= 0
                ? 1
                : _int(remoto['parcelas_taxa']),
            'estornado_em': _textoNulo(remoto['estornado_em']),
            'motivo_estorno': _texto(remoto['motivo_estorno']),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'movimento':
        final refs = await _refsMovimentoRemoto(
          empresaId: empresaId,
          remoto: remoto,
        );

        await database.update(
          'movimentos_financeiros',
          {
            'tipo': _texto(remoto['tipo']),
            'descricao': _texto(remoto['descricao']),
            'valor': _double(remoto['valor']),
            'forma_pagamento': _textoNulo(remoto['forma_pagamento']),
            'data': _texto(remoto['data']),
            ...refs,
            'parcela_numero': _intNulo(remoto['parcela_numero']),
            'total_parcelas': _int(remoto['total_parcelas']) <= 0
                ? 1
                : _int(remoto['total_parcelas']),
            'natureza': _textoPadrao(remoto['natureza'], 'Não classificado'),
            'origem': _textoPadrao(remoto['origem'], 'Manual'),
            'status': _textoPadrao(remoto['status'], 'Realizado'),
            'data_competencia': _textoNulo(remoto['data_competencia']),
            'data_vencimento': _textoNulo(remoto['data_vencimento']),
            'data_pagamento': _textoNulo(remoto['data_pagamento']),
            'numero_documento': _texto(remoto['numero_documento']),
            'observacoes': _texto(remoto['observacoes']),
            'impacta_dre': remoto['impacta_dre'] == true ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      default:
        throw StateError('Aplicacao remota nao implementada para $entidade');
    }
  }

  Future<Map<String, Object?>> _refsMovimentoLocal({
    required String empresaId,
    required Map<String, Object?> local,
  }) async {
    Future<String?> ref(String tabela, Object? value) async {
      final localId = _int(value);
      if (localId <= 0) return null;
      return _remotoPorLocalObrigatorio(
        tabela: tabela,
        empresaId: empresaId,
        localId: localId,
      );
    }

    return <String, Object?>{
      'cliente_id': await ref('imperium_sync_clientes', local['cliente_id']),
      'agendamento_id': await ref(
        'imperium_sync_agendamentos',
        local['agendamento_id'],
      ),
      'ordem_servico_id': await ref(
        'imperium_sync_ordens_servico',
        local['ordem_servico_id'],
      ),
      'pagamento_id': await ref(
        'imperium_sync_financeiro_pagamentos',
        local['pagamento_id'],
      ),
      'plano_conta_id': await ref(
        'imperium_sync_financeiro_plano_contas',
        local['plano_conta_id'],
      ),
      'conta_id': await ref(
        'imperium_sync_financeiro_contas',
        local['conta_id'],
      ),
      'fornecedor_id': await ref(
        'imperium_sync_financeiro_fornecedores',
        local['fornecedor_id'],
      ),
      'transferencia_id': await ref(
        'imperium_sync_financeiro_transferencias',
        local['transferencia_id'],
      ),
    };
  }

  Future<Map<String, Object?>> _refsMovimentoRemoto({
    required String empresaId,
    required Map<String, dynamic> remoto,
  }) async {
    Future<int?> ref(String tabela, Object? value) {
      return _localPorRemotoObrigatorioOuNulo(
        tabelaMapa: tabela,
        empresaId: empresaId,
        remotoId: _textoNulo(value),
      );
    }

    return <String, Object?>{
      'cliente_id': await ref('imperium_sync_clientes', remoto['cliente_id']),
      'agendamento_id': await ref(
        'imperium_sync_agendamentos',
        remoto['agendamento_id'],
      ),
      'ordem_servico_id': await ref(
        'imperium_sync_ordens_servico',
        remoto['ordem_servico_id'],
      ),
      'pagamento_id': await ref(
        'imperium_sync_financeiro_pagamentos',
        remoto['pagamento_id'],
      ),
      'plano_conta_id': await ref(
        'imperium_sync_financeiro_plano_contas',
        remoto['plano_conta_id'],
      ),
      'conta_id': await ref(
        'imperium_sync_financeiro_contas',
        remoto['conta_id'],
      ),
      'fornecedor_id': await ref(
        'imperium_sync_financeiro_fornecedores',
        remoto['fornecedor_id'],
      ),
      'transferencia_id': await ref(
        'imperium_sync_financeiro_transferencias',
        remoto['transferencia_id'],
      ),
    };
  }

  Future<bool> _reconstruirMapaOrigem({
    required String empresaId,
    required String entidade,
    required Map<String, dynamic> remoto,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return false;

    final dispositivoAtual = await _dispositivoId();
    if (origemDispositivo != dispositivoAtual) return false;

    final config = _config(entidade);
    final database = await _appDatabase.database;
    final local = await database.query(
      config.local,
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    if (local.isEmpty) return false;

    await _salvarMapa(
      tabela: config.mapa,
      empresaId: empresaId,
      localId: origemLocalId,
      remotoId: _texto(remoto['id']),
      localHash: _hash(entidade, local.first),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    return true;
  }

  Future<bool> _conflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_financeiro_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
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
    required Map<String, Object?> mapa,
    required Map<String, Object?> local,
    required String localHashAtual,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;

    final existente = await database.query(
      'imperium_sync_financeiro_conflitos',
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
      'local_hash_base': _texto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _texto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _texto(remoto['atualizado_em']),
      'local_json': jsonEncode(local),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'resolucao': null,
      'resolucao_detalhe': null,
      'detectado_em': DateTime.now().toIso8601String(),
      'resolvido_em': null,
    };

    if (existente.isEmpty) {
      await database.insert(
        'imperium_sync_financeiro_conflitos',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await database.update(
        'imperium_sync_financeiro_conflitos',
        dados,
        where: 'id = ?',
        whereArgs: [existente.first['id']],
      );
    }
  }

  Future<Map<String, Object?>> _buscarConflitoPendente(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito financeiro pendente nao encontrado.');
    }

    return rows.first;
  }

  Future<void> _encerrarConflito({
    required int conflitoId,
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'imperium_sync_financeiro_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [conflitoId],
    );
  }

  Future<Map<String, Object?>> _localPorId(String tabela, int localId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Registro local nao encontrado em $tabela.');
    }

    return rows.first;
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
    if (mapa == null) return null;

    final remoto = _texto(mapa['remoto_id']);
    return remoto.isEmpty ? null : remoto;
  }

  Future<String> _remotoPorLocalObrigatorio({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final remoto = await _remotoPorLocal(
      tabela: tabela,
      empresaId: empresaId,
      localId: localId,
    );

    if (remoto == null) throw _DependenciaFinanceiraV2Pendente();
    return remoto;
  }

  Future<int> _localPorRemotoObrigatorio({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    final mapa = await _mapaPorRemoto(
      tabela: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );

    if (mapa == null) throw _DependenciaFinanceiraV2Pendente();

    final localId = _int(mapa['local_id']);
    if (localId <= 0) throw _DependenciaFinanceiraV2Pendente();

    return localId;
  }

  Future<int?> _localPorRemotoObrigatorioOuNulo({
    required String tabelaMapa,
    required String empresaId,
    required String? remotoId,
  }) async {
    if (remotoId == null || remotoId.trim().isEmpty) return null;

    return _localPorRemotoObrigatorio(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
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

  Future<void> _atualizarTimestampMapa({
    required String tabela,
    required String empresaId,
    required int localId,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      tabela,
      {'remoto_atualizado_em': remotoAtualizadoEm},
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

    if (rows.isEmpty) {
      throw StateError('Configuracao de sincronizacao nao encontrada.');
    }

    final id = _texto(rows.first['dispositivo_id']);
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo nao encontrado.');
    }

    return id;
  }

  String _hash(String entidade, Map<String, Object?> local) {
    switch (entidade) {
      case 'plano':
        return _sha(<Object?>[
          local['codigo'],
          local['nome'],
          local['tipo'],
          local['natureza'],
          local['grupo_dre'],
          _intNulo(local['parent_id']),
          _int(local['ativo']),
          _int(local['ordem']),
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'conta':
        return _sha(<Object?>[
          local['nome'],
          local['tipo'],
          local['instituicao'],
          _double(local['saldo_inicial']),
          local['data_saldo_inicial'],
          local['observacoes'],
          _int(local['ativo']),
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'fornecedor':
        return _sha(<Object?>[
          local['nome'],
          local['documento'],
          local['telefone'],
          local['email'],
          local['endereco'],
          local['cidade'],
          local['estado'],
          local['categoria'],
          local['observacoes'],
          _int(local['ativo']),
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'regra_taxa':
        return _sha(<Object?>[
          local['nome'],
          local['forma_pagamento'],
          _int(local['parcelas']),
          _intNulo(local['conta_id']),
          _double(local['taxa_percentual']),
          _double(local['taxa_fixa']),
          _int(local['prazo_recebimento_dias']),
          _int(local['prioridade']),
          _int(local['repassar_cliente']),
          local['observacoes'],
          _int(local['ativo']),
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'transferencia':
        return _sha(<Object?>[
          _int(local['conta_origem_id']),
          _int(local['conta_destino_id']),
          _double(local['valor']),
          local['data'],
          local['descricao'],
          local['observacoes'],
          local['criado_em'],
        ]);

      case 'pagamento':
        return _sha(<Object?>[
          _int(local['ordem_servico_id']),
          local['status'],
          _double(local['valor']),
          local['forma_pagamento'],
          local['data_pagamento'],
          _intNulo(local['parcela_numero']),
          _intNulo(local['total_parcelas']),
          local['vencimento'],
          local['comprovante_caminho'],
          local['observacoes'],
          _doubleNulo(local['taxa_percentual']),
          _double(local['taxa_operacao']),
          _double(local['valor_liquido']),
          _intNulo(local['regra_taxa_id']),
          _int(local['parcelas_taxa']),
          local['estornado_em'],
          local['motivo_estorno'],
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'movimento':
        return _sha(<Object?>[
          local['tipo'],
          local['descricao'],
          _double(local['valor']),
          local['forma_pagamento'],
          local['data'],
          _intNulo(local['cliente_id']),
          _intNulo(local['agendamento_id']),
          _intNulo(local['ordem_servico_id']),
          _intNulo(local['pagamento_id']),
          _intNulo(local['plano_conta_id']),
          _intNulo(local['conta_id']),
          _intNulo(local['fornecedor_id']),
          _intNulo(local['transferencia_id']),
          _intNulo(local['nota_fiscal_id']),
          _intNulo(local['parcela_numero']),
          _int(local['total_parcelas']),
          local['natureza'],
          local['origem'],
          local['status'],
          local['data_competencia'],
          local['data_vencimento'],
          local['data_pagamento'],
          local['numero_documento'],
          local['observacoes'],
          _int(local['impacta_dre']),
        ]);

      default:
        throw StateError('Hash nao implementado para $entidade');
    }
  }

  String _sha(List<Object?> values) {
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static int? _intNulo(Object? value) {
    if (value == null) return null;
    final texto = value.toString().trim();
    if (texto.isEmpty) return null;
    final numero = int.tryParse(texto);
    return numero;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static double? _doubleNulo(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final texto = value.toString().trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    return double.tryParse(texto);
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoNulo(Object? value) {
    final valueText = _texto(value);
    return valueText.isEmpty ? null : valueText;
  }

  static String _textoPadrao(Object? value, String padrao) {
    final texto = _texto(value);
    return texto.isEmpty ? padrao : texto;
  }

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;

    final b = _texto(segundo);
    if (b.isNotEmpty) return b;

    return DateTime.now().toIso8601String();
  }
}

class _ConfigFinanceiro {
  const _ConfigFinanceiro({
    required this.local,
    required this.remota,
    required this.mapa,
  });

  final String local;
  final String remota;
  final String mapa;
}

class _DependenciaFinanceiraV2Pendente implements Exception {}
