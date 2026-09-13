import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';
import '../repositories/precificacao_repository.dart';
import 'precificacao_cloud_service.dart';
import 'supabase_bootstrap.dart';

class PrecificacaoCloudV2Service {
  PrecificacaoCloudV2Service._();

  static final PrecificacaoCloudV2Service instance =
      PrecificacaoCloudV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // precificacao-cloud-v2-cas-conflitos-simulacoes
  Future<void> garantirEstruturaLocal() async {
    await PrecificacaoCloudService.instance.garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_precificacao_conflitos (
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
      CREATE INDEX IF NOT EXISTS idx_precificacao_conflitos_pendentes
      ON imperium_sync_precificacao_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_precificacao_simulacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        margem_cliente REAL NOT NULL,
        margem_revenda_1_4 REAL NOT NULL,
        margem_revenda_5_9 REAL NOT NULL,
        margem_revenda_10_mais REAL NOT NULL,
        margem_minima REAL NOT NULL,
        taxa_cartao_percentual REAL NOT NULL DEFAULT 0,
        custo_hora REAL NOT NULL DEFAULT 0,
        meta_faturamento REAL NOT NULL DEFAULT 0,
        meses_media INTEGER NOT NULL DEFAULT 3,
        resultado_json TEXT NOT NULL DEFAULT '{}',
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        sincronizado_em TEXT,
        remoto_id TEXT
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_precificacao_simulacao_remota
      ON imperium_precificacao_simulacoes (empresa_id, remoto_id)
      WHERE remoto_id IS NOT NULL
    ''');
  }

  /// Executa o guard antes do V1.
  ///
  /// Retorna false quando existe conflito pendente. Nesse caso o V1 inteiro
  /// da precificacao deve ser pulado para impedir overwrite acidental.
  Future<bool> reconciliarAntesDoUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return true;

    try {
      await garantirEstruturaLocal();
      await _reconciliarConfig(empresaId);

      for (final entidade in _entidadesMapeadas) {
        await _reconciliarEntidade(empresaId, entidade);
      }

      await sincronizarSimulacoes(empresaId);

      final pendentes = await listarConflitosPendentes(empresaId: empresaId);
      return pendentes.isEmpty;
    } on PostgrestException catch (error) {
      if (error.code == '42501') return true;
      rethrow;
    }
  }

  Future<void> sincronizarDepoisDoDownload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      await _baixarSimulacoes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_precificacao_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> listarHistoricoConflitos({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_precificacao_conflitos',
      where: empresaId == null ? null : 'empresa_id = ?',
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    final conflito = await _carregarConflitoPendente(conflitoId);
    final entidade = _texto(conflito['entidade']);
    final empresaId = _texto(conflito['empresa_id']);
    final localId = _int(conflito['local_id']);

    if (entidade == 'config') {
      await _resolverConfigUsandoLocal(conflito);
      return;
    }

    final definicao = _definicao(entidade);
    final local = await _carregarLocal(definicao, localId);
    final remotoId = _texto(conflito['remoto_id']);

    if (local == null) {
      if (!definicao.softDelete) {
        throw StateError(
          'A entidade $entidade nao suporta exclusao remota controlada.',
        );
      }

      final remoto = await _buscarRemoto(
        definicao.tabelaRemota,
        empresaId,
        remotoId,
      );
      if (remoto == null) {
        await _salvarMapaResolvido(
          definicao: definicao,
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: '__excluido__',
          remotoAtualizadoEm: null,
        );
        await _encerrarConflito(
          conflitoId,
          resolucao: 'local',
          detalhe: 'Exclusao local confirmada; registro remoto ja ausente.',
        );
        return;
      }

      final atualizado = await _forcarSoftDelete(
        definicao.tabelaRemota,
        empresaId,
        remotoId,
      );

      await _salvarMapaResolvido(
        definicao: definicao,
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: '__excluido__',
        remotoAtualizadoEm: atualizado,
      );

      await _encerrarConflito(
        conflitoId,
        resolucao: 'local',
        detalhe: 'Exclusao local aplicada na nuvem.',
      );
      return;
    }

    final payload = await _payloadLocal(definicao, empresaId, localId, local);

    final client = _client;
    if (client == null) {
      throw StateError('Supabase nao esta disponivel.');
    }

    final rows = await client
        .from(definicao.tabelaRemota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em');

    if (rows.isEmpty) {
      throw StateError(
        'Registro remoto nao existe mais. Use a versao da nuvem ou revise.',
      );
    }

    await _salvarMapaResolvido(
      definicao: definicao,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: definicao.hash(local),
      remotoAtualizadoEm: rows.first['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'local',
      detalhe: 'Versao local aplicada na nuvem.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    final conflito = await _carregarConflitoPendente(conflitoId);
    final entidade = _texto(conflito['entidade']);
    final empresaId = _texto(conflito['empresa_id']);
    final localId = _int(conflito['local_id']);

    if (entidade == 'config') {
      await _resolverConfigUsandoNuvem(conflito);
      return;
    }

    final definicao = _definicao(entidade);
    final remotoId = _texto(conflito['remoto_id']);
    final remoto = await _buscarRemoto(
      definicao.tabelaRemota,
      empresaId,
      remotoId,
    );

    if (remoto == null) {
      if (!definicao.softDelete) {
        throw StateError('Registro remoto ausente para entidade $entidade.');
      }

      await _aplicarAusenciaRemota(definicao, localId);

      await _salvarMapaResolvido(
        definicao: definicao,
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: '__excluido__',
        remotoAtualizadoEm: null,
      );

      await _encerrarConflito(
        conflitoId,
        resolucao: 'nuvem',
        detalhe: 'Ausencia remota aplicada localmente.',
      );
      return;
    }

    await _aplicarRemoto(definicao, localId, remoto);
    final localDepois = await _carregarLocal(definicao, localId);

    final hashDepois = localDepois == null
        ? '__excluido__'
        : definicao.hash(localDepois);

    await _salvarMapaResolvido(
      definicao: definicao,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: hashDepois,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versao mais recente da nuvem aplicada no SQLite.',
    );
  }

  Future<int> simularESalvar({
    required String empresaId,
    required String nome,
    double? margemCliente,
    double? margemRevenda1a4,
    double? margemRevenda5a9,
    double? margemRevenda10Mais,
    double? margemMinima,
    double? taxaCartaoPercentual,
    double? custoHora,
    double metaFaturamento = 0,
    String observacoes = '',
  }) async {
    if (empresaId.trim().isEmpty) {
      throw ArgumentError('Empresa invalida.');
    }
    if (nome.trim().isEmpty) {
      throw ArgumentError('Informe um nome para o cenario.');
    }

    await garantirEstruturaLocal();
    final painel = await _precificacaoRepository.carregar();

    final mc = margemCliente ?? painel.config.margemCliente;
    final r14 = margemRevenda1a4 ?? painel.config.margemRevenda1a4;
    final r59 = margemRevenda5a9 ?? painel.config.margemRevenda5a9;
    final r10 = margemRevenda10Mais ?? painel.config.margemRevenda10Mais;
    final mm = margemMinima ?? painel.config.margemMinima;
    final taxa =
        taxaCartaoPercentual ?? painel.resumo.taxaCartaoMediaPercentual;
    final hora = custoHora ?? painel.resumo.custoHora;

    _validarMargens(
      margemCliente: mc,
      margemRevenda1a4: r14,
      margemRevenda5a9: r59,
      margemRevenda10Mais: r10,
      margemMinima: mm,
      taxaCartao: taxa,
    );

    final servicos = painel.servicos.map((servico) {
      // Recalcula custo de estrutura quando o cenario altera custo-hora.
      final custoEstrutura = (servico.tempoPrecificacaoMinutos / 60.0) * hora;
      final custoBase = servico.custoProdutos + custoEstrutura;

      final sugerido = _arredondarPreco(_precoComMargem(custoBase, mc, taxa));

      return <String, Object?>{
        'servico_id': servico.id,
        'nome': servico.nome,
        'preco_atual': servico.precoAtual,
        'custo_produtos': servico.custoProdutos,
        'custo_estrutura': custoEstrutura,
        'custo_base': custoBase,
        'preco_equilibrio': _precoComMargem(custoBase, 0, taxa),
        'preco_minimo_seguro': _precoComMargem(custoBase, mm, taxa),
        'preco_sugerido': sugerido,
        'preco_revenda_1_4': _arredondarPreco(
          _precoComMargem(custoBase, r14, taxa),
        ),
        'preco_revenda_5_9': _arredondarPreco(
          _precoComMargem(custoBase, r59, taxa),
        ),
        'preco_revenda_10_mais': _arredondarPreco(
          _precoComMargem(custoBase, r10, taxa),
        ),
        'diferenca_preco_atual': sugerido - servico.precoAtual,
      };
    }).toList();

    final resultado = <String, Object?>{
      'versao': 2,
      'horas_mensais_empresa': ImperiumRegrasNegocio.horasMensaisPadrao,
      'base_mensal_atual': painel.resumo.baseMensalUsada,
      'custo_hora_cenario': hora,
      'taxa_cartao_cenario': taxa,
      'meta_faturamento': metaFaturamento,
      'quantidade_servicos': servicos.length,
      'servicos': servicos,
    };

    final agora = DateTime.now().toIso8601String();
    final database = await _appDatabase.database;

    final id = await database.insert('imperium_precificacao_simulacoes', {
      'empresa_id': empresaId,
      'nome': nome.trim(),
      'margem_cliente': mc,
      'margem_revenda_1_4': r14,
      'margem_revenda_5_9': r59,
      'margem_revenda_10_mais': r10,
      'margem_minima': mm,
      'taxa_cartao_percentual': taxa,
      'custo_hora': hora,
      'meta_faturamento': metaFaturamento,
      'meses_media': painel.config.mesesMedia,
      'resultado_json': jsonEncode(resultado),
      'observacoes': observacoes.trim(),
      'criado_em': agora,
    });

    try {
      await _publicarSimulacaoLocal(empresaId, id);
    } on PostgrestException catch (error) {
      if (error.code != '42501') rethrow;
    }

    return id;
  }

  Future<List<Map<String, Object?>>> listarSimulacoes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_precificacao_simulacoes',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'criado_em DESC, id DESC',
    );
  }

  Future<void> sincronizarSimulacoes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final pendentes = await database.query(
      'imperium_precificacao_simulacoes',
      where: 'empresa_id = ? AND remoto_id IS NULL',
      whereArgs: [empresaId],
      orderBy: 'id ASC',
    );

    for (final item in pendentes) {
      await _publicarSimulacaoLocal(empresaId, _int(item['id']));
    }

    await _baixarSimulacoes(empresaId);
  }

  Future<void> _reconciliarConfig(String empresaId) async {
    final client = _client;
    if (client == null) return;

    if (await _possuiConflito('config', empresaId, 1)) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      'imperium_sync_precificacao_config',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      limit: 1,
    );

    if (mapas.isEmpty) return;

    final mapa = mapas.first;
    final config = await _precificacaoRepository.carregarConfig();
    final localHash = _hashConfig(config);
    final baseHash = _texto(mapa['local_hash']);
    final baseTs = _texto(mapa['remoto_atualizado_em']);

    final remotoRaw = await client
        .from('imperium_precificacao_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (remotoRaw == null) {
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'config',
        localId: 1,
        remotoId: empresaId,
        motivo: 'remoto_ausente',
        baseHash: baseHash,
        localHash: localHash,
        baseTs: baseTs,
        remotoTs: '',
        local: _configJson(config),
        remoto: const <String, dynamic>{},
      );
      return;
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);
    final remotoTs = _texto(remoto['atualizado_em']);
    final localChanged = localHash != baseHash;
    final remotoChanged = baseTs.isEmpty || remotoTs != baseTs;

    if (localChanged && remotoChanged) {
      await _registrarConflito(
        empresaId: empresaId,
        entidade: 'config',
        localId: 1,
        remotoId: empresaId,
        motivo: 'alteracao_concorrente',
        baseHash: baseHash,
        localHash: localHash,
        baseTs: baseTs,
        remotoTs: remotoTs,
        local: _configJson(config),
        remoto: remoto,
      );
      return;
    }

    if (localChanged) {
      final payload = await _payloadConfig(config);
      final rows = await client
          .from('imperium_precificacao_config')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('atualizado_em', baseTs)
          .select('empresa_id,atualizado_em');

      if (rows.isEmpty) {
        final atual = await client
            .from('imperium_precificacao_config')
            .select()
            .eq('empresa_id', empresaId)
            .maybeSingle();

        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'config',
          localId: 1,
          remotoId: empresaId,
          motivo: 'cas_falhou',
          baseHash: baseHash,
          localHash: localHash,
          baseTs: baseTs,
          remotoTs: _texto(atual?['atualizado_em']),
          local: _configJson(config),
          remoto: atual == null
              ? const <String, dynamic>{}
              : Map<String, dynamic>.from(atual),
        );
        return;
      }

      await database.update(
        'imperium_sync_precificacao_config',
        {
          'local_hash': localHash,
          'remoto_atualizado_em': rows.first['atualizado_em']?.toString(),
        },
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      );
      return;
    }

    if (remotoChanged) {
      await _aplicarConfigRemota(remoto);
      final aplicada = await _precificacaoRepository.carregarConfig();

      await database.update(
        'imperium_sync_precificacao_config',
        {'local_hash': _hashConfig(aplicada), 'remoto_atualizado_em': remotoTs},
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      );
    }
  }

  Future<void> _reconciliarEntidade(
    String empresaId,
    _EntidadePrecificacao definicao,
  ) async {
    final database = await _appDatabase.database;
    final mapas = await database.query(
      definicao.tabelaMapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'local_id ASC',
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      if (localId <= 0) continue;
      if (await _possuiConflito(definicao.nome, empresaId, localId)) {
        continue;
      }

      final remotoId = _texto(mapa['remoto_id']);
      final local = await _carregarLocal(definicao, localId);
      final remoto = await _buscarRemoto(
        definicao.tabelaRemota,
        empresaId,
        remotoId,
      );

      final baseHash = _texto(mapa['local_hash']);
      final baseTs = _texto(mapa['remoto_atualizado_em']);

      if (local == null) {
        await _reconciliarAusenciaLocal(
          empresaId: empresaId,
          definicao: definicao,
          localId: localId,
          remotoId: remotoId,
          remoto: remoto,
          baseHash: baseHash,
          baseTs: baseTs,
        );
        continue;
      }

      final localHash = definicao.hash(local);

      if (remoto == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: definicao.nome,
          localId: localId,
          remotoId: remotoId,
          motivo: 'remoto_ausente',
          baseHash: baseHash,
          localHash: localHash,
          baseTs: baseTs,
          remotoTs: '',
          local: Map<String, dynamic>.from(local),
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remotoTs = _texto(remoto['atualizado_em']);
      final localChanged = localHash != baseHash;
      final remotoChanged = baseTs.isEmpty || remotoTs != baseTs;
      final remotoExcluido =
          definicao.softDelete && _texto(remoto['excluido_em']).isNotEmpty;

      if (remotoExcluido) {
        if (localChanged) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: definicao.nome,
            localId: localId,
            remotoId: remotoId,
            motivo: 'alteracao_local_e_exclusao_remota',
            baseHash: baseHash,
            localHash: localHash,
            baseTs: baseTs,
            remotoTs: remotoTs,
            local: Map<String, dynamic>.from(local),
            remoto: remoto,
          );
          continue;
        }

        await _aplicarRemoto(definicao, localId, remoto);
        final depois = await _carregarLocal(definicao, localId);

        await _atualizarMapa(
          definicao: definicao,
          empresaId: empresaId,
          localId: localId,
          localHash: depois == null ? '__excluido__' : definicao.hash(depois),
          remotoAtualizadoEm: remotoTs,
        );
        continue;
      }

      if (localChanged && remotoChanged) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: definicao.nome,
          localId: localId,
          remotoId: remotoId,
          motivo: 'alteracao_concorrente',
          baseHash: baseHash,
          localHash: localHash,
          baseTs: baseTs,
          remotoTs: remotoTs,
          local: Map<String, dynamic>.from(local),
          remoto: remoto,
        );
        continue;
      }

      if (localChanged) {
        final payload = await _payloadLocal(
          definicao,
          empresaId,
          localId,
          local,
        );

        final client = _client;
        if (client == null) return;

        final rows = await client
            .from(definicao.tabelaRemota)
            .update(payload)
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .eq('atualizado_em', baseTs)
            .select('id,atualizado_em');

        if (rows.isEmpty) {
          final atual = await _buscarRemoto(
            definicao.tabelaRemota,
            empresaId,
            remotoId,
          );

          await _registrarConflito(
            empresaId: empresaId,
            entidade: definicao.nome,
            localId: localId,
            remotoId: remotoId,
            motivo: 'cas_falhou',
            baseHash: baseHash,
            localHash: localHash,
            baseTs: baseTs,
            remotoTs: _texto(atual?['atualizado_em']),
            local: Map<String, dynamic>.from(local),
            remoto: atual ?? const <String, dynamic>{},
          );
          continue;
        }

        await _atualizarMapa(
          definicao: definicao,
          empresaId: empresaId,
          localId: localId,
          localHash: localHash,
          remotoAtualizadoEm: rows.first['atualizado_em']?.toString(),
        );
        continue;
      }

      if (remotoChanged) {
        await _aplicarRemoto(definicao, localId, remoto);
        final depois = await _carregarLocal(definicao, localId);

        await _atualizarMapa(
          definicao: definicao,
          empresaId: empresaId,
          localId: localId,
          localHash: depois == null ? '__excluido__' : definicao.hash(depois),
          remotoAtualizadoEm: remotoTs,
        );
      }
    }
  }

  Future<void> _reconciliarAusenciaLocal({
    required String empresaId,
    required _EntidadePrecificacao definicao,
    required int localId,
    required String remotoId,
    required Map<String, dynamic>? remoto,
    required String baseHash,
    required String baseTs,
  }) async {
    if (!definicao.softDelete) {
      return;
    }

    if (remoto == null) {
      await _atualizarMapa(
        definicao: definicao,
        empresaId: empresaId,
        localId: localId,
        localHash: '__excluido__',
        remotoAtualizadoEm: null,
      );
      return;
    }

    final remotoTs = _texto(remoto['atualizado_em']);
    final jaExcluido = _texto(remoto['excluido_em']).isNotEmpty;

    if (jaExcluido) {
      await _atualizarMapa(
        definicao: definicao,
        empresaId: empresaId,
        localId: localId,
        localHash: '__excluido__',
        remotoAtualizadoEm: remotoTs,
      );
      return;
    }

    final remotoChanged = baseTs.isEmpty || remotoTs != baseTs;

    if (remotoChanged) {
      await _registrarConflito(
        empresaId: empresaId,
        entidade: definicao.nome,
        localId: localId,
        remotoId: remotoId,
        motivo: 'exclusao_local_e_alteracao_remota',
        baseHash: baseHash,
        localHash: '__excluido__',
        baseTs: baseTs,
        remotoTs: remotoTs,
        local: const <String, dynamic>{'excluido_localmente': true},
        remoto: remoto,
      );
      return;
    }

    final client = _client;
    if (client == null) return;

    final rows = await client
        .from(definicao.tabelaRemota)
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .eq('atualizado_em', baseTs)
        .select('id,atualizado_em');

    if (rows.isEmpty) {
      final atual = await _buscarRemoto(
        definicao.tabelaRemota,
        empresaId,
        remotoId,
      );

      await _registrarConflito(
        empresaId: empresaId,
        entidade: definicao.nome,
        localId: localId,
        remotoId: remotoId,
        motivo: 'cas_falhou_na_exclusao',
        baseHash: baseHash,
        localHash: '__excluido__',
        baseTs: baseTs,
        remotoTs: _texto(atual?['atualizado_em']),
        local: const <String, dynamic>{'excluido_localmente': true},
        remoto: atual ?? const <String, dynamic>{},
      );
      return;
    }

    await _atualizarMapa(
      definicao: definicao,
      empresaId: empresaId,
      localId: localId,
      localHash: '__excluido__',
      remotoAtualizadoEm: rows.first['atualizado_em']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _payloadConfig(PrecificacaoConfig config) async {
    return <String, dynamic>{
      'horas_produtivas_mes': ImperiumRegrasNegocio.horasMensaisPadrao,
      'meses_media': config.mesesMedia,
      'margem_cliente': config.margemCliente,
      'margem_revenda_1_4': config.margemRevenda1a4,
      'margem_revenda_5_9': config.margemRevenda5a9,
      'margem_revenda_10_mais': config.margemRevenda10Mais,
      'margem_minima': config.margemMinima,
      'origem_dispositivo': await _dispositivoId(),
      'origem_atualizado_em': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _payloadLocal(
    _EntidadePrecificacao definicao,
    String empresaId,
    int localId,
    Map<String, Object?> local,
  ) async {
    switch (definicao.nome) {
      case 'servico':
        return <String, dynamic>{
          'nome': _texto(local['nome']),
          'categoria': _texto(local['categoria']),
          'descricao': _texto(local['descricao']),
          'observacoes_padrao': _texto(local['observacoes_padrao']),
          'preco_padrao': _double(local['preco_padrao']),
          'duracao_minutos': _int(local['duracao_minutos']),
          'ativo': _int(local['ativo']) != 0,
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };
      case 'colaborador':
        return <String, dynamic>{
          'nome': _texto(local['nome']),
          'funcao': _texto(local['funcao']),
          'remuneracao_mensal': _double(local['remuneracao_mensal']),
          'encargos_mensais': _double(local['encargos_mensais']),
          'outros_custos_mensais': _double(local['outros_custos_mensais']),
          'horas_produtivas_mes': _double(local['horas_produtivas_mes']),
          'observacoes': _texto(local['observacoes']),
          'ativo': _int(local['ativo']) != 0,
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };
      case 'preferencia':
        final servicoRemotoId = await _remotoPorLocal(
          tabelaMapa: 'imperium_sync_precificacao_servicos',
          empresaId: empresaId,
          localId: localId,
        );
        if (servicoRemotoId == null) {
          throw StateError('Servico remoto nao mapeado para preferencia.');
        }
        return <String, dynamic>{
          'servico_id': servicoRemotoId,
          'tempo_precificacao_minutos': _doubleNulo(
            local['tempo_precificacao_minutos'],
          ),
          'aceita_revenda': _int(local['aceita_revenda']) != 0,
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
        };
      case 'receita':
        final servicoRemotoId = await _remotoPorLocal(
          tabelaMapa: 'imperium_sync_precificacao_servicos',
          empresaId: empresaId,
          localId: _int(local['servico_id']),
        );
        final itemRemotoId = await _remotoPorLocal(
          tabelaMapa: 'imperium_sync_estoque_itens',
          empresaId: empresaId,
          localId: _int(local['item_estoque_id']),
        );
        if (servicoRemotoId == null || itemRemotoId == null) {
          throw StateError('Dependencia remota da receita nao foi mapeada.');
        }
        return <String, dynamic>{
          'servico_id': servicoRemotoId,
          'item_estoque_id': itemRemotoId,
          'quantidade_padrao': _double(local['quantidade_padrao']),
          'unidade': _texto(local['unidade']),
          'obrigatorio': _int(local['obrigatorio']) != 0,
          'marcado_por_padrao': _int(local['marcado_por_padrao']) != 0,
          'ordem': _int(local['ordem']),
          'excluido_em': null,
        };
      default:
        throw StateError('Entidade sem payload: ${definicao.nome}.');
    }
  }

  Future<void> _aplicarConfigRemota(Map<String, dynamic> remoto) async {
    await _precificacaoRepository.salvarConfig(
      PrecificacaoConfig(
        horasProdutivasMes: ImperiumRegrasNegocio.horasMensaisPadrao,
        mesesMedia: _int(remoto['meses_media']).clamp(1, 12),
        margemCliente: _double(remoto['margem_cliente']),
        margemRevenda: _double(remoto['margem_revenda_5_9']),
        margemMinima: _double(remoto['margem_minima']),
        margemRevenda1a4: _double(remoto['margem_revenda_1_4']),
        margemRevenda5a9: _double(remoto['margem_revenda_5_9']),
        margemRevenda10Mais: _double(remoto['margem_revenda_10_mais']),
      ),
    );
  }

  Future<void> _aplicarRemoto(
    _EntidadePrecificacao definicao,
    int localId,
    Map<String, dynamic> remoto,
  ) async {
    final database = await _appDatabase.database;
    final excluido =
        definicao.softDelete && _texto(remoto['excluido_em']).isNotEmpty;

    switch (definicao.nome) {
      case 'servico':
        await database.update(
          'servicos_catalogo',
          {
            'nome': _texto(remoto['nome']),
            'categoria': _texto(remoto['categoria']),
            'descricao': _texto(remoto['descricao']),
            'observacoes_padrao': _texto(remoto['observacoes_padrao']),
            'preco_padrao': _double(remoto['preco_padrao']),
            'preco_minimo': _double(remoto['preco_padrao']),
            'preco_maximo': _double(remoto['preco_padrao']),
            'duracao_minutos': _int(remoto['duracao_minutos']),
            'ativo': excluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
      case 'colaborador':
        await database.update(
          'financeiro_colaboradores_custo',
          {
            'nome': _texto(remoto['nome']),
            'funcao': _texto(remoto['funcao']),
            'remuneracao_mensal': _double(remoto['remuneracao_mensal']),
            'encargos_mensais': _double(remoto['encargos_mensais']),
            'outros_custos_mensais': _double(remoto['outros_custos_mensais']),
            'horas_produtivas_mes': _double(remoto['horas_produtivas_mes']),
            'observacoes': _texto(remoto['observacoes']),
            'ativo': excluido ? 0 : (remoto['ativo'] == true ? 1 : 0),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
      case 'preferencia':
        await database.insert(
          'financeiro_precificacao_servicos',
          {
            'servico_id': localId,
            'tempo_precificacao_minutos': _doubleNulo(
              remoto['tempo_precificacao_minutos'],
            ),
            'aceita_revenda': remoto['aceita_revenda'] == true ? 1 : 0,
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        break;
      case 'receita':
        if (excluido) {
          await database.delete(
            'servico_produtos',
            where: 'id = ?',
            whereArgs: [localId],
          );
          break;
        }

        final empresaId = _texto(remoto['empresa_id']);
        final servicoLocalId = await _localPorRemoto(
          tabelaMapa: 'imperium_sync_precificacao_servicos',
          empresaId: empresaId,
          remotoId: _texto(remoto['servico_id']),
        );
        final itemLocalId = await _localPorRemoto(
          tabelaMapa: 'imperium_sync_estoque_itens',
          empresaId: empresaId,
          remotoId: _texto(remoto['item_estoque_id']),
        );
        if (servicoLocalId == null || itemLocalId == null) {
          throw StateError('Dependencia local da receita nao encontrada.');
        }

        await database.update(
          'servico_produtos',
          {
            'servico_id': servicoLocalId,
            'item_estoque_id': itemLocalId,
            'quantidade_padrao': _double(remoto['quantidade_padrao']),
            'unidade': _texto(remoto['unidade']),
            'obrigatorio': remoto['obrigatorio'] == true ? 1 : 0,
            'marcado_por_padrao': remoto['marcado_por_padrao'] == true ? 1 : 0,
            'ordem': _int(remoto['ordem']),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
    }
  }

  Future<void> _aplicarAusenciaRemota(
    _EntidadePrecificacao definicao,
    int localId,
  ) async {
    final database = await _appDatabase.database;

    switch (definicao.nome) {
      case 'servico':
        await database.update(
          'servicos_catalogo',
          {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
      case 'colaborador':
        await database.update(
          'financeiro_colaboradores_custo',
          {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
      case 'receita':
        await database.delete(
          'servico_produtos',
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
    }
  }

  Future<Map<String, Object?>?> _carregarLocal(
    _EntidadePrecificacao definicao,
    int localId,
  ) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      definicao.tabelaLocal,
      where: '${definicao.chaveLocal} = ?',
      whereArgs: [localId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> _buscarRemoto(
    String tabela,
    String empresaId,
    String remotoId,
  ) async {
    if (remotoId.trim().isEmpty) return null;
    final client = _client;
    if (client == null) return null;

    final raw = await client
        .from(tabela)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<void> _atualizarMapa({
    required _EntidadePrecificacao definicao,
    required String empresaId,
    required int localId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      definicao.tabelaMapa,
      {'local_hash': localHash, 'remoto_atualizado_em': remotoAtualizadoEm},
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
    );
  }

  Future<void> _salvarMapaResolvido({
    required _EntidadePrecificacao definicao,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(definicao.tabelaMapa, {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _possuiConflito(
    String entidade,
    String empresaId,
    int localId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? AND status = 'Pendente'",
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
    required String baseHash,
    required String localHash,
    required String baseTs,
    required String remotoTs,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    final existentes = await database.query(
      'imperium_sync_precificacao_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId],
      limit: 1,
    );

    final dados = <String, Object?>{
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': baseHash,
      'local_hash_atual': localHash,
      'remoto_atualizado_base': baseTs,
      'remoto_atualizado_atual': remotoTs,
      'local_json': jsonEncode(local),
      'remoto_json': jsonEncode(remoto),
      'detectado_em': agora,
    };

    if (existentes.isEmpty) {
      await database.insert('imperium_sync_precificacao_conflitos', {
        'empresa_id': empresaId,
        'entidade': entidade,
        'local_id': localId,
        ...dados,
        'status': 'Pendente',
      });
      return;
    }

    await database.update(
      'imperium_sync_precificacao_conflitos',
      dados,
      where: 'id = ?',
      whereArgs: [_int(existentes.first['id'])],
    );
  }

  Future<Map<String, Object?>> _carregarConflitoPendente(int id) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_precificacao_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito pendente nao encontrado.');
    }
    return rows.first;
  }

  Future<void> _encerrarConflito(
    int id, {
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'imperium_sync_precificacao_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _resolverConfigUsandoLocal(Map<String, Object?> conflito) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase nao esta disponivel.');
    }

    final empresaId = _texto(conflito['empresa_id']);
    final config = await _precificacaoRepository.carregarConfig();
    final payload = await _payloadConfig(config);

    final rows = await client
        .from('imperium_precificacao_config')
        .update(payload)
        .eq('empresa_id', empresaId)
        .select('empresa_id,atualizado_em');

    if (rows.isEmpty) {
      throw StateError('Configuracao remota nao existe mais.');
    }

    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_precificacao_config',
      {
        'empresa_id': empresaId,
        'local_hash': _hashConfig(config),
        'remoto_atualizado_em': rows.first['atualizado_em']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _encerrarConflito(
      _int(conflito['id']),
      resolucao: 'local',
      detalhe: 'Configuracao local aplicada na nuvem.',
    );
  }

  Future<void> _resolverConfigUsandoNuvem(Map<String, Object?> conflito) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase nao esta disponivel.');
    }

    final empresaId = _texto(conflito['empresa_id']);
    final remotoRaw = await client
        .from('imperium_precificacao_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError('Configuracao remota nao existe mais.');
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);
    await _aplicarConfigRemota(remoto);
    final aplicada = await _precificacaoRepository.carregarConfig();

    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_precificacao_config',
      {
        'empresa_id': empresaId,
        'local_hash': _hashConfig(aplicada),
        'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _encerrarConflito(
      _int(conflito['id']),
      resolucao: 'nuvem',
      detalhe: 'Configuracao da nuvem aplicada no SQLite.',
    );
  }

  Future<String?> _forcarSoftDelete(
    String tabela,
    String empresaId,
    String remotoId,
  ) async {
    final client = _client;
    if (client == null) return null;

    final rows = await client
        .from(tabela)
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em');

    return rows.isEmpty ? null : rows.first['atualizado_em']?.toString();
  }

  Future<void> _publicarSimulacaoLocal(String empresaId, int localId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_precificacao_simulacoes',
      where: 'empresa_id = ? AND id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (rows.isEmpty) return;
    final local = rows.first;

    if (_texto(local['remoto_id']).isNotEmpty) return;

    final dispositivo = await _dispositivoId();

    final existente = await client
        .from('imperium_precificacao_simulacoes')
        .select('id,criado_em')
        .eq('empresa_id', empresaId)
        .eq('origem_dispositivo', dispositivo)
        .eq('origem_local_id', localId)
        .maybeSingle();

    if (existente != null) {
      await database.update(
        'imperium_precificacao_simulacoes',
        {
          'remoto_id': existente['id']?.toString(),
          'sincronizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
      return;
    }

    final resultadoRaw = _texto(local['resultado_json']);
    Object resultadoJson;
    try {
      resultadoJson = jsonDecode(resultadoRaw);
    } catch (_) {
      resultadoJson = <String, Object?>{'raw': resultadoRaw};
    }

    final remoto = await client
        .from('imperium_precificacao_simulacoes')
        .insert({
          'empresa_id': empresaId,
          'origem_dispositivo': dispositivo,
          'origem_local_id': localId,
          'nome': _texto(local['nome']),
          'margem_cliente': _double(local['margem_cliente']),
          'margem_revenda_1_4': _double(local['margem_revenda_1_4']),
          'margem_revenda_5_9': _double(local['margem_revenda_5_9']),
          'margem_revenda_10_mais': _double(local['margem_revenda_10_mais']),
          'margem_minima': _double(local['margem_minima']),
          'taxa_cartao_percentual': _double(local['taxa_cartao_percentual']),
          'custo_hora': _double(local['custo_hora']),
          'meta_faturamento': _double(local['meta_faturamento']),
          'meses_media': _int(local['meses_media']),
          'resultado_json': resultadoJson,
          'observacoes': _texto(local['observacoes']),
          'criado_em': _texto(local['criado_em']),
        })
        .select('id,criado_em')
        .single();

    await database.update(
      'imperium_precificacao_simulacoes',
      {
        'remoto_id': remoto['id']?.toString(),
        'sincronizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> _baixarSimulacoes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_simulacoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em', ascending: false);

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      final existe = await database.query(
        'imperium_precificacao_simulacoes',
        columns: ['id'],
        where: 'empresa_id = ? AND remoto_id = ?',
        whereArgs: [empresaId, remotoId],
        limit: 1,
      );
      if (existe.isNotEmpty) continue;

      final origemDispositivo = _texto(remoto['origem_dispositivo']);
      final origemLocalId = _int(remoto['origem_local_id']);

      if (origemDispositivo == await _dispositivoId() && origemLocalId > 0) {
        final proprio = await database.query(
          'imperium_precificacao_simulacoes',
          columns: ['id'],
          where: 'empresa_id = ? AND id = ?',
          whereArgs: [empresaId, origemLocalId],
          limit: 1,
        );

        if (proprio.isNotEmpty) {
          await database.update(
            'imperium_precificacao_simulacoes',
            {
              'remoto_id': remotoId,
              'sincronizado_em': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [origemLocalId],
          );
          continue;
        }
      }

      await database.insert('imperium_precificacao_simulacoes', {
        'empresa_id': empresaId,
        'nome': _texto(remoto['nome']),
        'margem_cliente': _double(remoto['margem_cliente']),
        'margem_revenda_1_4': _double(remoto['margem_revenda_1_4']),
        'margem_revenda_5_9': _double(remoto['margem_revenda_5_9']),
        'margem_revenda_10_mais': _double(remoto['margem_revenda_10_mais']),
        'margem_minima': _double(remoto['margem_minima']),
        'taxa_cartao_percentual': _double(remoto['taxa_cartao_percentual']),
        'custo_hora': _double(remoto['custo_hora']),
        'meta_faturamento': _double(remoto['meta_faturamento']),
        'meses_media': _int(remoto['meses_media']),
        'resultado_json': jsonEncode(remoto['resultado_json']),
        'observacoes': _texto(remoto['observacoes']),
        'criado_em': _textoPreferido(
          remoto['criado_em'],
          DateTime.now().toIso8601String(),
        ),
        'sincronizado_em': DateTime.now().toIso8601String(),
        'remoto_id': remotoId,
      });
    }
  }

  void _validarMargens({
    required double margemCliente,
    required double margemRevenda1a4,
    required double margemRevenda5a9,
    required double margemRevenda10Mais,
    required double margemMinima,
    required double taxaCartao,
  }) {
    for (final valor in <double>[
      margemCliente,
      margemRevenda1a4,
      margemRevenda5a9,
      margemRevenda10Mais,
      margemMinima,
    ]) {
      if (valor < 0 || valor >= 95) {
        throw ArgumentError('Margens devem ficar entre 0% e 94,9%.');
      }
    }

    if (margemRevenda1a4 > margemCliente ||
        margemRevenda1a4 < margemRevenda5a9 ||
        margemRevenda5a9 < margemRevenda10Mais ||
        margemRevenda10Mais < margemMinima) {
      throw ArgumentError('Ordem das margens do cenario e invalida.');
    }

    if (taxaCartao < 0 || taxaCartao > 30) {
      throw ArgumentError('Taxa de cartao deve ficar entre 0% e 30%.');
    }
  }

  double _precoComMargem(
    double custoBase,
    double margemPercentual,
    double taxaPercentual,
  ) {
    if (custoBase <= 0) return 0;

    final margem = (margemPercentual / 100).clamp(0.0, 0.949).toDouble();
    final taxa = (taxaPercentual / 100).clamp(0.0, 0.30).toDouble();
    final divisor = 1 - margem - taxa;

    if (divisor <= 0.05) return custoBase / 0.05;
    return custoBase / divisor;
  }

  double _arredondarPreco(double valor) {
    if (valor <= 0) return 0;
    if (valor < 100) return (valor / 5).ceil() * 5.0;
    return (valor / 10).ceil() * 10.0;
  }

  Map<String, dynamic> _configJson(PrecificacaoConfig config) {
    return <String, dynamic>{
      'horas_produtivas_mes': ImperiumRegrasNegocio.horasMensaisPadrao,
      'meses_media': config.mesesMedia,
      'margem_cliente': config.margemCliente,
      'margem_revenda_1_4': config.margemRevenda1a4,
      'margem_revenda_5_9': config.margemRevenda5a9,
      'margem_revenda_10_mais': config.margemRevenda10Mais,
      'margem_minima': config.margemMinima,
    };
  }

  String _hashConfig(PrecificacaoConfig config) {
    return _sha(<Object?>[
      ImperiumRegrasNegocio.horasMensaisPadrao,
      config.mesesMedia,
      config.margemCliente,
      config.margemRevenda1a4,
      config.margemRevenda5a9,
      config.margemRevenda10Mais,
      config.margemMinima,
    ]);
  }

  String _hashServico(Map<String, Object?> local) {
    return _sha(<Object?>[
      local['nome'],
      local['categoria'],
      local['descricao'],
      local['observacoes_padrao'],
      _double(local['preco_padrao']),
      _int(local['duracao_minutos']),
      _int(local['ativo']),
      local['criado_em'],
      local['atualizado_em'],
    ]);
  }

  String _hashColaborador(Map<String, Object?> local) {
    return _sha(<Object?>[
      local['nome'],
      local['funcao'],
      _double(local['remuneracao_mensal']),
      _double(local['encargos_mensais']),
      _double(local['outros_custos_mensais']),
      _double(local['horas_produtivas_mes']),
      local['observacoes'],
      _int(local['ativo']),
      local['criado_em'],
      local['atualizado_em'],
    ]);
  }

  String _hashPreferencia(Map<String, Object?> local) {
    return _sha(<Object?>[
      _int(local['servico_id']),
      _doubleNulo(local['tempo_precificacao_minutos']),
      _int(local['aceita_revenda']),
      local['atualizado_em'],
    ]);
  }

  String _hashReceita(Map<String, Object?> local) {
    return _sha(<Object?>[
      _int(local['servico_id']),
      _int(local['item_estoque_id']),
      _double(local['quantidade_padrao']),
      local['unidade'],
      _int(local['obrigatorio']),
      _int(local['marcado_por_padrao']),
      _int(local['ordem']),
    ]);
  }

  String _sha(List<Object?> values) {
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
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

  Future<String?> _remotoPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
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

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
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

  _EntidadePrecificacao _definicao(String nome) {
    return _entidadesMapeadas.firstWhere(
      (item) => item.nome == nome,
      orElse: () => throw StateError('Entidade desconhecida: $nome.'),
    );
  }

  List<_EntidadePrecificacao> get _entidadesMapeadas => <_EntidadePrecificacao>[
    _EntidadePrecificacao(
      nome: 'colaborador',
      tabelaLocal: 'financeiro_colaboradores_custo',
      chaveLocal: 'id',
      tabelaMapa: 'imperium_sync_precificacao_colaboradores',
      tabelaRemota: 'imperium_precificacao_colaboradores_custo',
      softDelete: true,
      hash: _hashColaborador,
    ),
    _EntidadePrecificacao(
      nome: 'servico',
      tabelaLocal: 'servicos_catalogo',
      chaveLocal: 'id',
      tabelaMapa: 'imperium_sync_precificacao_servicos',
      tabelaRemota: 'imperium_precificacao_servicos_catalogo',
      softDelete: true,
      hash: _hashServico,
    ),
    _EntidadePrecificacao(
      nome: 'preferencia',
      tabelaLocal: 'financeiro_precificacao_servicos',
      chaveLocal: 'servico_id',
      tabelaMapa: 'imperium_sync_precificacao_preferencias',
      tabelaRemota: 'imperium_precificacao_servicos',
      softDelete: false,
      hash: _hashPreferencia,
    ),
    _EntidadePrecificacao(
      nome: 'receita',
      tabelaLocal: 'servico_produtos',
      chaveLocal: 'id',
      tabelaMapa: 'imperium_sync_precificacao_receitas',
      tabelaRemota: 'imperium_precificacao_servico_produtos',
      softDelete: true,
      hash: _hashReceita,
    ),
  ];

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static double? _doubleNulo(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoNulo(Object? value) {
    final text = _texto(value);
    return text.isEmpty ? null : text;
  }

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;

    final b = _texto(segundo);
    if (b.isNotEmpty) return b;

    return DateTime.now().toIso8601String();
  }
}

class _EntidadePrecificacao {
  const _EntidadePrecificacao({
    required this.nome,
    required this.tabelaLocal,
    required this.chaveLocal,
    required this.tabelaMapa,
    required this.tabelaRemota,
    required this.softDelete,
    required this.hash,
  });

  final String nome;
  final String tabelaLocal;
  final String chaveLocal;
  final String tabelaMapa;
  final String tabelaRemota;
  final bool softDelete;
  final String Function(Map<String, Object?>) hash;
}
