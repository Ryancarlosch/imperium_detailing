import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Multiempresa com isolamento físico do SQLite por empresa.
class EmpresaCloudService {
  EmpresaCloudService._();

  static final EmpresaCloudService instance = EmpresaCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // empresa-cloud-multiempresa-v2
  Future<List<Map<String, dynamic>>> listarEmpresasVinculadas() async {
    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) return const [];

    final vinculos = await client
        .from('empresa_usuarios')
        .select('empresa_id,papel,ativo,atualizado_em')
        .eq('user_id', user.id)
        .eq('ativo', true);

    final atualId = await _appDatabase.empresaAtivaId;
    final resultado = <Map<String, dynamic>>[];

    for (final raw in vinculos) {
      final vinculo = Map<String, dynamic>.from(raw);
      final papel = (vinculo['papel'] ?? '').toString().trim().toLowerCase();

      // A conta cloud representa a empresa. Funcionários continuam como
      // usuários internos, criados e gerenciados pelo administrador.
      if (papel != 'admin' && papel != 'proprietario') {
        continue;
      }

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
        'papel': papel,
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

  Future<void> trocarEmpresa(String empresaId) async {
    final client = _client;
    final user = client?.auth.currentUser;
    final destino = empresaId.trim();

    if (client == null || user == null) {
      throw StateError('É necessário estar conectado para trocar de empresa.');
    }

    if (destino.isEmpty) {
      throw ArgumentError('Empresa de destino inválida.');
    }

    final vinculo = await client
        .from('empresa_usuarios')
        .select('empresa_id,ativo')
        .eq('user_id', user.id)
        .eq('empresa_id', destino)
        .eq('ativo', true)
        .maybeSingle();

    if (vinculo == null) {
      throw StateError('Seu usuário não possui acesso ativo a esta empresa.');
    }

    final atual = await _appDatabase.empresaAtivaId;
    if (atual == destino) return;

    await _appDatabase.ativarEmpresa(
      destino,
      // Se ainda não havia tenant selecionado, a escolha explícita do usuário
      // autoriza adotar o banco legado para esta empresa.
      adotarBancoLegado: atual == null || atual.isEmpty,
    );
  }

  Future<Map<String, Object?>> diagnosticarMultiempresa() async {
    final empresas = await listarEmpresasVinculadas();
    final atual = empresas.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['atual'] == true,
      orElse: () => null,
    );
    final local = await _appDatabase.diagnosticarTenantLocal();

    return <String, Object?>{
      'total_empresas_ativas': empresas.length,
      'empresa_atual_id': atual?['empresa_id'],
      'empresa_atual_nome': atual?['nome'],
      'multiempresa_detectada': empresas.length > 1,
      'troca_segura_disponivel': true,
      'isolamento_local_por_banco': true,
      'motivo_bloqueio_troca': null,
      ...local,
    };
  }
}
