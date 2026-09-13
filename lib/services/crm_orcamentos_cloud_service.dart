import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// CRM + Orçamentos Cloud V1.
///
/// Estratégia conservadora:
/// - upload idempotente dos registros locais;
/// - soft delete remoto quando um registro mapeado some localmente;
/// - download somente de registros novos;
/// - registros já mapeados não são sobrescritos por download no V1;
/// - conflitos concorrentes ficam para V2.
class CrmOrcamentosCloudService {
  CrmOrcamentosCloudService._();

  static final CrmOrcamentosCloudService instance =
      CrmOrcamentosCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // crm-orcamentos-cloud-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_orcamentos',
      'imperium_sync_orcamento_itens',
      'imperium_sync_crm_leads',
      'imperium_sync_crm_interacoes',
      'imperium_sync_crm_campanhas',
      'imperium_sync_crm_cupons',
    ]) {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS $tabela (
          empresa_id TEXT NOT NULL,
          local_id INTEGER NOT NULL,
          remoto_id TEXT NOT NULL,
          local_hash TEXT,
          remoto_atualizado_em TEXT,
          PRIMARY KEY (empresa_id, local_id),
          UNIQUE (empresa_id, remoto_id)
        )
      ''');
    }

    // Estas tabelas auxiliares já existem nas telas/repositories de orçamento,
    // mas o sync precisa ser seguro mesmo se for o primeiro fluxo a acessá-las.
    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_preco_documentos (
        documento_tipo TEXT NOT NULL,
        documento_id INTEGER NOT NULL,
        perfil TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (documento_tipo, documento_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_orcamento_item_catalogo (
        orcamento_id INTEGER NOT NULL,
        ordem INTEGER NOT NULL,
        servico_catalogo_id INTEGER NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (orcamento_id, ordem)
      )
    ''');
  }

  Future<void> sincronizarUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      await _publicarOrcamentos(empresaId);
      await _publicarOrcamentoItens(empresaId);

      await _publicarCrmLeads(empresaId);
      await _publicarCrmInteracoes(empresaId);
      await _publicarCrmCampanhas(empresaId);
      await _publicarCrmCupons(empresaId);

      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'orcamento_itens',
        tabelaMapa: 'imperium_sync_orcamento_itens',
        tabelaRemota: 'imperium_orcamento_itens',
      );
      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'orcamentos',
        tabelaMapa: 'imperium_sync_orcamentos',
        tabelaRemota: 'imperium_orcamentos',
      );
      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'crm_interacoes',
        tabelaMapa: 'imperium_sync_crm_interacoes',
        tabelaRemota: 'imperium_crm_interacoes',
      );
      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'crm_cupons',
        tabelaMapa: 'imperium_sync_crm_cupons',
        tabelaRemota: 'imperium_crm_cupons',
      );
      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'crm_campanhas',
        tabelaMapa: 'imperium_sync_crm_campanhas',
        tabelaRemota: 'imperium_crm_campanhas',
      );
      await _marcarAusentesComoExcluidos(
        empresaId: empresaId,
        tabelaLocal: 'crm_leads',
        tabelaMapa: 'imperium_sync_crm_leads',
        tabelaRemota: 'imperium_crm_leads',
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<void> sincronizarDownloadNovos(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      await _baixarOrcamentosNovos(empresaId);
      await _baixarOrcamentoItensNovos(empresaId);

      await _baixarCrmLeadsNovos(empresaId);
      await _baixarCrmInteracoesNovas(empresaId);
      await _baixarCrmCampanhasNovas(empresaId);
      await _baixarCrmCuponsNovos(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
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

    return <String, Object?>{
      'empresa_id': empresaId,
      'orcamentos_mapeados': await contar('imperium_sync_orcamentos'),
      'itens_orcamento_mapeados': await contar('imperium_sync_orcamento_itens'),
      'crm_leads_mapeados': await contar('imperium_sync_crm_leads'),
      'crm_interacoes_mapeadas': await contar('imperium_sync_crm_interacoes'),
      'crm_campanhas_mapeadas': await contar('imperium_sync_crm_campanhas'),
      'crm_cupons_mapeados': await contar('imperium_sync_crm_cupons'),
    };
  }

  Future<void> _publicarOrcamentos(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('orcamentos', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final clienteLocalId = _int(local['cliente_id']);
      final clienteRemoto = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        localId: clienteLocalId,
      );
      if (clienteRemoto == null) continue;

      String? veiculoRemoto;
      final veiculoLocalId = _int(local['veiculo_id']);
      if (veiculoLocalId > 0) {
        veiculoRemoto = await _remotoPorLocal(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          localId: veiculoLocalId,
        );
        if (veiculoRemoto == null) continue;
      }

      final perfil = await _perfilOrcamento(localId);
      final hash = _hashOrcamento(local, perfil);

      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        localId: localId,
      );

      if (_texto(mapa?['local_hash']) == hash) continue;

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'cliente_id': clienteRemoto,
        'veiculo_id': veiculoRemoto,
        'servico': _texto(local['servico']),
        'descricao': _texto(local['descricao']),
        'valor': _double(local['valor']),
        'data_emissao': _texto(local['data_emissao']),
        'validade': _texto(local['validade']),
        'status': _textoPadrao(local['status'], 'Pendente'),
        'observacoes': _texto(local['observacoes']),
        'desconto': _double(local['desconto']),
        'perfil_preco': perfil,
        'origem_atualizado_em': DateTime.now().toIso8601String(),
        'excluido_em': null,
      };

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_orcamentos',
        mapa: mapa,
        payload: payload,
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarOrcamentoItens(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'orcamento_itens',
      orderBy: 'orcamento_id ASC, ordem ASC, id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      final orcamentoLocalId = _int(local['orcamento_id']);
      if (localId <= 0 || orcamentoLocalId <= 0) continue;

      final orcamentoRemoto = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        localId: orcamentoLocalId,
      );
      if (orcamentoRemoto == null) continue;

      final catalogoLocalId = await _catalogoDoItem(
        orcamentoLocalId,
        _int(local['ordem']),
      );

      final catalogoRemoto = catalogoLocalId == null
          ? null
          : await _remotoPorLocalSeTabelaExiste(
              tabelaMapa: 'imperium_sync_precificacao_servicos',
              empresaId: empresaId,
              localId: catalogoLocalId,
            );

      final hash = _hashOrcamentoItem(local, catalogoLocalId);
      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_orcamento_itens',
        empresaId: empresaId,
        localId: localId,
      );

      if (_texto(mapa?['local_hash']) == hash) continue;

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'orcamento_id': orcamentoRemoto,
        'servico_catalogo_id': catalogoRemoto,
        'origem_servico_catalogo_local_id': catalogoLocalId,
        'servico': _texto(local['servico']),
        'descricao': _texto(local['descricao']),
        'quantidade': _double(local['quantidade']),
        'valor_unitario': _double(local['valor_unitario']),
        'ordem': _int(local['ordem']),
        'excluido_em': null,
      };

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_orcamento_itens',
        mapa: mapa,
        payload: payload,
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_orcamento_itens',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarCrmLeads(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('crm_leads', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final clienteRemoto = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        localId: _int(local['cliente_id']),
      );
      if (_int(local['cliente_id']) > 0 && clienteRemoto == null) continue;

      final veiculoRemoto = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_veiculos',
        empresaId: empresaId,
        localId: _int(local['veiculo_id']),
      );
      if (_int(local['veiculo_id']) > 0 && veiculoRemoto == null) continue;

      final agendamentoRemoto =
          await _dependenciaOpcionalObrigatoriaSeInformada(
            tabelaMapa: 'imperium_sync_agendamentos',
            empresaId: empresaId,
            localId: _int(local['agendamento_id']),
          );
      if (_int(local['agendamento_id']) > 0 && agendamentoRemoto == null) {
        continue;
      }

      final hash = _hashCrmLead(local);
      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        localId: localId,
      );

      if (_texto(mapa?['local_hash']) == hash) continue;

      final payload = <String, dynamic>{
        'empresa_id': empresaId,
        'nome': _texto(local['nome']),
        'telefone': _texto(local['telefone']),
        'email': _texto(local['email']),
        'cliente_id': clienteRemoto,
        'veiculo_id': veiculoRemoto,
        'origem': _textoPadrao(local['origem'], 'Outro'),
        'servico_interesse': _texto(local['servico_interesse']),
        'veiculo_interesse': _texto(local['veiculo_interesse']),
        'valor_potencial': _double(local['valor_potencial']),
        'etapa': _textoPadrao(local['etapa'], 'Novo contato'),
        'responsavel': _texto(local['responsavel']),
        'proximo_contato': _textoNulo(local['proximo_contato']),
        'observacoes': _texto(local['observacoes']),
        'motivo_perda': _texto(local['motivo_perda']),
        'agendamento_id': agendamentoRemoto,
        'origem_criado_em': _textoNulo(local['criado_em']),
        'origem_atualizado_em': _textoNulo(local['atualizado_em']),
        'convertido_em': _textoNulo(local['convertido_em']),
        'excluido_em': null,
      };

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_crm_leads',
        mapa: mapa,
        payload: payload,
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarCrmInteracoes(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('crm_interacoes', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      final leadLocalId = _int(local['lead_id']);
      if (localId <= 0 || leadLocalId <= 0) continue;

      final leadRemoto = await _remotoPorLocal(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        localId: leadLocalId,
      );
      if (leadRemoto == null) continue;

      final hash = _hashCrmInteracao(local);
      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_crm_interacoes',
        empresaId: empresaId,
        localId: localId,
      );
      if (_texto(mapa?['local_hash']) == hash) continue;

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_crm_interacoes',
        mapa: mapa,
        payload: <String, dynamic>{
          'empresa_id': empresaId,
          'lead_id': leadRemoto,
          'tipo': _textoPadrao(local['tipo'], 'Contato'),
          'descricao': _texto(local['descricao']),
          'data_interacao': _texto(local['data_interacao']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'excluido_em': null,
        },
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_interacoes',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarCrmCampanhas(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('crm_campanhas', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashCrmCampanha(local);
      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        localId: localId,
      );
      if (_texto(mapa?['local_hash']) == hash) continue;

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_crm_campanhas',
        mapa: mapa,
        payload: <String, dynamic>{
          'empresa_id': empresaId,
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
        },
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _publicarCrmCupons(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('crm_cupons', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final campanhaRemota = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        localId: _int(local['campanha_id']),
      );
      if (_int(local['campanha_id']) > 0 && campanhaRemota == null) continue;

      final clienteRemoto = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        localId: _int(local['cliente_id']),
      );
      if (_int(local['cliente_id']) > 0 && clienteRemoto == null) continue;

      final leadRemoto = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        localId: _int(local['lead_id']),
      );
      if (_int(local['lead_id']) > 0 && leadRemoto == null) continue;

      final osRemota = await _dependenciaOpcionalObrigatoriaSeInformada(
        tabelaMapa: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: _int(local['ordem_servico_id']),
      );
      if (_int(local['ordem_servico_id']) > 0 && osRemota == null) continue;

      final hash = _hashCrmCupom(local);
      final mapa = await _mapaLocal(
        tabelaMapa: 'imperium_sync_crm_cupons',
        empresaId: empresaId,
        localId: localId,
      );
      if (_texto(mapa?['local_hash']) == hash) continue;

      final remoto = await _salvarRemotoMapeado(
        empresaId: empresaId,
        localId: localId,
        tabelaRemota: 'imperium_crm_cupons',
        mapa: mapa,
        payload: <String, dynamic>{
          'empresa_id': empresaId,
          'codigo': _texto(local['codigo']),
          'campanha_id': campanhaRemota,
          'cliente_id': clienteRemoto,
          'lead_id': leadRemoto,
          'beneficio_tipo': _texto(local['beneficio_tipo']),
          'beneficio_valor': _double(local['beneficio_valor']),
          'beneficio_descricao': _texto(local['beneficio_descricao']),
          'valor_minimo': _double(local['valor_minimo']),
          'validade_inicio': _texto(local['validade_inicio']),
          'validade_fim': _texto(local['validade_fim']),
          'status': _textoPadrao(local['status'], 'Ativo'),
          'usado_em': _textoNulo(local['usado_em']),
          'ordem_servico_id': osRemota,
          'chave_geracao': _texto(local['chave_geracao']),
          'origem_criado_em': _textoNulo(local['criado_em']),
          'excluido_em': null,
        },
      );

      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_cupons',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: hash,
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _salvarRemotoMapeado({
    required String empresaId,
    required int localId,
    required String tabelaRemota,
    required Map<String, Object?>? mapa,
    required Map<String, dynamic> payload,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível.');
    }

    final remotoId = _texto(mapa?['remoto_id']);

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from(tabelaRemota)
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      return Map<String, dynamic>.from(resposta);
    }

    final resposta = await client
        .from(tabelaRemota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .select('id,atualizado_em')
        .single();

    return Map<String, dynamic>.from(resposta);
  }

  Future<void> _baixarOrcamentosNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_orcamentos')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        remotoId: _texto(remoto['id']),
      )) {
        continue;
      }

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'orcamentos',
        tabelaMapa: 'imperium_sync_orcamentos',
        remoto: remoto,
        hashBuilder: (local) => _hashOrcamento(
          local,
          _textoPadrao(remoto['perfil_preco'], 'informado'),
        ),
      )) {
        continue;
      }

      final clienteLocal = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: _texto(remoto['cliente_id']),
      );
      if (clienteLocal == null) continue;

      int? veiculoLocal;
      final veiculoRemoto = _texto(remoto['veiculo_id']);
      if (veiculoRemoto.isNotEmpty) {
        veiculoLocal = await _localPorRemoto(
          tabelaMapa: 'imperium_sync_veiculos',
          empresaId: empresaId,
          remotoId: veiculoRemoto,
        );
        if (veiculoLocal == null) continue;
      }

      final localId = await database.insert('orcamentos', {
        'cliente_id': clienteLocal,
        'veiculo_id': veiculoLocal,
        'servico': _texto(remoto['servico']),
        'descricao': _texto(remoto['descricao']),
        'valor': _double(remoto['valor']),
        'data_emissao': _texto(remoto['data_emissao']),
        'validade': _texto(remoto['validade']),
        'status': _textoPadrao(remoto['status'], 'Pendente'),
        'observacoes': _texto(remoto['observacoes']),
        'desconto': _double(remoto['desconto']),
      });

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

      final local = await _localPorId('orcamentos', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        localId: localId,
        remotoId: _texto(remoto['id']),
        localHash: _hashOrcamento(
          local,
          _textoPadrao(remoto['perfil_preco'], 'informado'),
        ),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarOrcamentoItensNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_orcamento_itens')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_orcamento_itens',
        empresaId: empresaId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final orcamentoLocal = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_orcamentos',
        empresaId: empresaId,
        remotoId: _texto(remoto['orcamento_id']),
      );
      if (orcamentoLocal == null) continue;

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'orcamento_itens',
        tabelaMapa: 'imperium_sync_orcamento_itens',
        remoto: remoto,
        hashBuilder: (local) => _hashOrcamentoItem(
          local,
          _intNulo(remoto['origem_servico_catalogo_local_id']),
        ),
      )) {
        continue;
      }

      final localId = await database.insert('orcamento_itens', {
        'orcamento_id': orcamentoLocal,
        'servico': _texto(remoto['servico']),
        'descricao': _texto(remoto['descricao']),
        'quantidade': _double(remoto['quantidade']),
        'valor_unitario': _double(remoto['valor_unitario']),
        'ordem': _int(remoto['ordem']),
      });

      final servicoRemoto = _texto(remoto['servico_catalogo_id']);
      if (servicoRemoto.isNotEmpty) {
        final servicoLocal = await _localPorRemotoSeTabelaExiste(
          tabelaMapa: 'imperium_sync_precificacao_servicos',
          empresaId: empresaId,
          remotoId: servicoRemoto,
        );

        if (servicoLocal != null) {
          await database.insert(
            'financeiro_orcamento_item_catalogo',
            {
              'orcamento_id': orcamentoLocal,
              'ordem': _int(remoto['ordem']),
              'servico_catalogo_id': servicoLocal,
              'atualizado_em': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final local = await _localPorId('orcamento_itens', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_orcamento_itens',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashOrcamentoItem(
          local,
          await _catalogoDoItem(orcamentoLocal, _int(local['ordem'])),
        ),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarCrmLeadsNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_crm_leads')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        remotoId: remotoId,
      )) {
        continue;
      }

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'crm_leads',
        tabelaMapa: 'imperium_sync_crm_leads',
        remoto: remoto,
        hashBuilder: _hashCrmLead,
      )) {
        continue;
      }

      final clienteLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['cliente_id']),
      );
      final veiculoLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_veiculos',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['veiculo_id']),
      );
      final agendamentoLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_agendamentos',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['agendamento_id']),
      );

      final localId = await database.insert('crm_leads', {
        'nome': _texto(remoto['nome']),
        'telefone': _texto(remoto['telefone']),
        'email': _texto(remoto['email']),
        'cliente_id': clienteLocal,
        'veiculo_id': veiculoLocal,
        'origem': _textoPadrao(remoto['origem'], 'Outro'),
        'servico_interesse': _texto(remoto['servico_interesse']),
        'veiculo_interesse': _texto(remoto['veiculo_interesse']),
        'valor_potencial': _double(remoto['valor_potencial']),
        'etapa': _textoPadrao(remoto['etapa'], 'Novo contato'),
        'responsavel': _texto(remoto['responsavel']),
        'proximo_contato': _textoNulo(remoto['proximo_contato']),
        'observacoes': _texto(remoto['observacoes']),
        'motivo_perda': _texto(remoto['motivo_perda']),
        'agendamento_id': agendamentoLocal,
        'criado_em': _textoPreferido(
          remoto['origem_criado_em'],
          remoto['criado_em'],
        ),
        'atualizado_em': _textoPreferido(
          remoto['origem_atualizado_em'],
          remoto['atualizado_em'],
        ),
        'convertido_em': _textoNulo(remoto['convertido_em']),
      });

      final local = await _localPorId('crm_leads', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashCrmLead(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarCrmInteracoesNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_crm_interacoes')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_crm_interacoes',
        empresaId: empresaId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final leadLocal = await _localPorRemoto(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        remotoId: _texto(remoto['lead_id']),
      );
      if (leadLocal == null) continue;

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'crm_interacoes',
        tabelaMapa: 'imperium_sync_crm_interacoes',
        remoto: remoto,
        hashBuilder: _hashCrmInteracao,
      )) {
        continue;
      }

      final localId = await database.insert('crm_interacoes', {
        'lead_id': leadLocal,
        'tipo': _textoPadrao(remoto['tipo'], 'Contato'),
        'descricao': _texto(remoto['descricao']),
        'data_interacao': _texto(remoto['data_interacao']),
        'criado_em': _textoPreferido(
          remoto['origem_criado_em'],
          remoto['criado_em'],
        ),
      });

      final local = await _localPorId('crm_interacoes', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_interacoes',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashCrmInteracao(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarCrmCampanhasNovas(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_crm_campanhas')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        remotoId: remotoId,
      )) {
        continue;
      }

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'crm_campanhas',
        tabelaMapa: 'imperium_sync_crm_campanhas',
        remoto: remoto,
        hashBuilder: _hashCrmCampanha,
      )) {
        continue;
      }

      final localId = await database.insert('crm_campanhas', {
        'nome': _texto(remoto['nome']),
        'tipo': _textoPadrao(remoto['tipo'], 'Manual'),
        'beneficio_tipo': _textoPadrao(remoto['beneficio_tipo'], 'Percentual'),
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
      });

      final local = await _localPorId('crm_campanhas', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashCrmCampanha(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarCrmCuponsNovos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final remotos = await client
        .from('imperium_crm_cupons')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final database = await _appDatabase.database;

    for (final raw in remotos) {
      final remoto = Map<String, dynamic>.from(raw);
      final remotoId = _texto(remoto['id']);

      if (await _jaMapeadoRemoto(
        tabelaMapa: 'imperium_sync_crm_cupons',
        empresaId: empresaId,
        remotoId: remotoId,
      )) {
        continue;
      }

      if (await _reconstruirOrigem(
        empresaId: empresaId,
        tabelaLocal: 'crm_cupons',
        tabelaMapa: 'imperium_sync_crm_cupons',
        remoto: remoto,
        hashBuilder: _hashCrmCupom,
      )) {
        continue;
      }

      final campanhaLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_crm_campanhas',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['campanha_id']),
      );
      final clienteLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['cliente_id']),
      );
      final leadLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_crm_leads',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['lead_id']),
      );
      final osLocal = await _localPorRemotoOpcional(
        tabelaMapa: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: _textoNulo(remoto['ordem_servico_id']),
      );

      final codigo = _texto(remoto['codigo']);
      final existente = await database.query(
        'crm_cupons',
        columns: ['id'],
        where: 'codigo = ?',
        whereArgs: [codigo],
        limit: 1,
      );

      final localId = existente.isNotEmpty
          ? _int(existente.first['id'])
          : await database.insert('crm_cupons', {
              'codigo': codigo,
              'campanha_id': campanhaLocal,
              'cliente_id': clienteLocal,
              'lead_id': leadLocal,
              'beneficio_tipo': _texto(remoto['beneficio_tipo']),
              'beneficio_valor': _double(remoto['beneficio_valor']),
              'beneficio_descricao': _texto(remoto['beneficio_descricao']),
              'valor_minimo': _double(remoto['valor_minimo']),
              'validade_inicio': _texto(remoto['validade_inicio']),
              'validade_fim': _texto(remoto['validade_fim']),
              'status': _textoPadrao(remoto['status'], 'Ativo'),
              'usado_em': _textoNulo(remoto['usado_em']),
              'ordem_servico_id': osLocal,
              'chave_geracao': _texto(remoto['chave_geracao']),
              'criado_em': _textoPreferido(
                remoto['origem_criado_em'],
                remoto['criado_em'],
              ),
            });

      final local = await _localPorId('crm_cupons', localId);
      await _salvarMapa(
        tabelaMapa: 'imperium_sync_crm_cupons',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashCrmCupom(local),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<bool> _reconstruirOrigem({
    required String empresaId,
    required String tabelaLocal,
    required String tabelaMapa,
    required Map<String, dynamic> remoto,
    required String Function(Map<String, Object?>) hashBuilder,
  }) async {
    final origemDispositivo = _texto(remoto['origem_dispositivo']);
    final origemLocalId = _int(remoto['origem_local_id']);

    if (origemDispositivo.isEmpty || origemLocalId <= 0) return false;
    if (origemDispositivo != await _dispositivoId()) return false;

    final database = await _appDatabase.database;
    final local = await database.query(
      tabelaLocal,
      where: 'id = ?',
      whereArgs: [origemLocalId],
      limit: 1,
    );

    if (local.isEmpty) return false;

    await _salvarMapa(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: origemLocalId,
      remotoId: _texto(remoto['id']),
      localHash: hashBuilder(local.first),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    return true;
  }

  Future<void> _marcarAusentesComoExcluidos({
    required String empresaId,
    required String tabelaLocal,
    required String tabelaMapa,
    required String tabelaRemota,
  }) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final mapas = await database.query(
      tabelaMapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    for (final mapa in mapas) {
      if (_texto(mapa['local_hash']) == '__excluido__') continue;

      final localId = _int(mapa['local_id']);
      final remotoId = _texto(mapa['remoto_id']);
      if (localId <= 0 || remotoId.isEmpty) continue;

      final local = await database.query(
        tabelaLocal,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (local.isNotEmpty) continue;

      final resposta = await client
          .from(tabelaRemota)
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em');

      await database.update(
        tabelaMapa,
        {
          'local_hash': '__excluido__',
          'remoto_atualizado_em': resposta.isEmpty
              ? DateTime.now().toIso8601String()
              : resposta.first['atualizado_em']?.toString(),
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
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

  Future<Map<String, Object?>?> _mapaLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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

  Future<String?> _remotoPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;
    final mapa = await _mapaLocal(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
    final id = _texto(mapa?['remoto_id']);
    return id.isEmpty ? null : id;
  }

  Future<String?> _dependenciaOpcionalObrigatoriaSeInformada({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) {
    return _remotoPorLocal(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
  }

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;

    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _int(rows.first['local_id']);
    return id <= 0 ? null : id;
  }

  Future<int?> _localPorRemotoOpcional({
    required String tabelaMapa,
    required String empresaId,
    required String? remotoId,
  }) async {
    if (remotoId == null || remotoId.isEmpty) return null;

    if (!await _tabelaExiste(tabelaMapa)) return null;

    return _localPorRemoto(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
  }

  Future<String?> _remotoPorLocalSeTabelaExiste({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    if (!await _tabelaExiste(tabelaMapa)) return null;
    return _remotoPorLocal(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      localId: localId,
    );
  }

  Future<int?> _localPorRemotoSeTabelaExiste({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (!await _tabelaExiste(tabelaMapa)) return null;
    return _localPorRemoto(
      tabelaMapa: tabelaMapa,
      empresaId: empresaId,
      remotoId: remotoId,
    );
  }

  Future<bool> _tabelaExiste(String tabela) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [tabela],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _jaMapeadoRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return rows.isNotEmpty;
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

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Sync operacional ainda não preparou o dispositivo.');
    }

    final id = _texto(rows.first['dispositivo_id']);
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo está vazio.');
    }
    return id;
  }

  String _hashOrcamento(Map<String, Object?> local, String perfil) {
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
      perfil,
    ]);
  }

  String _hashOrcamentoItem(Map<String, Object?> local, int? catalogoLocalId) {
    return _sha(<Object?>[
      _int(local['orcamento_id']),
      local['servico'],
      local['descricao'],
      _double(local['quantidade']),
      _double(local['valor_unitario']),
      _int(local['ordem']),
      catalogoLocalId,
    ]);
  }

  String _hashCrmLead(Map<String, Object?> local) {
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
  }

  String _hashCrmInteracao(Map<String, Object?> local) {
    return _sha(<Object?>[
      _int(local['lead_id']),
      local['tipo'],
      local['descricao'],
      local['data_interacao'],
      local['criado_em'],
    ]);
  }

  String _hashCrmCampanha(Map<String, Object?> local) {
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
  }

  String _hashCrmCupom(Map<String, Object?> local) {
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
