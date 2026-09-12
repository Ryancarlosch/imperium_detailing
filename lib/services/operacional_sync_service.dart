import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'estoque_cloud_upload_service.dart';
import 'os_cloud_download_service.dart';
import 'os_cloud_upload_service.dart';
import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

class OperacionalSyncService {
  OperacionalSyncService._();

  static final OperacionalSyncService instance = OperacionalSyncService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  bool _sincronizando = false;

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        dispositivo_id TEXT NOT NULL,
        empresa_id TEXT,
        ultimo_sync_em TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_clientes (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_veiculos (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_agendamentos (
        empresa_id TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remoto_id TEXT NOT NULL,
        local_hash TEXT,
        remoto_atualizado_em TEXT,
        PRIMARY KEY (empresa_id, local_id),
        UNIQUE (empresa_id, remoto_id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_exclusoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        entidade TEXT NOT NULL,
        remoto_id TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        UNIQUE (empresa_id, entidade, remoto_id)
      )
    ''');

    final config = await database.query(
      'imperium_sync_config',
      where: 'id = 1',
      limit: 1,
    );

    if (config.isEmpty) {
      await database.insert('imperium_sync_config', {
        'id': 1,
        'dispositivo_id': _novoDispositivoId(),
        'empresa_id': null,
        'ultimo_sync_em': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<String> _dispositivoId() async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final config = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    final atual = config.isEmpty
        ? ''
        : (config.first['dispositivo_id'] ?? '').toString().trim();

    if (atual.isNotEmpty) return atual;

    final novo = _novoDispositivoId();

    await database.insert('imperium_sync_config', {
      'id': 1,
      'dispositivo_id': novo,
      'empresa_id': null,
      'ultimo_sync_em': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return novo;
  }

  String _novoDispositivoId() {
    final random = Random.secure();
    final tempo = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final aleatorio = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    return '$tempo-$aleatorio';
  }

  Future<String?> _empresaCache() async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final config = await database.query(
      'imperium_sync_config',
      columns: ['empresa_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (config.isEmpty) return null;

    final id = (config.first['empresa_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<void> _salvarEmpresaCache(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.update('imperium_sync_config', {
      'empresa_id': empresaId,
    }, where: 'id = 1');
  }

  Future<String?> empresaAtualId() async {
    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) return null;

    try {
      final vinculo = await client
          .from('empresa_usuarios')
          .select('empresa_id')
          .eq('user_id', user.id)
          .eq('ativo', true)
          .limit(1)
          .maybeSingle();

      final id = (vinculo?['empresa_id'] ?? '').toString().trim();

      if (id.isNotEmpty) {
        await _salvarEmpresaCache(id);
        return id;
      }
    } catch (_) {
      // Offline: usa o último tenant confirmado apenas para fila/local.
    }

    return _empresaCache();
  }

  Future<void> tentarSincronizarTudo() async {
    try {
      await sincronizarTudo();
    } catch (_) {
      // Offline-first: a falha remota não bloqueia o SQLite.
    }
  }

  Future<void> sincronizarTudo() async {
    if (_sincronizando) return;

    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) return;

    _sincronizando = true;

    try {
      await garantirEstruturaLocal();

      final empresaId = await empresaAtualId();

      if (empresaId == null || empresaId.isEmpty) return;

      await _processarExclusoes(empresaId);

      // Se o local mudou desde o último espelho, envia primeiro.
      await _publicarClientesLocais(empresaId);
      await _publicarVeiculosLocais(empresaId);
      await _publicarAgendamentosLocais(empresaId);

      // os-cloud-upload-call-v1
      // Etapa 4 inicia upload-only para nao contaminar Financeiro/Estoque
      // nem baixar OS antes da homologacao do nucleo.
      await OsCloudUploadService.instance.sincronizarUpload(empresaId);

      // estoque-cloud-upload-call-v1
      // Etapa 5 inicia upload-only: item -> lote -> movimentacao.
      // Nao altera saldo local nem Financeiro.
      await EstoqueCloudUploadService.instance.sincronizarUpload(empresaId);
      // Depois baixa o estado compartilhado.
      await _baixarClientes(empresaId);
      await _baixarVeiculos(empresaId);
      await _baixarAgendamentos(empresaId);
      await OsCloudDownloadService.instance.sincronizarDownloadNovos(empresaId);

      // O Ponto já possui sua própria estrutura de nuvem.
      await _sincronizarPontoFuncionario();

      final database = await _appDatabase.database;
      await database.update('imperium_sync_config', {
        'empresa_id': empresaId,
        'ultimo_sync_em': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> registrarExclusaoVeiculo(int localId) async {
    await _registrarExclusao(
      entidade: 'veiculo',
      tabelaMapa: 'imperium_sync_veiculos',
      localId: localId,
    );
  }

  Future<void> registrarExclusaoAgendamento(int localId) async {
    await _registrarExclusao(
      entidade: 'agendamento',
      tabelaMapa: 'imperium_sync_agendamentos',
      localId: localId,
    );
  }

  Future<void> _registrarExclusao({
    required String entidade,
    required String tabelaMapa,
    required int localId,
  }) async {
    await garantirEstruturaLocal();

    final empresaId = await empresaAtualId();
    if (empresaId == null || empresaId.isEmpty) return;

    final database = await _appDatabase.database;

    final mapa = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (mapa.isEmpty) return;

    final remotoId = (mapa.first['remoto_id'] ?? '').toString().trim();
    if (remotoId.isEmpty) return;

    await database.insert('imperium_sync_exclusoes', {
      'empresa_id': empresaId,
      'entidade': entidade,
      'remoto_id': remotoId,
      'criado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _processarExclusoes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;

    final pendentes = await database.query(
      'imperium_sync_exclusoes',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'id ASC',
    );

    for (final item in pendentes) {
      final id = _int(item['id']);
      final entidade = (item['entidade'] ?? '').toString();
      final remotoId = (item['remoto_id'] ?? '').toString().trim();

      if (id <= 0 || remotoId.isEmpty) continue;

      String? tabelaRemota;
      String? tabelaMapa;

      if (entidade == 'veiculo') {
        tabelaRemota = 'imperium_veiculos';
        tabelaMapa = 'imperium_sync_veiculos';
      } else if (entidade == 'agendamento') {
        tabelaRemota = 'imperium_agendamentos';
        tabelaMapa = 'imperium_sync_agendamentos';
      }

      if (tabelaRemota == null || tabelaMapa == null) {
        await database.delete(
          'imperium_sync_exclusoes',
          where: 'id = ?',
          whereArgs: [id],
        );
        continue;
      }

      await client
          .from(tabelaRemota)
          .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId);

      await database.delete(
        tabelaMapa,
        where: 'empresa_id = ? AND remoto_id = ?',
        whereArgs: [empresaId, remotoId],
      );

      await database.delete(
        'imperium_sync_exclusoes',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _publicarClientesLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('clientes');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashCliente(local);
      final mapa = await _mapaLocal(
        'imperium_sync_clientes',
        empresaId,
        localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarCliente(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarCliente({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'nome': (local['nome'] ?? '').toString(),
      'telefone': (local['telefone'] ?? '').toString(),
      'email': (local['email'] ?? '').toString(),
      'endereco': (local['endereco'] ?? '').toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'ativo': _int(local['ativo']) != 0,
      'arquivado_em': _nuloTexto(local['arquivado_em']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();

    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_clientes')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_clientes')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_clientes',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarVeiculosLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('veiculos');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashVeiculo(local);
      final mapa = await _mapaLocal(
        'imperium_sync_veiculos',
        empresaId,
        localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarVeiculo(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarVeiculo({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final clienteLocalId = _int(local['cliente_id']);

    final clienteRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_clientes',
      empresaId: empresaId,
      localId: clienteLocalId,
    );

    if (clienteRemotoId == null) {
      throw StateError(
        'Cliente local #$clienteLocalId ainda não foi sincronizado.',
      );
    }

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteRemotoId,
      'marca': (local['marca'] ?? '').toString(),
      'modelo': (local['modelo'] ?? '').toString(),
      'placa': (local['placa'] ?? '').toString(),
      'cor': (local['cor'] ?? '').toString(),
      'ano': (local['ano'] ?? '').toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();

    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_veiculos')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_veiculos')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_veiculos',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarAgendamentosLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('agendamentos');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashAgendamento(local);
      final mapa = await _mapaLocal(
        'imperium_sync_agendamentos',
        empresaId,
        localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarAgendamento(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarAgendamento({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final clienteLocalId = _int(local['cliente_id']);
    final veiculoLocalId = _int(local['veiculo_id']);

    final clienteRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_clientes',
      empresaId: empresaId,
      localId: clienteLocalId,
    );

    final veiculoRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_veiculos',
      empresaId: empresaId,
      localId: veiculoLocalId,
    );

    if (clienteRemotoId == null || veiculoRemotoId == null) {
      throw StateError(
        'Cliente/veículo do agendamento #$localId '
        'ainda não foi sincronizado.',
      );
    }

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteRemotoId,
      'veiculo_id': veiculoRemotoId,
      'servico': (local['servico'] ?? '').toString(),
      'data': (local['data'] ?? '').toString(),
      'hora': (local['hora'] ?? '').toString(),
      'valor': _double(local['valor']),
      'status': (local['status'] ?? 'Agendado').toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();

    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_agendamentos')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_agendamentos')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_agendamentos',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _baixarClientes(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final dados = await client
        .from('imperium_clientes')
        .select(
          'id,nome,telefone,email,endereco,observacoes,'
          'ativo,arquivado_em,excluido_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('nome');

    final database = await _appDatabase.database;

    for (final item in dados) {
      final remoto = Map<String, dynamic>.from(item);
      final remotoId = remoto['id'].toString();

      final mapa = await _mapaRemoto(
        'imperium_sync_clientes',
        empresaId,
        remotoId,
      );

      if (_nuloTexto(remoto['excluido_em']) != null) {
        if (mapa != null) {
          final localId = _int(mapa['local_id']);

          if (localId > 0) {
            await database.delete(
              'clientes',
              where: 'id = ?',
              whereArgs: [localId],
            );
          }

          await database.delete(
            'imperium_sync_clientes',
            where: 'empresa_id = ? AND remoto_id = ?',
            whereArgs: [empresaId, remotoId],
          );
        }
        continue;
      }

      final dadosLocais = <String, Object?>{
        'nome': (remoto['nome'] ?? '').toString(),
        'telefone': (remoto['telefone'] ?? '').toString(),
        'email': (remoto['email'] ?? '').toString(),
        'endereco': (remoto['endereco'] ?? '').toString(),
        'observacoes': (remoto['observacoes'] ?? '').toString(),
        'ativo': remoto['ativo'] == true ? 1 : 0,
        'arquivado_em': _nuloTexto(remoto['arquivado_em']),
      };

      final int localId;

      if (mapa == null) {
        localId = await database.insert(
          'clientes',
          dadosLocais,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        localId = _int(mapa['local_id']);

        if (localId <= 0) continue;

        await database.update(
          'clientes',
          dadosLocais,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashCliente({'id': localId, ...dadosLocais}),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  // sync-veiculo-anti-duplicacao-v1
  Future<int?> _veiculoLocalPorPlaca({
    required Database database,
    required int clienteLocalId,
    required dynamic placa,
  }) async {
    final normalizada = (placa ?? '')
        .toString()
        .trim()
        .toUpperCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');

    if (normalizada.isEmpty) return null;

    final rows = await database.rawQuery(
      '''
      SELECT id
      FROM veiculos
      WHERE cliente_id = ?
        AND UPPER(
          REPLACE(REPLACE(TRIM(COALESCE(placa, '')), '-', ''), ' ', '')
        ) = ?
      ORDER BY id ASC
      LIMIT 1
      ''',
      [clienteLocalId, normalizada],
    );

    if (rows.isEmpty) return null;
    final id = _int(rows.first['id']);
    return id > 0 ? id : null;
  }

  Future<void> _baixarVeiculos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final dados = await client
        .from('imperium_veiculos')
        .select(
          'id,cliente_id,marca,modelo,placa,cor,ano,observacoes,'
          'excluido_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('marca');

    final database = await _appDatabase.database;

    for (final item in dados) {
      final remoto = Map<String, dynamic>.from(item);
      final remotoId = remoto['id'].toString();

      final mapa = await _mapaRemoto(
        'imperium_sync_veiculos',
        empresaId,
        remotoId,
      );

      if (_nuloTexto(remoto['excluido_em']) != null) {
        if (mapa != null) {
          final localId = _int(mapa['local_id']);

          if (localId > 0) {
            await database.delete(
              'veiculos',
              where: 'id = ?',
              whereArgs: [localId],
            );
          }

          await database.delete(
            'imperium_sync_veiculos',
            where: 'empresa_id = ? AND remoto_id = ?',
            whereArgs: [empresaId, remotoId],
          );
        }
        continue;
      }

      final clienteLocalId = await _localPorRemoto(
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: remoto['cliente_id'].toString(),
      );

      if (clienteLocalId == null) continue;

      final dadosLocais = <String, Object?>{
        'cliente_id': clienteLocalId,
        'marca': (remoto['marca'] ?? '').toString(),
        'modelo': (remoto['modelo'] ?? '').toString(),
        'placa': (remoto['placa'] ?? '').toString(),
        'cor': (remoto['cor'] ?? '').toString(),
        'ano': (remoto['ano'] ?? '').toString(),
        'observacoes': (remoto['observacoes'] ?? '').toString(),
      };

      final int localId;

      if (mapa == null) {
        final porPlaca = await _veiculoLocalPorPlaca(
          database: database,
          clienteLocalId: clienteLocalId,
          placa: remoto['placa'],
        );

        if (porPlaca != null) {
          final mapaExistente = await _mapaLocal(
            'imperium_sync_veiculos',
            empresaId,
            porPlaca,
          );
          final outroRemotoId = (mapaExistente?['remoto_id'] ?? '')
              .toString()
              .trim();

          if (outroRemotoId.isNotEmpty && outroRemotoId != remotoId) {
            continue;
          }

          localId = porPlaca;
          await database.update(
            'veiculos',
            dadosLocais,
            where: 'id = ?',
            whereArgs: [localId],
          );
        } else {
          localId = await database.insert(
            'veiculos',
            dadosLocais,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      } else {
        localId = _int(mapa['local_id']);

        if (localId <= 0) continue;

        await database.update(
          'veiculos',
          dadosLocais,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashVeiculo({'id': localId, ...dadosLocais}),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _baixarAgendamentos(String empresaId) async {
    final client = _client;
    if (client == null) return;

    final dados = await client
        .from('imperium_agendamentos')
        .select(
          'id,cliente_id,veiculo_id,servico,data,hora,valor,status,'
          'observacoes,excluido_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('data')
        .order('hora');

    final database = await _appDatabase.database;

    for (final item in dados) {
      final remoto = Map<String, dynamic>.from(item);
      final remotoId = remoto['id'].toString();

      final mapa = await _mapaRemoto(
        'imperium_sync_agendamentos',
        empresaId,
        remotoId,
      );

      if (_nuloTexto(remoto['excluido_em']) != null) {
        if (mapa != null) {
          final localId = _int(mapa['local_id']);

          if (localId > 0) {
            await database.delete(
              'agendamentos',
              where: 'id = ?',
              whereArgs: [localId],
            );
          }

          await database.delete(
            'imperium_sync_agendamentos',
            where: 'empresa_id = ? AND remoto_id = ?',
            whereArgs: [empresaId, remotoId],
          );
        }
        continue;
      }

      final clienteLocalId = await _localPorRemoto(
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: remoto['cliente_id'].toString(),
      );

      final veiculoLocalId = await _localPorRemoto(
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        remotoId: remoto['veiculo_id'].toString(),
      );

      if (clienteLocalId == null || veiculoLocalId == null) continue;

      final dadosLocais = <String, Object?>{
        'cliente_id': clienteLocalId,
        'veiculo_id': veiculoLocalId,
        'servico': (remoto['servico'] ?? '').toString(),
        'data': (remoto['data'] ?? '').toString(),
        'hora': (remoto['hora'] ?? '').toString(),
        'valor': _double(remoto['valor']),
        'status': (remoto['status'] ?? 'Agendado').toString(),
        'observacoes': (remoto['observacoes'] ?? '').toString(),
      };

      final int localId;

      if (mapa == null) {
        localId = await database.insert(
          'agendamentos',
          dadosLocais,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        localId = _int(mapa['local_id']);

        if (localId <= 0) continue;

        await database.update(
          'agendamentos',
          dadosLocais,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      await _salvarMapa(
        tabela: 'imperium_sync_agendamentos',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashAgendamento({'id': localId, ...dadosLocais}),
        remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
      );
    }
  }

  Future<void> _sincronizarPontoFuncionario() async {
    final database = await _appDatabase.database;

    final tabela = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = 'imperium_dispositivo_acesso'
      LIMIT 1
    ''');

    if (tabela.isEmpty) return;

    final dispositivo = await database.query(
      'imperium_dispositivo_acesso',
      where: 'id = 1 AND modo = ?',
      whereArgs: ['funcionario'],
      limit: 1,
    );

    if (dispositivo.isEmpty) return;

    final colaboradorLocalId = _int(dispositivo.first['colaborador_local_id']);

    if (colaboradorLocalId <= 0) return;

    try {
      final estado = await PontoNuvemService.instance.obterEstadoMigracao();

      if (estado['migracao_concluida'] != true) return;

      final agora = DateTime.now();

      await PontoNuvemService.instance.sincronizarPeriodo(
        colaboradorLocalId: colaboradorLocalId,
        inicio: DateTime(agora.year, agora.month, 1),
        fim: DateTime(agora.year, agora.month + 1, 0),
      );
    } catch (_) {
      // Meu Ponto também sincroniza quando for aberto.
    }
  }

  Future<Map<String, Object?>?> _mapaLocal(
    String tabela,
    String empresaId,
    int localId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      tabela,
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return Map<String, Object?>.from(resultado.first);
  }

  Future<Map<String, Object?>?> _mapaRemoto(
    String tabela,
    String empresaId,
    String remotoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      tabela,
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return Map<String, Object?>.from(resultado.first);
  }

  Future<String?> _remotoPorLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final mapa = await _mapaLocal(tabela, empresaId, localId);
    final id = (mapa?['remoto_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<int?> _localPorRemoto({
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    final mapa = await _mapaRemoto(tabela, empresaId, remotoId);
    final id = _int(mapa?['local_id']);
    return id <= 0 ? null : id;
  }

  Future<void> _salvarMapa({
    required String tabela,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    required String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(tabela, {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String _hashCliente(Map<String, Object?> item) {
    return _hash([
      (item['nome'] ?? '').toString(),
      (item['telefone'] ?? '').toString(),
      (item['email'] ?? '').toString(),
      (item['endereco'] ?? '').toString(),
      (item['observacoes'] ?? '').toString(),
      _int(item['ativo']) != 0,
      _nuloTexto(item['arquivado_em']),
    ]);
  }

  String _hashVeiculo(Map<String, Object?> item) {
    return _hash([
      _int(item['cliente_id']),
      (item['marca'] ?? '').toString(),
      (item['modelo'] ?? '').toString(),
      (item['placa'] ?? '').toString(),
      (item['cor'] ?? '').toString(),
      (item['ano'] ?? '').toString(),
      (item['observacoes'] ?? '').toString(),
    ]);
  }

  String _hashAgendamento(Map<String, Object?> item) {
    return _hash([
      _int(item['cliente_id']),
      _int(item['veiculo_id']),
      (item['servico'] ?? '').toString(),
      (item['data'] ?? '').toString(),
      (item['hora'] ?? '').toString(),
      _double(item['valor']).toStringAsFixed(2),
      (item['status'] ?? '').toString(),
      (item['observacoes'] ?? '').toString(),
    ]);
  }

  String _hash(List<Object?> valores) {
    return sha256.convert(utf8.encode(jsonEncode(valores))).toString();
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String? _nuloTexto(dynamic valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }
}
