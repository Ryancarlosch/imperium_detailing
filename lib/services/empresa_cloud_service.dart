import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Diagnóstico multiempresa.
///
/// V1 apenas lista vínculos. Não troca o tenant porque as tabelas de domínio
/// do SQLite ainda não possuem empresa_id.
class EmpresaCloudService {
  EmpresaCloudService._();

  static final EmpresaCloudService instance = EmpresaCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // empresa-cloud-multiempresa-foundation-v1
  Future<List<Map<String, dynamic>>> listarEmpresasVinculadas() async {
    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) return const [];

    final vinculos = await client
        .from('empresa_usuarios')
        .select('empresa_id,papel,ativo,atualizado_em')
        .eq('user_id', user.id)
        .eq('ativo', true);

    final atualId = await _empresaCache();
    final resultado = <Map<String, dynamic>>[];

    for (final raw in vinculos) {
      final vinculo = Map<String, dynamic>.from(raw);
      final empresaId = (vinculo['empresa_id'] ?? '').toString().trim();
      if (empresaId.isEmpty) continue;

      final empresaRaw = await client
          .from('empresas')
          .select('id,nome,slug,ativo,atualizado_em')
          .eq('id', empresaId)
          .maybeSingle();

      if (empresaRaw == null) continue;

      final empresa = Map<String, dynamic>.from(empresaRaw);

      resultado.add(<String, dynamic>{
        'empresa_id': empresaId,
        'nome': (empresa['nome'] ?? '').toString(),
        'slug': (empresa['slug'] ?? '').toString(),
        'papel': (vinculo['papel'] ?? '').toString(),
        'ativo': empresa['ativo'] == true && vinculo['ativo'] == true,
        'atual': atualId == empresaId,
        'atualizado_em': empresa['atualizado_em'],
      });
    }

    resultado.sort((a, b) {
      final aAtual = a['atual'] == true ? 0 : 1;
      final bAtual = b['atual'] == true ? 0 : 1;
      if (aAtual != bAtual) return aAtual.compareTo(bAtual);

      return (a['nome'] ?? '').toString().toLowerCase().compareTo(
        (b['nome'] ?? '').toString().toLowerCase(),
      );
    });

    return resultado;
  }

  Future<Map<String, Object?>> diagnosticarMultiempresa() async {
    final empresas = await listarEmpresasVinculadas();
    final atual = empresas.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['atual'] == true,
      orElse: () => null,
    );

    return <String, Object?>{
      'total_empresas_ativas': empresas.length,
      'empresa_atual_id': atual?['empresa_id'],
      'empresa_atual_nome': atual?['nome'],
      'multiempresa_detectada': empresas.length > 1,
      'troca_segura_disponivel': empresas.length <= 1,
      'motivo_bloqueio_troca': empresas.length > 1
          ? 'SQLite local ainda não está isolado por empresa.'
          : null,
    };
  }

  Future<String?> _empresaCache() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        dispositivo_id TEXT NOT NULL,
        empresa_id TEXT,
        ultimo_sync_em TEXT
      )
    ''');

    final rows = await database.query(
      'imperium_sync_config',
      columns: ['empresa_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final id = (rows.first['empresa_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }
}
