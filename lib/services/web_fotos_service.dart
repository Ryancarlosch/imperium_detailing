import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_cloud_operacional_service.dart';
import 'web_origem_service.dart';

class WebFotosPacote {
  const WebFotosPacote({
    required this.gerais,
    required this.fotosOs,
    required this.clientes,
    required this.veiculos,
    required this.ordens,
  });

  final List<Map<String, dynamic>> gerais;
  final List<Map<String, dynamic>> fotosOs;
  final List<Map<String, dynamic>> clientes;
  final List<Map<String, dynamic>> veiculos;
  final List<Map<String, dynamic>> ordens;
}

class WebFotosService {
  WebFotosService._();

  static final WebFotosService instance = WebFotosService._();

  static const String bucketGaleria = 'imperium-fotos-servico';

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir Fotos.');
    }
    return empresa;
  }

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');
    return client;
  }

  Future<WebFotosPacote> carregar() async {
    final empresaId = await _empresaId();
    final operacional = WebCloudOperacionalService.instance;

    final resultados = await Future.wait<dynamic>([
      _client
          .from('imperium_fotos_servico')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .order('criado_em', ascending: false),
      _client
          .from('imperium_ordem_servico_fotos')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .order('criado_em', ascending: false),
      operacional.listarClientes(),
      operacional.listarVeiculos(),
      operacional.listarOrdens(),
    ]);

    return WebFotosPacote(
      gerais: _lista(resultados[0]),
      fotosOs: _lista(resultados[1]),
      clientes: resultados[2] as List<Map<String, dynamic>>,
      veiculos: resultados[3] as List<Map<String, dynamic>>,
      ordens: resultados[4] as List<Map<String, dynamic>>,
    );
  }

  Future<Uint8List> baixar({
    required String bucket,
    required String storagePath,
  }) async {
    final caminho = storagePath.trim();
    if (caminho.isEmpty) return Uint8List(0);
    return _client.storage.from(bucket).download(caminho);
  }

  Future<void> criarAntesDepois({
    required String clienteId,
    required String veiculoId,
    required String descricao,
    required String data,
    required Uint8List antesBytes,
    required String antesNome,
    Uint8List? depoisBytes,
    String depoisNome = '',
  }) async {
    if (clienteId.trim().isEmpty || veiculoId.trim().isEmpty) {
      throw ArgumentError('Selecione cliente e veículo.');
    }
    if (antesBytes.isEmpty) {
      throw ArgumentError('Selecione pelo menos a foto de antes.');
    }

    final empresaId = await _empresaId();
    final origem = await WebOrigemService.instance.proxima();
    final base = empresaId +
        '/galeria/web/' +
        origem.dispositivoId +
        '/' +
        origem.localId.toString();

    final antesExt = _extensao(antesNome);
    final antesPath = base + '/antes.' + antesExt;
    final antesMime = _mime(antesExt);

    await _client.storage.from(bucketGaleria).uploadBinary(
      antesPath,
      antesBytes,
      fileOptions: FileOptions(upsert: true, contentType: antesMime),
    );

    String? depoisPath;
    String? depoisMime;
    String? depoisSha;
    if (depoisBytes != null && depoisBytes.isNotEmpty) {
      final depoisExt = _extensao(depoisNome);
      depoisPath = base + '/depois.' + depoisExt;
      depoisMime = _mime(depoisExt);
      depoisSha = sha256.convert(depoisBytes).toString();

      await _client.storage.from(bucketGaleria).uploadBinary(
        depoisPath,
        depoisBytes,
        fileOptions: FileOptions(upsert: true, contentType: depoisMime),
      );
    }

    await _client.from('imperium_fotos_servico').insert({
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'origem_dispositivo': origem.dispositivoId,
      'origem_local_id': origem.localId,
      'descricao': descricao.trim(),
      'data': data.trim(),
      'antes_storage_bucket': bucketGaleria,
      'antes_storage_path': antesPath,
      'antes_nome_original': antesNome,
      'antes_sha256': sha256.convert(antesBytes).toString(),
      'antes_tamanho': antesBytes.length,
      'antes_mime': antesMime,
      'depois_storage_bucket': depoisPath == null ? null : bucketGaleria,
      'depois_storage_path': depoisPath,
      'depois_nome_original': depoisPath == null ? null : depoisNome,
      'depois_sha256': depoisSha,
      'depois_tamanho': depoisBytes?.length,
      'depois_mime': depoisMime,
      'excluido_em': null,
    });
  }

  static List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String _extensao(String nome) {
    final lower = nome.toLowerCase();
    final ponto = lower.lastIndexOf('.');
    if (ponto < 0 || ponto == lower.length - 1) return 'jpg';
    final ext = lower.substring(ponto + 1);
    if (<String>{'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(ext)) {
      return ext;
    }
    return 'jpg';
  }

  static String _mime(String ext) {
    return switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }
}
