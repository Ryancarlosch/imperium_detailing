// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'tenant_local_storage_service.dart';

class FotosServicoCloudService {
  FotosServicoCloudService._();

  static final FotosServicoCloudService instance = FotosServicoCloudService._();

  static const String bucket = 'imperium-fotos-servico';

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_fotos_servico (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT NOT NULL DEFAULT '',
        remoto_atualizado_em TEXT,
        antes_storage_path TEXT,
        depois_storage_path TEXT,
        sincronizado_em TEXT,
        PRIMARY KEY (empresa_id, local_id)
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_fotos_servico_remoto
      ON imperium_sync_fotos_servico (empresa_id, remoto_id)
    ''');
  }

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (client == null || empresaId.trim().isEmpty) return;

    await garantirEstruturaLocal();
    await _upload(empresaId);
    await _download(empresaId);
  }

  Future<void> _upload(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final locais = await database.query('fotos_servico', orderBy: 'id ASC');
    final dispositivoId = await _dispositivoId();

    for (final local in locais) {
      final localId = _int(local['id']);
      final clienteLocalId = _int(local['cliente_id']);
      final veiculoLocalId = _int(local['veiculo_id']);
      if (localId <= 0 || clienteLocalId <= 0 || veiculoLocalId <= 0) {
        continue;
      }

      final clienteRemotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        localId: clienteLocalId,
      );
      final veiculoRemotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        localId: veiculoLocalId,
      );
      if (clienteRemotoId == null || veiculoRemotoId == null) continue;

      final antes = await _arquivo(_texto(local['caminho_antes']));
      final depois = await _arquivo(_texto(local['caminho_depois']));
      final hash = _hashLocal(
        clienteLocalId: clienteLocalId,
        veiculoLocalId: veiculoLocalId,
        descricao: _texto(local['descricao']),
        data: _texto(local['data']),
        antesSha: antes?.sha256 ?? '',
        depoisSha: depois?.sha256 ?? '',
      );

      final mapa = await _mapaLocal(empresaId, localId);
      if (mapa != null && _texto(mapa['local_hash']) == hash) continue;

      final base =
          empresaId + '/galeria/' + dispositivoId + '/' + localId.toString();
      final antesStorage = antes == null
          ? null
          : await _subir(base + '/antes.' + antes.extensao, antes);
      final depoisStorage = depois == null
          ? null
          : await _subir(base + '/depois.' + depois.extensao, depois);

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'cliente_id': clienteRemotoId,
        'veiculo_id': veiculoRemotoId,
        'origem_dispositivo': dispositivoId,
        'origem_local_id': localId,
        'descricao': _texto(local['descricao']),
        'data': _texto(local['data']),
        'antes_storage_bucket': antesStorage == null ? null : bucket,
        'antes_storage_path': antesStorage,
        'antes_nome_original': antes?.nome,
        'antes_sha256': antes?.sha256,
        'antes_tamanho': antes?.bytes.length,
        'antes_mime': antes?.mime,
        'depois_storage_bucket': depoisStorage == null ? null : bucket,
        'depois_storage_path': depoisStorage,
        'depois_nome_original': depois?.nome,
        'depois_sha256': depois?.sha256,
        'depois_tamanho': depois?.bytes.length,
        'depois_mime': depois?.mime,
        'excluido_em': null,
      };

      Map<String, dynamic> remoto;
      if (mapa == null) {
        final raw = await client
            .from('imperium_fotos_servico')
            .upsert(
              payload,
              onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
            )
            .select()
            .single();
        remoto = Map<String, dynamic>.from(raw);
      } else {
        final remotoId = _texto(mapa['remoto_id']);
        final rows = await client
            .from('imperium_fotos_servico')
            .update(payload)
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .select();
        if ((rows as List).isEmpty) continue;
        remoto = Map<String, dynamic>.from(rows.first as Map);
      }

      await _salvarMapa(
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        antesStoragePath: antesStorage,
        depoisStoragePath: depoisStorage,
      );
    }
  }

  Future<void> _download(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final raw = await client
        .from('imperium_fotos_servico')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final item in raw) {
      final remoto = Map<String, dynamic>.from(item);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;
      if (await _localPorRemoto(empresaId, remotoId) != null) continue;

      final clienteLocalId = await _localPorRemotoMapa(
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: _texto(remoto['cliente_id']),
      );
      final veiculoLocalId = await _localPorRemotoMapa(
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        remotoId: _texto(remoto['veiculo_id']),
      );
      if (clienteLocalId == null || veiculoLocalId == null) continue;

      final antesPath = await _materializar(
        remotoId: remotoId,
        tipo: 'antes',
        storagePath: _texto(remoto['antes_storage_path']),
        nomeOriginal: _texto(remoto['antes_nome_original']),
        mime: _texto(remoto['antes_mime']),
      );
      final depoisPath = await _materializar(
        remotoId: remotoId,
        tipo: 'depois',
        storagePath: _texto(remoto['depois_storage_path']),
        nomeOriginal: _texto(remoto['depois_nome_original']),
        mime: _texto(remoto['depois_mime']),
      );

      final localId = await database.insert('fotos_servico', {
        'cliente_id': clienteLocalId,
        'veiculo_id': veiculoLocalId,
        'caminho_antes': antesPath ?? '',
        'caminho_depois': depoisPath ?? '',
        'descricao': _texto(remoto['descricao']),
        'data': _texto(remoto['data']),
      });

      final hash = _hashLocal(
        clienteLocalId: clienteLocalId,
        veiculoLocalId: veiculoLocalId,
        descricao: _texto(remoto['descricao']),
        data: _texto(remoto['data']),
        antesSha: _texto(remoto['antes_sha256']),
        depoisSha: _texto(remoto['depois_sha256']),
      );

      await _salvarMapa(
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
        antesStoragePath: _textoNulo(remoto['antes_storage_path']),
        depoisStoragePath: _textoNulo(remoto['depois_storage_path']),
      );
    }
  }

  Future<String?> _subir(String destino, _ArquivoLocal arquivo) async {
    final client = _client;
    if (client == null) return null;

    await client.storage
        .from(bucket)
        .uploadBinary(
          destino,
          arquivo.bytes,
          fileOptions: FileOptions(upsert: true, contentType: arquivo.mime),
        );
    return destino;
  }

  Future<String?> _materializar({
    required String remotoId,
    required String tipo,
    required String storagePath,
    required String nomeOriginal,
    required String mime,
  }) async {
    final client = _client;
    if (client == null || storagePath.isEmpty) return null;

    final bytes = await client.storage.from(bucket).download(storagePath);
    if (bytes.isEmpty) return null;

    final pasta = await TenantLocalStorageService.instance.pasta(
      'fotos_servico',
      segmentos: <String>['cloud', remotoId],
    );
    final ext = _extensao(
      nomeOriginal.isEmpty ? _nomePorMime(mime) : nomeOriginal,
    );
    final destino = path.join(pasta.path, tipo + '.' + ext);
    await File(destino).writeAsBytes(bytes, flush: true);
    return destino;
  }

  Future<_ArquivoLocal?> _arquivo(String caminho) async {
    if (caminho.isEmpty) return null;
    final file = File(caminho);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final nome = path.basename(caminho);
    final ext = _extensao(nome);
    return _ArquivoLocal(
      bytes: bytes,
      nome: nome,
      extensao: ext,
      mime: _mime(ext),
      sha256: sha256.convert(bytes).toString(),
    );
  }

  Future<Map<String, Object?>?> _mapaLocal(
    String empresaId,
    int localId,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_fotos_servico',
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int?> _localPorRemoto(String empresaId, String remotoId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_fotos_servico',
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<String?> _remotoPorLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _textoNulo(rows.first['remoto_id']);
  }

  Future<int?> _localPorRemotoMapa({
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<void> _salvarMapa({
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    required String? remotoAtualizadoEm,
    required String? antesStoragePath,
    required String? depoisStoragePath,
  }) async {
    final database = await _appDatabase.database;
    await database.insert('imperium_sync_fotos_servico', {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
      'antes_storage_path': antesStoragePath,
      'depois_storage_path': depoisStoragePath,
      'sincronizado_em': DateTime.now().toIso8601String(),
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
      throw StateError('Configuração de sincronização não encontrada.');
    }
    final id = _texto(rows.first['dispositivo_id']);
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo não encontrado.');
    }
    return id;
  }

  static String _hashLocal({
    required int clienteLocalId,
    required int veiculoLocalId,
    required String descricao,
    required String data,
    required String antesSha,
    required String depoisSha,
  }) {
    return sha256
        .convert(
          utf8.encode(
            jsonEncode(<Object?>[
              clienteLocalId,
              veiculoLocalId,
              descricao,
              data,
              antesSha,
              depoisSha,
            ]),
          ),
        )
        .toString();
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String _texto(dynamic valor) => (valor ?? '').toString().trim();

  static String? _textoNulo(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }

  static String _extensao(String nome) {
    final ext = path.extension(nome).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  static String _mime(String ext) {
    return switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  static String _nomePorMime(String mime) {
    if (mime.contains('png')) return 'arquivo.png';
    if (mime.contains('webp')) return 'arquivo.webp';
    if (mime.contains('gif')) return 'arquivo.gif';
    return 'arquivo.jpg';
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
