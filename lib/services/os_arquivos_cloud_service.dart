import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'os_cloud_upload_service.dart';
import 'supabase_bootstrap.dart';
import 'tenant_local_storage_service.dart';

/// Arquivos Cloud da OS V1.
///
/// Sincroniza:
/// - fotos Antes/Depois;
/// - checklist e foto de avaria;
/// - assinatura do cliente.
///
/// O comprovante de pagamento continua no Financeiro Cloud V3 e no bucket
/// próprio `imperium-financeiro-comprovantes`.
///
/// No Android, arquivos remotos são materializados no diretório de documentos
/// do app para que as telas legadas continuem usando Image.file sem reescrita.
class OsArquivosCloudService {
  OsArquivosCloudService._();

  static final OsArquivosCloudService instance = OsArquivosCloudService._();

  static const String bucket = 'imperium-os-arquivos';

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // os-arquivos-cloud-v1
  Future<void> garantirEstruturaLocal() async {
    await OsCloudUploadService.instance.garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_fotos (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT,
        storage_path TEXT,
        sha256 TEXT,
        tamanho INTEGER,
        mime TEXT,
        status TEXT NOT NULL DEFAULT 'Pendente',
        erro TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_checklist (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT,
        storage_path TEXT,
        sha256 TEXT,
        tamanho INTEGER,
        mime TEXT,
        status TEXT NOT NULL DEFAULT 'Pendente',
        erro TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_assinaturas (
        empresa_id TEXT NOT NULL,
        os_local_id INTEGER NOT NULL,
        os_remoto_id TEXT NOT NULL,
        local_path TEXT,
        local_sha256 TEXT,
        remoto_sha256 TEXT,
        storage_path TEXT,
        tamanho INTEGER,
        mime TEXT,
        status TEXT NOT NULL DEFAULT 'Pendente',
        erro TEXT,
        sincronizado_em TEXT,
        PRIMARY KEY (empresa_id, os_local_id),
        UNIQUE (empresa_id, os_remoto_id)
      )
    ''');
  }

  Future<void> sincronizarUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();
      await _uploadFotos(empresaId);
      await _uploadChecklist(empresaId);
      await _uploadAssinaturas(empresaId);
      await _softDeleteAusentes(
        empresaId: empresaId,
        tabelaLocal: 'ordem_servico_fotos',
        tabelaMapa: 'imperium_sync_os_fotos',
        tabelaRemota: 'imperium_ordem_servico_fotos',
      );
      await _softDeleteAusentes(
        empresaId: empresaId,
        tabelaLocal: 'ordem_servico_checklist',
        tabelaMapa: 'imperium_sync_os_checklist',
        tabelaRemota: 'imperium_ordem_servico_checklist',
      );
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
      await _baixarFotos(empresaId);
      await _baixarChecklist(empresaId);
      await _baixarAssinaturas(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    Future<int> contar(String tabela, String chave) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela WHERE empresa_id = ? $chave',
        [empresaId],
      );
      return _int(rows.first['total']);
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'bucket': bucket,
      'fotos_mapeadas': await contar('imperium_sync_os_fotos', ''),
      'checklist_mapeado': await contar('imperium_sync_os_checklist', ''),
      'assinaturas_mapeadas': await contar('imperium_sync_os_assinaturas', ''),
      'fotos_com_erro': await contar(
        'imperium_sync_os_fotos',
        "AND status = 'Erro'",
      ),
      'checklist_com_erro': await contar(
        'imperium_sync_os_checklist',
        "AND status = 'Erro'",
      ),
      'assinaturas_com_erro': await contar(
        'imperium_sync_os_assinaturas',
        "AND status = 'Erro'",
      ),
      'comprovantes_financeiros_em_bucket_separado': true,
    };
  }

  Future<Uint8List?> baixarFotoBytes({
    required String empresaId,
    required int fotoLocalId,
  }) async {
    await garantirEstruturaLocal();
    return _baixarPorMapa(
      tabelaMapa: 'imperium_sync_os_fotos',
      empresaId: empresaId,
      localIdColumn: 'local_id',
      localId: fotoLocalId,
    );
  }

  Future<Uint8List?> baixarFotoAvariaBytes({
    required String empresaId,
    required int checklistLocalId,
  }) async {
    await garantirEstruturaLocal();
    return _baixarPorMapa(
      tabelaMapa: 'imperium_sync_os_checklist',
      empresaId: empresaId,
      localIdColumn: 'local_id',
      localId: checklistLocalId,
    );
  }

  Future<Uint8List?> baixarAssinaturaBytes({
    required String empresaId,
    required int ordemServicoLocalId,
  }) async {
    await garantirEstruturaLocal();
    return _baixarPorMapa(
      tabelaMapa: 'imperium_sync_os_assinaturas',
      empresaId: empresaId,
      localIdColumn: 'os_local_id',
      localId: ordemServicoLocalId,
    );
  }

  Future<void> _uploadFotos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'ordem_servico_fotos',
      orderBy: 'ordem_servico_id ASC, etapa ASC, ordem ASC, id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      final osLocalId = _int(local['ordem_servico_id']);
      if (localId <= 0 || osLocalId <= 0) continue;

      final osRemotoId = await _remotoOs(
        empresaId: empresaId,
        osLocalId: osLocalId,
      );
      if (osRemotoId == null) continue;

      final caminho = _texto(local['caminho']);
      final arquivo = await _lerArquivo(caminho);

      if (arquivo == null) {
        await _marcarErro(
          tabela: 'imperium_sync_os_fotos',
          empresaId: empresaId,
          localIdColumn: 'local_id',
          localId: localId,
          erro: 'Arquivo local não encontrado: $caminho',
        );
        continue;
      }

      final hash = _hashFoto(local, arquivo.sha256);
      final mapa = await _mapa(
        tabela: 'imperium_sync_os_fotos',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
      );

      if (_texto(mapa?['local_hash']) == hash &&
          _texto(mapa?['status']) == 'Sincronizado') {
        continue;
      }

      final destino =
          '$empresaId/ordens-servico/$osRemotoId/fotos/'
          '$localId-${arquivo.sha256.substring(0, 20)}.${arquivo.extensao}';

      await client.storage
          .from(bucket)
          .uploadBinary(
            destino,
            arquivo.bytes,
            fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
          );

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'ordem_servico_id': osRemotoId,
        'etapa': _textoPadrao(local['etapa'], 'Antes'),
        'descricao': _texto(local['descricao']),
        'data_registro': _texto(local['data']),
        'ordem': _int(local['ordem']),
        'origem_caminho': caminho,
        'storage_bucket': bucket,
        'storage_path': destino,
        'nome_original': arquivo.nome,
        'sha256': arquivo.sha256,
        'tamanho': arquivo.bytes.length,
        'mime': arquivo.mime,
        'excluido_em': null,
      };

      final remoto = await _upsertOrigem(
        tabela: 'imperium_ordem_servico_fotos',
        empresaId: empresaId,
        localId: localId,
        mapa: mapa,
        payload: payload,
      );

      await _salvarMapaArquivo(
        tabela: 'imperium_sync_os_fotos',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        storagePath: destino,
        sha256Arquivo: arquivo.sha256,
        tamanho: arquivo.bytes.length,
        mime: arquivo.mime,
      );
    }
  }

  Future<void> _uploadChecklist(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'ordem_servico_checklist',
      orderBy: 'ordem_servico_id ASC, categoria ASC, ordem ASC, id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      final osLocalId = _int(local['ordem_servico_id']);
      if (localId <= 0 || osLocalId <= 0) continue;

      final osRemotoId = await _remotoOs(
        empresaId: empresaId,
        osLocalId: osLocalId,
      );
      if (osRemotoId == null) continue;

      final caminho = _texto(local['foto_avaria']);
      final arquivo = caminho.isEmpty ? null : await _lerArquivo(caminho);
      final arquivoSha = arquivo?.sha256 ?? '';

      if (caminho.isNotEmpty && arquivo == null) {
        await _marcarErro(
          tabela: 'imperium_sync_os_checklist',
          empresaId: empresaId,
          localIdColumn: 'local_id',
          localId: localId,
          erro: 'Foto de avaria local não encontrada: $caminho',
        );
      }

      final hash = _hashChecklist(local, arquivoSha);
      final mapa = await _mapa(
        tabela: 'imperium_sync_os_checklist',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
      );

      if (_texto(mapa?['local_hash']) == hash &&
          _texto(mapa?['status']) == 'Sincronizado') {
        continue;
      }

      String? storagePath;
      if (arquivo != null) {
        storagePath =
            '$empresaId/ordens-servico/$osRemotoId/checklist/'
            '$localId-${arquivo.sha256.substring(0, 20)}.${arquivo.extensao}';

        await client.storage
            .from(bucket)
            .uploadBinary(
              storagePath,
              arquivo.bytes,
              fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
            );
      }

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'ordem_servico_id': osRemotoId,
        'categoria': _textoPadrao(local['categoria'], 'Geral'),
        'item': _texto(local['item']),
        'marcado': _int(local['marcado']) != 0,
        'status': _int(local['status']),
        'observacao': _texto(local['observacao']),
        'avaria_localizacao': _texto(local['avaria_localizacao']),
        'avaria_data_registro': _textoNulo(local['avaria_data_registro']),
        'ordem': _int(local['ordem']),
        'foto_avaria_origem_caminho': caminho.isEmpty ? null : caminho,
        'foto_avaria_storage_bucket': storagePath == null ? null : bucket,
        'foto_avaria_storage_path': storagePath,
        'foto_avaria_nome_original': arquivo?.nome,
        'foto_avaria_sha256': arquivo?.sha256,
        'foto_avaria_tamanho': arquivo?.bytes.length,
        'foto_avaria_mime': arquivo?.mime,
        'excluido_em': null,
      };

      final remoto = await _upsertOrigem(
        tabela: 'imperium_ordem_servico_checklist',
        empresaId: empresaId,
        localId: localId,
        mapa: mapa,
        payload: payload,
      );

      await _salvarMapaArquivo(
        tabela: 'imperium_sync_os_checklist',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        storagePath: storagePath,
        sha256Arquivo: arquivo?.sha256,
        tamanho: arquivo?.bytes.length,
        mime: arquivo?.mime,
      );
    }
  }

  Future<void> _uploadAssinaturas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query(
      'ordens_servico',
      columns: ['id', 'assinatura_cliente'],
      where:
          "assinatura_cliente IS NOT NULL AND TRIM(assinatura_cliente) != ''",
    );

    for (final local in locais) {
      final osLocalId = _int(local['id']);
      if (osLocalId <= 0) continue;

      final osRemotoId = await _remotoOs(
        empresaId: empresaId,
        osLocalId: osLocalId,
      );
      if (osRemotoId == null) continue;

      final caminho = _texto(local['assinatura_cliente']);
      final arquivo = await _lerArquivo(caminho);

      if (arquivo == null) {
        await _salvarAssinaturaErro(
          empresaId: empresaId,
          osLocalId: osLocalId,
          osRemotoId: osRemotoId,
          localPath: caminho,
          erro: 'Assinatura local não encontrada.',
        );
        continue;
      }

      final mapa = await _mapa(
        tabela: 'imperium_sync_os_assinaturas',
        empresaId: empresaId,
        localIdColumn: 'os_local_id',
        localId: osLocalId,
      );

      if (_texto(mapa?['local_sha256']) == arquivo.sha256 &&
          _texto(mapa?['status']) == 'Sincronizado') {
        continue;
      }

      final remotoAtual = await client
          .from('imperium_ordens_servico')
          .select('assinatura_sha256,assinatura_storage_path')
          .eq('empresa_id', empresaId)
          .eq('id', osRemotoId)
          .maybeSingle();

      final remotoSha = _texto(remotoAtual?['assinatura_sha256']);
      final remotoBase = _texto(mapa?['remoto_sha256']);
      final localBase = _texto(mapa?['local_sha256']);

      final localMudou = localBase.isNotEmpty && localBase != arquivo.sha256;
      final remotoMudou = remotoBase.isNotEmpty && remotoBase != remotoSha;

      if (localMudou &&
          remotoMudou &&
          remotoSha.isNotEmpty &&
          remotoSha != arquivo.sha256) {
        await _salvarAssinaturaErro(
          empresaId: empresaId,
          osLocalId: osLocalId,
          osRemotoId: osRemotoId,
          localPath: caminho,
          erro: 'Conflito de assinatura local x nuvem.',
          localSha: arquivo.sha256,
          remotoSha: remotoSha,
          status: 'Conflito',
        );
        continue;
      }

      final destino =
          '$empresaId/ordens-servico/$osRemotoId/assinatura/'
          'assinatura-${arquivo.sha256.substring(0, 20)}.${arquivo.extensao}';

      await client.storage
          .from(bucket)
          .uploadBinary(
            destino,
            arquivo.bytes,
            fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
          );

      final resposta = await client
          .from('imperium_ordens_servico')
          .update({
            'assinatura_origem_caminho': caminho,
            'assinatura_storage_bucket': bucket,
            'assinatura_storage_path': destino,
            'assinatura_nome_original': arquivo.nome,
            'assinatura_sha256': arquivo.sha256,
            'assinatura_tamanho': arquivo.bytes.length,
            'assinatura_mime': arquivo.mime,
          })
          .eq('empresa_id', empresaId)
          .eq('id', osRemotoId)
          .select('id,atualizado_em,assinatura_sha256')
          .single();

      await database.insert(
        'imperium_sync_os_assinaturas',
        {
          'empresa_id': empresaId,
          'os_local_id': osLocalId,
          'os_remoto_id': osRemotoId,
          'local_path': caminho,
          'local_sha256': arquivo.sha256,
          'remoto_sha256': resposta['assinatura_sha256']?.toString(),
          'storage_path': destino,
          'tamanho': arquivo.bytes.length,
          'mime': arquivo.mime,
          'status': 'Sincronizado',
          'erro': null,
          'sincronizado_em': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // O upload de metadados da assinatura altera atualizado_em da OS.
      // Atualiza o baseline do mapa da OS para não gerar falso conflito.
      await database.update(
        'imperium_sync_ordens_servico',
        {'remoto_atualizado_em': resposta['atualizado_em']?.toString()},
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, osLocalId],
      );
    }
  }

  Future<void> _baixarFotos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_ordem_servico_fotos')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      final osLocalId = await _localOs(
        empresaId: empresaId,
        osRemotoId: _texto(remoto['ordem_servico_id']),
      );
      if (osLocalId == null) continue;

      var mapa = await _mapaPorRemoto(
        tabela: 'imperium_sync_os_fotos',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      int localId;
      if (mapa == null) {
        localId =
            await _recuperarOrigemLocal(
              empresaId: empresaId,
              tabelaLocal: 'ordem_servico_fotos',
              remoto: remoto,
            ) ??
            0;

        if (localId <= 0) {
          final caminho = await _materializarArquivo(
            empresaId: empresaId,
            osLocalId: osLocalId,
            tipo: 'fotos',
            remotoId: remotoId,
            storagePath: _texto(remoto['storage_path']),
            nomeOriginal: _texto(remoto['nome_original']),
            mime: _texto(remoto['mime']),
          );

          if (caminho == null) continue;

          localId = await database.insert('ordem_servico_fotos', {
            'ordem_servico_id': osLocalId,
            'etapa': _textoPadrao(remoto['etapa'], 'Antes'),
            'caminho': caminho,
            'descricao': _texto(remoto['descricao']),
            'data': _texto(remoto['data_registro']),
            'ordem': _int(remoto['ordem']),
          });
        }

        mapa = <String, Object?>{'local_id': localId, 'remoto_id': remotoId};
      } else {
        localId = _int(mapa['local_id']);
        final localRows = await database.query(
          'ordem_servico_fotos',
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );

        if (localRows.isEmpty) continue;

        final atual = localRows.first;
        final caminhoAtual = _texto(atual['caminho']);
        final existe =
            caminhoAtual.isNotEmpty && await File(caminhoAtual).exists();

        if (!existe) {
          final caminho = await _materializarArquivo(
            empresaId: empresaId,
            osLocalId: osLocalId,
            tipo: 'fotos',
            remotoId: remotoId,
            storagePath: _texto(remoto['storage_path']),
            nomeOriginal: _texto(remoto['nome_original']),
            mime: _texto(remoto['mime']),
          );

          if (caminho != null) {
            await database.update(
              'ordem_servico_fotos',
              {'caminho': caminho},
              where: 'id = ?',
              whereArgs: [localId],
            );
          }
        }
      }

      final local = await _localPorId('ordem_servico_fotos', localId);
      await _salvarMapaArquivo(
        tabela: 'imperium_sync_os_fotos',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
        remotoId: remotoId,
        localHash: _hashFoto(local, _texto(remoto['sha256'])),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        storagePath: _textoNulo(remoto['storage_path']),
        sha256Arquivo: _textoNulo(remoto['sha256']),
        tamanho: _intNulo(remoto['tamanho']),
        mime: _textoNulo(remoto['mime']),
      );
    }
  }

  Future<void> _baixarChecklist(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_ordem_servico_checklist')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);
      final osLocalId = await _localOs(
        empresaId: empresaId,
        osRemotoId: _texto(remoto['ordem_servico_id']),
      );
      if (osLocalId == null) continue;

      var mapa = await _mapaPorRemoto(
        tabela: 'imperium_sync_os_checklist',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      int localId;
      if (mapa == null) {
        localId =
            await _recuperarOrigemLocal(
              empresaId: empresaId,
              tabelaLocal: 'ordem_servico_checklist',
              remoto: remoto,
            ) ??
            0;

        String? fotoPath;
        final remotoStorage = _texto(remoto['foto_avaria_storage_path']);
        if (remotoStorage.isNotEmpty) {
          fotoPath = await _materializarArquivo(
            empresaId: empresaId,
            osLocalId: osLocalId,
            tipo: 'checklist',
            remotoId: remotoId,
            storagePath: remotoStorage,
            nomeOriginal: _texto(remoto['foto_avaria_nome_original']),
            mime: _texto(remoto['foto_avaria_mime']),
          );
        }

        if (localId <= 0) {
          localId = await database.insert('ordem_servico_checklist', {
            'ordem_servico_id': osLocalId,
            'categoria': _textoPadrao(remoto['categoria'], 'Geral'),
            'item': _texto(remoto['item']),
            'marcado': remoto['marcado'] == true ? 1 : 0,
            'status': _int(remoto['status']),
            'observacao': _texto(remoto['observacao']),
            'foto_avaria': fotoPath,
            'avaria_localizacao': _texto(remoto['avaria_localizacao']),
            'avaria_data_registro': _textoNulo(remoto['avaria_data_registro']),
            'ordem': _int(remoto['ordem']),
          });
        }
      } else {
        localId = _int(mapa['local_id']);
        final localRows = await database.query(
          'ordem_servico_checklist',
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );
        if (localRows.isEmpty) continue;

        final local = localRows.first;
        var fotoPath = _textoNulo(local['foto_avaria']);
        final storage = _texto(remoto['foto_avaria_storage_path']);
        final existe = fotoPath != null && await File(fotoPath).exists();

        if (!existe && storage.isNotEmpty) {
          fotoPath = await _materializarArquivo(
            empresaId: empresaId,
            osLocalId: osLocalId,
            tipo: 'checklist',
            remotoId: remotoId,
            storagePath: storage,
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
            'foto_avaria': fotoPath,
            'avaria_localizacao': _texto(remoto['avaria_localizacao']),
            'avaria_data_registro': _textoNulo(remoto['avaria_data_registro']),
            'ordem': _int(remoto['ordem']),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      final local = await _localPorId('ordem_servico_checklist', localId);
      await _salvarMapaArquivo(
        tabela: 'imperium_sync_os_checklist',
        empresaId: empresaId,
        localIdColumn: 'local_id',
        localId: localId,
        remotoId: remotoId,
        localHash: _hashChecklist(local, _texto(remoto['foto_avaria_sha256'])),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        storagePath: _textoNulo(remoto['foto_avaria_storage_path']),
        sha256Arquivo: _textoNulo(remoto['foto_avaria_sha256']),
        tamanho: _intNulo(remoto['foto_avaria_tamanho']),
        mime: _textoNulo(remoto['foto_avaria_mime']),
      );
    }
  }

  Future<void> _baixarAssinaturas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_ordens_servico')
        .select(
          'id,atualizado_em,assinatura_storage_path,assinatura_nome_original,'
          'assinatura_sha256,assinatura_tamanho,assinatura_mime',
        )
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null);

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final storagePath = _texto(remoto['assinatura_storage_path']);
      if (storagePath.isEmpty) continue;

      final osRemotoId = _texto(remoto['id']);
      final osLocalId = await _localOs(
        empresaId: empresaId,
        osRemotoId: osRemotoId,
      );
      if (osLocalId == null) continue;

      final osRows = await database.query(
        'ordens_servico',
        columns: ['assinatura_cliente'],
        where: 'id = ?',
        whereArgs: [osLocalId],
        limit: 1,
      );
      if (osRows.isEmpty) continue;

      final localPath = _texto(osRows.first['assinatura_cliente']);
      final existe = localPath.isNotEmpty && await File(localPath).exists();
      final mapa = await _mapa(
        tabela: 'imperium_sync_os_assinaturas',
        empresaId: empresaId,
        localIdColumn: 'os_local_id',
        localId: osLocalId,
      );

      final remotoSha = _texto(remoto['assinatura_sha256']);

      if (existe) {
        final localArquivo = await _lerArquivo(localPath);
        final localSha = localArquivo?.sha256 ?? '';

        if (localSha.isNotEmpty &&
            remotoSha.isNotEmpty &&
            localSha != remotoSha &&
            _texto(mapa?['remoto_sha256']).isNotEmpty) {
          await _salvarAssinaturaErro(
            empresaId: empresaId,
            osLocalId: osLocalId,
            osRemotoId: osRemotoId,
            localPath: localPath,
            erro: 'Conflito de assinatura local x nuvem.',
            localSha: localSha,
            remotoSha: remotoSha,
            status: 'Conflito',
          );
          continue;
        }
      }

      if (!existe) {
        final novoPath = await _materializarArquivo(
          empresaId: empresaId,
          osLocalId: osLocalId,
          tipo: 'assinatura',
          remotoId: osRemotoId,
          storagePath: storagePath,
          nomeOriginal: _texto(remoto['assinatura_nome_original']),
          mime: _texto(remoto['assinatura_mime']),
        );

        if (novoPath == null) continue;

        await database.update(
          'ordens_servico',
          {'assinatura_cliente': novoPath},
          where: 'id = ?',
          whereArgs: [osLocalId],
        );
      }

      final caminhoAtualRows = await database.query(
        'ordens_servico',
        columns: ['assinatura_cliente'],
        where: 'id = ?',
        whereArgs: [osLocalId],
        limit: 1,
      );
      final caminhoAtual = _texto(caminhoAtualRows.first['assinatura_cliente']);

      await database.insert(
        'imperium_sync_os_assinaturas',
        {
          'empresa_id': empresaId,
          'os_local_id': osLocalId,
          'os_remoto_id': osRemotoId,
          'local_path': caminhoAtual,
          'local_sha256': remotoSha,
          'remoto_sha256': remotoSha,
          'storage_path': storagePath,
          'tamanho': _intNulo(remoto['assinatura_tamanho']),
          'mime': _textoNulo(remoto['assinatura_mime']),
          'status': 'Sincronizado',
          'erro': null,
          'sincronizado_em': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await database.update(
        'imperium_sync_ordens_servico',
        {'remoto_atualizado_em': remoto['atualizado_em']?.toString()},
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, osLocalId],
      );
    }
  }

  Future<Map<String, dynamic>> _upsertOrigem({
    required String tabela,
    required String empresaId,
    required int localId,
    required Map<String, Object?>? mapa,
    required Map<String, dynamic> payload,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível.');
    }

    final remotoId = _texto(mapa?['remoto_id']);

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from(tabela)
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      return Map<String, dynamic>.from(resposta);
    }

    final resposta = await client
        .from(tabela)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em')
        .single();

    return Map<String, dynamic>.from(resposta);
  }

  Future<void> _softDeleteAusentes({
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
      if (_texto(mapa['local_hash']) == '__excluido__') continue;

      final localId = _int(mapa['local_id']);
      final remotoId = _texto(mapa['remoto_id']);
      if (localId <= 0 || remotoId.isEmpty) continue;

      final local = await database.query(
        tabelaLocal,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (local.isNotEmpty) continue;

      final resposta = await client
          .from(tabelaRemota)
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em');

      await database.update(
        tabelaMapa,
        {
          'local_hash': '__excluido__',
          'status': 'Sincronizado',
          'erro': null,
          'remoto_atualizado_em': resposta.isEmpty
              ? DateTime.now().toIso8601String()
              : resposta.first['atualizado_em']?.toString(),
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
    }
  }

  Future<_ArquivoLocal?> _lerArquivo(String caminho) async {
    if (caminho.trim().isEmpty) return null;

    final arquivo = File(caminho);
    if (!await arquivo.exists()) return null;

    final bytes = await arquivo.readAsBytes();
    if (bytes.isEmpty) return null;

    final nome = path.basename(caminho);
    final extensao = _extensao(nome);
    final mime = _mime(nome);
    final hash = sha256.convert(bytes).toString();

    return _ArquivoLocal(
      bytes: bytes,
      nome: nome,
      extensao: extensao,
      mime: mime,
      sha256: hash,
    );
  }

  Future<String?> _materializarArquivo({
    required String empresaId,
    required int osLocalId,
    required String tipo,
    required String remotoId,
    required String storagePath,
    required String nomeOriginal,
    required String mime,
  }) async {
    final client = _client;
    if (client == null || storagePath.trim().isEmpty) return null;

    final bytes = await client.storage.from(bucket).download(storagePath);
    if (bytes.isEmpty) return null;

    final pasta = await TenantLocalStorageService.instance.pasta(
      'ordens_servico',
      segmentos: <String>[osLocalId.toString(), 'cloud', tipo],
    );

    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }

    final ext = _extensao(
      nomeOriginal.isEmpty ? _nomePorMime(mime) : nomeOriginal,
    );
    final nomeSeguro = '${_seguro(remotoId)}.$ext';
    final destino = path.join(pasta.path, nomeSeguro);

    await File(destino).writeAsBytes(bytes, flush: true);
    return destino;
  }

  Future<Uint8List?> _baixarPorMapa({
    required String tabelaMapa,
    required String empresaId,
    required String localIdColumn,
    required int localId,
  }) async {
    final client = _client;
    if (client == null) return null;

    final mapa = await _mapa(
      tabela: tabelaMapa,
      empresaId: empresaId,
      localIdColumn: localIdColumn,
      localId: localId,
    );

    final storagePath = _texto(mapa?['storage_path']);
    if (storagePath.isEmpty) return null;

    return client.storage.from(bucket).download(storagePath);
  }

  Future<String?> _remotoOs({
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

  Future<int?> _localOs({
    required String empresaId,
    required String osRemotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_ordens_servico',
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, osRemotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<Map<String, Object?>?> _mapa({
    required String tabela,
    required String empresaId,
    required String localIdColumn,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'empresa_id = ? AND $localIdColumn = ?',
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

  Future<void> _salvarMapaArquivo({
    required String tabela,
    required String empresaId,
    required String localIdColumn,
    required int localId,
    required String remotoId,
    required String localHash,
    String? remotoAtualizadoEm,
    String? storagePath,
    String? sha256Arquivo,
    int? tamanho,
    String? mime,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(tabela, {
      'empresa_id': empresaId,
      localIdColumn: localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
      'storage_path': storagePath,
      'sha256': sha256Arquivo,
      'tamanho': tamanho,
      'mime': mime,
      'status': 'Sincronizado',
      'erro': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _marcarErro({
    required String tabela,
    required String empresaId,
    required String localIdColumn,
    required int localId,
    required String erro,
  }) async {
    final database = await _appDatabase.database;
    final atual = await _mapa(
      tabela: tabela,
      empresaId: empresaId,
      localIdColumn: localIdColumn,
      localId: localId,
    );

    if (atual == null) return;

    await database.update(
      tabela,
      {'status': 'Erro', 'erro': erro},
      where: 'empresa_id = ? AND $localIdColumn = ?',
      whereArgs: [empresaId, localId],
    );
  }

  Future<void> _salvarAssinaturaErro({
    required String empresaId,
    required int osLocalId,
    required String osRemotoId,
    required String localPath,
    required String erro,
    String? localSha,
    String? remotoSha,
    String status = 'Erro',
  }) async {
    final database = await _appDatabase.database;

    await database.insert('imperium_sync_os_assinaturas', {
      'empresa_id': empresaId,
      'os_local_id': osLocalId,
      'os_remoto_id': osRemotoId,
      'local_path': localPath,
      'local_sha256': localSha,
      'remoto_sha256': remotoSha,
      'storage_path': null,
      'tamanho': null,
      'mime': null,
      'status': status,
      'erro': erro,
      'sincronizado_em': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> _recuperarOrigemLocal({
    required String empresaId,
    required String tabelaLocal,
    required Map<String, dynamic> remoto,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return null;
    if (origemDispositivo != await _dispositivoId()) return null;

    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaLocal,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    return rows.isEmpty ? null : origemLocalId;
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

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Identificador do dispositivo não foi preparado.');
    }

    final id = _texto(rows.first['dispositivo_id']);
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo está vazio.');
    }
    return id;
  }

  String _hashFoto(Map<String, Object?> local, String arquivoSha) {
    return sha256
        .convert(
          Uint8List.fromList(
            utf8Bytes(<Object?>[
              _int(local['ordem_servico_id']),
              local['etapa'],
              local['descricao'],
              local['data'],
              _int(local['ordem']),
              arquivoSha,
            ]),
          ),
        )
        .toString();
  }

  String _hashChecklist(Map<String, Object?> local, String arquivoSha) {
    return sha256
        .convert(
          Uint8List.fromList(
            utf8Bytes(<Object?>[
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
            ]),
          ),
        )
        .toString();
  }

  List<int> utf8Bytes(List<Object?> valores) {
    return valores.join('\u001f').codeUnits;
  }

  String _extensao(String nome) {
    final ext = path.extension(nome).replaceFirst('.', '').toLowerCase();
    if (ext.isEmpty) return 'jpg';
    if (ext == 'jpeg' || ext == 'jpg') return 'jpg';
    if (ext == 'png' || ext == 'webp' || ext == 'heic' || ext == 'pdf') {
      return ext;
    }
    return 'bin';
  }

  String _mime(String nome) {
    switch (_extensao(nome)) {
      case 'jpg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
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

class _ArquivoLocal {
  const _ArquivoLocal({
    required this.bytes,
    required this.nome,
    required this.extensao,
    required this.mime,
    required this.sha256,
  });

  final Uint8List bytes;
  final String nome;
  final String extensao;
  final String mime;
  final String sha256;
}
