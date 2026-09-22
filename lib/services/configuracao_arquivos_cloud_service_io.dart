import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';
import 'supabase_bootstrap.dart';
import 'tenant_local_storage_service.dart';

/// Logo e assinatura da empresa no Storage privado.
///
/// Os arquivos ficam fora do payload textual de ConfiguracaoCloudService para
/// não sincronizar caminhos locais entre aparelhos. Cada dispositivo mantém
/// seu próprio cache e o Supabase guarda somente metadados portáveis.
class ConfiguracaoArquivosCloudService {
  ConfiguracaoArquivosCloudService._();

  static final ConfiguracaoArquivosCloudService instance =
      ConfiguracaoArquivosCloudService._();

  static const String bucket = 'imperium-configuracoes-arquivos';

  final AppDatabase _appDatabase = AppDatabase.instance;
  final ConfiguracaoRepository _repository = ConfiguracaoRepository();
  final TenantLocalStorageService _localStorage =
      TenantLocalStorageService.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_configuracao_arquivos (
        empresa_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        local_hash TEXT NOT NULL DEFAULT '',
        remoto_atualizado_em TEXT,
        storage_path TEXT,
        PRIMARY KEY (empresa_id, tipo)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_configuracao_arquivos_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_atualizado_base TEXT,
        remoto_atualizado_atual TEXT,
        remoto_json TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Pendente',
        resolucao TEXT,
        detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_config_arquivos_conflitos
      ON imperium_sync_configuracao_arquivos_conflitos (
        empresa_id,
        status,
        tipo
      )
    ''');
  }

  Future<void> sincronizar(String empresaId) async {
    final id = empresaId.trim();
    final client = _client;
    if (id.isEmpty || client == null || client.auth.currentUser == null) return;

    await garantirEstruturaLocal();

    try {
      if (await possuiConflitosPendentes(id)) return;

      final config = await _repository.obterConfiguracao();
      await _sincronizarTipo(
        empresaId: id,
        tipo: 'logo',
        caminhoLocal: config.caminhoLogo,
      );
      await _sincronizarTipo(
        empresaId: id,
        tipo: 'assinatura_empresa',
        caminhoLocal: config.caminhoAssinaturaEmpresa,
      );
    } on PostgrestException catch (error) {
      // Funcionários não administradores recebem 42501 pelas políticas. Isso
      // é esperado: custos/configurações sensíveis permanecem somente admin.
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_configuracao_arquivos_conflitos',
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
      'imperium_sync_configuracao_arquivos_conflitos',
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final mapas = await database.rawQuery(
      '''
      SELECT tipo, local_hash, remoto_atualizado_em, storage_path
      FROM imperium_sync_configuracao_arquivos
      WHERE empresa_id = ?
      ORDER BY tipo
      ''',
      [empresaId],
    );
    final conflitos = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_configuracao_arquivos_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [empresaId],
    );

    return <String, Object?>{
      'empresa_id': empresaId,
      'bucket': bucket,
      'arquivos_mapeados': mapas.length,
      'mapas': mapas,
      'conflitos_pendentes': _int(conflitos.first['total']),
    };
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final tipo = _texto(conflito['tipo']);
    final remoto = await _buscarRemoto(empresaId, tipo);

    if (remoto == null) {
      throw StateError('O arquivo remoto não existe mais.');
    }

    await _aplicarRemoto(empresaId: empresaId, tipo: tipo, remoto: remoto);
    await _encerrarConflito(
      conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Arquivo da nuvem aplicado neste aparelho.',
    );
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final tipo = _texto(conflito['tipo']);
    final remotoEsperado = _texto(conflito['remoto_atualizado_atual']).trim();
    final config = await _repository.obterConfiguracao();
    final caminho = _caminho(config, tipo);
    final arquivo = await _arquivoSeExiste(caminho);
    final remoto = await _buscarRemoto(empresaId, tipo);

    if (arquivo == null) {
      if (remoto == null) {
        await _salvarMapa(
          empresaId: empresaId,
          tipo: tipo,
          localHash: '',
          remotoAtualizadoEm: null,
          storagePath: null,
        );
      } else {
        final atualizado = await _marcarRemotoExcluido(
          empresaId: empresaId,
          tipo: tipo,
          remotoEsperado: remotoEsperado,
        );
        await _salvarMapa(
          empresaId: empresaId,
          tipo: tipo,
          localHash: '',
          remotoAtualizadoEm: _texto(atualizado['atualizado_em']),
          storagePath: _texto(atualizado['storage_path']),
        );
      }
    } else {
      final hash = await _hashArquivo(arquivo);
      final publicado = await _publicarArquivo(
        empresaId: empresaId,
        tipo: tipo,
        arquivo: arquivo,
        hash: hash,
        remotoAtual: remoto,
        remotoEsperado: remotoEsperado,
      );
      await _salvarMapa(
        empresaId: empresaId,
        tipo: tipo,
        localHash: hash,
        remotoAtualizadoEm: _texto(publicado['atualizado_em']),
        storagePath: _texto(publicado['storage_path']),
      );
    }

    await _encerrarConflito(
      conflitoId,
      resolucao: 'local',
      detalhe: 'Arquivo deste aparelho aplicado na nuvem com CAS.',
    );
  }

  Future<void> _sincronizarTipo({
    required String empresaId,
    required String tipo,
    required String? caminhoLocal,
  }) async {
    final arquivo = await _arquivoSeExiste(caminhoLocal);
    final localHash = arquivo == null ? '' : await _hashArquivo(arquivo);
    final mapa = await _mapa(empresaId, tipo);
    final remoto = await _buscarRemoto(empresaId, tipo);

    if (mapa == null) {
      if (remoto == null) {
        if (arquivo != null) {
          final publicado = await _publicarArquivo(
            empresaId: empresaId,
            tipo: tipo,
            arquivo: arquivo,
            hash: localHash,
          );
          await _salvarMapa(
            empresaId: empresaId,
            tipo: tipo,
            localHash: localHash,
            remotoAtualizadoEm: _texto(publicado['atualizado_em']),
            storagePath: _texto(publicado['storage_path']),
          );
        }
        return;
      }

      final remotoExcluido = _texto(remoto['excluido_em']).isNotEmpty;
      final remotoHash = _texto(remoto['sha256']);

      if (arquivo == null) {
        await _aplicarRemoto(empresaId: empresaId, tipo: tipo, remoto: remoto);
        return;
      }

      if (!remotoExcluido && remotoHash == localHash) {
        await _salvarMapa(
          empresaId: empresaId,
          tipo: tipo,
          localHash: localHash,
          remotoAtualizadoEm: _texto(remoto['atualizado_em']),
          storagePath: _texto(remoto['storage_path']),
        );
        return;
      }

      await _registrarConflito(
        empresaId: empresaId,
        tipo: tipo,
        motivo: remotoExcluido
            ? 'primeira_sincronizacao_remoto_excluido'
            : 'primeira_sincronizacao_divergente',
        mapa: const <String, Object?>{},
        localHashAtual: localHash,
        remoto: remoto,
      );
      return;
    }

    final baseHash = _texto(mapa['local_hash']);
    final baseTs = _texto(mapa['remoto_atualizado_em']);
    final localMudou = localHash != baseHash;

    if (remoto == null) {
      await _registrarConflito(
        empresaId: empresaId,
        tipo: tipo,
        motivo: 'registro_remoto_ausente',
        mapa: mapa,
        localHashAtual: localHash,
        remoto: const <String, dynamic>{},
      );
      return;
    }

    final remotoTs = _texto(remoto['atualizado_em']);
    final remotoMudou =
        baseTs.isEmpty || remotoTs.isEmpty || remotoTs != baseTs;

    if (localMudou && remotoMudou) {
      await _registrarConflito(
        empresaId: empresaId,
        tipo: tipo,
        motivo: 'alteracao_concorrente',
        mapa: mapa,
        localHashAtual: localHash,
        remoto: remoto,
      );
      return;
    }

    if (localMudou) {
      if (arquivo == null) {
        final atualizado = await _marcarRemotoExcluido(
          empresaId: empresaId,
          tipo: tipo,
          remotoEsperado: baseTs,
        );
        await _salvarMapa(
          empresaId: empresaId,
          tipo: tipo,
          localHash: '',
          remotoAtualizadoEm: _texto(atualizado['atualizado_em']),
          storagePath: _texto(atualizado['storage_path']),
        );
        return;
      }

      final publicado = await _publicarArquivo(
        empresaId: empresaId,
        tipo: tipo,
        arquivo: arquivo,
        hash: localHash,
        remotoAtual: remoto,
        remotoEsperado: baseTs,
      );
      await _salvarMapa(
        empresaId: empresaId,
        tipo: tipo,
        localHash: localHash,
        remotoAtualizadoEm: _texto(publicado['atualizado_em']),
        storagePath: _texto(publicado['storage_path']),
      );
      return;
    }

    if (remotoMudou) {
      await _aplicarRemoto(empresaId: empresaId, tipo: tipo, remoto: remoto);
    }
  }

  Future<Map<String, dynamic>> _publicarArquivo({
    required String empresaId,
    required String tipo,
    required File arquivo,
    required String hash,
    Map<String, dynamic>? remotoAtual,
    String? remotoEsperado,
  }) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    final bytes = await arquivo.readAsBytes();
    final extensao = _extensao(arquivo.path);
    final storagePath = '$empresaId/configuracoes/$tipo/$hash$extensao';
    final mime = _mime(arquivo.path);

    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            storagePath,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: mime,
              upsert: false,
              cacheControl: '3600',
            ),
          );
    } on StorageException catch (error) {
      // Caminho é derivado do SHA-256. Objeto já existente com o mesmo nome é
      // o mesmo conteúdo; nesse caso basta reutilizá-lo.
      final msg = error.message.toLowerCase();
      if (!msg.contains('already exists') && !msg.contains('duplicate')) {
        rethrow;
      }
    }

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'tipo': tipo,
      'storage_bucket': bucket,
      'storage_path': storagePath,
      'nome_original': path.basename(arquivo.path),
      'sha256': hash,
      'tamanho': bytes.length,
      'mime': mime,
      'excluido_em': null,
    };

    if (remotoAtual == null) {
      return Map<String, dynamic>.from(
        await client
            .from('imperium_configuracao_arquivos')
            .upsert(payload, onConflict: 'empresa_id,tipo')
            .select()
            .single(),
      );
    }

    var query = client
        .from('imperium_configuracao_arquivos')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('tipo', tipo);
    final esperado = (remotoEsperado ?? '').trim();
    if (esperado.isNotEmpty) query = query.eq('atualizado_em', esperado);

    final rows = await query.select();
    if (rows.isEmpty) {
      throw StateError(
        'O arquivo da empresa mudou na nuvem durante a gravação. Sincronize e revise o conflito.',
      );
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>> _marcarRemotoExcluido({
    required String empresaId,
    required String tipo,
    required String remotoEsperado,
  }) async {
    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');

    var query = client
        .from('imperium_configuracao_arquivos')
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('empresa_id', empresaId)
        .eq('tipo', tipo);
    if (remotoEsperado.trim().isNotEmpty) {
      query = query.eq('atualizado_em', remotoEsperado.trim());
    }

    final rows = await query.select();
    if (rows.isEmpty) {
      throw StateError(
        'O arquivo da empresa mudou na nuvem durante a exclusão. Sincronize novamente.',
      );
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> _aplicarRemoto({
    required String empresaId,
    required String tipo,
    required Map<String, dynamic> remoto,
  }) async {
    final remotoTs = _texto(remoto['atualizado_em']);
    final storagePath = _texto(remoto['storage_path']);

    if (_texto(remoto['excluido_em']).isNotEmpty) {
      await _atualizarCaminho(tipo, null);
      await _salvarMapa(
        empresaId: empresaId,
        tipo: tipo,
        localHash: '',
        remotoAtualizadoEm: remotoTs,
        storagePath: storagePath,
      );
      return;
    }

    final client = _client;
    if (client == null) throw StateError('Supabase indisponível.');
    if (storagePath.isEmpty) {
      throw StateError('Arquivo remoto sem caminho de Storage.');
    }

    final bytes = await client.storage.from(bucket).download(storagePath);
    final esperado = _texto(remoto['sha256']);
    final recebido = sha256.convert(bytes).toString();
    if (esperado.isNotEmpty && recebido != esperado) {
      throw StateError('Arquivo remoto falhou na verificação SHA-256.');
    }

    final diretorio = await _localStorage.pasta(
      'configuracoes',
      segmentos: const ['cloud'],
    );
    final extensao = _extensao(
      _texto(remoto['nome_original']).isNotEmpty
          ? _texto(remoto['nome_original'])
          : storagePath,
    );
    final destino = File(
      path.join(diretorio.path, '$tipo-${recebido.substring(0, 16)}$extensao'),
    );
    await destino.writeAsBytes(bytes, flush: true);
    await _atualizarCaminho(tipo, destino.path);

    await _salvarMapa(
      empresaId: empresaId,
      tipo: tipo,
      localHash: recebido,
      remotoAtualizadoEm: remotoTs,
      storagePath: storagePath,
    );
  }

  Future<Map<String, dynamic>?> _buscarRemoto(
    String empresaId,
    String tipo,
  ) async {
    final client = _client;
    if (client == null) return null;
    final raw = await client
        .from('imperium_configuracao_arquivos')
        .select()
        .eq('empresa_id', empresaId)
        .eq('tipo', tipo)
        .maybeSingle();
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<Map<String, Object?>?> _mapa(String empresaId, String tipo) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_configuracao_arquivos',
      where: 'empresa_id = ? AND tipo = ?',
      whereArgs: [empresaId, tipo],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _salvarMapa({
    required String empresaId,
    required String tipo,
    required String localHash,
    required String? remotoAtualizadoEm,
    required String? storagePath,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(
      'imperium_sync_configuracao_arquivos',
      {
        'empresa_id': empresaId,
        'tipo': tipo,
        'local_hash': localHash,
        'remoto_atualizado_em': remotoAtualizadoEm,
        'storage_path': storagePath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String tipo,
    required String motivo,
    required Map<String, Object?> mapa,
    required String localHashAtual,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final existentes = await database.query(
      'imperium_sync_configuracao_arquivos_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND tipo = ? AND status = 'Pendente'",
      whereArgs: [empresaId, tipo],
      limit: 1,
    );

    final dados = <String, Object?>{
      'empresa_id': empresaId,
      'tipo': tipo,
      'motivo': motivo,
      'local_hash_base': _texto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _texto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _texto(remoto['atualizado_em']),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'resolucao': null,
      'detalhe': null,
      'detectado_em': DateTime.now().toIso8601String(),
      'resolvido_em': null,
    };

    if (existentes.isEmpty) {
      await database.insert(
        'imperium_sync_configuracao_arquivos_conflitos',
        dados,
      );
    } else {
      await database.update(
        'imperium_sync_configuracao_arquivos_conflitos',
        dados,
        where: 'id = ?',
        whereArgs: [existentes.first['id']],
      );
    }
  }

  Future<Map<String, Object?>> _conflitoPendente(int id) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_configuracao_arquivos_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Conflito de arquivo não encontrado.');
    return rows.first;
  }

  Future<void> _encerrarConflito(
    int id, {
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_configuracao_arquivos_conflitos',
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

  Future<File?> _arquivoSeExiste(String? caminho) async {
    final texto = (caminho ?? '').trim();
    if (texto.isEmpty) return null;
    final arquivo = File(texto);
    return await arquivo.exists() ? arquivo : null;
  }

  Future<String> _hashArquivo(File arquivo) async {
    return sha256.convert(await arquivo.readAsBytes()).toString();
  }

  Future<void> _atualizarCaminho(String tipo, String? caminho) async {
    if (tipo == 'logo') {
      await _repository.atualizarLogo(caminho);
      return;
    }
    if (tipo == 'assinatura_empresa') {
      await _repository.atualizarAssinaturaEmpresa(caminho);
      return;
    }
    throw ArgumentError('Tipo de arquivo de configuração inválido: $tipo');
  }

  String? _caminho(Configuracao config, String tipo) {
    return switch (tipo) {
      'logo' => config.caminhoLogo,
      'assinatura_empresa' => config.caminhoAssinaturaEmpresa,
      _ => null,
    };
  }

  String _extensao(String caminho) {
    final ext = path.extension(caminho).toLowerCase();
    if (ext.length >= 2 && ext.length <= 8) return ext;
    return '.bin';
  }

  String _mime(String caminho) {
    return switch (path.extension(caminho).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.svg' => 'image/svg+xml',
      _ => 'application/octet-stream',
    };
  }

  static int _int(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse((valor ?? '').toString()) ?? 0;
  }

  static String _texto(Object? valor) => (valor ?? '').toString();
}
