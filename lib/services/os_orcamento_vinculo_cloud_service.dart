import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincroniza a relação Orçamento -> Ordem de Serviço depois que os dois
/// módulos já possuem seus mapas local/remoto.
///
/// A etapa de OS roda antes de CRM/Orçamentos no motor de sync. Por isso o
/// vínculo é reconciliado no fim de CRM, quando ambos os IDs já são conhecidos.
class OsOrcamentoVinculoCloudService {
  OsOrcamentoVinculoCloudService._();

  static final OsOrcamentoVinculoCloudService instance =
      OsOrcamentoVinculoCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (client == null || empresaId.trim().isEmpty) return;

    final database = await _appDatabase.database;
    final remotos = await client
        .from('imperium_ordens_servico')
        .select('id,orcamento_id,atualizado_em')
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null);

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final osRemotoId = _texto(remoto['id']);
      if (osRemotoId.isEmpty) continue;

      final osLocalId = await _localPorRemoto(
        database: database,
        tabelaMapa: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: osRemotoId,
      );
      if (osLocalId == null) continue;

      final linhasOs = await database.query(
        'ordens_servico',
        columns: ['id', 'orcamento_id'],
        where: 'id = ?',
        whereArgs: [osLocalId],
        limit: 1,
      );
      if (linhasOs.isEmpty) continue;

      final orcamentoLocalAtual = _intNulo(linhasOs.first['orcamento_id']);
      final orcamentoRemotoId = _texto(remoto['orcamento_id']);

      if (orcamentoRemotoId.isNotEmpty) {
        final orcamentoLocalId = await _localPorRemoto(
          database: database,
          tabelaMapa: 'imperium_sync_orcamentos',
          empresaId: empresaId,
          remotoId: orcamentoRemotoId,
        );
        if (orcamentoLocalId == null) {
          // O orçamento pode ter sido excluído ou ainda não ter mapa local.
          // Não apagamos um vínculo local válido sem ter a dependência.
          continue;
        }

        if (orcamentoLocalAtual != null &&
            orcamentoLocalAtual != orcamentoLocalId) {
          throw StateError(
            'A OS local #$osLocalId está vinculada a outro orçamento. '
            'Revise o conflito antes de continuar a sincronização.',
          );
        }

        if (orcamentoLocalAtual != orcamentoLocalId) {
          await database.update(
            'ordens_servico',
            {'orcamento_id': orcamentoLocalId},
            where: 'id = ?',
            whereArgs: [osLocalId],
          );
        }
        continue;
      }

      if (orcamentoLocalAtual == null || orcamentoLocalAtual <= 0) continue;

      final orcamentoRemoto = await _remotoPorLocal(
        database: database,
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        localId: orcamentoLocalAtual,
      );
      if (orcamentoRemoto == null) continue;

      final atualizado = await client
          .from('imperium_ordens_servico')
          .update({'orcamento_id': orcamentoRemoto})
          .eq('empresa_id', empresaId)
          .eq('id', osRemotoId)
          .isFilter('orcamento_id', null)
          .select('id,orcamento_id')
          .maybeSingle();

      if (atualizado != null) continue;

      final atual = await client
          .from('imperium_ordens_servico')
          .select('orcamento_id')
          .eq('empresa_id', empresaId)
          .eq('id', osRemotoId)
          .maybeSingle();

      final remotoAtual = _texto(atual?['orcamento_id']);
      if (remotoAtual.isNotEmpty && remotoAtual != orcamentoRemoto) {
        throw StateError(
          'A OS #$osLocalId foi vinculada a outro orçamento na nuvem.',
        );
      }
    }
  }

  Future<int?> _localPorRemoto({
    required DatabaseExecutor database,
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final localId = _intNulo(rows.first['local_id']);
    return localId != null && localId > 0 ? localId : null;
  }

  Future<String?> _remotoPorLocal({
    required DatabaseExecutor database,
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    final rows = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final remotoId = _texto(rows.first['remoto_id']);
    return remotoId.isEmpty ? null : remotoId;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();

    final texto = valor.toString().trim();
    if (texto.isEmpty) return null;
    return int.tryParse(texto);
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';
}
