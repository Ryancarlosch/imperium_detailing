import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'financeiro_cloud_v2_service.dart';
import 'supabase_bootstrap.dart';

/// Financeiro Cloud V3.
///
/// Fecha o nucleo financeiro compartilhado com:
/// - custos fixos;
/// - metas;
/// - conciliacoes;
/// - comprovantes em Storage privado;
/// - diagnostico local de sincronizacao.
///
/// Nao chama repositories financeiros durante download.
class FinanceiroCloudV3Service {
  FinanceiroCloudV3Service._();

  static final FinanceiroCloudV3Service instance = FinanceiroCloudV3Service._();

  static const String comprovantesBucket = 'imperium-financeiro-comprovantes';

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // financeiro-cloud-v3
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_financeiro_custos_fixos',
      'imperium_sync_financeiro_metas',
      'imperium_sync_financeiro_conciliacoes',
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
      CREATE TABLE IF NOT EXISTS imperium_sync_financeiro_comprovantes (
        empresa_id TEXT NOT NULL,
        pagamento_local_id INTEGER NOT NULL,
        pagamento_remoto_id TEXT NOT NULL,
        local_path TEXT,
        sha256 TEXT,
        storage_bucket TEXT,
        storage_path TEXT,
        nome_original TEXT,
        mime_type TEXT,
        tamanho INTEGER,
        status TEXT NOT NULL DEFAULT 'Pendente',
        erro TEXT,
        sincronizado_em TEXT,
        PRIMARY KEY (empresa_id, pagamento_local_id)
      )
    ''');
  }

  Future<void> sincronizarUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      if (await FinanceiroCloudV2Service.instance.possuiConflitosPendentes(
        empresaId,
      )) {
        return;
      }

      await _reconciliarMutavel(empresaId, 'custo_fixo');
      await _reconciliarMutavel(empresaId, 'meta');

      if (await FinanceiroCloudV2Service.instance.possuiConflitosPendentes(
        empresaId,
      )) {
        return;
      }

      await _publicarMutaveis(empresaId, 'custo_fixo');
      await _publicarMutaveis(empresaId, 'meta');
      await _publicarConciliacoes(empresaId);
      await _sincronizarComprovantesUpload(empresaId);
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
      await _baixarMutaveisNovos(empresaId, 'custo_fixo');
      await _baixarMutaveisNovos(empresaId, 'meta');
      await _baixarConciliacoesNovas(empresaId);
      await _sincronizarMetadadosComprovantes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    Future<int> contar(
      String tabela, {
      String? where,
      List<Object?>? whereArgs,
    }) async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela'
        '${where == null ? '' : ' WHERE $where'}',
        whereArgs,
      );
      return _int(result.first['total']);
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'conflitos_pendentes': await contar(
        'imperium_sync_financeiro_conflitos',
        where: "empresa_id = ? AND status = 'Pendente'",
        whereArgs: [empresaId],
      ),
      'comprovantes_mapeados': await contar(
        'imperium_sync_financeiro_comprovantes',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'comprovantes_com_erro': await contar(
        'imperium_sync_financeiro_comprovantes',
        where: "empresa_id = ? AND status = 'Erro'",
        whereArgs: [empresaId],
      ),
      'custos_fixos_mapeados': await contar(
        'imperium_sync_financeiro_custos_fixos',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'metas_mapeadas': await contar(
        'imperium_sync_financeiro_metas',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
      'conciliacoes_mapeadas': await contar(
        'imperium_sync_financeiro_conciliacoes',
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      ),
    };
  }

  // financeiro-cloud-v3-resolucao
  Future<void> resolverUsandoLocal(int conflitoId) async {
    final conflito = await _buscarConflitoV3(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final entidade = _texto(conflito['entidade']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);

    final config = _configMutavel(entidade);
    final local = await _localPorId(config.local, localId);
    final payload = await _payloadMutavel(
      empresaId: empresaId,
      entidade: entidade,
      local: local,
    );

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponivel.');
    }

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
      localHash: _hashMutavel(entidade, local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'local',
      detalhe: 'Versao local V3 aplicada na nuvem.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    final conflito = await _buscarConflitoV3(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final entidade = _texto(conflito['entidade']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);

    final config = _configMutavel(entidade);
    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponivel.');
    }

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

    await _aplicarMutavelRemoto(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remoto: remoto,
    );

    final local = await _localPorId(config.local, localId);

    await _salvarMapa(
      tabela: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: _hashMutavel(entidade, local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versao da nuvem V3 aplicada diretamente no SQLite.',
    );
  }

  Future<Uint8List?> baixarComprovanteBytes({
    required String empresaId,
    required int pagamentoLocalId,
  }) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) return null;

    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_comprovantes',
      columns: ['storage_bucket', 'storage_path'],
      where: 'empresa_id = ? AND pagamento_local_id = ?',
      whereArgs: [empresaId, pagamentoLocalId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final bucket = _textoPadrao(
      rows.first['storage_bucket'],
      comprovantesBucket,
    );
    final path = _texto(rows.first['storage_path']);
    if (path.isEmpty) return null;

    return client.storage.from(bucket).download(path);
  }

  Future<void> _reconciliarMutavel(String empresaId, String entidade) async {
    final client = _client;
    if (client == null) return;

    final config = _configMutavel(entidade);
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
          remoto: const <String, dynamic>{},
          localHashAtual: '',
        );
        continue;
      }

      final local = locais.first;
      final hashAtual = _hashMutavel(entidade, local);
      final localMudou = hashAtual != _texto(mapa['local_hash']);

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
          remoto: const <String, dynamic>{},
          localHashAtual: hashAtual,
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
          remoto: remoto,
          localHashAtual: hashAtual,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        try {
          await _aplicarMutavelRemoto(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remoto: remoto,
          );
        } on _DependenciaFinanceiroV3Pendente {
          continue;
        }

        final localAtual = await _localPorId(config.local, localId);

        await _salvarMapa(
          tabela: config.mapa,
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: _hashMutavel(entidade, localAtual),
          remotoAtualizadoEm: remotoAtual,
        );
      }
    }
  }

  Future<void> _publicarMutaveis(String empresaId, String entidade) async {
    final client = _client;
    if (client == null) return;

    final config = _configMutavel(entidade);
    final database = await _appDatabase.database;
    final locais = await database.query(config.local, orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      if (await _conflitoPendente(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
      )) {
        continue;
      }

      final hash = _hashMutavel(entidade, local);
      final mapa = await _mapaLocal(
        tabela: config.mapa,
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      Map<String, dynamic> payload;
      try {
        payload = await _payloadMutavel(
          empresaId: empresaId,
          entidade: entidade,
          local: local,
        );
      } on _DependenciaFinanceiroV3Pendente {
        continue;
      }

      final remotoId = _texto(mapa == null ? null : mapa['remoto_id']);
      Map<String, dynamic> remotoSalvo;

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

        remotoSalvo = Map<String, dynamic>.from(resposta);
      } else {
        final esperado = _texto(mapa?['remoto_atualizado_em']);

        final resposta = esperado.isEmpty
            ? await client
                  .from(config.remota)
                  .update(payload)
                  .eq('empresa_id', empresaId)
                  .eq('id', remotoId)
                  .select('id,atualizado_em')
            : await client
                  .from(config.remota)
                  .update(payload)
                  .eq('empresa_id', empresaId)
                  .eq('id', remotoId)
                  .eq('atualizado_em', esperado)
                  .select('id,atualizado_em');

        if (resposta.isEmpty) {
          final remotoAtualRaw = await client
              .from(config.remota)
              .select()
              .eq('empresa_id', empresaId)
              .eq('id', remotoId)
              .maybeSingle();

          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'cas_falhou_alteracao_concorrente',
            mapa: mapa!,
            local: local,
            remoto: remotoAtualRaw == null
                ? const <String, dynamic>{}
                : Map<String, dynamic>.from(remotoAtualRaw),
            localHashAtual: hash,
          );
          continue;
        }

        remotoSalvo = Map<String, dynamic>.from(resposta.first);
      }

      await _salvarMapa(
        tabela: config.mapa,
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remotoSalvo['id']),
        localHash: hash,
        remotoAtualizadoEm: remotoSalvo['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarConciliacoes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_conciliacoes_conta',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final contaRemota = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: _int(local['conta_id']),
      );
      if (contaRemota == null) continue;

      final movimentoLocalId = _int(local['movimento_ajuste_id']);
      final movimentoRemoto = movimentoLocalId <= 0
          ? null
          : await _remotoPorLocal(
              tabela: 'imperium_sync_financeiro_movimentos',
              empresaId: empresaId,
              localId: movimentoLocalId,
            );

      if (movimentoLocalId > 0 && movimentoRemoto == null) continue;

      final hash = _hashConciliacao(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_conciliacoes',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'conta_id': contaRemota,
        'origem_conta_local_id': _int(local['conta_id']),
        'data_conciliacao': _texto(local['data_conciliacao']),
        'saldo_calculado': _double(local['saldo_calculado']),
        'saldo_informado': _double(local['saldo_informado']),
        'diferenca': _double(local['diferenca']),
        'status': _textoPadrao(local['status'], 'Conciliado'),
        'movimento_ajuste_id': movimentoRemoto,
        'origem_movimento_ajuste_local_id': _intNulo(
          local['movimento_ajuste_id'],
        ),
        'observacoes': _texto(local['observacoes']),
        'origem_criado_em': _textoNulo(local['criado_em']),
        'excluido_em': null,
      };

      final remotoId = _texto(mapa == null ? null : mapa['remoto_id']);
      final Map<String, dynamic> remoto;

      if (remotoId.isEmpty) {
        payload['origem_dispositivo'] = await _dispositivoId();
        payload['origem_local_id'] = localId;

        final resposta = await client
            .from('imperium_financeiro_conciliacoes')
            .upsert(
              payload,
              onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
            )
            .select('id,atualizado_em')
            .single();

        remoto = Map<String, dynamic>.from(resposta);
      } else {
        final resposta = await client
            .from('imperium_financeiro_conciliacoes')
            .update(payload)
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .select('id,atualizado_em')
            .single();

        remoto = Map<String, dynamic>.from(resposta);
      }

      await _salvarMapa(
        tabela: 'imperium_sync_financeiro_conciliacoes',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _sincronizarComprovantesUpload(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final pagamentos = await database.rawQuery('''
      SELECT id, comprovante_caminho
      FROM ordem_servico_pagamentos
      WHERE TRIM(COALESCE(comprovante_caminho, '')) != ''
      ORDER BY id ASC
    ''');

    for (final pagamento in pagamentos) {
      final localId = _int(pagamento['id']);
      final localPath = _texto(pagamento['comprovante_caminho']);

      if (localId <= 0 || localPath.isEmpty) continue;

      final remotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_financeiro_pagamentos',
        empresaId: empresaId,
        localId: localId,
      );
      if (remotoId == null) continue;

      try {
        final arquivo = XFile(localPath);
        final bytes = await arquivo.readAsBytes();
        if (bytes.isEmpty) continue;

        final arquivoHash = sha256.convert(bytes).toString();
        final existente = await database.query(
          'imperium_sync_financeiro_comprovantes',
          where: 'empresa_id = ? AND pagamento_local_id = ?',
          whereArgs: [empresaId, localId],
          limit: 1,
        );

        if (existente.isNotEmpty &&
            _texto(existente.first['sha256']) == arquivoHash &&
            _texto(existente.first['status']) == 'Enviado') {
          continue;
        }

        final nomeOriginal = p.basename(localPath);
        var extensao = p.extension(nomeOriginal).toLowerCase();
        extensao = extensao.replaceAll(RegExp(r'[^a-z0-9.]'), '');
        if (extensao.isEmpty || extensao.length > 12) extensao = '.bin';

        final mimeType = _mimePorExtensao(extensao);
        final storagePath =
            '$empresaId/pagamentos/$remotoId/'
            '${arquivoHash.substring(0, 20)}$extensao';

        await client.storage
            .from(comprovantesBucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                upsert: true,
                cacheControl: '3600',
                contentType: mimeType,
              ),
            );

        final remoto = await client
            .from('imperium_financeiro_pagamentos_os')
            .update({
              'comprovante_storage_bucket': comprovantesBucket,
              'comprovante_storage_path': storagePath,
              'comprovante_nome_original': nomeOriginal,
              'comprovante_sha256': arquivoHash,
              'comprovante_tamanho': bytes.length,
              'comprovante_mime': mimeType,
            })
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .select('atualizado_em')
            .single();

        await database.update(
          'imperium_sync_financeiro_pagamentos',
          {'remoto_atualizado_em': remoto['atualizado_em']?.toString()},
          where: 'empresa_id = ? AND local_id = ?',
          whereArgs: [empresaId, localId],
        );

        await _salvarComprovanteLocal(
          empresaId: empresaId,
          pagamentoLocalId: localId,
          pagamentoRemotoId: remotoId,
          localPath: localPath,
          sha: arquivoHash,
          storagePath: storagePath,
          nomeOriginal: nomeOriginal,
          mimeType: mimeType,
          tamanho: bytes.length,
          status: 'Enviado',
        );
      } catch (error) {
        await _salvarComprovanteLocal(
          empresaId: empresaId,
          pagamentoLocalId: localId,
          pagamentoRemotoId: remotoId,
          localPath: localPath,
          status: 'Erro',
          erro: error.toString(),
        );
      }
    }
  }

  Future<void> _sincronizarMetadadosComprovantes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_pagamentos_os')
        .select(
          'id,comprovante_storage_bucket,comprovante_storage_path,'
          'comprovante_nome_original,comprovante_sha256,'
          'comprovante_tamanho,comprovante_mime',
        )
        .eq('empresa_id', empresaId);

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      final storagePath = _texto(remoto['comprovante_storage_path']);
      if (remotoId.isEmpty || storagePath.isEmpty) continue;

      final mapaPagamento = await _mapaPorRemoto(
        tabela: 'imperium_sync_financeiro_pagamentos',
        empresaId: empresaId,
        remotoId: remotoId,
      );
      if (mapaPagamento == null) continue;

      final localId = _int(mapaPagamento['local_id']);
      if (localId <= 0) continue;

      final atual = await database.query(
        'imperium_sync_financeiro_comprovantes',
        where: 'empresa_id = ? AND pagamento_local_id = ?',
        whereArgs: [empresaId, localId],
        limit: 1,
      );

      await _salvarComprovanteLocal(
        empresaId: empresaId,
        pagamentoLocalId: localId,
        pagamentoRemotoId: remotoId,
        localPath: atual.isEmpty ? null : _textoNulo(atual.first['local_path']),
        sha: _textoNulo(remoto['comprovante_sha256']),
        storageBucket: _textoPadrao(
          remoto['comprovante_storage_bucket'],
          comprovantesBucket,
        ),
        storagePath: storagePath,
        nomeOriginal: _textoNulo(remoto['comprovante_nome_original']),
        mimeType: _textoNulo(remoto['comprovante_mime']),
        tamanho: _intNulo(remoto['comprovante_tamanho']),
        status: atual.isNotEmpty && _texto(atual.first['status']) == 'Enviado'
            ? 'Enviado'
            : 'Disponivel',
      );
    }
  }

  Future<void> _salvarComprovanteLocal({
    required String empresaId,
    required int pagamentoLocalId,
    required String pagamentoRemotoId,
    String? localPath,
    String? sha,
    String? storageBucket,
    String? storagePath,
    String? nomeOriginal,
    String? mimeType,
    int? tamanho,
    required String status,
    String? erro,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_sync_financeiro_comprovantes',
      {
        'empresa_id': empresaId,
        'pagamento_local_id': pagamentoLocalId,
        'pagamento_remoto_id': pagamentoRemotoId,
        'local_path': localPath,
        'sha256': sha,
        'storage_bucket': storageBucket ?? comprovantesBucket,
        'storage_path': storagePath,
        'nome_original': nomeOriginal,
        'mime_type': mimeType,
        'tamanho': tamanho,
        'status': status,
        'erro': erro,
        'sincronizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _baixarMutaveisNovos(String empresaId, String entidade) async {
    final client = _client;
    if (client == null) return;

    final config = _configMutavel(entidade);
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
        final localId = await _inserirMutavelRemoto(
          empresaId: empresaId,
          entidade: entidade,
          remoto: remoto,
        );
        final local = await _localPorId(config.local, localId);

        await _salvarMapa(
          tabela: config.mapa,
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: _hashMutavel(entidade, local),
          remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        );
      } on _DependenciaFinanceiroV3Pendente {
        continue;
      }
    }
  }

  Future<void> _baixarConciliacoesNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_financeiro_conciliacoes')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _mapaPorRemoto(
            tabela: 'imperium_sync_financeiro_conciliacoes',
            empresaId: empresaId,
            remotoId: remotoId,
          ) !=
          null) {
        continue;
      }

      if (await _reconstruirMapaConciliacaoOrigem(
        empresaId: empresaId,
        remoto: remoto,
      )) {
        continue;
      }

      try {
        final contaLocal = await _localPorRemotoObrigatorio(
          tabelaMapa: 'imperium_sync_financeiro_contas',
          empresaId: empresaId,
          remotoId: _texto(remoto['conta_id']),
        );

        final movimentoLocal = await _localPorRemotoOpcional(
          tabelaMapa: 'imperium_sync_financeiro_movimentos',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['movimento_ajuste_id']),
        );

        final localId = await database.insert(
          'financeiro_conciliacoes_conta',
          {
            'conta_id': contaLocal,
            'data_conciliacao': _texto(remoto['data_conciliacao']),
            'saldo_calculado': _double(remoto['saldo_calculado']),
            'saldo_informado': _double(remoto['saldo_informado']),
            'diferenca': _double(remoto['diferenca']),
            'status': _textoPadrao(remoto['status'], 'Conciliado'),
            'movimento_ajuste_id': movimentoLocal,
            'observacoes': _texto(remoto['observacoes']),
            'criado_em': _textoPreferido(
              remoto['origem_criado_em'],
              remoto['criado_em'],
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final local = await _localPorId(
          'financeiro_conciliacoes_conta',
          localId,
        );

        await _salvarMapa(
          tabela: 'imperium_sync_financeiro_conciliacoes',
          empresaId: empresaId,
          localId: localId,
          remotoId: remotoId,
          localHash: _hashConciliacao(local),
          remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        );
      } on _DependenciaFinanceiroV3Pendente {
        continue;
      }
    }
  }

  Future<int> _inserirMutavelRemoto({
    required String empresaId,
    required String entidade,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final planoLocal = await _localPorRemotoOpcional(
      tabelaMapa: 'imperium_sync_financeiro_plano_contas',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['plano_conta_id']),
    );

    if (entidade == 'custo_fixo') {
      return database.insert('financeiro_custos_fixos', {
        'nome': _texto(remoto['nome']),
        'valor_mensal': _double(remoto['valor_mensal']),
        'categoria': _textoPadrao(remoto['categoria'], 'Despesa fixa'),
        'dia_vencimento': _intNulo(remoto['dia_vencimento']),
        'plano_conta_id': planoLocal,
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

    if (entidade == 'meta') {
      return database.insert('financeiro_metas', {
        'ano': _int(remoto['ano']),
        'mes': _int(remoto['mes']),
        'tipo': _texto(remoto['tipo']),
        'plano_conta_id': planoLocal,
        'valor_meta': _double(remoto['valor_meta']),
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

    throw StateError('Entidade V3 invalida: $entidade');
  }

  Future<Map<String, dynamic>> _payloadMutavel({
    required String empresaId,
    required String entidade,
    required Map<String, Object?> local,
  }) async {
    final planoLocalId = _int(local['plano_conta_id']);
    final planoRemoto = planoLocalId <= 0
        ? null
        : await _remotoPorLocal(
            tabela: 'imperium_sync_financeiro_plano_contas',
            empresaId: empresaId,
            localId: planoLocalId,
          );

    if (planoLocalId > 0 && planoRemoto == null) {
      throw _DependenciaFinanceiroV3Pendente();
    }

    if (entidade == 'custo_fixo') {
      return <String, dynamic>{
        'empresa_id': empresaId,
        'nome': _texto(local['nome']),
        'valor_mensal': _double(local['valor_mensal']),
        'categoria': _textoPadrao(local['categoria'], 'Despesa fixa'),
        'dia_vencimento': _intNulo(local['dia_vencimento']),
        'plano_conta_id': planoRemoto,
        'origem_plano_conta_local_id': _intNulo(local['plano_conta_id']),
        'observacoes': _texto(local['observacoes']),
        'ativo': _int(local['ativo']) != 0,
        'origem_criado_em': _textoNulo(local['criado_em']),
        'origem_atualizado_em': _textoNulo(local['atualizado_em']),
        'excluido_em': null,
      };
    }

    if (entidade == 'meta') {
      return <String, dynamic>{
        'empresa_id': empresaId,
        'ano': _int(local['ano']),
        'mes': _int(local['mes']),
        'tipo': _texto(local['tipo']),
        'plano_conta_id': planoRemoto,
        'origem_plano_conta_local_id': _intNulo(local['plano_conta_id']),
        'valor_meta': _double(local['valor_meta']),
        'observacoes': _texto(local['observacoes']),
        'ativo': _int(local['ativo']) != 0,
        'origem_criado_em': _textoNulo(local['criado_em']),
        'origem_atualizado_em': _textoNulo(local['atualizado_em']),
        'excluido_em': null,
      };
    }

    throw StateError('Payload V3 invalido: $entidade');
  }

  Future<void> _aplicarMutavelRemoto({
    required String empresaId,
    required String entidade,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final planoLocal = await _localPorRemotoOpcional(
      tabelaMapa: 'imperium_sync_financeiro_plano_contas',
      empresaId: empresaId,
      remotoId: _textoNulo(remoto['plano_conta_id']),
    );
    final excluido = _texto(remoto['excluido_em']).isNotEmpty;

    if (entidade == 'custo_fixo') {
      await database.update(
        'financeiro_custos_fixos',
        {
          'nome': _texto(remoto['nome']),
          'valor_mensal': _double(remoto['valor_mensal']),
          'categoria': _textoPadrao(remoto['categoria'], 'Despesa fixa'),
          'dia_vencimento': _intNulo(remoto['dia_vencimento']),
          'plano_conta_id': planoLocal,
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
      return;
    }

    if (entidade == 'meta') {
      await database.update(
        'financeiro_metas',
        {
          'ano': _int(remoto['ano']),
          'mes': _int(remoto['mes']),
          'tipo': _texto(remoto['tipo']),
          'plano_conta_id': planoLocal,
          'valor_meta': _double(remoto['valor_meta']),
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
      return;
    }

    throw StateError('Aplicacao V3 invalida: $entidade');
  }

  _ConfigV3 _configMutavel(String entidade) {
    switch (entidade) {
      case 'custo_fixo':
        return const _ConfigV3(
          local: 'financeiro_custos_fixos',
          remota: 'imperium_financeiro_custos_fixos',
          mapa: 'imperium_sync_financeiro_custos_fixos',
        );
      case 'meta':
        return const _ConfigV3(
          local: 'financeiro_metas',
          remota: 'imperium_financeiro_metas',
          mapa: 'imperium_sync_financeiro_metas',
        );
      default:
        throw StateError('Entidade V3 invalida: $entidade');
    }
  }

  Future<bool> _reconstruirMapaOrigem({
    required String empresaId,
    required String entidade,
    required Map<String, dynamic> remoto,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return false;
    if (origemDispositivo != await _dispositivoId()) return false;

    final config = _configMutavel(entidade);
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
      localHash: _hashMutavel(entidade, local.first),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    return true;
  }

  Future<bool> _reconstruirMapaConciliacaoOrigem({
    required String empresaId,
    required Map<String, dynamic> remoto,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return false;
    if (origemDispositivo != await _dispositivoId()) return false;

    final database = await _appDatabase.database;
    final local = await database.query(
      'financeiro_conciliacoes_conta',
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    if (local.isEmpty) return false;

    await _salvarMapa(
      tabela: 'imperium_sync_financeiro_conciliacoes',
      empresaId: empresaId,
      localId: origemLocalId,
      remotoId: _texto(remoto['id']),
      localHash: _hashConciliacao(local.first),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    return true;
  }

  Future<bool> _conflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND status = 'Pendente'",
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
    required Map<String, Object?> mapa,
    required Map<String, Object?> local,
    required Map<String, dynamic> remoto,
    required String localHashAtual,
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

  Future<Map<String, Object?>> _buscarConflitoV3(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_financeiro_conflitos',
      where:
          "id = ? AND status = 'Pendente' "
          "AND entidade IN ('custo_fixo', 'meta')",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito V3 pendente nao encontrado.');
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
      'imperium_sync_financeiro_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
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
    final localId = _int(mapa == null ? null : mapa['local_id']);

    if (mapa == null || localId <= 0) {
      throw _DependenciaFinanceiroV3Pendente();
    }

    return localId;
  }

  Future<int?> _localPorRemotoOpcional({
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

  String _hashMutavel(String entidade, Map<String, Object?> local) {
    if (entidade == 'custo_fixo') {
      return _sha(<Object?>[
        local['nome'],
        _double(local['valor_mensal']),
        local['categoria'],
        _intNulo(local['dia_vencimento']),
        _intNulo(local['plano_conta_id']),
        local['observacoes'],
        _int(local['ativo']),
        local['criado_em'],
        local['atualizado_em'],
      ]);
    }

    if (entidade == 'meta') {
      return _sha(<Object?>[
        _int(local['ano']),
        _int(local['mes']),
        local['tipo'],
        _intNulo(local['plano_conta_id']),
        _double(local['valor_meta']),
        local['observacoes'],
        _int(local['ativo']),
        local['criado_em'],
        local['atualizado_em'],
      ]);
    }

    throw StateError('Hash V3 invalido: $entidade');
  }

  String _hashConciliacao(Map<String, Object?> local) {
    return _sha(<Object?>[
      _int(local['conta_id']),
      local['data_conciliacao'],
      _double(local['saldo_calculado']),
      _double(local['saldo_informado']),
      _double(local['diferenca']),
      local['status'],
      _intNulo(local['movimento_ajuste_id']),
      local['observacoes'],
      local['criado_em'],
    ]);
  }

  String _sha(List<Object?> values) {
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  }

  static String _mimePorExtensao(String extensao) {
    switch (extensao.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static int? _intNulo(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoNulo(Object? value) {
    final text = _texto(value);
    return text.isEmpty ? null : text;
  }

  static String _textoPadrao(Object? value, String padrao) {
    final text = _texto(value);
    return text.isEmpty ? padrao : text;
  }

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;
    final b = _texto(segundo);
    if (b.isNotEmpty) return b;
    return DateTime.now().toIso8601String();
  }
}

class _ConfigV3 {
  const _ConfigV3({
    required this.local,
    required this.remota,
    required this.mapa,
  });

  final String local;
  final String remota;
  final String mapa;
}

class _DependenciaFinanceiroV3Pendente implements Exception {}
