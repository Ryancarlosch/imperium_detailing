import 'dart:typed_data';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Leitura Web dos arquivos já sincronizados da Ordem de Serviço.
///
/// Mantém o Storage privado e reutiliza as políticas RLS existentes.
/// Não depende de `dart:io`: no navegador os arquivos são baixados como bytes.
class WebOsArquivosService {
  WebOsArquivosService._();

  static final WebOsArquivosService instance = WebOsArquivosService._();

  static const String bucketPadrao = 'imperium-os-arquivos';

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

    final checklist = (checklistRaw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(_ativo)
        .toList();

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
      'arquivos': arquivos,
      'total_fotos': arquivos.where((a) => a['tipo'] == 'foto').length,
      'total_avarias': arquivos.where((a) => a['tipo'] == 'avaria').length,
      'tem_assinatura': arquivos.any((a) => a['tipo'] == 'assinatura'),
    };
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
}
