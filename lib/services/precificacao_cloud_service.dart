import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';
import '../repositories/precificacao_repository.dart';
import 'supabase_bootstrap.dart';

/// Precificacao Cloud V1.
///
/// Compartilha:
/// - configuracao oficial de margens;
/// - catalogo de servicos;
/// - preferencias de precificacao;
/// - receita padrao de produtos;
/// - colaboradores/custos de mao de obra;
/// - snapshot calculado por servico.
///
/// A regra de horas mensais da empresa permanece fixa em 220h.
class PrecificacaoCloudService {
  PrecificacaoCloudService._();

  static final PrecificacaoCloudService instance = PrecificacaoCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // precificacao-cloud-v1
  Future<void> garantirEstruturaLocal() async {
    // O proprio repository garante as tabelas dinamicas da precificacao.
    await _precificacaoRepository.carregar();

    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_precificacao_config (
        empresa_id TEXT PRIMARY KEY,
        local_hash TEXT,
        remoto_atualizado_em TEXT
      )
    ''');

    for (final tabela in <String>[
      'imperium_sync_precificacao_servicos',
      'imperium_sync_precificacao_preferencias',
      'imperium_sync_precificacao_receitas',
      'imperium_sync_precificacao_colaboradores',
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
      CREATE TABLE IF NOT EXISTS imperium_sync_precificacao_snapshots (
        empresa_id TEXT NOT NULL,
        servico_local_id INTEGER NOT NULL,
        servico_remoto_id TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, servico_local_id)
      )
    ''');
  }

  Future<void> sincronizarUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      final painel = await _precificacaoRepository.carregar();

      await _publicarConfig(empresaId, painel.config);
      await _publicarColaboradores(empresaId);
      await _publicarCatalogo(empresaId);
      await _publicarPreferencias(empresaId);
      await _publicarReceitas(empresaId);
      await _publicarSnapshots(empresaId, painel);
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

      await _baixarConfig(empresaId);
      await _baixarColaboradoresNovos(empresaId);
      await _baixarCatalogoNovo(empresaId);
      await _baixarPreferencias(empresaId);
      await _baixarReceitasNovas(empresaId);
      await _baixarSnapshots(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    Future<int> contar(String tabela) async {
      final resultado = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela WHERE empresa_id = ?',
        [empresaId],
      );
      return _int(resultado.first['total']);
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'horas_mensais_oficiais': ImperiumRegrasNegocio.horasMensaisPadrao,
      'servicos_mapeados': await contar('imperium_sync_precificacao_servicos'),
      'preferencias_mapeadas': await contar(
        'imperium_sync_precificacao_preferencias',
      ),
      'receitas_mapeadas': await contar('imperium_sync_precificacao_receitas'),
      'colaboradores_mapeados': await contar(
        'imperium_sync_precificacao_colaboradores',
      ),
      'snapshots_mapeados': await contar(
        'imperium_sync_precificacao_snapshots',
      ),
    };
  }

  Future<void> _publicarConfig(
    String empresaId,
    PrecificacaoConfig config,
  ) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapa = await database.query(
      'imperium_sync_precificacao_config',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      limit: 1,
    );

    final localHash = _hashConfig(config);

    // Em um aparelho novo, a configuracao remota ganha prioridade para que
    // o default local nao sobrescreva as margens reais da empresa.
    if (mapa.isEmpty) {
      final remotoAtual = await client
          .from('imperium_precificacao_config')
          .select()
          .eq('empresa_id', empresaId)
          .maybeSingle();

      if (remotoAtual != null) {
        await _aplicarConfigRemota(Map<String, dynamic>.from(remotoAtual));
        final configAplicada = await _precificacaoRepository.carregarConfig();
        await _salvarMapaConfig(
          empresaId: empresaId,
          localHash: _hashConfig(configAplicada),
          remotoAtualizadoEm: remotoAtual['atualizado_em']?.toString(),
        );
        return;
      }
    }

    if (mapa.isNotEmpty && _texto(mapa.first['local_hash']) == localHash) {
      return;
    }

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
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

    final remoto = await client
        .from('imperium_precificacao_config')
        .upsert(payload, onConflict: 'empresa_id')
        .select('empresa_id,atualizado_em')
        .single();

    await _salvarMapaConfig(
      empresaId: empresaId,
      localHash: localHash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarCatalogo(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('servicos_catalogo', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      await _publicarComMapa(
        empresaId: empresaId,
        localId: localId,
        local: local,
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        tabelaRemota: 'imperium_precificacao_servicos_catalogo',
        hash: _hashServico(local),
        payload: <String, dynamic>{
          'empresa_id': empresaId,
          'nome': _texto(local['nome']),
          'categoria': _texto(local['categoria']),
          'descricao': _texto(local['descricao']),
          'observacoes_padrao': _texto(local['observacoes_padrao']),
          'preco_padrao': _double(local['preco_padrao']),
          'duracao_minutos': _int(local['duracao_minutos']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        },
      );
    }
  }

  Future<void> _publicarColaboradores(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_colaboradores_custo',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      await _publicarComMapa(
        empresaId: empresaId,
        localId: localId,
        local: local,
        tabelaMapa: 'imperium_sync_precificacao_colaboradores',
        tabelaRemota: 'imperium_precificacao_colaboradores_custo',
        hash: _hashColaborador(local),
        payload: <String, dynamic>{
          'empresa_id': empresaId,
          'nome': _texto(local['nome']),
          'funcao': _texto(local['funcao']),
          'remuneracao_mensal': _double(local['remuneracao_mensal']),
          'encargos_mensais': _double(local['encargos_mensais']),
          'outros_custos_mensais': _double(local['outros_custos_mensais']),
          'horas_produtivas_mes': _double(local['horas_produtivas_mes']),
          'observacoes': _texto(local['observacoes']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        },
      );
    }
  }

  Future<void> _publicarPreferencias(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_precificacao_servicos',
      orderBy: 'servico_id ASC',
    );

    for (final local in locais) {
      final servicoLocalId = _int(local['servico_id']);
      if (servicoLocalId <= 0) continue;

      final servicoRemotoId = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        localId: servicoLocalId,
      );
      if (servicoRemotoId == null) continue;

      final hash = _hashPreferencia(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_precificacao_preferencias',
        empresaId: empresaId,
        localId: servicoLocalId,
      );

      if (mapa != null && _texto(mapa['local_hash']) == hash) {
        continue;
      }

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'servico_id': servicoRemotoId,
        'tempo_precificacao_minutos': _doubleNulo(
          local['tempo_precificacao_minutos'],
        ),
        'aceita_revenda': _int(local['aceita_revenda']) != 0,
        'origem_atualizado_em': _textoNulo(local['atualizado_em']),
      };

      final remoto = await client
          .from('imperium_precificacao_servicos')
          .upsert(payload, onConflict: 'empresa_id,servico_id')
          .select('id,atualizado_em')
          .single();

      await _salvarMapa(
        tabela: 'imperium_sync_precificacao_preferencias',
        empresaId: empresaId,
        localId: servicoLocalId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarReceitas(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('servico_produtos', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      final servicoLocalId = _int(local['servico_id']);
      final itemLocalId = _int(local['item_estoque_id']);

      if (localId <= 0 || servicoLocalId <= 0 || itemLocalId <= 0) {
        continue;
      }

      final servicoRemotoId = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        localId: servicoLocalId,
      );
      final itemRemotoId = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_estoque_itens',
        empresaId: empresaId,
        localId: itemLocalId,
      );

      if (servicoRemotoId == null || itemRemotoId == null) continue;

      await _publicarComMapa(
        empresaId: empresaId,
        localId: localId,
        local: local,
        tabelaMapa: 'imperium_sync_precificacao_receitas',
        tabelaRemota: 'imperium_precificacao_servico_produtos',
        hash: _hashReceita(local),
        payload: <String, dynamic>{
          'empresa_id': empresaId,
          'servico_id': servicoRemotoId,
          'item_estoque_id': itemRemotoId,
          'quantidade_padrao': _double(local['quantidade_padrao']),
          'unidade': _texto(local['unidade']),
          'obrigatorio': _int(local['obrigatorio']) != 0,
          'marcado_por_padrao': _int(local['marcado_por_padrao']) != 0,
          'ordem': _int(local['ordem']),
          'excluido_em': null,
        },
      );
    }
  }

  Future<void> _publicarSnapshots(
    String empresaId,
    PrecificacaoPainel painel,
  ) async {
    final client = _client;
    if (client == null) return;

    for (final servico in painel.servicos) {
      final remotoId = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        localId: servico.id,
      );
      if (remotoId == null) continue;

      await client.from('imperium_precificacao_snapshots').upsert({
        'empresa_id': empresaId,
        'servico_id': remotoId,
        'preco_atual': servico.precoAtual,
        'tempo_precificacao_minutos': servico.tempoPrecificacaoMinutos,
        'tempo_medio_real_minutos': servico.tempoMedioRealMinutos,
        'amostras_tempo_real': servico.amostrasTempoReal,
        'custo_produtos': servico.custoProdutos,
        'custo_estrutura': servico.custoEstrutura,
        'custo_base': servico.custoBase,
        'preco_equilibrio': servico.precoEquilibrio,
        'preco_minimo_seguro': servico.precoMinimoSeguro,
        'preco_sugerido': servico.precoSugerido,
        'preco_revenda_1_4': servico.precoRevenda1a4,
        'preco_revenda_5_9': servico.precoRevenda5a9,
        'preco_revenda_10_mais': servico.precoRevenda10Mais,
        'margem_atual': servico.margemAtual,
        'custo_hora': painel.resumo.custoHora,
        'base_mensal_usada': painel.resumo.baseMensalUsada,
        'taxa_cartao_media_percentual': painel.resumo.taxaCartaoMediaPercentual,
        'meses_considerados': painel.resumo.mesesConsiderados,
        'calculado_em': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'empresa_id,servico_id');
    }
  }

  Future<void> _publicarComMapa({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required String tabelaMapa,
    required String tabelaRemota,
    required String hash,
    required Map<String, dynamic> payload,
  }) async {
    final client = _client;
    if (client == null) return;

    final mapa = await _mapaLocal(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );

    if (mapa != null && _texto(mapa['local_hash']) == hash) {
      return;
    }

    final remotoId = _texto(mapa?['remoto_id']);
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from(tabelaRemota)
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from(tabelaRemota)
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: _texto(remoto['id']),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _baixarConfig(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotoRaw = await client
        .from('imperium_precificacao_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (remotoRaw == null) return;

    final remoto = Map<String, dynamic>.from(remotoRaw);
    final database = await _appDatabase.database;
    final mapa = await database.query(
      'imperium_sync_precificacao_config',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      limit: 1,
    );

    final configLocal = await _precificacaoRepository.carregarConfig();
    final localHash = _hashConfig(configLocal);

    if (mapa.isNotEmpty && _texto(mapa.first['local_hash']) != localHash) {
      // V1 nao sobrescreve uma configuracao local alterada depois do baseline.
      return;
    }

    if (mapa.isNotEmpty &&
        _texto(mapa.first['remoto_atualizado_em']) ==
            _texto(remoto['atualizado_em'])) {
      return;
    }

    await _aplicarConfigRemota(remoto);
    final aplicada = await _precificacaoRepository.carregarConfig();

    await _salvarMapaConfig(
      empresaId: empresaId,
      localHash: _hashConfig(aplicada),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
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

  Future<void> _baixarCatalogoNovo(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_servicos_catalogo')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_precificacao_servicos',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      final origemLocalId = await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'servicos_catalogo',
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        remoto: remoto,
        hashBuilder: _hashServico,
      );
      if (origemLocalId != null) continue;

      final existentes = await database.query(
        'servicos_catalogo',
        where: 'LOWER(TRIM(nome)) = LOWER(TRIM(?)) AND categoria = ?',
        whereArgs: [_texto(remoto['nome']), _texto(remoto['categoria'])],
        limit: 1,
      );

      final localId = existentes.isNotEmpty
          ? _int(existentes.first['id'])
          : await database.insert('servicos_catalogo', {
              'nome': _texto(remoto['nome']),
              'categoria': _texto(remoto['categoria']),
              'descricao': _texto(remoto['descricao']),
              'observacoes_padrao': _texto(remoto['observacoes_padrao']),
              'preco_minimo': _double(remoto['preco_padrao']),
              'preco_padrao': _double(remoto['preco_padrao']),
              'preco_maximo': _double(remoto['preco_padrao']),
              'duracao_minutos': _int(remoto['duracao_minutos']),
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

      final local = await _localPorId('servicos_catalogo', localId);

      await _salvarMapa(
        tabela: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashServico(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarColaboradoresNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_colaboradores_custo')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_precificacao_colaboradores',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      final origemLocalId = await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'financeiro_colaboradores_custo',
        tabelaMapa: 'imperium_sync_precificacao_colaboradores',
        remoto: remoto,
        hashBuilder: _hashColaborador,
      );
      if (origemLocalId != null) continue;

      final existentes = await database.query(
        'financeiro_colaboradores_custo',
        where: 'LOWER(TRIM(nome)) = LOWER(TRIM(?)) AND funcao = ?',
        whereArgs: [_texto(remoto['nome']), _texto(remoto['funcao'])],
        limit: 1,
      );

      final localId = existentes.isNotEmpty
          ? _int(existentes.first['id'])
          : await database.insert(
              'financeiro_colaboradores_custo',
              {
                'nome': _texto(remoto['nome']),
                'funcao': _texto(remoto['funcao']),
                'remuneracao_mensal': _double(remoto['remuneracao_mensal']),
                'encargos_mensais': _double(remoto['encargos_mensais']),
                'outros_custos_mensais': _double(
                  remoto['outros_custos_mensais'],
                ),
                'horas_produtivas_mes': _double(remoto['horas_produtivas_mes']),
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
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            );

      final local = await _localPorId(
        'financeiro_colaboradores_custo',
        localId,
      );

      await _salvarMapa(
        tabela: 'imperium_sync_precificacao_colaboradores',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashColaborador(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarPreferencias(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_servicos')
        .select()
        .eq('empresa_id', empresaId);

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final servicoLocalId = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        remotoId: _texto(remoto['servico_id']),
      );
      if (servicoLocalId == null) continue;

      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_precificacao_preferencias',
        empresaId: empresaId,
        localId: servicoLocalId,
      );

      if (mapa != null) continue;

      await database.insert(
        'financeiro_precificacao_servicos',
        {
          'servico_id': servicoLocalId,
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

      final local = await database.query(
        'financeiro_precificacao_servicos',
        where: 'servico_id = ?',
        whereArgs: [servicoLocalId],
        limit: 1,
      );

      if (local.isEmpty) continue;

      await _salvarMapa(
        tabela: 'imperium_sync_precificacao_preferencias',
        empresaId: empresaId,
        localId: servicoLocalId,
        remotoId: _texto(remoto['id']),
        localHash: _hashPreferencia(local.first),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarReceitasNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_servico_produtos')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('ordem');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_precificacao_receitas',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

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

      if (servicoLocalId == null || itemLocalId == null) continue;

      final existentes = await database.query(
        'servico_produtos',
        where: 'servico_id = ? AND item_estoque_id = ?',
        whereArgs: [servicoLocalId, itemLocalId],
        limit: 1,
      );

      final localId = existentes.isNotEmpty
          ? _int(existentes.first['id'])
          : await database.insert('servico_produtos', {
              'servico_id': servicoLocalId,
              'item_estoque_id': itemLocalId,
              'quantidade_padrao': _double(remoto['quantidade_padrao']),
              'unidade': _texto(remoto['unidade']),
              'obrigatorio': remoto['obrigatorio'] == true ? 1 : 0,
              'marcado_por_padrao': remoto['marcado_por_padrao'] == true
                  ? 1
                  : 0,
              'ordem': _int(remoto['ordem']),
            }, conflictAlgorithm: ConflictAlgorithm.abort);

      final local = await _localPorId('servico_produtos', localId);

      await _salvarMapa(
        tabela: 'imperium_sync_precificacao_receitas',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashReceita(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarSnapshots(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_precificacao_snapshots')
        .select()
        .eq('empresa_id', empresaId);

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final servicoRemotoId = _texto(remoto['servico_id']);
      final servicoLocalId = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_precificacao_servicos',
        empresaId: empresaId,
        remotoId: servicoRemotoId,
      );
      if (servicoLocalId == null) continue;

      await database.insert(
        'imperium_sync_precificacao_snapshots',
        {
          'empresa_id': empresaId,
          'servico_local_id': servicoLocalId,
          'servico_remoto_id': servicoRemotoId,
          'snapshot_json': jsonEncode(remoto),
          'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int?> _reconstruirOrigem({
    required String empresaId,
    required String tabelaLocal,
    required String tabelaMapa,
    required Map<String, dynamic> remoto,
    required String Function(Map<String, Object?>) hashBuilder,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return null;
    if (origemDispositivo != await _dispositivoId()) return null;

    final database = await _appDatabase.database;
    final local = await database.query(
      tabelaLocal,
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    if (local.isEmpty) return null;

    await _salvarMapa(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: origemLocalId,
      remotoId: _texto(remoto['id']),
      localHash: hashBuilder(local.first),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    return origemLocalId;
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
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    final mapa = await _mapaLocal(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
    final id = _texto(mapa?['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.trim().isEmpty) return null;

    final mapa = await _mapaPorRemoto(
      tabela: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
    final id = _int(mapa?['local_id']);
    return id <= 0 ? null : id;
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

  Future<void> _salvarMapaConfig({
    required String empresaId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_sync_precificacao_config',
      {
        'empresa_id': empresaId,
        'local_hash': localHash,
        'remoto_atualizado_em': remotoAtualizadoEm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
