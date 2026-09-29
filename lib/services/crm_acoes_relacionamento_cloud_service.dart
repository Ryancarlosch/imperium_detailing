import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincroniza o estado da Central de relacionamento entre o SQLite e o Cloud.
///
/// As ações são geradas de forma determinística no Cloud. O Android mantém
/// uma cópia offline e marca alterações locais com [sync_pendente]. Quando a
/// conexão volta, concluir/adiar/ignorar é publicado pelas mesmas RPCs usadas
/// no Web, preservando CAS por atualizado_em.
class CrmAcoesRelacionamentoCloudService {
  CrmAcoesRelacionamentoCloudService._();

  static final CrmAcoesRelacionamentoCloudService instance =
      CrmAcoesRelacionamentoCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizar() async {
    final client = _client;
    final empresaId = (await _appDatabase.empresaAtivaId)?.trim() ?? '';
    if (client == null || empresaId.isEmpty) return;

    try {
      final database = await _appDatabase.database;
      await _garantirEstrutura(database);

      final hoje = DateTime.now();
      final referencia =
          '${hoje.year.toString().padLeft(4, '0')}-'
          '${hoje.month.toString().padLeft(2, '0')}-'
          '${hoje.day.toString().padLeft(2, '0')}';

      await client.rpc(
        'imperium_crm_sincronizar_acoes_web',
        params: <String, dynamic>{
          'p_empresa_id': empresaId,
          'p_referencia': referencia,
        },
      );

      await _baixar(database, client, empresaId);
      await _publicarPendentes(database, client, empresaId);
      await _baixar(database, client, empresaId);
    } on PostgrestException catch (error) {
      // Mantém o CRM local utilizável quando o usuário está offline/sem módulo.
      if (error.code == '42501') return;
      rethrow;
    } catch (_) {
      // O SQLite continua sendo a fonte offline. O próximo ciclo tenta de novo.
    }
  }

  Future<void> marcarPendente(int acaoId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);
    await database.update(
      'crm_acoes_relacionamento',
      {'sync_pendente': 1},
      where: 'id = ?',
      whereArgs: [acaoId],
    );
  }

  Future<void> _baixar(
    Database database,
    SupabaseClient client,
    String empresaId,
  ) async {
    final resposta = await client
        .from('imperium_crm_acoes_relacionamento')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em');

    for (final raw in resposta as List) {
      final remoto = Map<String, dynamic>.from(raw as Map);
      await _aplicarRemoto(database, empresaId, remoto);
    }
  }

  Future<void> _aplicarRemoto(
    Database database,
    String empresaId,
    Map<String, dynamic> remoto,
  ) async {
    final remotoId = (remoto['id'] ?? '').toString();
    if (remotoId.isEmpty) return;

    final existentePorRemoto = await database.query(
      'crm_acoes_relacionamento',
      where: 'remoto_id = ?',
      whereArgs: [remotoId],
      limit: 1,
    );

    Map<String, Object?>? existente =
        existentePorRemoto.isEmpty ? null : existentePorRemoto.first;

    final entidadeTipo = (remoto['entidade_tipo'] ?? '').toString();
    final entidadeLocalId = await _localPorRemoto(
      database: database,
      empresaId: empresaId,
      entidadeTipo: entidadeTipo,
      remotoId: (remoto['entidade_id'] ?? '').toString(),
    );
    if (entidadeLocalId == null) return;

    if (existente == null) {
      final candidatos = await database.query(
        'crm_acoes_relacionamento',
        where: entidadeTipo == 'lead'
            ? 'tipo = ? AND entidade_tipo = ? AND entidade_id = ? AND vencimento = ?'
            : 'tipo = ? AND entidade_tipo = ? AND entidade_id = ?',
        whereArgs: entidadeTipo == 'lead'
            ? [
                (remoto['tipo'] ?? '').toString(),
                entidadeTipo,
                entidadeLocalId,
                (remoto['vencimento'] ?? '').toString(),
              ]
            : [
                (remoto['tipo'] ?? '').toString(),
                entidadeTipo,
                entidadeLocalId,
              ],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (candidatos.isNotEmpty) existente = candidatos.first;
    }

    final clienteLocalId = await _localOpcionalPorRemoto(
      database,
      'imperium_sync_clientes',
      empresaId,
      remoto['cliente_id'],
    );
    final leadLocalId = await _localOpcionalPorRemoto(
      database,
      'imperium_sync_crm_leads',
      empresaId,
      remoto['lead_id'],
    );

    final base = <String, Object?>{
      'tipo': (remoto['tipo'] ?? '').toString(),
      'entidade_tipo': entidadeTipo,
      'entidade_id': entidadeLocalId,
      'cliente_id': clienteLocalId,
      'lead_id': leadLocalId,
      'titulo': (remoto['titulo'] ?? '').toString(),
      'nome_contato': (remoto['nome_contato'] ?? '').toString(),
      'telefone': (remoto['telefone'] ?? '').toString(),
      'mensagem_sugerida': (remoto['mensagem_sugerida'] ?? '').toString(),
      'vencimento': (remoto['vencimento'] ?? '').toString(),
      'prioridade': (remoto['prioridade'] ?? 'Normal').toString(),
      'remoto_id': remotoId,
      'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
    };

    if (existente != null) {
      final localId = _int(existente['id']);
      final pendente = _int(existente['sync_pendente']) == 1;
      if (!pendente) {
        base.addAll(<String, Object?>{
          'status': (remoto['status'] ?? 'Pendente').toString(),
          'concluida_em': remoto['concluida_em']?.toString(),
          'adiada_para': remoto['adiada_para']?.toString(),
          'observacoes': (remoto['observacoes'] ?? '').toString(),
          'atualizado_em':
              remoto['atualizado_em']?.toString() ??
              DateTime.now().toIso8601String(),
          'sync_pendente': 0,
        });
      }
      await database.update(
        'crm_acoes_relacionamento',
        base,
        where: 'id = ?',
        whereArgs: [localId],
      );
      return;
    }

    await database.insert('crm_acoes_relacionamento', <String, Object?>{
      'chave': 'cloud:$remotoId',
      ...base,
      'status': (remoto['status'] ?? 'Pendente').toString(),
      'concluida_em': remoto['concluida_em']?.toString(),
      'adiada_para': remoto['adiada_para']?.toString(),
      'observacoes': (remoto['observacoes'] ?? '').toString(),
      'criado_em':
          remoto['criado_em']?.toString() ?? DateTime.now().toIso8601String(),
      'atualizado_em':
          remoto['atualizado_em']?.toString() ?? DateTime.now().toIso8601String(),
      'sync_pendente': 0,
    });
  }

  Future<void> _publicarPendentes(
    Database database,
    SupabaseClient client,
    String empresaId,
  ) async {
    final pendentes = await database.query(
      'crm_acoes_relacionamento',
      where: 'sync_pendente = 1 AND remoto_id IS NOT NULL',
      orderBy: 'id ASC',
    );

    for (final row in pendentes) {
      final id = _int(row['id']);
      final remotoId = (row['remoto_id'] ?? '').toString();
      final atualizadoBase = row['remoto_atualizado_em']?.toString();
      if (id <= 0 || remotoId.isEmpty) continue;

      dynamic resposta;
      final status = (row['status'] ?? '').toString();

      if (status == 'Concluida') {
        String? proximoContato;
        final leadId = _intNulo(row['lead_id']);
        if (leadId != null &&
            (row['tipo'] ?? '').toString() == 'Follow-up lead') {
          final leads = await database.query(
            'crm_leads',
            columns: ['proximo_contato'],
            where: 'id = ?',
            whereArgs: [leadId],
            limit: 1,
          );
          if (leads.isNotEmpty) {
            proximoContato = leads.first['proximo_contato']?.toString();
          }
        }

        final origemLocalId = DateTime.now().microsecondsSinceEpoch;
        resposta = await client.rpc(
          'imperium_crm_concluir_acao_web',
          params: <String, dynamic>{
            'p_empresa_id': empresaId,
            'p_acao_id': remotoId,
            'p_atualizado_em_base': atualizadoBase,
            'p_observacoes': (row['observacoes'] ?? '').toString(),
            'p_proximo_contato': proximoContato,
            'p_origem_dispositivo': 'android-crm-relacionamento',
            'p_interacao_origem_local_id': origemLocalId,
          },
        );
      } else if (status == 'Ignorada') {
        resposta = await client.rpc(
          'imperium_crm_ignorar_acao_web',
          params: <String, dynamic>{
            'p_empresa_id': empresaId,
            'p_acao_id': remotoId,
            'p_atualizado_em_base': atualizadoBase,
            'p_motivo': (row['observacoes'] ?? '').toString(),
          },
        );
      } else if ((row['adiada_para'] ?? '').toString().trim().isNotEmpty) {
        resposta = await client.rpc(
          'imperium_crm_adiar_acao_web',
          params: <String, dynamic>{
            'p_empresa_id': empresaId,
            'p_acao_id': remotoId,
            'p_atualizado_em_base': atualizadoBase,
            'p_nova_data': (row['adiada_para'] ?? '').toString(),
          },
        );
      } else {
        await database.update(
          'crm_acoes_relacionamento',
          {'sync_pendente': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        continue;
      }

      final mapa = Map<String, dynamic>.from(resposta as Map);
      await database.update(
        'crm_acoes_relacionamento',
        {
          'remoto_atualizado_em': mapa['atualizado_em']?.toString(),
          'sync_pendente': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int?> _localPorRemoto({
    required Database database,
    required String empresaId,
    required String entidadeTipo,
    required String remotoId,
  }) async {
    if (remotoId.trim().isEmpty) return null;
    final tabela = switch (entidadeTipo) {
      'lead' => 'imperium_sync_crm_leads',
      'orcamento' => 'imperium_sync_orcamentos',
      'ordem_servico' => 'imperium_sync_ordens_servico',
      'cupom' => 'imperium_sync_crm_cupons',
      _ => '',
    };
    if (tabela.isEmpty) return null;
    return _localOpcionalPorRemoto(database, tabela, empresaId, remotoId);
  }

  Future<int?> _localOpcionalPorRemoto(
    Database database,
    String tabela,
    String empresaId,
    dynamic remotoId,
  ) async {
    final id = remotoId?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    try {
      final rows = await database.query(
        tabela,
        columns: ['local_id'],
        where: 'empresa_id = ? AND remoto_id = ?',
        whereArgs: [empresaId, id],
        limit: 1,
      );
      return rows.isEmpty ? null : _intNulo(rows.first['local_id']);
    } on DatabaseException {
      return null;
    }
  }

  Future<void> _garantirEstrutura(Database database) async {
    final colunas = await database.rawQuery(
      'PRAGMA table_info(crm_acoes_relacionamento)',
    );
    if (colunas.isEmpty) return;

    final nomes = colunas.map((e) => e['name']?.toString()).toSet();
    if (!nomes.contains('remoto_id')) {
      await database.execute(
        'ALTER TABLE crm_acoes_relacionamento ADD COLUMN remoto_id TEXT',
      );
    }
    if (!nomes.contains('remoto_atualizado_em')) {
      await database.execute(
        'ALTER TABLE crm_acoes_relacionamento ADD COLUMN remoto_atualizado_em TEXT',
      );
    }
    if (!nomes.contains('sync_pendente')) {
      await database.execute(
        'ALTER TABLE crm_acoes_relacionamento ADD COLUMN sync_pendente INTEGER NOT NULL DEFAULT 0',
      );
    }
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_acoes_remoto_id
      ON crm_acoes_relacionamento (remoto_id)
      WHERE remoto_id IS NOT NULL
    ''');
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }
}
