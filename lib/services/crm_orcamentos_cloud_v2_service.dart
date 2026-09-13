import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'crm_orcamentos_cloud_service.dart';
import 'supabase_bootstrap.dart';

/// CRM + Orçamentos Cloud V2.
///
/// Protege registros já mapeados contra sobrescrita concorrente.
/// - local limpo + remoto mudou: aplica a nuvem direto no SQLite;
/// - local mudou + remoto limpo: deixa o V1 publicar normalmente;
/// - local mudou + remoto mudou: cria conflito e bloqueia só este módulo;
/// - exclusão remota: exige escolha explícita;
/// - resolução "local" usa CAS pelo atualizado_em remoto observado;
/// - resolução "nuvem" aplica diretamente no SQLite, sem efeitos de negócio.
class CrmOrcamentosCloudV2Service {
  CrmOrcamentosCloudV2Service._();

  static final CrmOrcamentosCloudV2Service instance =
      CrmOrcamentosCloudV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  static const List<String> _entidades = <String>[
    'orcamento',
    'orcamento_item',
    'crm_lead',
    'crm_interacao',
    'crm_campanha',
    'crm_cupom',
  ];

  // crm-orcamentos-cloud-v2
  Future<void> garantirEstruturaLocal() async {
    await CrmOrcamentosCloudService.instance.garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_crm_orcamentos_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        entidade TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_atualizado_base TEXT,
        remoto_atualizado_atual TEXT,
        local_json TEXT NOT NULL DEFAULT '',
        remoto_json TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Pendente',
        resolucao TEXT,
        resolucao_detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_crm_orc_conflitos_pendentes
      ON imperium_sync_crm_orcamentos_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');
  }

  /// Retorna false quando CRM/Orçamentos deve ficar bloqueado para upload.
  Future<bool> prepararUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return false;

    try {
      await garantirEstruturaLocal();

      if (await possuiConflitosPendentes(empresaId)) return false;

      for (final entidade in _entidades) {
        await _reconciliarEntidade(empresaId: empresaId, entidade: entidade);
      }

      return !await possuiConflitosPendentes(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return false;
      rethrow;
    }
  }

  /// Executar depois do download V1.
  /// Atualiza registros já mapeados que mudaram apenas na nuvem e detecta
  /// alterações concorrentes ocorridas durante o ciclo.
  Future<void> sincronizarDepoisDoDownload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      for (final entidade in _entidades) {
        await _reconciliarEntidade(empresaId: empresaId, entidade: entidade);
      }
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_crm_orcamentos_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_crm_orcamentos_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    Future<int> contar(String tabela) async {
      final rows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM $tabela WHERE empresa_id = ?',
        [empresaId],
      );
      return _int(rows.first['total']);
    }

    final conflitos = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_crm_orcamentos_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [empresaId],
    );

    return <String, Object?>{
      'empresa_id': empresaId,
      'orcamentos_mapeados': await contar('imperium_sync_orcamentos'),
      'itens_orcamento_mapeados': await contar('imperium_sync_orcamento_itens'),
      'crm_leads_mapeados': await contar('imperium_sync_crm_leads'),
      'crm_interacoes_mapeadas': await contar('imperium_sync_crm_interacoes'),
      'crm_campanhas_mapeadas': await contar('imperium_sync_crm_campanhas'),
      'crm_cupons_mapeados': await contar('imperium_sync_crm_cupons'),
      'conflitos_pendentes': _int(conflitos.first['total']),
    };
  }

  // crm-orcamentos-cloud-v2-resolucao
  Future<void> resolverUsandoLocal(int conflitoId) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível para resolver o conflito.');
    }

    final conflito = await _buscarConflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final entidade = _texto(conflito['entidade']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final remotoEsperado = _texto(conflito['remoto_atualizado_atual']);
    final config = _config(entidade);

    final database = await _appDatabase.database;
    final locais = await database.query(
      config.local,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (locais.isEmpty) {
      final filtro = client
          .from(config.remota)
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId);

      final resposta = remotoEsperado.isEmpty
          ? await filtro.select('id,atualizado_em').maybeSingle()
          : await filtro
                .eq('atualizado_em', remotoEsperado)
                .select('id,atualizado_em')
                .maybeSingle();

      if (resposta == null) {
        throw StateError(
          'A nuvem mudou novamente. Sincronize e revise o conflito.',
        );
      }

      await database.update(
        config.mapa,
        {
          'local_hash': '__excluido__',
          'remoto_atualizado_em': resposta['atualizado_em']?.toString(),
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );

      await _encerrarConflito(
        conflitoId: conflitoId,
        resolucao: 'local',
        detalhe: 'Exclusão local aplicada na nuvem com CAS.',
      );
      return;
    }

    final local = locais.first;
    final payload = await _payloadLocal(
      empresaId: empresaId,
      entidade: entidade,
      local: local,
    );

    final filtro = client
        .from(config.remota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId);

    final resposta = remotoEsperado.isEmpty
        ? await filtro.select('id,atualizado_em').maybeSingle()
        : await filtro
              .eq('atualizado_em', remotoEsperado)
              .select('id,atualizado_em')
              .maybeSingle();

    if (resposta == null) {
      throw StateError(
        'A nuvem mudou novamente. Sincronize e revise o conflito.',
      );
    }

    await _salvarMapa(
      tabelaMapa: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: await _hashLocal(entidade, local),
      remotoAtualizadoEm: resposta['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId: conflitoId,
      resolucao: 'local',
      detalhe: 'Versão local aplicada na nuvem com CAS.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    await garantirEstruturaLocal();

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível para resolver o conflito.');
    }

    final conflito = await _buscarConflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final entidade = _texto(conflito['entidade']);
    final localId = _int(conflito['local_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final config = _config(entidade);

    final remotoRaw = await client
        .from(config.remota)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError(
        'Registro remoto não existe mais. Escolha manter o local após reparar '
        'a origem remota.',
      );
    }

    final remoto = Map<String, dynamic>.from(remotoRaw);
    final database = await _appDatabase.database;
    final locais = await database.query(
      config.local,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (_texto(remoto['excluido_em']).isNotEmpty) {
      if (locais.isNotEmpty) {
        await database.delete(
          config.local,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await database.update(
        config.mapa,
        {
          'local_hash': '__excluido__',
          'remoto_atualizado_em': remoto['atualizado_em']?.toString(),
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );

      await _encerrarConflito(
        conflitoId: conflitoId,
        resolucao: 'nuvem',
        detalhe: 'Exclusão remota aplicada diretamente no SQLite.',
      );
      return;
    }

    if (locais.isEmpty) {
      // O V1 sabe inserir dependências e reconstruir mapas com segurança.
      await database.delete(
        config.mapa,
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );

      await CrmOrcamentosCloudService.instance.sincronizarDownloadNovos(
        empresaId,
      );

      final reconstruido = await database.query(
        config.mapa,
        columns: ['local_id'],
        where: 'empresa_id = ? AND remoto_id = ?',
        whereArgs: [empresaId, remotoId],
        limit: 1,
      );

      if (reconstruido.isEmpty) {
        throw StateError(
          'Não foi possível restaurar a versão da nuvem por falta de '
          'dependência local sincronizada.',
        );
      }

      await _encerrarConflito(
        conflitoId: conflitoId,
        resolucao: 'nuvem',
        detalhe: 'Registro local restaurado pela versão da nuvem.',
      );
      return;
    }

    await _aplicarRemoto(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remoto: remoto,
    );

    final localAtual = await _localPorId(config.local, localId);

    await _salvarMapa(
      tabelaMapa: config.mapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: await _hashLocal(entidade, localAtual),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId: conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versão da nuvem aplicada diretamente no SQLite.',
    );
  }

  Future<void> _reconciliarEntidade({
    required String empresaId,
    required String entidade,
  }) async {
    final client = _client;
    if (client == null) return;

    final config = _config(entidade);
    final database = await _appDatabase.database;
    final mapas = await database.query(
      config.mapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      if (_texto(mapa['local_hash']) == '__excluido__') continue;

      final localId = _int(mapa['local_id']);
      final remotoId = _texto(mapa['remoto_id']);

      if (localId <= 0 || remotoId.isEmpty) continue;

      if (await _conflitoPendente(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final remotoRaw = await client
          .from(config.remota)
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoRaw == null) {
        final locais = await database.query(
          config.local,
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );

        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_remoto_ausente',
          mapa: mapa,
          local: locais.isEmpty ? const <String, Object?>{} : locais.first,
          localHashAtual: locais.isEmpty
              ? ''
              : await _hashLocal(entidade, locais.first),
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoBase = _texto(mapa['remoto_atualizado_em']);
      final remotoAtual = _texto(remoto['atualizado_em']);
      final remotoMudou =
          remotoBase.isEmpty ||
          remotoAtual.isEmpty ||
          remotoAtual != remotoBase;

      final locais = await database.query(
        config.local,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (_texto(remoto['excluido_em']).isNotEmpty) {
        if (locais.isEmpty) {
          await database.update(
            config.mapa,
            {'local_hash': '__excluido__', 'remoto_atualizado_em': remotoAtual},
            where: 'empresa_id = ? AND local_id = ?',
            whereArgs: [empresaId, localId],
          );
        } else {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'registro_excluido_na_nuvem',
            mapa: mapa,
            local: locais.first,
            localHashAtual: await _hashLocal(entidade, locais.first),
            remoto: remoto,
          );
        }
        continue;
      }

      if (locais.isEmpty) {
        if (remotoMudou) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'local_excluido_remoto_alterado',
            mapa: mapa,
            local: const <String, Object?>{},
            localHashAtual: '',
            remoto: remoto,
          );
        }
        // Se a nuvem está igual à base, o V1 pode aplicar o soft delete local.
        continue;
      }

      final local = locais.first;
      final localHashAtual = await _hashLocal(entidade, local);
      final localHashBase = _texto(mapa['local_hash']);
      final localMudou =
          localHashBase.isEmpty || localHashAtual != localHashBase;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'alteracao_concorrente',
          mapa: mapa,
          local: local,
          localHashAtual: localHashAtual,
          remoto: remoto,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        try {
          await _aplicarRemoto(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remoto: remoto,
          );

          final localAtual = await _localPorId(config.local, localId);

          await _salvarMapa(
            tabelaMapa: config.mapa,
            empresaId: empresaId,
            localId: localId,
            remotoId: remotoId,
            localHash: await _hashLocal(entidade, localAtual),
            remotoAtualizadoEm: remotoAtual,
          );
        } on StateError catch (error) {
          await _registrarConflito(
            empresaId: empresaId,
            entidade: entidade,
            localId: localId,
            remotoId: remotoId,
            motivo: 'dependencia_remota_nao_mapeada',
            mapa: mapa,
            local: local,
            localHashAtual: localHashAtual,
            remoto: remoto,
            detalhe: error.toString(),
          );
        }
      }
    }
  }

  Future<void> _aplicarRemoto({
    required String empresaId,
    required String entidade,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;

    switch (entidade) {
      case 'orcamento':
        final cliente = await _localObrigatorioPorRemoto(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          remotoId: _texto(remoto['cliente_id']),
          nome: 'cliente do orçamento',
        );

        final veiculo = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['veiculo_id']),
          nome: 'veículo do orçamento',
        );

        await database.update(
          'orcamentos',
          {
            'cliente_id': cliente,
            'veiculo_id': veiculo,
            'servico': _texto(remoto['servico']),
            'descricao': _texto(remoto['descricao']),
            'valor': _double(remoto['valor']),
            'data_emissao': _texto(remoto['data_emissao']),
            'validade': _texto(remoto['validade']),
            'status': _textoPadrao(remoto['status'], 'Pendente'),
            'observacoes': _texto(remoto['observacoes']),
            'desconto': _double(remoto['desconto']),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );

        final agora = DateTime.now().toIso8601String();
        await database.insert(
          'financeiro_preco_documentos',
          {
            'documento_tipo': 'ORCAMENTO',
            'documento_id': localId,
            'perfil': _textoPadrao(remoto['perfil_preco'], 'informado'),
            'criado_em': agora,
            'atualizado_em': agora,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;

      case 'orcamento_item':
        final orcamento = await _localObrigatorioPorRemoto(
          tabelaMapa: 'imperium_sync_orcamentos',
          empresaId: empresaId,
          remotoId: _texto(remoto['orcamento_id']),
          nome: 'orçamento do item',
        );

        await database.update(
          'orcamento_itens',
          {
            'orcamento_id': orcamento,
            'servico': _texto(remoto['servico']),
            'descricao': _texto(remoto['descricao']),
            'quantidade': _double(remoto['quantidade']),
            'valor_unitario': _double(remoto['valor_unitario']),
            'ordem': _int(remoto['ordem']),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );

        final ordem = _int(remoto['ordem']);
        final servicoRemoto = _texto(remoto['servico_catalogo_id']);

        await database.delete(
          'financeiro_orcamento_item_catalogo',
          where: 'orcamento_id = ? AND ordem = ?',
          whereArgs: [orcamento, ordem],
        );

        if (servicoRemoto.isNotEmpty) {
          final servicoLocal = await _localOpcionalPorRemoto(
            tabelaMapa: 'imperium_sync_precificacao_servicos',
            empresaId: empresaId,
            remotoId: servicoRemoto,
            nome: 'serviço do catálogo',
            permitirTabelaAusente: true,
          );

          if (servicoLocal != null) {
            await database.insert(
              'financeiro_orcamento_item_catalogo',
              {
                'orcamento_id': orcamento,
                'ordem': ordem,
                'servico_catalogo_id': servicoLocal,
                'atualizado_em': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        return;

      case 'crm_lead':
        final cliente = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['cliente_id']),
          nome: 'cliente do lead',
        );
        final veiculo = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['veiculo_id']),
          nome: 'veículo do lead',
        );
        final agendamento = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_agendamentos',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['agendamento_id']),
          nome: 'agendamento do lead',
        );

        await database.update(
          'crm_leads',
          {
            'nome': _texto(remoto['nome']),
            'telefone': _texto(remoto['telefone']),
            'email': _texto(remoto['email']),
            'cliente_id': cliente,
            'veiculo_id': veiculo,
            'origem': _textoPadrao(remoto['origem'], 'Outro'),
            'servico_interesse': _texto(remoto['servico_interesse']),
            'veiculo_interesse': _texto(remoto['veiculo_interesse']),
            'valor_potencial': _double(remoto['valor_potencial']),
            'etapa': _textoPadrao(remoto['etapa'], 'Novo contato'),
            'responsavel': _texto(remoto['responsavel']),
            'proximo_contato': _textoNulo(remoto['proximo_contato']),
            'observacoes': _texto(remoto['observacoes']),
            'motivo_perda': _texto(remoto['motivo_perda']),
            'agendamento_id': agendamento,
            'criado_em': _textoPreferido(
              remoto['origem_criado_em'],
              remoto['criado_em'],
            ),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
            'convertido_em': _textoNulo(remoto['convertido_em']),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'crm_interacao':
        final lead = await _localObrigatorioPorRemoto(
          tabelaMapa: 'imperium_sync_crm_leads',
          empresaId: empresaId,
          remotoId: _texto(remoto['lead_id']),
          nome: 'lead da interação',
        );

        await database.update(
          'crm_interacoes',
          {
            'lead_id': lead,
            'tipo': _textoPadrao(remoto['tipo'], 'Contato'),
            'descricao': _texto(remoto['descricao']),
            'data_interacao': _texto(remoto['data_interacao']),
            'criado_em': _textoPreferido(
              remoto['origem_criado_em'],
              remoto['criado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'crm_campanha':
        await database.update(
          'crm_campanhas',
          {
            'nome': _texto(remoto['nome']),
            'tipo': _textoPadrao(remoto['tipo'], 'Manual'),
            'beneficio_tipo': _textoPadrao(
              remoto['beneficio_tipo'],
              'Percentual',
            ),
            'beneficio_valor': _double(remoto['beneficio_valor']),
            'beneficio_descricao': _texto(remoto['beneficio_descricao']),
            'valor_minimo': _double(remoto['valor_minimo']),
            'dias_validade': _int(remoto['dias_validade']),
            'dias_sem_retorno': _int(remoto['dias_sem_retorno']),
            'ativo': remoto['ativo'] == true ? 1 : 0,
            'criado_em': _textoPreferido(
              remoto['origem_criado_em'],
              remoto['criado_em'],
            ),
            'atualizado_em': _textoPreferido(
              remoto['origem_atualizado_em'],
              remoto['atualizado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      case 'crm_cupom':
        final campanha = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_crm_campanhas',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['campanha_id']),
          nome: 'campanha do cupom',
        );
        final cliente = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['cliente_id']),
          nome: 'cliente do cupom',
        );
        final lead = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_crm_leads',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['lead_id']),
          nome: 'lead do cupom',
        );
        final ordem = await _localOpcionalPorRemoto(
          tabelaMapa: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          remotoId: _textoNulo(remoto['ordem_servico_id']),
          nome: 'OS do cupom',
        );

        await database.update(
          'crm_cupons',
          {
            'codigo': _texto(remoto['codigo']),
            'campanha_id': campanha,
            'cliente_id': cliente,
            'lead_id': lead,
            'beneficio_tipo': _texto(remoto['beneficio_tipo']),
            'beneficio_valor': _double(remoto['beneficio_valor']),
            'beneficio_descricao': _texto(remoto['beneficio_descricao']),
            'valor_minimo': _double(remoto['valor_minimo']),
            'validade_inicio': _texto(remoto['validade_inicio']),
            'validade_fim': _texto(remoto['validade_fim']),
            'status': _textoPadrao(remoto['status'], 'Ativo'),
            'usado_em': _textoNulo(remoto['usado_em']),
            'ordem_servico_id': ordem,
            'chave_geracao': _texto(remoto['chave_geracao']),
            'criado_em': _textoPreferido(
              remoto['origem_criado_em'],
              remoto['criado_em'],
            ),
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        return;

      default:
        throw StateError('Entidade CRM/Orçamento inválida: $entidade');
    }
  }

  Future<Map<String, dynamic>> _payloadLocal({
    required String empresaId,
    required String entidade,
    required Map<String, Object?> local,
  }) async {
    switch (entidade) {
      case 'orcamento':
        final cliente = await _remotoObrigatorioPorLocal(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          localId: _int(local['cliente_id']),
          nome: 'cliente do orçamento',
        );
        final veiculo = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          localId: _intNulo(local['veiculo_id']),
          nome: 'veículo do orçamento',
        );

        return <String, dynamic>{
          'cliente_id': cliente,
          'veiculo_id': veiculo,
          'servico': _texto(local['servico']),
          'descricao': _texto(local['descricao']),
          'valor': _double(local['valor']),
          'data_emissao': _texto(local['data_emissao']),
          'validade': _texto(local['validade']),
          'status': _textoPadrao(local['status'], 'Pendente'),
          'observacoes': _texto(local['observacoes']),
          'desconto': _double(local['desconto']),
          'perfil_preco': await _perfilOrcamento(_int(local['id'])),
          'origem_atualizado_em': DateTime.now().toIso8601String(),
          'excluido_em': null,
        };

      case 'orcamento_item':
        final orcamento = await _remotoObrigatorioPorLocal(
          tabelaMapa: 'imperium_sync_orcamentos',
          empresaId: empresaId,
          localId: _int(local['orcamento_id']),
          nome: 'orçamento do item',
        );
        final catalogoLocal = await _catalogoDoItem(
          _int(local['orcamento_id']),
          _int(local['ordem']),
        );
        final catalogo = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_precificacao_servicos',
          empresaId: empresaId,
          localId: catalogoLocal,
          nome: 'serviço do catálogo',
          permitirTabelaAusente: true,
        );

        return <String, dynamic>{
          'orcamento_id': orcamento,
          'servico_catalogo_id': catalogo,
          'origem_servico_catalogo_local_id': catalogoLocal,
          'servico': _texto(local['servico']),
          'descricao': _texto(local['descricao']),
          'quantidade': _double(local['quantidade']),
          'valor_unitario': _double(local['valor_unitario']),
          'ordem': _int(local['ordem']),
          'excluido_em': null,
        };

      case 'crm_lead':
        final cliente = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          localId: _intNulo(local['cliente_id']),
          nome: 'cliente do lead',
        );
        final veiculo = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          localId: _intNulo(local['veiculo_id']),
          nome: 'veículo do lead',
        );
        final agendamento = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_agendamentos',
          empresaId: empresaId,
          localId: _intNulo(local['agendamento_id']),
          nome: 'agendamento do lead',
        );

        return <String, dynamic>{
          'nome': _texto(local['nome']),
          'telefone': _texto(local['telefone']),
          'email': _texto(local['email']),
          'cliente_id': cliente,
          'veiculo_id': veiculo,
          'origem': _textoPadrao(local['origem'], 'Outro'),
          'servico_interesse': _texto(local['servico_interesse']),
          'veiculo_interesse': _texto(local['veiculo_interesse']),
          'valor_potencial': _double(local['valor_potencial']),
          'etapa': _textoPadrao(local['etapa'], 'Novo contato'),
          'responsavel': _texto(local['responsavel']),
          'proximo_contato': _textoNulo(local['proximo_contato']),
          'observacoes': _texto(local['observacoes']),
          'motivo_perda': _texto(local['motivo_perda']),
          'agendamento_id': agendamento,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'convertido_em': _textoNulo(local['convertido_em']),
          'excluido_em': null,
        };

      case 'crm_interacao':
        final lead = await _remotoObrigatorioPorLocal(
          tabelaMapa: 'imperium_sync_crm_leads',
          empresaId: empresaId,
          localId: _int(local['lead_id']),
          nome: 'lead da interação',
        );

        return <String, dynamic>{
          'lead_id': lead,
          'tipo': _textoPadrao(local['tipo'], 'Contato'),
          'descricao': _texto(local['descricao']),
          'data_interacao': _texto(local['data_interacao']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'excluido_em': null,
        };

      case 'crm_campanha':
        return <String, dynamic>{
          'nome': _texto(local['nome']),
          'tipo': _textoPadrao(local['tipo'], 'Manual'),
          'beneficio_tipo': _textoPadrao(local['beneficio_tipo'], 'Percentual'),
          'beneficio_valor': _double(local['beneficio_valor']),
          'beneficio_descricao': _texto(local['beneficio_descricao']),
          'valor_minimo': _double(local['valor_minimo']),
          'dias_validade': _int(local['dias_validade']),
          'dias_sem_retorno': _int(local['dias_sem_retorno']),
          'ativo': _int(local['ativo']) != 0,
          'origem_criado_em': _textoNulo(local['criado_em']),
          'origem_atualizado_em': _textoNulo(local['atualizado_em']),
          'excluido_em': null,
        };

      case 'crm_cupom':
        final campanha = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_crm_campanhas',
          empresaId: empresaId,
          localId: _intNulo(local['campanha_id']),
          nome: 'campanha do cupom',
        );
        final cliente = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_clientes',
          empresaId: empresaId,
          localId: _intNulo(local['cliente_id']),
          nome: 'cliente do cupom',
        );
        final lead = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_crm_leads',
          empresaId: empresaId,
          localId: _intNulo(local['lead_id']),
          nome: 'lead do cupom',
        );
        final ordem = await _remotoOpcionalPorLocal(
          tabelaMapa: 'imperium_sync_ordens_servico',
          empresaId: empresaId,
          localId: _intNulo(local['ordem_servico_id']),
          nome: 'OS do cupom',
        );

        return <String, dynamic>{
          'codigo': _texto(local['codigo']),
          'campanha_id': campanha,
          'cliente_id': cliente,
          'lead_id': lead,
          'beneficio_tipo': _texto(local['beneficio_tipo']),
          'beneficio_valor': _double(local['beneficio_valor']),
          'beneficio_descricao': _texto(local['beneficio_descricao']),
          'valor_minimo': _double(local['valor_minimo']),
          'validade_inicio': _texto(local['validade_inicio']),
          'validade_fim': _texto(local['validade_fim']),
          'status': _textoPadrao(local['status'], 'Ativo'),
          'usado_em': _textoNulo(local['usado_em']),
          'ordem_servico_id': ordem,
          'chave_geracao': _texto(local['chave_geracao']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'excluido_em': null,
        };

      default:
        throw StateError('Entidade CRM/Orçamento inválida: $entidade');
    }
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required Map<String, Object?> mapa,
    required Map<String, Object?> local,
    required String localHashAtual,
    required Map<String, dynamic> remoto,
    String detalhe = '',
  }) async {
    if (await _conflitoPendente(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remotoId: remotoId,
    )) {
      return;
    }

    final database = await _appDatabase.database;

    await database.insert('imperium_sync_crm_orcamentos_conflitos', {
      'empresa_id': empresaId,
      'entidade': entidade,
      'local_id': localId,
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': _texto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _texto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _texto(remoto['atualizado_em']),
      'local_json': jsonEncode(local),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'resolucao': null,
      'resolucao_detalhe': detalhe,
      'detectado_em': DateTime.now().toIso8601String(),
      'resolvido_em': null,
    });
  }

  Future<bool> _conflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_crm_orcamentos_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>> _buscarConflitoPendente(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_crm_orcamentos_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito não encontrado ou já resolvido.');
    }
    return rows.first;
  }

  Future<void> _encerrarConflito({
    required int conflitoId,
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_crm_orcamentos_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conflitoId],
    );
  }

  _ConfigCrmOrc _config(String entidade) {
    switch (entidade) {
      case 'orcamento':
        return const _ConfigCrmOrc(
          local: 'orcamentos',
          remota: 'imperium_orcamentos',
          mapa: 'imperium_sync_orcamentos',
        );
      case 'orcamento_item':
        return const _ConfigCrmOrc(
          local: 'orcamento_itens',
          remota: 'imperium_orcamento_itens',
          mapa: 'imperium_sync_orcamento_itens',
        );
      case 'crm_lead':
        return const _ConfigCrmOrc(
          local: 'crm_leads',
          remota: 'imperium_crm_leads',
          mapa: 'imperium_sync_crm_leads',
        );
      case 'crm_interacao':
        return const _ConfigCrmOrc(
          local: 'crm_interacoes',
          remota: 'imperium_crm_interacoes',
          mapa: 'imperium_sync_crm_interacoes',
        );
      case 'crm_campanha':
        return const _ConfigCrmOrc(
          local: 'crm_campanhas',
          remota: 'imperium_crm_campanhas',
          mapa: 'imperium_sync_crm_campanhas',
        );
      case 'crm_cupom':
        return const _ConfigCrmOrc(
          local: 'crm_cupons',
          remota: 'imperium_crm_cupons',
          mapa: 'imperium_sync_crm_cupons',
        );
      default:
        throw StateError('Entidade CRM/Orçamento inválida: $entidade');
    }
  }

  Future<String> _hashLocal(String entidade, Map<String, Object?> local) async {
    switch (entidade) {
      case 'orcamento':
        return _sha(<Object?>[
          _int(local['cliente_id']),
          _intNulo(local['veiculo_id']),
          local['servico'],
          local['descricao'],
          _double(local['valor']),
          local['data_emissao'],
          local['validade'],
          local['status'],
          local['observacoes'],
          _double(local['desconto']),
          await _perfilOrcamento(_int(local['id'])),
        ]);

      case 'orcamento_item':
        return _sha(<Object?>[
          _int(local['orcamento_id']),
          local['servico'],
          local['descricao'],
          _double(local['quantidade']),
          _double(local['valor_unitario']),
          _int(local['ordem']),
          await _catalogoDoItem(
            _int(local['orcamento_id']),
            _int(local['ordem']),
          ),
        ]);

      case 'crm_lead':
        return _sha(<Object?>[
          local['nome'],
          local['telefone'],
          local['email'],
          _intNulo(local['cliente_id']),
          _intNulo(local['veiculo_id']),
          local['origem'],
          local['servico_interesse'],
          local['veiculo_interesse'],
          _double(local['valor_potencial']),
          local['etapa'],
          local['responsavel'],
          local['proximo_contato'],
          local['observacoes'],
          local['motivo_perda'],
          _intNulo(local['agendamento_id']),
          local['criado_em'],
          local['atualizado_em'],
          local['convertido_em'],
        ]);

      case 'crm_interacao':
        return _sha(<Object?>[
          _int(local['lead_id']),
          local['tipo'],
          local['descricao'],
          local['data_interacao'],
          local['criado_em'],
        ]);

      case 'crm_campanha':
        return _sha(<Object?>[
          local['nome'],
          local['tipo'],
          local['beneficio_tipo'],
          _double(local['beneficio_valor']),
          local['beneficio_descricao'],
          _double(local['valor_minimo']),
          _int(local['dias_validade']),
          _int(local['dias_sem_retorno']),
          _int(local['ativo']),
          local['criado_em'],
          local['atualizado_em'],
        ]);

      case 'crm_cupom':
        return _sha(<Object?>[
          local['codigo'],
          _intNulo(local['campanha_id']),
          _intNulo(local['cliente_id']),
          _intNulo(local['lead_id']),
          local['beneficio_tipo'],
          _double(local['beneficio_valor']),
          local['beneficio_descricao'],
          _double(local['valor_minimo']),
          local['validade_inicio'],
          local['validade_fim'],
          local['status'],
          local['usado_em'],
          _intNulo(local['ordem_servico_id']),
          local['chave_geracao'],
          local['criado_em'],
        ]);

      default:
        throw StateError('Entidade CRM/Orçamento inválida: $entidade');
    }
  }

  Future<String> _perfilOrcamento(int orcamentoId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'financeiro_preco_documentos',
      columns: ['perfil'],
      where: 'documento_tipo = ? AND documento_id = ?',
      whereArgs: ['ORCAMENTO', orcamentoId],
      limit: 1,
    );

    if (rows.isEmpty) return 'informado';
    return _textoPadrao(rows.first['perfil'], 'informado');
  }

  Future<int?> _catalogoDoItem(int orcamentoId, int ordem) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'financeiro_orcamento_item_catalogo',
      columns: ['servico_catalogo_id'],
      where: 'orcamento_id = ? AND ordem = ?',
      whereArgs: [orcamentoId, ordem],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final id = _int(rows.first['servico_catalogo_id']);
    return id <= 0 ? null : id;
  }

  Future<Map<String, Object?>> _localPorId(String tabela, int localId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Registro local não encontrado em $tabela.');
    }
    return rows.first;
  }

  Future<String> _remotoObrigatorioPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
    required String nome,
  }) async {
    final id = await _remotoOpcionalPorLocal(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      nome: nome,
    );

    if (id == null) {
      throw StateError('$nome ainda não está sincronizado.');
    }
    return id;
  }

  Future<String?> _remotoOpcionalPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int? localId,
    required String nome,
    bool permitirTabelaAusente = false,
  }) async {
    if (localId == null || localId <= 0) return null;

    final database = await _appDatabase.database;
    if (!await _tabelaExiste(tabelaMapa)) {
      if (permitirTabelaAusente) return null;
      throw StateError('Mapa local ausente para $nome.');
    }

    final rows = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('$nome ainda não está sincronizado.');
    }

    final id = _texto(rows.first['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<int> _localObrigatorioPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
    required String nome,
  }) async {
    final id = await _localOpcionalPorRemoto(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
      nome: nome,
    );

    if (id == null) {
      throw StateError('$nome ainda não existe neste aparelho.');
    }
    return id;
  }

  Future<int?> _localOpcionalPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String? remotoId,
    required String nome,
    bool permitirTabelaAusente = false,
  }) async {
    if (remotoId == null || remotoId.isEmpty) return null;

    final database = await _appDatabase.database;
    if (!await _tabelaExiste(tabelaMapa)) {
      if (permitirTabelaAusente) return null;
      throw StateError('Mapa local ausente para $nome.');
    }

    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('$nome ainda não existe neste aparelho.');
    }

    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<bool> _tabelaExiste(String tabela) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [tabela],
    );
    return rows.isNotEmpty;
  }

  Future<void> _salvarMapa({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;
    await database.insert(tabelaMapa, {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String _sha(List<Object?> values) {
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static int? _intNulo(Object? value) {
    if (value == null) return null;
    final texto = value.toString().trim();
    if (texto.isEmpty) return null;
    return int.tryParse(texto);
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String? _textoNulo(Object? value) {
    final texto = _texto(value);
    return texto.isEmpty ? null : texto;
  }

  static String _textoPadrao(Object? value, String padrao) {
    final texto = _texto(value);
    return texto.isEmpty ? padrao : texto;
  }

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = _texto(primeiro);
    if (a.isNotEmpty) return a;
    final b = _texto(segundo);
    if (b.isNotEmpty) return b;
    return DateTime.now().toIso8601String();
  }
}

class _ConfigCrmOrc {
  const _ConfigCrmOrc({
    required this.local,
    required this.remota,
    required this.mapa,
  });

  final String local;
  final String remota;
  final String mapa;
}
