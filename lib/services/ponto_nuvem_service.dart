import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../repositories/ponto_repository.dart';
import 'supabase_bootstrap.dart';

class PontoNuvemService {
  PontoNuvemService._();

  static final PontoNuvemService instance = PontoNuvemService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sincronizacao_ponto_colaboradores (
        local_id INTEGER PRIMARY KEY,
        empresa_id TEXT NOT NULL,
        remoto_id TEXT NOT NULL,
        sincronizado_em TEXT NOT NULL,
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<String?> empresaAtualId() async {
    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      return null;
    }

    final vinculo = await client
        .from('empresa_usuarios')
        .select('empresa_id')
        .eq('user_id', user.id)
        .eq('ativo', true)
        .limit(1)
        .maybeSingle();

    final id = vinculo?['empresa_id']?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  Future<bool> get conectado async {
    return await empresaAtualId() != null;
  }

  Future<bool> get pontoHibridoAtivo async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return false;
    }

    final estado = await client
        .from('ponto_sync_estado')
        .select('migracao_concluida')
        .eq('empresa_id', empresaId)
        .maybeSingle();

    return estado?['migracao_concluida'] == true;
  }

  Future<Map<String, dynamic>> obterEstadoMigracao() async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return const {'conectado': false, 'migracao_concluida': false};
    }

    final estado = await client
        .from('ponto_sync_estado')
        .select('migracao_concluida,migracao_concluida_em,atualizado_em')
        .eq('empresa_id', empresaId)
        .maybeSingle();

    return {
      'conectado': true,
      'migracao_concluida': estado?['migracao_concluida'] == true,
      'migracao_concluida_em': estado?['migracao_concluida_em'],
      'atualizado_em': estado?['atualizado_em'],
    };
  }

  Future<String?> remotoIdPorLocal(int localId, {String? empresaId}) async {
    if (localId <= 0) return null;

    final idEmpresa = empresaId ?? await empresaAtualId();
    if (idEmpresa == null) return null;

    await garantirEstruturaLocal();

    final database = await _appDatabase.database;

    final local = await database.query(
      'sincronizacao_ponto_colaboradores',
      columns: ['remoto_id'],
      where: 'local_id = ? AND empresa_id = ?',
      whereArgs: [localId, idEmpresa],
      limit: 1,
    );

    if (local.isNotEmpty) {
      final id = local.first['remoto_id']?.toString().trim() ?? '';
      if (id.isNotEmpty) return id;
    }

    final client = _client;
    if (client == null) return null;

    final remoto = await client
        .from('ponto_colaboradores')
        .select('id')
        .eq('empresa_id', idEmpresa)
        .eq('origem_local_id', localId)
        .limit(1)
        .maybeSingle();

    final remotoId = remoto?['id']?.toString().trim() ?? '';

    if (remotoId.isEmpty) {
      return null;
    }

    await _salvarVinculo(
      localId: localId,
      empresaId: idEmpresa,
      remotoId: remotoId,
    );

    return remotoId;
  }

  Future<void> _salvarVinculo({
    required int localId,
    required String empresaId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'sincronizacao_ponto_colaboradores',
      {
        'local_id': localId,
        'empresa_id': empresaId,
        'remoto_id': remotoId,
        'sincronizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> colaboradorRemotoPorLocal(int localId) async {
    final empresaId = await empresaAtualId();
    if (empresaId == null) return null;

    final remotoId = await remotoIdPorLocal(localId, empresaId: empresaId);

    if (remotoId == null) return null;

    final client = _client;
    if (client == null) return null;

    final item = await client
        .from('ponto_colaboradores')
        .select('id,nome,funcao,ativo,auth_user_id,origem_local_id')
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    return item == null ? null : Map<String, dynamic>.from(item);
  }

  Future<List<Map<String, dynamic>>> listarColaboradoresRemotos() async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return const [];
    }

    final dados = await client
        .from('ponto_colaboradores')
        .select(
          'id,nome,funcao,ativo,auth_user_id,origem_local_id,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('nome');

    return dados
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> vincularUsuario({
    required String colaboradorRemotoId,
    required String email,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    await client.rpc(
      'ponto_vincular_usuario_colaborador',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorRemotoId,
        'p_email': email.trim(),
      },
    );
  }

  Future<Map<String, dynamic>?> registrarBatida(int colaboradorLocalId) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return null;
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      throw StateError(
        'Funcionário ainda não está vinculado ao Ponto na nuvem.',
      );
    }

    final resposta = await client.rpc(
      'ponto_registrar_batida',
      params: {'p_empresa_id': empresaId, 'p_colaborador_id': remotoId},
    );

    final mapa = _mapa(resposta);
    final registro = _mapa(mapa['registro']);

    if (registro.isNotEmpty) {
      await _espelharRegistro(
        colaboradorLocalId: colaboradorLocalId,
        registro: registro,
      );
    }

    return mapa;
  }

  Future<bool> sincronizarDia({
    required int colaboradorLocalId,
    required DateTime data,
  }) async {
    return sincronizarPeriodo(
      colaboradorLocalId: colaboradorLocalId,
      inicio: data,
      fim: data,
    );
  }

  Future<bool> sincronizarPeriodo({
    required int colaboradorLocalId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return false;
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      return false;
    }

    final dados = await client
        .from('ponto_registros')
        .select(
          'id,data,situacao,entrada,intervalo_inicio,intervalo_fim,'
          'saida,observacoes,criado_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', remotoId)
        .gte('data', _data(inicio))
        .lte('data', _data(fim))
        .order('data');

    final database = await _appDatabase.database;

    final remotosPorData = <String, Map<String, dynamic>>{};

    for (final item in dados) {
      final mapa = Map<String, dynamic>.from(item);
      final data = mapa['data']?.toString() ?? '';
      if (data.isEmpty) continue;

      remotosPorData[data] = mapa;

      await _espelharRegistro(
        colaboradorLocalId: colaboradorLocalId,
        registro: mapa,
      );
    }

    // Se um registro remoto foi excluído por administrador em outro aparelho,
    // remove o espelho local dentro do período.
    final locais = await database.query(
      'financeiro_ponto_registros',
      columns: ['id', 'data'],
      where: 'colaborador_id = ? AND date(data) BETWEEN date(?) AND date(?)',
      whereArgs: [colaboradorLocalId, _data(inicio), _data(fim)],
    );

    for (final local in locais) {
      final data = local['data']?.toString() ?? '';
      if (data.isEmpty || remotosPorData.containsKey(data)) continue;

      await database.delete(
        'financeiro_ponto_registros',
        where: 'id = ?',
        whereArgs: [local['id']],
      );
    }

    await sincronizarJornada();
    await sincronizarConfig();
    await sincronizarFechamentos(colaboradorLocalId: colaboradorLocalId);

    return true;
  }

  Future<void> sincronizarJornada() async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) return;

    final dados = await client
        .from('ponto_jornada')
        .select(
          'dia_semana,ativo,entrada,intervalo_inicio,intervalo_fim,'
          'saida,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('dia_semana');

    final database = await _appDatabase.database;

    for (final item in dados) {
      await database.insert('financeiro_ponto_jornada', {
        'dia_semana': _int(item['dia_semana']),
        'ativo': item['ativo'] == true ? 1 : 0,
        'entrada': _horaLocal(item['entrada']),
        'intervalo_inicio': _horaLocal(item['intervalo_inicio']),
        'intervalo_fim': _horaLocal(item['intervalo_fim']),
        'saida': _horaLocal(item['saida']),
        'atualizado_em':
            item['atualizado_em']?.toString() ??
            DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> sincronizarConfig() async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) return;

    final item = await client
        .from('ponto_config')
        .select('adicional_hora_extra,atualizado_em')
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (item == null) return;

    final database = await _appDatabase.database;

    await database.insert('financeiro_ponto_config', {
      'id': 1,
      'adicional_hora_extra': _double(item['adicional_hora_extra'], 50),
      'atualizado_em':
          item['atualizado_em']?.toString() ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> salvarConfig(double percentual) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    await client.rpc(
      'ponto_salvar_config_admin',
      params: {'p_empresa_id': empresaId, 'p_adicional_hora_extra': percentual},
    );

    await sincronizarConfig();
  }

  Future<void> salvarJornada({
    required int diaSemana,
    required bool ativo,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    await client.rpc(
      'ponto_salvar_jornada_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_dia_semana': diaSemana,
        'p_ativo': ativo,
        'p_entrada': _horaNula(entrada),
        'p_intervalo_inicio': _horaNula(intervaloInicio),
        'p_intervalo_fim': _horaNula(intervaloFim),
        'p_saida': _horaNula(saida),
      },
    );

    await sincronizarJornada();
  }

  Future<Map<String, dynamic>> salvarRegistroAdmin({
    required int colaboradorLocalId,
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    String motivo = '',
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      throw StateError('Funcionário não vinculado à nuvem.');
    }

    final resposta = await client.rpc(
      'ponto_salvar_registro_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': remotoId,
        'p_data': _data(data),
        'p_situacao': situacao,
        'p_entrada': _horaNula(entrada),
        'p_intervalo_inicio': _horaNula(intervaloInicio),
        'p_intervalo_fim': _horaNula(intervaloFim),
        'p_saida': _horaNula(saida),
        'p_observacoes': observacoes.trim(),
        'p_motivo': motivo.trim(),
      },
    );

    final registro = _mapa(resposta);

    await _espelharRegistro(
      colaboradorLocalId: colaboradorLocalId,
      registro: registro,
    );

    return registro;
  }

  Future<void> removerRegistroAdmin({
    required int colaboradorLocalId,
    required DateTime data,
    required String motivo,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      throw StateError('Funcionário não vinculado à nuvem.');
    }

    final remoto = await client
        .from('ponto_registros')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', remotoId)
        .eq('data', _data(data))
        .maybeSingle();

    final registroRemotoId = remoto?['id']?.toString();

    if (registroRemotoId == null || registroRemotoId.isEmpty) {
      return;
    }

    await client.rpc(
      'ponto_remover_registro_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_registro_id': registroRemotoId,
        'p_motivo': motivo.trim(),
      },
    );
  }

  Future<Set<String>> listarDiasCorrigidos({
    required int colaboradorLocalId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return const <String>{};
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      return const <String>{};
    }

    final resposta = await client.rpc(
      'ponto_listar_dias_corrigidos',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': remotoId,
        'p_inicio': _data(inicio),
        'p_fim': _data(fim),
      },
    );

    if (resposta is! List) {
      return const <String>{};
    }

    return resposta
        .whereType<Map>()
        .map((item) => item['data']?.toString().trim() ?? '')
        .where((data) => data.isNotEmpty)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> listarAjustes({
    required int colaboradorLocalId,
    required DateTime data,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return const [];
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) return const [];

    final dados = await client
        .from('ponto_ajustes')
        .select('id,data,acao,motivo,antes_json,depois_json,criado_em')
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', remotoId)
        .eq('data', _data(data))
        .order('criado_em', ascending: false);

    return dados
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> fecharCompetencia({
    required int colaboradorLocalId,
    required DateTime competencia,
    required Map<String, dynamic> snapshot,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      throw StateError('Funcionário não vinculado à nuvem.');
    }

    await client.rpc(
      'ponto_fechar_competencia_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': remotoId,
        'p_competencia':
            '${competencia.year.toString().padLeft(4, '0')}-'
            '${competencia.month.toString().padLeft(2, '0')}-01',
        'p_snapshot': snapshot,
      },
    );

    await sincronizarFechamentos(colaboradorLocalId: colaboradorLocalId);
  }

  Future<void> reabrirCompetencia({
    required int colaboradorLocalId,
    required DateTime competencia,
    required String motivo,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) {
      throw StateError('Funcionário não vinculado à nuvem.');
    }

    await client.rpc(
      'ponto_reabrir_competencia_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': remotoId,
        'p_competencia':
            '${competencia.year.toString().padLeft(4, '0')}-'
            '${competencia.month.toString().padLeft(2, '0')}-01',
        'p_motivo': motivo.trim(),
      },
    );

    await sincronizarFechamentos(colaboradorLocalId: colaboradorLocalId);
  }

  Future<void> sincronizarFechamentos({required int colaboradorLocalId}) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) return;

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) return;

    final dados = await client
        .from('ponto_fechamentos')
        .select(
          'competencia,status,snapshot_json,fechado_em,reaberto_em,'
          'motivo_reabertura,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', remotoId);

    final database = await _appDatabase.database;

    for (final item in dados) {
      final competencia = item['competencia']?.toString() ?? '';
      if (competencia.isEmpty) continue;

      final snapshot = item['snapshot_json'];

      await database.insert(
        'financeiro_ponto_fechamentos',
        {
          'colaborador_id': colaboradorLocalId,
          'competencia': competencia.substring(0, 7),
          'status': item['status']?.toString() ?? 'Aberto',
          'snapshot_json': snapshot == null ? null : jsonEncode(snapshot),
          'fechado_em': item['fechado_em']?.toString(),
          'reaberto_em': item['reaberto_em']?.toString(),
          'motivo_reabertura': item['motivo_reabertura']?.toString() ?? '',
          'atualizado_em':
              item['atualizado_em']?.toString() ??
              DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<Map<String, dynamic>>> listarHistoricoFechamento({
    required int colaboradorLocalId,
    required DateTime competencia,
  }) async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      return const [];
    }

    final remotoId = await remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );

    if (remotoId == null) return const [];

    final competenciaBanco =
        '${competencia.year.toString().padLeft(4, '0')}-'
        '${competencia.month.toString().padLeft(2, '0')}-01';

    final dados = await client
        .from('ponto_fechamento_historico')
        .select('id,competencia,acao,motivo,snapshot_json,criado_em')
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', remotoId)
        .eq('competencia', competenciaBanco)
        .order('criado_em', ascending: false);

    return dados
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> migrarHistoricoLocalCompleto() async {
    final empresaId = await empresaAtualId();
    final client = _client;

    if (empresaId == null || client == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    // Garante as tabelas SQLite do Ponto antes de ler o histórico.
    // Isso é necessário quando o usuário ainda não abriu o módulo Ponto
    // neste banco/aparelho após uma atualização.
    await PontoRepository().garantirEstrutura();
    await garantirEstruturaLocal();

    final database = await _appDatabase.database;

    final colaboradores = await database.query(
      'financeiro_colaboradores_custo',
      columns: ['id', 'nome', 'funcao', 'ativo'],
      orderBy: 'id ASC',
    );

    var colaboradoresOk = 0;
    var registrosOk = 0;
    var ajustesOk = 0;
    var fechamentosOk = 0;

    // 1. Colaboradores
    for (final item in colaboradores) {
      final localId = _int(item['id']);
      if (localId <= 0) continue;

      final resultado = await client.rpc(
        'ponto_importar_colaborador',
        params: {
          'p_empresa_id': empresaId,
          'p_origem_local_id': localId,
          'p_nome': item['nome']?.toString() ?? '',
          'p_funcao': item['funcao']?.toString() ?? '',
          'p_ativo': _int(item['ativo']) == 1,
        },
      );

      final remotoId = resultado?.toString().trim() ?? '';
      if (remotoId.isEmpty) {
        throw StateError(
          'A nuvem não retornou o ID do funcionário local #$localId.',
        );
      }

      await _salvarVinculo(
        localId: localId,
        empresaId: empresaId,
        remotoId: remotoId,
      );

      colaboradoresOk++;
    }

    // 2. Jornada
    final jornada = await database.query(
      'financeiro_ponto_jornada',
      orderBy: 'dia_semana ASC',
    );

    for (final item in jornada) {
      await client.rpc(
        'ponto_salvar_jornada_admin',
        params: {
          'p_empresa_id': empresaId,
          'p_dia_semana': _int(item['dia_semana']),
          'p_ativo': _int(item['ativo']) == 1,
          'p_entrada': _horaNula(item['entrada']?.toString()),
          'p_intervalo_inicio': _horaNula(item['intervalo_inicio']?.toString()),
          'p_intervalo_fim': _horaNula(item['intervalo_fim']?.toString()),
          'p_saida': _horaNula(item['saida']?.toString()),
        },
      );
    }

    // 3. Configuração
    final config = await database.query(
      'financeiro_ponto_config',
      where: 'id = 1',
      limit: 1,
    );

    if (config.isNotEmpty) {
      await client.rpc(
        'ponto_salvar_config_admin',
        params: {
          'p_empresa_id': empresaId,
          'p_adicional_hora_extra': _double(
            config.first['adicional_hora_extra'],
            50,
          ),
        },
      );
    }

    // 4. Registros
    final registros = await database.query(
      'financeiro_ponto_registros',
      orderBy: 'data ASC, id ASC',
    );

    for (final item in registros) {
      final localId = _int(item['colaborador_id']);
      final remotoId = await remotoIdPorLocal(localId, empresaId: empresaId);

      if (remotoId == null) {
        throw StateError('Funcionário local #$localId sem vínculo remoto.');
      }

      final data = item['data']?.toString().trim() ?? '';
      if (data.isEmpty) continue;

      await client.rpc(
        'ponto_salvar_registro_admin',
        params: {
          'p_empresa_id': empresaId,
          'p_colaborador_id': remotoId,
          'p_data': data,
          'p_situacao': item['situacao']?.toString() ?? 'Trabalhado',
          'p_entrada': _horaNula(item['entrada']?.toString()),
          'p_intervalo_inicio': _horaNula(item['intervalo_inicio']?.toString()),
          'p_intervalo_fim': _horaNula(item['intervalo_fim']?.toString()),
          'p_saida': _horaNula(item['saida']?.toString()),
          'p_observacoes': item['observacoes']?.toString() ?? '',
          'p_motivo': 'Migração inicial do SQLite',
        },
      );

      registrosOk++;
    }

    // 5. Histórico de ajustes já existente.
    final ajustes = await database.query(
      'financeiro_ponto_ajustes',
      orderBy: 'id ASC',
    );

    for (final item in ajustes) {
      final localId = _int(item['colaborador_id']);
      final remotoId = await remotoIdPorLocal(localId, empresaId: empresaId);

      if (remotoId == null) continue;

      dynamic antes;
      dynamic depois;

      try {
        final texto = item['antes_json']?.toString().trim() ?? '';
        if (texto.isNotEmpty) antes = jsonDecode(texto);
      } catch (_) {
        antes = null;
      }

      try {
        final texto = item['depois_json']?.toString().trim() ?? '';
        if (texto.isNotEmpty) depois = jsonDecode(texto);
      } catch (_) {
        depois = null;
      }

      await client.rpc(
        'ponto_importar_ajuste_historico',
        params: {
          'p_empresa_id': empresaId,
          'p_colaborador_id': remotoId,
          'p_data': item['data']?.toString(),
          'p_acao': item['acao']?.toString() ?? 'Importacao',
          'p_motivo': item['motivo']?.toString() ?? 'Migração do SQLite',
          'p_antes_json': antes,
          'p_depois_json': depois,
          'p_criado_em': item['criado_em']?.toString(),
        },
      );

      ajustesOk++;
    }

    // 6. Fechamentos já concluídos.
    final fechamentos = await database.query(
      'financeiro_ponto_fechamentos',
      where: 'status = ?',
      whereArgs: ['Fechado'],
      orderBy: 'competencia ASC, id ASC',
    );

    for (final item in fechamentos) {
      final localId = _int(item['colaborador_id']);
      final remotoId = await remotoIdPorLocal(localId, empresaId: empresaId);

      if (remotoId == null) continue;

      final competenciaTexto = item['competencia']?.toString().trim() ?? '';
      if (competenciaTexto.isEmpty) continue;

      final competencia = competenciaTexto.length >= 7
          ? '${competenciaTexto.substring(0, 7)}-01'
          : competenciaTexto;

      dynamic snapshot;

      try {
        final texto = item['snapshot_json']?.toString().trim() ?? '';
        snapshot = texto.isEmpty ? <String, dynamic>{} : jsonDecode(texto);
      } catch (_) {
        snapshot = <String, dynamic>{};
      }

      await client.rpc(
        'ponto_fechar_competencia_admin',
        params: {
          'p_empresa_id': empresaId,
          'p_colaborador_id': remotoId,
          'p_competencia': competencia,
          'p_snapshot': snapshot,
        },
      );

      fechamentosOk++;
    }

    // Só ativa o modo híbrido após todas as etapas acima concluírem.
    await client.rpc(
      'ponto_concluir_migracao',
      params: {'p_empresa_id': empresaId},
    );

    return {
      'colaboradores': colaboradoresOk,
      'registros': registrosOk,
      'ajustes': ajustesOk,
      'fechamentos': fechamentosOk,
      'migracao_concluida': true,
    };
  }

  Future<void> _espelharRegistro({
    required int colaboradorLocalId,
    required Map<String, dynamic> registro,
  }) async {
    final database = await _appDatabase.database;

    final data = registro['data']?.toString() ?? '';
    if (data.isEmpty) return;

    final existente = await database.query(
      'financeiro_ponto_registros',
      columns: ['id', 'criado_em'],
      where: 'colaborador_id = ? AND data = ?',
      whereArgs: [colaboradorLocalId, data],
      limit: 1,
    );

    final agora = DateTime.now().toIso8601String();
    final dados = <String, dynamic>{
      'colaborador_id': colaboradorLocalId,
      'data': data,
      'situacao': registro['situacao']?.toString() ?? 'Trabalhado',
      'entrada': _horaLocal(registro['entrada']),
      'intervalo_inicio': _horaLocal(registro['intervalo_inicio']),
      'intervalo_fim': _horaLocal(registro['intervalo_fim']),
      'saida': _horaLocal(registro['saida']),
      'observacoes': registro['observacoes']?.toString() ?? '',
      'atualizado_em': registro['atualizado_em']?.toString() ?? agora,
    };

    if (existente.isEmpty) {
      dados['criado_em'] = registro['criado_em']?.toString() ?? agora;

      await database.insert(
        'financeiro_ponto_registros',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await database.update(
        'financeiro_ponto_registros',
        dados,
        where: 'id = ?',
        whereArgs: [existente.first['id']],
      );
    }
  }

  Map<String, dynamic> _mapa(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is Map) {
      return Map<String, dynamic>.from(valor);
    }

    return <String, dynamic>{};
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _double(dynamic valor, [double padrao = 0]) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? padrao;
  }

  String _data(DateTime data) {
    return '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  String? _horaLocal(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final partes = texto.split(':');
    if (partes.length < 2) return texto;

    return '${partes[0].padLeft(2, '0')}:'
        '${partes[1].padLeft(2, '0')}';
  }

  String? _horaNula(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
