import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Etapa 4 - OS Cloud.
///
/// Subetapa V1 propositalmente upload-only:
/// - publica a OS e seus itens/servicos;
/// - nao baixa OS para outro dispositivo;
/// - nao publica pagamentos, produtos, fotos ou assinatura local.
class OsCloudUploadService {
  OsCloudUploadService._();

  static final OsCloudUploadService instance = OsCloudUploadService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // os-cloud-upload-service-v1
  Future<void> sincronizarUpload(String empresaId) async {
    if (empresaId.trim().isEmpty || _client == null) return;

    await garantirEstruturaLocal();
    await _publicarOrdensServicoLocais(empresaId);
    await _publicarItensOrdensServicoLocais(empresaId);
  }

  // os-cloud-upload-mapas-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_ordens_servico (
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
      CREATE TABLE IF NOT EXISTS imperium_sync_ordem_servico_itens (
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

  Future<void> _publicarOrdensServicoLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('ordens_servico');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashOrdemServico(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarOrdemServico(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }

    await _marcarAusentesComoExcluidos(
      empresaId: empresaId,
      tabelaLocal: 'ordens_servico',
      tabelaMapa: 'imperium_sync_ordens_servico',
      tabelaRemota: 'imperium_ordens_servico',
    );
  }

  Future<void> _publicarOrdemServico({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final clienteLocalId = _int(local['cliente_id']);
    if (clienteLocalId <= 0) {
      throw StateError('Cliente inválido na OS #$localId.');
    }

    final clienteRemotoId = await _remotoPorLocal(
      tabela: 'imperium_sync_clientes',
      empresaId: empresaId,
      localId: clienteLocalId,
    );

    if (clienteRemotoId == null) {
      throw StateError('Cliente da OS #$localId ainda não foi sincronizado.');
    }

    String? veiculoRemotoId;
    final veiculoLocalId = _int(local['veiculo_id']);
    if (veiculoLocalId > 0) {
      veiculoRemotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        localId: veiculoLocalId,
      );

      if (veiculoRemotoId == null) {
        throw StateError('Veículo da OS #$localId ainda não foi sincronizado.');
      }
    }

    String? agendamentoRemotoId;
    final agendamentoLocalId = _int(local['agendamento_id']);
    if (agendamentoLocalId > 0) {
      agendamentoRemotoId = await _remotoPorLocal(
        tabela: 'imperium_sync_agendamentos',
        empresaId: empresaId,
        localId: agendamentoLocalId,
      );

      if (agendamentoRemotoId == null) {
        throw StateError(
          'Agendamento da OS #$localId ainda não foi sincronizado.',
        );
      }
    }

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteRemotoId,
      'veiculo_id': veiculoRemotoId,
      'agendamento_id': agendamentoRemotoId,
      'numero': (local['numero'] ?? '').toString(),
      'status': (local['status'] ?? 'Aberta').toString(),
      'data_abertura': (local['data_abertura'] ?? '').toString(),
      'data_inicio': _nuloTexto(local['data_inicio']),
      'data_finalizacao': _nuloTexto(local['data_finalizacao']),
      'hora_entrada': _nuloTexto(local['hora_entrada']),
      'hora_saida': _nuloTexto(local['hora_saida']),
      'funcionario_responsavel': (local['funcionario_responsavel'] ?? '')
          .toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'valor_total': _double(local['valor_total']),
      'desconto': _double(local['desconto']),
      'forma_pagamento': _nuloTexto(local['forma_pagamento']),
      'quilometragem_entrada': (local['quilometragem_entrada'] ?? '')
          .toString(),
      'combustivel_entrada': (local['combustivel_entrada'] ?? '').toString(),
      'revisada_em': _nuloTexto(local['revisada_em']),
      'motivo_ultima_revisao': (local['motivo_ultima_revisao'] ?? '')
          .toString(),
      'quantidade_revisoes': _int(local['quantidade_revisoes']),
      'assinatura_desatualizada': _int(local['assinatura_desatualizada']) != 0,
      'status_pagamento': (local['status_pagamento'] ?? 'Pendente').toString(),
      'valor_recebido': _double(local['valor_recebido']),
      'vencimento_pagamento': _nuloTexto(local['vencimento_pagamento']),
      'pagamento_atualizado_em': _nuloTexto(local['pagamento_atualizado_em']),
      'desconto_negociacao': _double(local['desconto_negociacao']),
      'acrescimo_negociacao': _double(local['acrescimo_negociacao']),
      'juros_parcelamento': _double(local['juros_parcelamento']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_ordens_servico')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_ordens_servico')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_ordens_servico',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarItensOrdensServicoLocais(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('ordem_servico_itens');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashOrdemServicoItem(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_ordem_servico_itens',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarOrdemServicoItem(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }

    await _marcarAusentesComoExcluidos(
      empresaId: empresaId,
      tabelaLocal: 'ordem_servico_itens',
      tabelaMapa: 'imperium_sync_ordem_servico_itens',
      tabelaRemota: 'imperium_ordem_servico_itens',
    );
  }

  Future<void> _publicarOrdemServicoItem({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final ordemLocalId = _int(local['ordem_servico_id']);
    if (ordemLocalId <= 0) {
      throw StateError('OS inválida no item #$localId.');
    }

    final ordemRemotaId = await _remotoPorLocal(
      tabela: 'imperium_sync_ordens_servico',
      empresaId: empresaId,
      localId: ordemLocalId,
    );

    if (ordemRemotaId == null) {
      throw StateError('OS do item #$localId ainda não foi sincronizada.');
    }

    final dispositivoId = await _dispositivoId();

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'ordem_servico_id': ordemRemotaId,
      'servico': (local['servico'] ?? '').toString(),
      'descricao': (local['descricao'] ?? '').toString(),
      'quantidade': _double(local['quantidade']),
      'valor_unitario': _double(local['valor_unitario']),
      'concluido': _int(local['concluido']) != 0,
      'ordem': _int(local['ordem']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = dispositivoId;
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_ordem_servico_itens')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_ordem_servico_itens')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();

      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_ordem_servico_itens',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  // Quando a edicao local recria itens com novos IDs, os IDs antigos
  // sao apenas marcados como excluidos na nuvem. Nada e apagado fisicamente.
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
      if ((mapa['local_hash'] ?? '').toString() == '__excluido__') continue;

      final localId = _int(mapa['local_id']);
      final remotoId = (mapa['remoto_id'] ?? '').toString().trim();
      if (localId <= 0 || remotoId.isEmpty) continue;

      final local = await database.query(
        tabelaLocal,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (local.isNotEmpty) continue;

      final agora = DateTime.now().toIso8601String();

      await client
          .from(tabelaRemota)
          .update({'excluido_em': agora})
          .eq('empresa_id', empresaId)
          .eq('id', remotoId);

      await database.update(
        tabelaMapa,
        {'local_hash': '__excluido__', 'remoto_atualizado_em': agora},
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
    }
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (resultado.isEmpty) {
      throw StateError(
        'Identificador do dispositivo ainda não foi preparado pelo sync.',
      );
    }

    final id = (resultado.first['dispositivo_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo está vazio.');
    }

    return id;
  }

  Future<Map<String, Object?>?> _mapaLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
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

  Future<String?> _remotoPorLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;

    final mapa = await _mapaLocal(
      tabela: tabela,
      empresaId: empresaId,
      localId: localId,
    );

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    return remotoId.isEmpty ? null : remotoId;
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

  String _hashOrdemServico(Map<String, Object?> item) {
    return _hash([
      _int(item['cliente_id']),
      _int(item['veiculo_id']),
      _int(item['agendamento_id']),
      (item['numero'] ?? '').toString(),
      (item['status'] ?? '').toString(),
      (item['data_abertura'] ?? '').toString(),
      _nuloTexto(item['data_inicio']),
      _nuloTexto(item['data_finalizacao']),
      _nuloTexto(item['hora_entrada']),
      _nuloTexto(item['hora_saida']),
      (item['funcionario_responsavel'] ?? '').toString(),
      (item['observacoes'] ?? '').toString(),
      _double(item['valor_total']).toStringAsFixed(2),
      _double(item['desconto']).toStringAsFixed(2),
      _nuloTexto(item['forma_pagamento']),
      (item['quilometragem_entrada'] ?? '').toString(),
      (item['combustivel_entrada'] ?? '').toString(),
      _nuloTexto(item['revisada_em']),
      (item['motivo_ultima_revisao'] ?? '').toString(),
      _int(item['quantidade_revisoes']),
      _int(item['assinatura_desatualizada']) != 0,
      (item['status_pagamento'] ?? '').toString(),
      _double(item['valor_recebido']).toStringAsFixed(2),
      _nuloTexto(item['vencimento_pagamento']),
      _nuloTexto(item['pagamento_atualizado_em']),
      _double(item['desconto_negociacao']).toStringAsFixed(2),
      _double(item['acrescimo_negociacao']).toStringAsFixed(2),
      _double(item['juros_parcelamento']).toStringAsFixed(2),
    ]);
  }

  String _hashOrdemServicoItem(Map<String, Object?> item) {
    return _hash([
      _int(item['ordem_servico_id']),
      (item['servico'] ?? '').toString(),
      (item['descricao'] ?? '').toString(),
      _double(item['quantidade']).toStringAsFixed(6),
      _double(item['valor_unitario']).toStringAsFixed(2),
      _int(item['concluido']) != 0,
      _int(item['ordem']),
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
