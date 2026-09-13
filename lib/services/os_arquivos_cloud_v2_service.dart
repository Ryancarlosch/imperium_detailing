import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'os_arquivos_cloud_service.dart';
import 'supabase_bootstrap.dart';

/// Arquivos Cloud da OS V2.
///
/// Protege checklist/foto de avaria e assinatura contra edição concorrente.
/// Fotos Antes/Depois continuam append/soft-delete no V1.
///
/// Regra:
/// - só local mudou: V1 pode publicar;
/// - só nuvem mudou: aplica a nuvem localmente e atualiza o baseline;
/// - ambos mudaram: registra conflito e bloqueia apenas Arquivos da OS;
/// - "Usar local": grava com CAS por atualizado_em;
/// - "Usar nuvem": baixa/aplica direto no SQLite.
class OsArquivosCloudV2Service {
  OsArquivosCloudV2Service._();

  static final OsArquivosCloudV2Service instance = OsArquivosCloudV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // os-arquivos-cloud-v2
  Future<void> garantirEstruturaLocal() async {
    await OsArquivosCloudService.instance.garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_arquivos_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        entidade TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_base TEXT,
        remoto_atual TEXT,
        remoto_atualizado_atual TEXT,
        status TEXT NOT NULL DEFAULT 'Pendente',
        resolucao TEXT,
        detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_os_arquivos_conflitos
      ON imperium_sync_os_arquivos_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');
  }

  /// Deve rodar antes do upload V1 e novamente antes do download V1.
  Future<bool> prepararSincronizacao(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return false;

    try {
      await garantirEstruturaLocal();

      if (await possuiConflitosPendentes(empresaId)) return false;

      await _reconciliarChecklist(empresaId);
      await _reconciliarAssinaturas(empresaId);

      return !await possuiConflitosPendentes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return false;
      rethrow;
    }
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_os_arquivos_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    required String empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_os_arquivos_conflitos',
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final base = await OsArquivosCloudService.instance.diagnosticar(empresaId);
    final database = await _appDatabase.database;

    final conflitos = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_os_arquivos_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [empresaId],
    );

    final assinaturasConflito = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_os_assinaturas
      WHERE empresa_id = ? AND status = 'Conflito'
      ''',
      [empresaId],
    );

    return <String, Object?>{
      ...base,
      'conflitos_pendentes': _int(conflitos.first['total']),
      'assinaturas_em_conflito': _int(assinaturasConflito.first['total']),
    };
  }

  // os-arquivos-cloud-v2-resolucao
  Future<void> resolverUsandoLocal(int conflitoId) async {
    await garantirEstruturaLocal();

    final conflito = await _buscarConflito(conflitoId);
    final entidade = _texto(conflito['entidade']);

    if (entidade == 'checklist') {
      await _resolverChecklistLocal(conflitoId, conflito);
    } else if (entidade == 'assinatura') {
      await _resolverAssinaturaLocal(conflitoId, conflito);
    } else {
      throw StateError('Entidade de conflito inválida: $entidade');
    }
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    await garantirEstruturaLocal();

    final conflito = await _buscarConflito(conflitoId);
    final entidade = _texto(conflito['entidade']);

    if (entidade == 'checklist') {
      await _resolverChecklistNuvem(conflitoId, conflito);
    } else if (entidade == 'assinatura') {
      await _resolverAssinaturaNuvem(conflitoId, conflito);
    } else {
      throw StateError('Entidade de conflito inválida: $entidade');
    }
  }

  Future<void> _reconciliarChecklist(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      'imperium_sync_os_checklist',
      where: "empresa_id = ? AND local_hash != '__excluido__'",
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      final remotoId = _texto(mapa['remoto_id']);
      if (localId <= 0 || remotoId.isEmpty) continue;

      if (await _jaExisteConflito(
        empresaId: empresaId,
        entidade: 'checklist',
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final remotoRaw = await client
          .from('imperium_ordem_servico_checklist')
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoRaw == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'checklist',
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_remoto_ausente',
          localHashBase: _texto(mapa['local_hash']),
          localHashAtual: await _hashChecklistLocalSeExiste(localId),
          remotoBase: _texto(mapa['remoto_atualizado_em']),
          remotoAtual: '',
          remotoAtualizadoAtual: '',
        );
        continue;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoBase = _texto(mapa['remoto_atualizado_em']);
      final remotoAtualizado = _texto(remoto['atualizado_em']);
      final remotoMudou =
          remotoBase.isNotEmpty &&
          remotoAtualizado.isNotEmpty &&
          remotoBase != remotoAtualizado;

      final locais = await database.query(
        'ordem_servico_checklist',
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (_texto(remoto['excluido_em']).isNotEmpty) {
        if (locais.isNotEmpty) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: 'checklist',
            localId: localId,
            remotoId: remotoId,
            motivo: 'excluido_na_nuvem',
            localHashBase: _texto(mapa['local_hash']),
            localHashAtual: await _hashChecklistLocal(locais.first),
            remotoBase: remotoBase,
            remotoAtual: '__excluido__',
            remotoAtualizadoAtual: remotoAtualizado,
          );
        }
        continue;
      }

      if (locais.isEmpty) {
        if (remotoMudou) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: 'checklist',
            localId: localId,
            remotoId: remotoId,
            motivo: 'excluido_local_remoto_alterado',
            localHashBase: _texto(mapa['local_hash']),
            localHashAtual: '__excluido__',
            remotoBase: remotoBase,
            remotoAtual: remotoAtualizado,
            remotoAtualizadoAtual: remotoAtualizado,
          );
        }
        continue;
      }

      final localHashAtual = await _hashChecklistLocal(locais.first);
      final localHashBase = _texto(mapa['local_hash']);
      final localMudou =
          localHashBase.isNotEmpty && localHashAtual != localHashBase;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'checklist',
          localId: localId,
          remotoId: remotoId,
          motivo: 'alteracao_concorrente',
          localHashBase: localHashBase,
          localHashAtual: localHashAtual,
          remotoBase: remotoBase,
          remotoAtual: remotoAtualizado,
          remotoAtualizadoAtual: remotoAtualizado,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        await _aplicarChecklistRemoto(
          empresaId: empresaId,
          localId: localId,
          remoto: remoto,
        );
      }
    }
  }

  Future<void> _reconciliarAssinaturas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      'imperium_sync_os_assinaturas',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['os_local_id']);
      final remotoId = _texto(mapa['os_remoto_id']);
      if (localId <= 0 || remotoId.isEmpty) continue;

      if (await _jaExisteConflito(
        empresaId: empresaId,
        entidade: 'assinatura',
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final remotoRaw = await client
          .from('imperium_ordens_servico')
          .select(
            'id,atualizado_em,assinatura_storage_path,'
            'assinatura_nome_original,assinatura_sha256,'
            'assinatura_tamanho,assinatura_mime',
          )
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoRaw == null) continue;

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoSha = _texto(remoto['assinatura_sha256']);
      final remotoBase = _texto(mapa['remoto_sha256']);

      final os = await database.query(
        'ordens_servico',
        columns: ['assinatura_cliente'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (os.isEmpty) continue;

      final caminho = _texto(os.first['assinatura_cliente']);
      final localSha = await _shaArquivo(caminho) ?? '';
      final localBase = _texto(mapa['local_sha256']);

      final localMudou = localSha != localBase;
      final remotoMudou = remotoSha != remotoBase;

      if (_texto(mapa['status']) == 'Conflito' ||
          (localMudou && remotoMudou && localSha != remotoSha)) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: 'assinatura',
          localId: localId,
          remotoId: remotoId,
          motivo: 'alteracao_concorrente',
          localHashBase: localBase,
          localHashAtual: localSha,
          remotoBase: remotoBase,
          remotoAtual: remotoSha,
          remotoAtualizadoAtual: _texto(remoto['atualizado_em']),
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        await _aplicarAssinaturaRemota(
          empresaId: empresaId,
          osLocalId: localId,
          osRemotoId: remotoId,
          remoto: remoto,
        );
      }
    }
  }

  Future<void> _aplicarChecklistRemoto({
    required String empresaId,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final storagePath = _texto(remoto['foto_avaria_storage_path']);
    String? fotoLocal;

    if (storagePath.isNotEmpty) {
      fotoLocal = await _materializar(
        osLocalId: await _osLocalDoChecklist(localId),
        tipo: 'checklist-v2',
        remotoId: _texto(remoto['id']),
        storagePath: storagePath,
        nomeOriginal: _texto(remoto['foto_avaria_nome_original']),
        mime: _texto(remoto['foto_avaria_mime']),
      );
    }

    await database.update(
      'ordem_servico_checklist',
      {
        'categoria': _textoPadrao(remoto['categoria'], 'Geral'),
        'item': _texto(remoto['item']),
        'marcado': remoto['marcado'] == true ? 1 : 0,
        'status': _int(remoto['status']),
        'observacao': _texto(remoto['observacao']),
        'foto_avaria': fotoLocal,
        'avaria_localizacao': _texto(remoto['avaria_localizacao']),
        'avaria_data_registro': _textoNulo(remoto['avaria_data_registro']),
        'ordem': _int(remoto['ordem']),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );

    final atualizado = await _localPorId('ordem_servico_checklist', localId);

    await database.update(
      'imperium_sync_os_checklist',
      {
        'local_hash': await _hashChecklistLocal(atualizado),
        'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
        'storage_path': _textoNulo(remoto['foto_avaria_storage_path']),
        'sha256': _textoNulo(remoto['foto_avaria_sha256']),
        'tamanho': _intNulo(remoto['foto_avaria_tamanho']),
        'mime': _textoNulo(remoto['foto_avaria_mime']),
        'status': 'Sincronizado',
        'erro': null,
      },
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
    );
  }

  Future<void> _aplicarAssinaturaRemota({
    required String empresaId,
    required int osLocalId,
    required String osRemotoId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final storagePath = _texto(remoto['assinatura_storage_path']);
    final remotoSha = _texto(remoto['assinatura_sha256']);

    String? localPath;
    if (storagePath.isNotEmpty) {
      localPath = await _materializar(
        osLocalId: osLocalId,
        tipo: 'assinatura-v2',
        remotoId: osRemotoId,
        storagePath: storagePath,
        nomeOriginal: _texto(remoto['assinatura_nome_original']),
        mime: _texto(remoto['assinatura_mime']),
      );
    }

    await database.update(
      'ordens_servico',
      {'assinatura_cliente': localPath},
      where: 'id = ?',
      whereArgs: [osLocalId],
    );

    await database.insert('imperium_sync_os_assinaturas', {
      'empresa_id': empresaId,
      'os_local_id': osLocalId,
      'os_remoto_id': osRemotoId,
      'local_path': localPath,
      'local_sha256': remotoSha,
      'remoto_sha256': remotoSha,
      'storage_path': storagePath.isEmpty ? null : storagePath,
      'tamanho': _intNulo(remoto['assinatura_tamanho']),
      'mime': _textoNulo(remoto['assinatura_mime']),
      'status': 'Sincronizado',
      'erro': null,
      'sincronizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await database.update(
      'imperium_sync_ordens_servico',
      {'remoto_atualizado_em': remoto['atualizado_em']?.toString()},
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, osLocalId],
    );
  }

  Future<void> _resolverChecklistLocal(
    int conflitoId,
    Map<String, Object?> conflito,
  ) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    final empresaId = _texto(conflito['empresa_id']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final esperado = _texto(conflito['remoto_atualizado_atual']);
    final database = await _appDatabase.database;

    final locais = await database.query(
      'ordem_servico_checklist',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (locais.isEmpty) {
      final resposta = esperado.isEmpty
          ? await client
                .from('imperium_ordem_servico_checklist')
                .update({
                  'excluido_em': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .select('id,atualizado_em')
                .maybeSingle()
          : await client
                .from('imperium_ordem_servico_checklist')
                .update({
                  'excluido_em': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('empresa_id', empresaId)
                .eq('id', remotoId)
                .eq('atualizado_em', esperado)
                .select('id,atualizado_em')
                .maybeSingle();

      if (resposta == null) {
        throw StateError('A nuvem mudou novamente. Sincronize e revise.');
      }

      await database.update(
        'imperium_sync_os_checklist',
        {
          'local_hash': '__excluido__',
          'remoto_atualizado_em': resposta['atualizado_em']?.toString(),
          'status': 'Sincronizado',
          'erro': null,
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );

      await _encerrar(conflitoId, 'local', 'Exclusão local aplicada com CAS.');
      return;
    }

    final local = locais.first;
    final osRemotoId = await _osRemoto(
      empresaId: empresaId,
      osLocalId: _int(local['ordem_servico_id']),
    );
    if (osRemotoId == null) {
      throw StateError('OS ainda não está mapeada na nuvem.');
    }

    final arquivo = await _arquivoLocal(_texto(local['foto_avaria']));
    String? storagePath;

    if (arquivo != null) {
      storagePath =
          '$empresaId/ordens-servico/$osRemotoId/checklist/'
          '$localId-${arquivo.sha.substring(0, 20)}.${arquivo.extensao}';

      await client.storage
          .from(OsArquivosCloudService.bucket)
          .uploadBinary(
            storagePath,
            arquivo.bytes,
            fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
          );
    }

    final payload = <String, dynamic>{
      'categoria': _textoPadrao(local['categoria'], 'Geral'),
      'item': _texto(local['item']),
      'marcado': _int(local['marcado']) != 0,
      'status': _int(local['status']),
      'observacao': _texto(local['observacao']),
      'avaria_localizacao': _texto(local['avaria_localizacao']),
      'avaria_data_registro': _textoNulo(local['avaria_data_registro']),
      'ordem': _int(local['ordem']),
      'foto_avaria_origem_caminho': _textoNulo(local['foto_avaria']),
      'foto_avaria_storage_bucket': storagePath == null
          ? null
          : OsArquivosCloudService.bucket,
      'foto_avaria_storage_path': storagePath,
      'foto_avaria_nome_original': arquivo?.nome,
      'foto_avaria_sha256': arquivo?.sha,
      'foto_avaria_tamanho': arquivo?.bytes.length,
      'foto_avaria_mime': arquivo?.mime,
      'excluido_em': null,
    };

    final resposta = esperado.isEmpty
        ? await client
              .from('imperium_ordem_servico_checklist')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', remotoId)
              .select('id,atualizado_em')
              .maybeSingle()
        : await client
              .from('imperium_ordem_servico_checklist')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', remotoId)
              .eq('atualizado_em', esperado)
              .select('id,atualizado_em')
              .maybeSingle();

    if (resposta == null) {
      throw StateError('A nuvem mudou novamente. Sincronize e revise.');
    }

    await database.update(
      'imperium_sync_os_checklist',
      {
        'local_hash': await _hashChecklistLocal(local),
        'remoto_atualizado_em': resposta['atualizado_em']?.toString(),
        'storage_path': storagePath,
        'sha256': arquivo?.sha,
        'tamanho': arquivo?.bytes.length,
        'mime': arquivo?.mime,
        'status': 'Sincronizado',
        'erro': null,
      },
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
    );

    await _encerrar(conflitoId, 'local', 'Checklist local aplicado com CAS.');
  }

  Future<void> _resolverChecklistNuvem(
    int conflitoId,
    Map<String, Object?> conflito,
  ) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    final empresaId = _texto(conflito['empresa_id']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final database = await _appDatabase.database;

    final remotoRaw = await client
        .from('imperium_ordem_servico_checklist')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError('Checklist remoto não existe mais.');
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);

    if (_texto(remoto['excluido_em']).isNotEmpty) {
      await database.delete(
        'ordem_servico_checklist',
        where: 'id = ?',
        whereArgs: [localId],
      );
      await database.update(
        'imperium_sync_os_checklist',
        {
          'local_hash': '__excluido__',
          'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
          'status': 'Sincronizado',
          'erro': null,
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
      await _encerrar(conflitoId, 'nuvem', 'Exclusão remota aplicada.');
      return;
    }

    final existe = await database.query(
      'ordem_servico_checklist',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (existe.isEmpty) {
      throw StateError(
        'Checklist local foi removido. Restaure a sincronização da OS antes.',
      );
    }

    await _aplicarChecklistRemoto(
      empresaId: empresaId,
      localId: localId,
      remoto: remoto,
    );
    await _encerrar(conflitoId, 'nuvem', 'Checklist da nuvem aplicado.');
  }

  Future<void> _resolverAssinaturaLocal(
    int conflitoId,
    Map<String, Object?> conflito,
  ) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    final empresaId = _texto(conflito['empresa_id']);
    final osLocalId = _int(conflito['local_id']);
    final osRemotoId = _texto(conflito['remoto_id']);
    final esperado = _texto(conflito['remoto_atualizado_atual']);
    final database = await _appDatabase.database;

    final os = await database.query(
      'ordens_servico',
      columns: ['assinatura_cliente'],
      where: 'id = ?',
      whereArgs: [osLocalId],
      limit: 1,
    );

    if (os.isEmpty) throw StateError('OS local não encontrada.');

    final caminho = _texto(os.first['assinatura_cliente']);
    final arquivo = await _arquivoLocal(caminho);

    String? storagePath;
    if (arquivo != null) {
      storagePath =
          '$empresaId/ordens-servico/$osRemotoId/assinatura/'
          'assinatura-${arquivo.sha.substring(0, 20)}.${arquivo.extensao}';

      await client.storage
          .from(OsArquivosCloudService.bucket)
          .uploadBinary(
            storagePath,
            arquivo.bytes,
            fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
          );
    }

    final payload = <String, dynamic>{
      'assinatura_origem_caminho': arquivo == null ? null : caminho,
      'assinatura_storage_bucket': arquivo == null
          ? null
          : OsArquivosCloudService.bucket,
      'assinatura_storage_path': storagePath,
      'assinatura_nome_original': arquivo?.nome,
      'assinatura_sha256': arquivo?.sha,
      'assinatura_tamanho': arquivo?.bytes.length,
      'assinatura_mime': arquivo?.mime,
    };

    final resposta = esperado.isEmpty
        ? await client
              .from('imperium_ordens_servico')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', osRemotoId)
              .select('id,atualizado_em,assinatura_sha256')
              .maybeSingle()
        : await client
              .from('imperium_ordens_servico')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('id', osRemotoId)
              .eq('atualizado_em', esperado)
              .select('id,atualizado_em,assinatura_sha256')
              .maybeSingle();

    if (resposta == null) {
      throw StateError('A nuvem mudou novamente. Sincronize e revise.');
    }

    await database.insert('imperium_sync_os_assinaturas', {
      'empresa_id': empresaId,
      'os_local_id': osLocalId,
      'os_remoto_id': osRemotoId,
      'local_path': arquivo == null ? null : caminho,
      'local_sha256': arquivo?.sha ?? '',
      'remoto_sha256': resposta['assinatura_sha256']?.toString() ?? '',
      'storage_path': storagePath,
      'tamanho': arquivo?.bytes.length,
      'mime': arquivo?.mime,
      'status': 'Sincronizado',
      'erro': null,
      'sincronizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await database.update(
      'imperium_sync_ordens_servico',
      {'remoto_atualizado_em': resposta['atualizado_em']?.toString()},
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, osLocalId],
    );

    await _encerrar(conflitoId, 'local', 'Assinatura local aplicada com CAS.');
  }

  Future<void> _resolverAssinaturaNuvem(
    int conflitoId,
    Map<String, Object?> conflito,
  ) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    final empresaId = _texto(conflito['empresa_id']);
    final osLocalId = _int(conflito['local_id']);
    final osRemotoId = _texto(conflito['remoto_id']);

    final remotoRaw = await client
        .from('imperium_ordens_servico')
        .select(
          'id,atualizado_em,assinatura_storage_path,'
          'assinatura_nome_original,assinatura_sha256,'
          'assinatura_tamanho,assinatura_mime',
        )
        .eq('empresa_id', empresaId)
        .eq('id', osRemotoId)
        .maybeSingle();

    if (remotoRaw == null) throw StateError('OS remota não encontrada.');

    await _aplicarAssinaturaRemota(
      empresaId: empresaId,
      osLocalId: osLocalId,
      osRemotoId: osRemotoId,
      remoto: Map<String, dynamic>.from(remotoRaw),
    );

    await _encerrar(conflitoId, 'nuvem', 'Assinatura da nuvem aplicada.');
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required String localHashBase,
    required String localHashAtual,
    required String remotoBase,
    required String remotoAtual,
    required String remotoAtualizadoAtual,
  }) async {
    if (await _jaExisteConflito(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remotoId: remotoId,
    )) {
      return;
    }

    final database = await _appDatabase.database;
    await database.insert('imperium_sync_os_arquivos_conflitos', {
      'empresa_id': empresaId,
      'entidade': entidade,
      'local_id': localId,
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': localHashBase,
      'local_hash_atual': localHashAtual,
      'remoto_base': remotoBase,
      'remoto_atual': remotoAtual,
      'remoto_atualizado_atual': remotoAtualizadoAtual,
      'status': 'Pendente',
      'resolucao': null,
      'detalhe': null,
      'detectado_em': DateTime.now().toIso8601String(),
      'resolvido_em': null,
    });
  }

  Future<bool> _jaExisteConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_os_arquivos_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>> _buscarConflito(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_os_arquivos_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito não encontrado ou já resolvido.');
    }
    return rows.first;
  }

  Future<void> _encerrar(int id, String resolucao, String detalhe) async {
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_os_arquivos_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> _hashChecklistLocalSeExiste(int localId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'ordem_servico_checklist',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return '__excluido__';
    return _hashChecklistLocal(rows.first);
  }

  Future<String> _hashChecklistLocal(Map<String, Object?> local) async {
    final arquivoSha = await _shaArquivo(_texto(local['foto_avaria'])) ?? '';

    return sha256.convert(<int>[
      ...<Object?>[
        _int(local['ordem_servico_id']),
        local['categoria'],
        local['item'],
        _int(local['marcado']),
        _int(local['status']),
        local['observacao'],
        local['avaria_localizacao'],
        local['avaria_data_registro'],
        _int(local['ordem']),
        arquivoSha,
      ].join('\u001f').codeUnits,
    ]).toString();
  }

  Future<_ArquivoV2?> _arquivoLocal(String caminho) async {
    if (caminho.trim().isEmpty) return null;
    final file = File(caminho);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final nome = path.basename(caminho);
    final ext = _extensao(nome);

    return _ArquivoV2(
      bytes: bytes,
      nome: nome,
      extensao: ext,
      mime: _mime(ext),
      sha: sha256.convert(bytes).toString(),
    );
  }

  Future<String?> _shaArquivo(String caminho) async {
    final arquivo = await _arquivoLocal(caminho);
    return arquivo?.sha;
  }

  Future<String?> _materializar({
    required int osLocalId,
    required String tipo,
    required String remotoId,
    required String storagePath,
    required String nomeOriginal,
    required String mime,
  }) async {
    final client = _client;
    if (client == null || storagePath.trim().isEmpty) return null;

    final bytes = await client.storage
        .from(OsArquivosCloudService.bucket)
        .download(storagePath);

    if (bytes.isEmpty) return null;

    final docs = await getApplicationDocumentsDirectory();
    final pasta = Directory(
      path.join(
        docs.path,
        'ordens_servico',
        osLocalId.toString(),
        'cloud',
        tipo,
      ),
    );

    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }

    final ext = _extensao(
      nomeOriginal.isEmpty ? _nomePorMime(mime) : nomeOriginal,
    );
    final destino = path.join(pasta.path, '${_seguro(remotoId)}.$ext');

    await File(destino).writeAsBytes(bytes, flush: true);
    return destino;
  }

  Future<int> _osLocalDoChecklist(int checklistLocalId) async {
    final local = await _localPorId(
      'ordem_servico_checklist',
      checklistLocalId,
    );
    final id = _int(local['ordem_servico_id']);
    if (id <= 0) throw StateError('OS inválida no checklist.');
    return id;
  }

  Future<String?> _osRemoto({
    required String empresaId,
    required int osLocalId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_ordens_servico',
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, osLocalId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final id = _texto(rows.first['remoto_id']);
    return id.isEmpty ? null : id;
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
      throw StateError('Registro local não encontrado em $tabela.');
    }
    return rows.first;
  }

  String _extensao(String nome) {
    final ext = path.extension(nome).replaceFirst('.', '').toLowerCase();
    if (ext == 'jpeg' || ext == 'jpg') return 'jpg';
    if (ext == 'png' || ext == 'webp' || ext == 'heic' || ext == 'pdf') {
      return ext;
    }
    return 'jpg';
  }

  String _mime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String _nomePorMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/png':
        return 'arquivo.png';
      case 'image/webp':
        return 'arquivo.webp';
      case 'image/heic':
        return 'arquivo.heic';
      case 'application/pdf':
        return 'arquivo.pdf';
      default:
        return 'arquivo.jpg';
    }
  }

  String _seguro(String valor) {
    return valor.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static int? _intNulo(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoNulo(Object? value) {
    final texto = _texto(value);
    return texto.isEmpty ? null : texto;
  }

  static String _textoPadrao(Object? value, String padrao) {
    final texto = _texto(value);
    return texto.isEmpty ? padrao : texto;
  }
}

class _ArquivoV2 {
  const _ArquivoV2({
    required this.bytes,
    required this.nome,
    required this.extensao,
    required this.mime,
    required this.sha,
  });

  final Uint8List bytes;
  final String nome;
  final String extensao;
  final String mime;
  final String sha;
}
