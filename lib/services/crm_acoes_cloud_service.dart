import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../repositories/crm_operacao_repository.dart';
import 'supabase_bootstrap.dart';

class CrmAcoesCloudService {
  CrmAcoesCloudService._();

  static final CrmAcoesCloudService instance = CrmAcoesCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (client == null || empresaId.trim().isEmpty) return;

    final agora = DateTime.now();
    final referencia =
        '${agora.year.toString().padLeft(4, '0')}-'
        '${agora.month.toString().padLeft(2, '0')}-'
        '${agora.day.toString().padLeft(2, '0')}';

    await client.rpc(
      'imperium_crm_sincronizar_acoes_web',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_referencia': referencia,
      },
    );

    final database = await _appDatabase.database;
    await CrmOperacaoRepository().garantirEstrutura();
    await _garantirMapa(database);

    final remotas = await client
        .from('imperium_crm_acoes_relacionamento')
        .select()
        .eq('empresa_id', empresaId)
        .order('vencimento')
        .order('criado_em');

    for (final raw in remotas as List) {
      var remoto = Map<String, dynamic>.from(raw as Map);
      final remotoId = _texto(remoto['id']);
      if (remotoId.isEmpty) continue;

      final identidade = await _identidadeLocal(
        database,
        empresaId: empresaId,
        remoto: remoto,
      );
      if (identidade == null) continue;

      final mapa = await _mapaRemoto(
        database,
        empresaId: empresaId,
        remotoId: remotoId,
      );

      Map<String, Object?>? local;
      int? localId;

      if (mapa != null) {
        localId = _intNulo(mapa['local_id']);
        if (localId != null) {
          local = await _acaoLocalPorId(database, localId);
        }
      }

      local ??= await _acaoLocalPorChave(database, identidade.chave);
      localId ??= _intNulo(local?['id']);

      if (local == null || localId == null || localId <= 0) {
        localId = await database.insert(
          CrmOperacaoRepository.tabelaAcoes,
          _dadosLocais(remoto, identidade),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        local = await _acaoLocalPorId(database, localId);
      } else {
        final localMudou =
            mapa != null &&
            _texto(local['atualizado_em']) !=
                _texto(mapa['local_atualizado_em']);
        final remotoMudou =
            mapa != null &&
            _texto(remoto['atualizado_em']) !=
                _texto(mapa['remoto_atualizado_em']);

        var usarLocal = false;

        if (mapa == null) {
          usarLocal =
              _estadoLocalTemAcao(local) && !_estadoRemotoTemAcao(remoto);
          if (_estadoLocalTemAcao(local) && _estadoRemotoTemAcao(remoto)) {
            usarLocal = _maisNovo(
              local['atualizado_em'],
              remoto['atualizado_em'],
            );
          }
        } else if (localMudou && !remotoMudou) {
          usarLocal = true;
        } else if (localMudou && remotoMudou) {
          usarLocal = _maisNovo(
            local['atualizado_em'],
            remoto['atualizado_em'],
          );
        }

        if (usarLocal) {
          remoto = await _publicarEstadoLocal(
            client,
            empresaId: empresaId,
            remoto: remoto,
            local: local,
          );

          // Mesmo quando tentamos publicar o estado local, o CAS pode perder
          // para uma alteração mais recente feita no Web. Sempre reaplicamos
          // o estado efetivamente retornado pelo Cloud para encerrar a
          // reconciliação sem deixar Android e Web divergentes.
          await database.update(
            CrmOperacaoRepository.tabelaAcoes,
            _dadosLocais(remoto, identidade),
            where: 'id = ?',
            whereArgs: [localId],
          );
          local = await _acaoLocalPorId(database, localId);
        } else {
          await database.update(
            CrmOperacaoRepository.tabelaAcoes,
            _dadosLocais(remoto, identidade),
            where: 'id = ?',
            whereArgs: [localId],
          );
          local = await _acaoLocalPorId(database, localId);
        }
      }

      if (local == null) continue;

      await _salvarMapa(
        database,
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localAtualizadoEm: _texto(local['atualizado_em']),
        remotoAtualizadoEm: _texto(remoto['atualizado_em']),
      );
    }
  }

  Future<Map<String, dynamic>> _publicarEstadoLocal(
    SupabaseClient client, {
    required String empresaId,
    required Map<String, dynamic> remoto,
    required Map<String, Object?> local,
  }) async {
    final esperado = _texto(remoto['atualizado_em']);
    final agora = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'status': _texto(local['status']).isEmpty
          ? 'Pendente'
          : _texto(local['status']),
      'vencimento': _texto(local['vencimento']),
      'concluida_em': _textoNulo(local['concluida_em']),
      'adiada_para': _textoNulo(local['adiada_para']),
      'observacoes': _texto(local['observacoes']),
      'atualizado_em': agora,
    };

    var query = client
        .from('imperium_crm_acoes_relacionamento')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', _texto(remoto['id']));

    if (esperado.isNotEmpty) {
      query = query.eq('atualizado_em', esperado);
    }

    final atualizado = await query.select().maybeSingle();
    if (atualizado != null) {
      return Map<String, dynamic>.from(atualizado);
    }

    final atual = await client
        .from('imperium_crm_acoes_relacionamento')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', _texto(remoto['id']))
        .single();

    return Map<String, dynamic>.from(atual);
  }

  Future<_IdentidadeAcao?> _identidadeLocal(
    DatabaseExecutor database, {
    required String empresaId,
    required Map<String, dynamic> remoto,
  }) async {
    final tipo = _texto(remoto['entidade_tipo']);
    final remotoEntidade = _texto(remoto['entidade_id']);

    final tabelaMapa = switch (tipo) {
      'lead' => 'imperium_sync_crm_leads',
      'orcamento' => 'imperium_sync_orcamentos',
      'ordem_servico' => 'imperium_sync_ordens_servico',
      'cupom' => 'imperium_sync_crm_cupons',
      _ => '',
    };
    if (tabelaMapa.isEmpty || remotoEntidade.isEmpty) return null;

    final entidadeLocal = await _localPorRemoto(
      database,
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoEntidade,
    );
    if (entidadeLocal == null) return null;

    final clienteLocal = await _localOpcional(
      database,
      tabelaMapa: 'imperium_sync_clientes',
      empresaId: empresaId,
      remotoId: _texto(remoto['cliente_id']),
    );
    final leadLocal = await _localOpcional(
      database,
      tabelaMapa: 'imperium_sync_crm_leads',
      empresaId: empresaId,
      remotoId: _texto(remoto['lead_id']),
    );

    final chave = switch (tipo) {
      'lead' =>
        'lead:$entidadeLocal:${_sufixoFollowUp(_texto(remoto['chave']))}',
      'orcamento' => 'orcamento:$entidadeLocal',
      'ordem_servico' => 'posvenda:$entidadeLocal',
      'cupom' => 'cupom:$entidadeLocal',
      _ => '',
    };
    if (chave.isEmpty || chave.endsWith(':')) return null;

    return _IdentidadeAcao(
      chave: chave,
      entidadeId: entidadeLocal,
      clienteId: clienteLocal,
      leadId: leadLocal,
    );
  }

  Map<String, Object?> _dadosLocais(
    Map<String, dynamic> remoto,
    _IdentidadeAcao identidade,
  ) {
    return <String, Object?>{
      'chave': identidade.chave,
      'tipo': _texto(remoto['tipo']),
      'entidade_tipo': _texto(remoto['entidade_tipo']),
      'entidade_id': identidade.entidadeId,
      'cliente_id': identidade.clienteId,
      'lead_id': identidade.leadId,
      'titulo': _texto(remoto['titulo']),
      'nome_contato': _texto(remoto['nome_contato']),
      'telefone': _texto(remoto['telefone']),
      'mensagem_sugerida': _texto(remoto['mensagem_sugerida']),
      'vencimento': _texto(remoto['vencimento']),
      'prioridade': _texto(remoto['prioridade']).isEmpty
          ? 'Normal'
          : _texto(remoto['prioridade']),
      'status': _texto(remoto['status']).isEmpty
          ? 'Pendente'
          : _texto(remoto['status']),
      'concluida_em': _textoNulo(remoto['concluida_em']),
      'adiada_para': _textoNulo(remoto['adiada_para']),
      'observacoes': _texto(remoto['observacoes']),
      'criado_em': _texto(remoto['criado_em']),
      'atualizado_em': _texto(remoto['atualizado_em']),
    };
  }

  Future<void> _garantirMapa(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_crm_acoes (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_atualizado_em TEXT,
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<Map<String, Object?>?> _acaoLocalPorId(
    DatabaseExecutor database,
    int id,
  ) async {
    final rows = await database.query(
      CrmOperacaoRepository.tabelaAcoes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _acaoLocalPorChave(
    DatabaseExecutor database,
    String chave,
  ) async {
    final rows = await database.query(
      CrmOperacaoRepository.tabelaAcoes,
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<Map<String, Object?>?> _mapaRemoto(
    DatabaseExecutor database, {
    required String empresaId,
    required String remotoId,
  }) async {
    final rows = await database.query(
      'imperium_sync_crm_acoes',
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> _salvarMapa(
    DatabaseExecutor database, {
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localAtualizadoEm,
    required String remotoAtualizadoEm,
  }) async {
    await database.insert('imperium_sync_crm_acoes', <String, Object?>{
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_atualizado_em': localAtualizadoEm,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> _localPorRemoto(
    DatabaseExecutor database, {
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
    final id = _intNulo(rows.first['local_id']);
    return id != null && id > 0 ? id : null;
  }

  Future<int?> _localOpcional(
    DatabaseExecutor database, {
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;
    return _localPorRemoto(
      database,
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
  }

  static bool _estadoLocalTemAcao(Map<String, Object?> local) {
    return _texto(local['status']) != 'Pendente' ||
        _texto(local['observacoes']).isNotEmpty ||
        _texto(local['adiada_para']).isNotEmpty ||
        _texto(local['concluida_em']).isNotEmpty;
  }

  static bool _estadoRemotoTemAcao(Map<String, dynamic> remoto) {
    return _texto(remoto['status']) != 'Pendente' ||
        _texto(remoto['observacoes']).isNotEmpty ||
        _texto(remoto['adiada_para']).isNotEmpty ||
        _texto(remoto['concluida_em']).isNotEmpty;
  }

  static bool _maisNovo(dynamic local, dynamic remoto) {
    final a = DateTime.tryParse(_texto(local));
    final b = DateTime.tryParse(_texto(remoto));
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
  }

  static String _sufixoFollowUp(String chave) {
    final partes = chave.split(':');
    return partes.length >= 3 ? partes.last.trim() : '';
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String? _textoNulo(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
  }
}

class _IdentidadeAcao {
  const _IdentidadeAcao({
    required this.chave,
    required this.entidadeId,
    required this.clienteId,
    required this.leadId,
  });

  final String chave;
  final int entidadeId;
  final int? clienteId;
  final int? leadId;
}
