import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class WebConfiguracaoArquivo {
  const WebConfiguracaoArquivo({
    required this.tipo,
    required this.storageBucket,
    required this.storagePath,
    required this.nomeOriginal,
    required this.sha256,
    required this.tamanho,
    required this.mime,
    required this.atualizadoEm,
  });

  final String tipo;
  final String storageBucket;
  final String storagePath;
  final String nomeOriginal;
  final String sha256;
  final int tamanho;
  final String mime;
  final String atualizadoEm;

  factory WebConfiguracaoArquivo.fromMap(Map<String, dynamic> map) {
    return WebConfiguracaoArquivo(
      tipo: (map['tipo'] ?? '').toString(),
      storageBucket: (map['storage_bucket'] ?? '').toString(),
      storagePath: (map['storage_path'] ?? '').toString(),
      nomeOriginal: (map['nome_original'] ?? '').toString(),
      sha256: (map['sha256'] ?? '').toString(),
      tamanho: _int(map['tamanho']),
      mime: (map['mime'] ?? 'application/octet-stream').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class WebConfiguracaoArquivoService {
  WebConfiguracaoArquivoService._();

  static final WebConfiguracaoArquivoService instance =
      WebConfiguracaoArquivoService._();

  static const bucket = 'imperium-configuracoes-arquivos';
  static const tiposValidos = <String>{'logo', 'assinatura_empresa'};

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<String> _empresaId() async {
    final id = (await AppDatabase.instance.empresaAtivaId ?? '').trim();
    if (id.isEmpty) {
      throw StateError('Selecione uma empresa antes de gerenciar arquivos.');
    }
    return id;
  }

  Future<Map<String, WebConfiguracaoArquivo>> listarAtivos() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_configuracao_arquivos')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null);

    final resultado = <String, WebConfiguracaoArquivo>{};
    for (final item in raw) {
      final arquivo = WebConfiguracaoArquivo.fromMap(
        Map<String, dynamic>.from(item),
      );
      if (tiposValidos.contains(arquivo.tipo)) {
        resultado[arquivo.tipo] = arquivo;
      }
    }
    return resultado;
  }

  Future<Uint8List?> baixar(WebConfiguracaoArquivo? arquivo) async {
    if (arquivo == null || arquivo.storagePath.trim().isEmpty) return null;
    final bucketId = arquivo.storageBucket.trim().isEmpty
        ? bucket
        : arquivo.storageBucket.trim();
    return _client.storage.from(bucketId).download(arquivo.storagePath);
  }

  Future<WebConfiguracaoArquivo> salvar({
    required String tipo,
    required Uint8List bytes,
    required String nomeOriginal,
    required String mime,
  }) async {
    final tipoNormalizado = tipo.trim();
    if (!tiposValidos.contains(tipoNormalizado)) {
      throw ArgumentError('Tipo de arquivo de configuração inválido.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('O arquivo selecionado está vazio.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('O arquivo deve ter no máximo 10 MB.');
    }

    final mimeNormalizado = _mimeImagem(mime, nomeOriginal);
    final extensao = _extensao(mimeNormalizado, nomeOriginal);
    final empresaId = await _empresaId();
    final hash = sha256.convert(bytes).toString();
    final storagePath =
        '$empresaId/configuracoes/$tipoNormalizado/$hash.$extensao';

    await _client.storage.from(bucket).uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(
        cacheControl: '3600',
        upsert: true,
        contentType: mimeNormalizado,
      ),
    );

    final raw = await _client
        .from('imperium_configuracao_arquivos')
        .upsert(
          <String, dynamic>{
            'empresa_id': empresaId,
            'tipo': tipoNormalizado,
            'storage_bucket': bucket,
            'storage_path': storagePath,
            'nome_original': nomeOriginal.trim(),
            'sha256': hash,
            'tamanho': bytes.length,
            'mime': mimeNormalizado,
            'excluido_em': null,
          },
          onConflict: 'empresa_id,tipo',
        )
        .select()
        .single();

    return WebConfiguracaoArquivo.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> remover(String tipo) async {
    final tipoNormalizado = tipo.trim();
    if (!tiposValidos.contains(tipoNormalizado)) {
      throw ArgumentError('Tipo de arquivo de configuração inválido.');
    }

    final empresaId = await _empresaId();
    await _client
        .from('imperium_configuracao_arquivos')
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('empresa_id', empresaId)
        .eq('tipo', tipoNormalizado);
  }

  static String _mimeImagem(String mime, String nome) {
    final informado = mime.trim().toLowerCase();
    if (informado == 'image/png' ||
        informado == 'image/jpeg' ||
        informado == 'image/webp') {
      return informado;
    }

    final lower = nome.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  static String _extensao(String mime, String nome) {
    if (mime == 'image/jpeg') return 'jpg';
    if (mime == 'image/webp') return 'webp';
    if (mime == 'image/png') return 'png';

    final ponto = nome.lastIndexOf('.');
    if (ponto >= 0 && ponto < nome.length - 1) {
      final ext = nome.substring(ponto + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) return ext;
    }
    return 'png';
  }
}
