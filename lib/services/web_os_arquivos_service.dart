import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

/// Gestão Web dos arquivos sincronizados da Ordem de Serviço.
///
/// Mantém o Storage privado e reutiliza as políticas RLS existentes.
/// Não depende de `dart:io`: no navegador os arquivos são baixados como bytes.
class WebOsArquivosService {
  WebOsArquivosService._();

  static final WebOsArquivosService instance = WebOsArquivosService._();

  static const String bucketPadrao = 'imperium-os-arquivos';
  static const int tamanhoMaximoImagem = 20 * 1024 * 1024;

  final WebOrigemService _origem = WebOrigemService.instance;

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError(
        'Selecione uma empresa antes de abrir os arquivos da OS.',
      );
    }
    return empresa;
  }

  Future<Map<String, dynamic>> carregar(String ordemId) async {
    final id = ordemId.trim();
    if (id.isEmpty) throw ArgumentError('Ordem de serviço inválida.');

    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();

    final ordemRaw = await client
        .from('imperium_ordens_servico')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', id)
        .single();

    final fotosRaw = await client
        .from('imperium_ordem_servico_fotos')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', id);

    final checklistRaw = await client
        .from('imperium_ordem_servico_checklist')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', id);

    final ordem = Map<String, dynamic>.from(ordemRaw);
    final arquivos = <Map<String, dynamic>>[];

    final fotos =
        (fotosRaw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(_ativo)
            .toList()
          ..sort((a, b) {
            final etapa = _texto(a['etapa']).compareTo(_texto(b['etapa']));
            if (etapa != 0) return etapa;
            return _inteiro(a['ordem']).compareTo(_inteiro(b['ordem']));
          });

    for (final foto in fotos) {
      final path = _texto(foto['storage_path']);
      if (path.isEmpty) continue;

      arquivos.add(<String, dynamic>{
        'tipo': 'foto',
        'titulo': _texto(foto['etapa']).isEmpty
            ? 'Foto da OS'
            : 'Foto · ${_texto(foto['etapa'])}',
        'descricao': _texto(foto['descricao']),
        'bucket': _bucket(foto['storage_bucket']),
        'path': path,
        'nome': _texto(foto['nome_original']),
        'mime': _texto(foto['mime']),
        'data': _texto(foto['data_registro']),
      });
    }

    final checklist =
        (checklistRaw as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(_ativo)
            .toList()
          ..sort((a, b) {
            final categoria = _texto(
              a['categoria'],
            ).compareTo(_texto(b['categoria']));
            if (categoria != 0) return categoria;
            return _inteiro(a['ordem']).compareTo(_inteiro(b['ordem']));
          });

    for (final item in checklist) {
      final path = _texto(item['foto_avaria_storage_path']);
      if (path.isEmpty) continue;

      final categoria = _texto(item['categoria']);
      final nomeItem = _texto(item['item']);
      final titulo = [
        if (categoria.isNotEmpty) categoria,
        if (nomeItem.isNotEmpty) nomeItem,
      ].join(' · ');

      arquivos.add(<String, dynamic>{
        'tipo': 'avaria',
        'titulo': titulo.isEmpty ? 'Foto de avaria' : 'Avaria · $titulo',
        'descricao': _texto(item['observacao']),
        'bucket': _bucket(item['foto_avaria_storage_bucket']),
        'path': path,
        'nome': _texto(item['foto_avaria_nome_original']),
        'mime': _texto(item['foto_avaria_mime']),
        'data': '',
      });
    }

    final assinaturaPath = _texto(ordem['assinatura_storage_path']);
    if (assinaturaPath.isNotEmpty) {
      arquivos.add(<String, dynamic>{
        'tipo': 'assinatura',
        'titulo': 'Assinatura do cliente',
        'descricao': '',
        'bucket': _bucket(ordem['assinatura_storage_bucket']),
        'path': assinaturaPath,
        'nome': _texto(ordem['assinatura_nome_original']),
        'mime': _texto(ordem['assinatura_mime']),
        'data': '',
      });
    }

    return <String, dynamic>{
      'ordem': ordem,
      'checklist': checklist,
      'arquivos': arquivos,
      'total_fotos': arquivos.where((a) => a['tipo'] == 'foto').length,
      'total_avarias': arquivos.where((a) => a['tipo'] == 'avaria').length,
      'tem_assinatura': arquivos.any((a) => a['tipo'] == 'assinatura'),
    };
  }

  Future<void> adicionarFoto({
    required String ordemId,
    required String etapa,
    required String descricao,
    required Uint8List bytes,
    required String nomeOriginal,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('Selecione uma imagem válida.');
    if (bytes.length > tamanhoMaximoImagem) {
      throw ArgumentError('A imagem deve ter no máximo 20 MB.');
    }

    final contexto = await _contextoEditavel(ordemId);
    final empresaId = contexto.empresaId;
    final id = contexto.ordemId;
    final origem = await _origem.proxima();
    final hash = sha256.convert(bytes).toString();
    final extensao = _extensao(nomeOriginal);
    final mime = _mime(extensao);
    final caminho =
        '$empresaId/ordens-servico/$id/fotos/'
        'web-${origem.localId}-${hash.substring(0, 20)}.$extensao';

    await _client.storage
        .from(bucketPadrao)
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: mime),
        );

    await _client
        .from('imperium_ordem_servico_fotos')
        .upsert(<String, dynamic>{
          'empresa_id': empresaId,
          'origem_dispositivo': origem.dispositivoId,
          'origem_local_id': origem.localId,
          'ordem_servico_id': id,
          'etapa': etapa.trim().isEmpty ? 'Antes' : etapa.trim(),
          'descricao': descricao.trim(),
          'data_registro': DateTime.now().toIso8601String(),
          'ordem': DateTime.now().microsecondsSinceEpoch,
          'origem_caminho': 'web:$nomeOriginal',
          'storage_bucket': bucketPadrao,
          'storage_path': caminho,
          'nome_original': nomeOriginal.trim(),
          'sha256': hash,
          'tamanho': bytes.length,
          'mime': mime,
          'excluido_em': null,
        }, onConflict: 'empresa_id,origem_dispositivo,origem_local_id');
  }

  Future<void> salvarChecklist({
    required String ordemId,
    Map<String, dynamic>? atual,
    required String categoria,
    required String item,
    required int status,
    required String observacao,
    required String localizacaoAvaria,
    Uint8List? fotoBytes,
    String fotoNome = '',
  }) async {
    if (item.trim().isEmpty) {
      throw ArgumentError('Informe o item do checklist.');
    }
    if (status < 0 || status > 2) {
      throw ArgumentError('Status do checklist inválido.');
    }
    if (fotoBytes != null && fotoBytes.length > tamanhoMaximoImagem) {
      throw ArgumentError('A foto da avaria deve ter no máximo 20 MB.');
    }

    final contexto = await _contextoEditavel(ordemId);
    final origem = await _origem.proxima();
    final atualId = _texto(atual?['id']);
    final payload = <String, dynamic>{
      'empresa_id': contexto.empresaId,
      'ordem_servico_id': contexto.ordemId,
      'categoria': categoria.trim().isEmpty ? 'Geral' : categoria.trim(),
      'item': item.trim(),
      'marcado': status != 0,
      'status': status,
      'observacao': observacao.trim(),
      'avaria_localizacao': status == 2 ? localizacaoAvaria.trim() : '',
      'avaria_data_registro': status == 2
          ? DateTime.now().toIso8601String()
          : null,
      'ordem': _inteiro(atual?['ordem']) == 0
          ? DateTime.now().microsecondsSinceEpoch
          : _inteiro(atual?['ordem']),
      'excluido_em': null,
    };

    if (fotoBytes != null && fotoBytes.isNotEmpty) {
      final hash = sha256.convert(fotoBytes).toString();
      final extensao = _extensao(fotoNome);
      final mime = _mime(extensao);
      final caminho =
          '${contexto.empresaId}/ordens-servico/${contexto.ordemId}/checklist/'
          'web-${origem.localId}-${hash.substring(0, 20)}.$extensao';

      await _client.storage
          .from(bucketPadrao)
          .uploadBinary(
            caminho,
            fotoBytes,
            fileOptions: FileOptions(upsert: true, contentType: mime),
          );

      payload.addAll(<String, dynamic>{
        'foto_avaria_origem_caminho': 'web:$fotoNome',
        'foto_avaria_storage_bucket': bucketPadrao,
        'foto_avaria_storage_path': caminho,
        'foto_avaria_nome_original': fotoNome.trim(),
        'foto_avaria_sha256': hash,
        'foto_avaria_tamanho': fotoBytes.length,
        'foto_avaria_mime': mime,
      });
    } else if (status != 2) {
      payload.addAll(<String, dynamic>{
        'foto_avaria_origem_caminho': null,
        'foto_avaria_storage_bucket': null,
        'foto_avaria_storage_path': null,
        'foto_avaria_nome_original': null,
        'foto_avaria_sha256': null,
        'foto_avaria_tamanho': null,
        'foto_avaria_mime': null,
      });
    }

    if (atualId.isEmpty) {
      payload.addAll(<String, dynamic>{
        'origem_dispositivo': origem.dispositivoId,
        'origem_local_id': origem.localId,
      });
      await _client
          .from('imperium_ordem_servico_checklist')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          );
      return;
    }

    final esperado = _texto(atual?['atualizado_em']);
    dynamic query = _client
        .from('imperium_ordem_servico_checklist')
        .update(payload)
        .eq('empresa_id', contexto.empresaId)
        .eq('id', atualId);
    if (esperado.isNotEmpty) query = query.eq('atualizado_em', esperado);
    final resposta = await query.select('id').maybeSingle();
    if (resposta == null) {
      throw StateError(
        'O checklist foi alterado em outro aparelho. Atualize e tente novamente.',
      );
    }
  }

  Future<void> salvarAssinatura({
    required String ordemId,
    required String atualizadoEm,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('A assinatura está vazia.');

    final contexto = await _contextoEditavel(ordemId);
    final hash = sha256.convert(bytes).toString();
    final caminho =
        '${contexto.empresaId}/ordens-servico/${contexto.ordemId}/assinatura/'
        'assinatura-web-${hash.substring(0, 20)}.png';

    await _client.storage
        .from(bucketPadrao)
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );

    dynamic query = _client
        .from('imperium_ordens_servico')
        .update(<String, dynamic>{
          'assinatura_origem_caminho': 'web:assinatura.png',
          'assinatura_storage_bucket': bucketPadrao,
          'assinatura_storage_path': caminho,
          'assinatura_nome_original': 'assinatura.png',
          'assinatura_sha256': hash,
          'assinatura_tamanho': bytes.length,
          'assinatura_mime': 'image/png',
          'assinatura_desatualizada': false,
        })
        .eq('empresa_id', contexto.empresaId)
        .eq('id', contexto.ordemId);
    if (atualizadoEm.trim().isNotEmpty) {
      query = query.eq('atualizado_em', atualizadoEm.trim());
    }
    final resposta = await query.select('id').maybeSingle();
    if (resposta == null) {
      throw StateError(
        'A OS foi alterada em outro aparelho. Atualize antes de assinar.',
      );
    }
  }

  Future<_WebOsContexto> _contextoEditavel(String ordemId) async {
    final id = ordemId.trim();
    if (id.isEmpty) throw ArgumentError('Ordem de serviço inválida.');

    final empresaId = await _empresaId();
    final ordem = await _client
        .from('imperium_ordens_servico')
        .select('id,status,atualizado_em')
        .eq('empresa_id', empresaId)
        .eq('id', id)
        .single();
    final status = _texto(ordem['status']);
    if (status != 'Aberta' && status != 'Em andamento') {
      throw StateError(
        'Somente OS aberta ou em andamento aceita novos arquivos.',
      );
    }
    return _WebOsContexto(empresaId: empresaId, ordemId: id);
  }

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');
    return client;
  }

  Future<Uint8List> baixar(Map<String, dynamic> arquivo) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final path = _texto(arquivo['path']);
    if (path.isEmpty) throw StateError('Arquivo sem caminho no Storage.');

    final bucket = _bucket(arquivo['bucket']);
    return client.storage.from(bucket).download(path);
  }

  static bool _ativo(Map<String, dynamic> row) {
    return _texto(row['excluido_em']).isEmpty;
  }

  static String _bucket(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? bucketPadrao : texto;
  }

  static String _texto(dynamic valor) => (valor ?? '').toString().trim();

  static int _inteiro(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(_texto(valor)) ?? 0;
  }

  static String _extensao(String nome) {
    final texto = nome.toLowerCase();
    final ponto = texto.lastIndexOf('.');
    if (ponto < 0 || ponto == texto.length - 1) return 'jpg';
    final extensao = texto.substring(ponto + 1);
    return <String>{'jpg', 'jpeg', 'png', 'webp'}.contains(extensao)
        ? extensao
        : 'jpg';
  }

  static String _mime(String extensao) => switch (extensao.toLowerCase()) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class _WebOsContexto {
  const _WebOsContexto({required this.empresaId, required this.ordemId});

  final String empresaId;
  final String ordemId;
}
