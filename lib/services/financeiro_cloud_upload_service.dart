import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Financeiro Cloud V1.
///
/// Upload-only e conservador:
/// plano de contas -> contas -> pagamentos da OS -> movimentos.
///
/// O V1 nao baixa dados financeiros e nao altera saldo/DRE local.
class FinanceiroCloudUploadService {
  FinanceiroCloudUploadService._();

  static final FinanceiroCloudUploadService instance =
      FinanceiroCloudUploadService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // financeiro-cloud-upload-v1
  Future<void> sincronizarUpload(String empresaId) async {
    if (empresaId.trim().isEmpty || _client == null) return;

    try {
      await garantirEstruturaLocal();
      await _publicarPlanoContas(empresaId);
      await _publicarContas(empresaId);
      await _publicarPagamentos(empresaId);
      await _publicarMovimentos(empresaId);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  // financeiro-cloud-mapas-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    for (final tabela in <String>[
      'imperium_sync_financeiro_plano_contas',
      'imperium_sync_financeiro_contas',
      'imperium_sync_financeiro_pagamentos',
      'imperium_sync_financeiro_movimentos',
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
  }

  Future<void> _publicarPlanoContas(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'financeiro_plano_contas',
      orderBy: 'ordem ASC, codigo ASC, id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashPlano(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_plano_contas',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarPlano(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarPlano({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final database = await _appDatabase.database;
    final parentLocalId = _int(local['parent_id']);
    String? parentCodigo;

    if (parentLocalId > 0) {
      final parent = await database.query(
        'financeiro_plano_contas',
        columns: ['codigo'],
        where: 'id = ?',
        whereArgs: [parentLocalId],
        limit: 1,
      );
      if (parent.isNotEmpty) {
        parentCodigo = _textoNulo(parent.first['codigo']);
      }
    }

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'codigo': (local['codigo'] ?? '').toString(),
      'nome': (local['nome'] ?? '').toString(),
      'tipo': (local['tipo'] ?? '').toString(),
      'natureza': (local['natureza'] ?? '').toString(),
      'grupo_dre': (local['grupo_dre'] ?? 'Não DRE').toString(),
      'parent_codigo': parentCodigo,
      'ativo': _int(local['ativo']) != 0,
      'ordem': _int(local['ordem']),
      'origem_criado_em': _textoNulo(local['criado_em']),
      'origem_atualizado_em': _textoNulo(local['atualizado_em']),
      'excluido_em': null,
    };

    var remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      final existente = await client
          .from('imperium_financeiro_plano_contas')
          .select('id,atualizado_em')
          .eq('empresa_id', empresaId)
          .eq('codigo', payload['codigo'])
          .maybeSingle();

      if (existente != null) {
        remotoId = existente['id'].toString();
        final resposta = await client
            .from('imperium_financeiro_plano_contas')
            .update(payload)
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .select('id,atualizado_em')
            .single();
        remoto = Map<String, dynamic>.from(resposta);
      } else {
        payload['origem_dispositivo'] = await _dispositivoId();
        payload['origem_local_id'] = localId;

        final resposta = await client
            .from('imperium_financeiro_plano_contas')
            .insert(payload)
            .select('id,atualizado_em')
            .single();
        remoto = Map<String, dynamic>.from(resposta);
      }
    } else {
      final resposta = await client
          .from('imperium_financeiro_plano_contas')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_financeiro_plano_contas',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarContas(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query('financeiro_contas', orderBy: 'id ASC');

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final hash = _hashConta(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_contas',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarConta(
          empresaId: empresaId,
          localId: localId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarConta({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'nome': (local['nome'] ?? '').toString(),
      'tipo': (local['tipo'] ?? 'Conta bancária').toString(),
      'instituicao': (local['instituicao'] ?? '').toString(),
      'saldo_inicial': _double(local['saldo_inicial']),
      'data_saldo_inicial': _textoNulo(local['data_saldo_inicial']),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'ativo': _int(local['ativo']) != 0,
      'origem_criado_em': _textoNulo(local['criado_em']),
      'origem_atualizado_em': _textoNulo(local['atualizado_em']),
      'excluido_em': null,
    };

    var remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      final existente = await client
          .from('imperium_financeiro_contas')
          .select('id,atualizado_em')
          .eq('empresa_id', empresaId)
          .eq('nome', payload['nome'])
          .maybeSingle();

      if (existente != null) {
        remotoId = existente['id'].toString();
        final resposta = await client
            .from('imperium_financeiro_contas')
            .update(payload)
            .eq('empresa_id', empresaId)
            .eq('id', remotoId)
            .select('id,atualizado_em')
            .single();
        remoto = Map<String, dynamic>.from(resposta);
      } else {
        payload['origem_dispositivo'] = await _dispositivoId();
        payload['origem_local_id'] = localId;

        final resposta = await client
            .from('imperium_financeiro_contas')
            .insert(payload)
            .select('id,atualizado_em')
            .single();
        remoto = Map<String, dynamic>.from(resposta);
      }
    } else {
      final resposta = await client
          .from('imperium_financeiro_contas')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_financeiro_contas',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarPagamentos(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'ordem_servico_pagamentos',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final ordemLocalId = _int(local['ordem_servico_id']);
      if (ordemLocalId <= 0) continue;

      final ordemRemotaId = await _remotoPorLocal(
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: ordemLocalId,
      );
      if (ordemRemotaId == null) continue;

      final hash = _hashPagamento(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_pagamentos',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarPagamento(
          empresaId: empresaId,
          localId: localId,
          ordemRemotaId: ordemRemotaId,
          local: local,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<void> _publicarPagamento({
    required String empresaId,
    required int localId,
    required String ordemRemotaId,
    required Map<String, Object?> local,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'ordem_servico_id': ordemRemotaId,
      'status': (local['status'] ?? 'Pago').toString(),
      'valor': _double(local['valor']),
      'forma_pagamento': (local['forma_pagamento'] ?? '').toString(),
      'data_pagamento': _textoNulo(local['data_pagamento']),
      'parcela_numero': _intNulo(local['parcela_numero']),
      'total_parcelas': _intNulo(local['total_parcelas']),
      'vencimento': _textoNulo(local['vencimento']),
      'comprovante_origem_caminho': _textoNulo(local['comprovante_caminho']),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'taxa_percentual': _doubleNulo(local['taxa_percentual']),
      'taxa_operacao': _double(local['taxa_operacao']),
      'valor_liquido': _double(local['valor_liquido']),
      'origem_regra_taxa_local_id': _intNulo(local['regra_taxa_id']),
      'parcelas_taxa': _int(local['parcelas_taxa']) <= 0
          ? 1
          : _int(local['parcelas_taxa']),
      'estornado_em': _textoNulo(local['estornado_em']),
      'motivo_estorno': (local['motivo_estorno'] ?? '').toString(),
      'origem_criado_em': _textoNulo(local['criado_em']),
      'origem_atualizado_em': _textoNulo(local['atualizado_em']),
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_financeiro_pagamentos_os')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_financeiro_pagamentos_os')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_financeiro_pagamentos',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<void> _publicarMovimentos(String empresaId) async {
    final database = await _appDatabase.database;
    final locais = await database.query(
      'movimentos_financeiros',
      orderBy: 'id ASC',
    );

    for (final local in locais) {
      final localId = _int(local['id']);
      if (localId <= 0) continue;

      final dependencias = await _dependenciasMovimento(
        empresaId: empresaId,
        local: local,
      );
      if (dependencias == null) continue;

      final hash = _hashMovimento(local);
      final mapa = await _mapaLocal(
        tabela: 'imperium_sync_financeiro_movimentos',
        empresaId: empresaId,
        localId: localId,
      );

      if (mapa == null || (mapa['local_hash'] ?? '').toString() != hash) {
        await _publicarMovimento(
          empresaId: empresaId,
          localId: localId,
          local: local,
          dependencias: dependencias,
          mapa: mapa,
          hash: hash,
        );
      }
    }
  }

  Future<Map<String, String?>?> _dependenciasMovimento({
    required String empresaId,
    required Map<String, Object?> local,
  }) async {
    Future<String?> resolver(
      String tabelaMapa,
      Object? valor, {
      bool obrigatorio = true,
    }) async {
      final localId = _int(valor);
      if (localId <= 0) return null;

      final remoto = await _remotoPorLocal(
        tabela: tabelaMapa,
        empresaId: empresaId,
        localId: localId,
      );

      if (obrigatorio && remoto == null) {
        throw _DependenciaFinanceiraPendente();
      }

      return remoto;
    }

    try {
      return <String, String?>{
        'cliente_id': await resolver(
          'imperium_sync_clientes',
          local['cliente_id'],
        ),
        'agendamento_id': await resolver(
          'imperium_sync_agendamentos',
          local['agendamento_id'],
        ),
        'ordem_servico_id': await resolver(
          'imperium_sync_ordens_servico',
          local['ordem_servico_id'],
        ),
        'pagamento_id': await resolver(
          'imperium_sync_financeiro_pagamentos',
          local['pagamento_id'],
        ),
        'plano_conta_id': await resolver(
          'imperium_sync_financeiro_plano_contas',
          local['plano_conta_id'],
        ),
        'conta_id': await resolver(
          'imperium_sync_financeiro_contas',
          local['conta_id'],
        ),
      };
    } on _DependenciaFinanceiraPendente {
      return null;
    }
  }

  Future<void> _publicarMovimento({
    required String empresaId,
    required int localId,
    required Map<String, Object?> local,
    required Map<String, String?> dependencias,
    required Map<String, Object?>? mapa,
    required String hash,
  }) async {
    final client = _client;
    if (client == null) return;

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'tipo': (local['tipo'] ?? '').toString(),
      'descricao': (local['descricao'] ?? '').toString(),
      'valor': _double(local['valor']),
      'forma_pagamento': _textoNulo(local['forma_pagamento']),
      'data': (local['data'] ?? '').toString(),
      ...dependencias,
      'origem_cliente_local_id': _intNulo(local['cliente_id']),
      'origem_agendamento_local_id': _intNulo(local['agendamento_id']),
      'origem_ordem_servico_local_id': _intNulo(local['ordem_servico_id']),
      'origem_pagamento_local_id': _intNulo(local['pagamento_id']),
      'origem_plano_conta_local_id': _intNulo(local['plano_conta_id']),
      'origem_conta_local_id': _intNulo(local['conta_id']),
      'origem_fornecedor_local_id': _intNulo(local['fornecedor_id']),
      'origem_transferencia_local_id': _intNulo(local['transferencia_id']),
      'origem_nota_fiscal_local_id': _intNulo(local['nota_fiscal_id']),
      'parcela_numero': _intNulo(local['parcela_numero']),
      'total_parcelas': _int(local['total_parcelas']) <= 0
          ? 1
          : _int(local['total_parcelas']),
      'natureza': (local['natureza'] ?? 'Não classificado').toString(),
      'origem': (local['origem'] ?? 'Manual').toString(),
      'status': (local['status'] ?? 'Realizado').toString(),
      'data_competencia': _textoNulo(local['data_competencia']),
      'data_vencimento': _textoNulo(local['data_vencimento']),
      'data_pagamento': _textoNulo(local['data_pagamento']),
      'numero_documento': (local['numero_documento'] ?? '').toString(),
      'observacoes': (local['observacoes'] ?? '').toString(),
      'impacta_dre': _int(local['impacta_dre']) != 0,
      'excluido_em': null,
    };

    final remotoId = (mapa?['remoto_id'] ?? '').toString().trim();
    final Map<String, dynamic> remoto;

    if (remotoId.isEmpty) {
      payload['origem_dispositivo'] = await _dispositivoId();
      payload['origem_local_id'] = localId;

      final resposta = await client
          .from('imperium_financeiro_movimentos')
          .upsert(
            payload,
            onConflict: 'empresa_id,origem_dispositivo,origem_local_id',
          )
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    } else {
      final resposta = await client
          .from('imperium_financeiro_movimentos')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .select('id,atualizado_em')
          .single();
      remoto = Map<String, dynamic>.from(resposta);
    }

    await _salvarMapa(
      tabela: 'imperium_sync_financeiro_movimentos',
      empresaId: empresaId,
      localId: localId,
      remotoId: remoto['id'].toString(),
      localHash: hash,
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<Map<String, Object?>?> _mapaLocal({
    required String tabela,
    required String empresaId,
    required int localId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabela,
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
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

    if (mapa == null) return null;

    final remoto = (mapa['remoto_id'] ?? '').toString().trim();
    return remoto.isEmpty ? null : remoto;
  }

  Future<void> _salvarMapa({
    required String tabela,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    String? remotoAtualizadoEm,
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

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Configuração de sincronização não encontrada.');
    }

    final id = (rows.first['dispositivo_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw StateError('Identificador do dispositivo não encontrado.');
    }

    return id;
  }

  String _hashPlano(Map<String, Object?> local) {
    return _hash(<Object?>[
      local['codigo'],
      local['nome'],
      local['tipo'],
      local['natureza'],
      local['grupo_dre'],
      _intNulo(local['parent_id']),
      _int(local['ativo']),
      _int(local['ordem']),
      local['criado_em'],
      local['atualizado_em'],
    ]);
  }

  String _hashConta(Map<String, Object?> local) {
    return _hash(<Object?>[
      local['nome'],
      local['tipo'],
      local['instituicao'],
      _double(local['saldo_inicial']),
      local['data_saldo_inicial'],
      local['observacoes'],
      _int(local['ativo']),
      local['criado_em'],
      local['atualizado_em'],
    ]);
  }

  String _hashPagamento(Map<String, Object?> local) {
    return _hash(<Object?>[
      _int(local['ordem_servico_id']),
      local['status'],
      _double(local['valor']),
      local['forma_pagamento'],
      local['data_pagamento'],
      _intNulo(local['parcela_numero']),
      _intNulo(local['total_parcelas']),
      local['vencimento'],
      local['comprovante_caminho'],
      local['observacoes'],
      _doubleNulo(local['taxa_percentual']),
      _double(local['taxa_operacao']),
      _double(local['valor_liquido']),
      _intNulo(local['regra_taxa_id']),
      _int(local['parcelas_taxa']),
      local['estornado_em'],
      local['motivo_estorno'],
      local['criado_em'],
      local['atualizado_em'],
    ]);
  }

  String _hashMovimento(Map<String, Object?> local) {
    return _hash(<Object?>[
      local['tipo'],
      local['descricao'],
      _double(local['valor']),
      local['forma_pagamento'],
      local['data'],
      _intNulo(local['cliente_id']),
      _intNulo(local['agendamento_id']),
      _intNulo(local['ordem_servico_id']),
      _intNulo(local['pagamento_id']),
      _intNulo(local['plano_conta_id']),
      _intNulo(local['conta_id']),
      _intNulo(local['fornecedor_id']),
      _intNulo(local['transferencia_id']),
      _intNulo(local['nota_fiscal_id']),
      _intNulo(local['parcela_numero']),
      _int(local['total_parcelas']),
      local['natureza'],
      local['origem'],
      local['status'],
      local['data_competencia'],
      local['data_vencimento'],
      local['data_pagamento'],
      local['numero_documento'],
      local['observacoes'],
      _int(local['impacta_dre']),
    ]);
  }

  String _hash(List<Object?> values) {
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static int? _intNulo(Object? value) {
    final result = _int(value);
    return result <= 0 ? null : result;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static double? _doubleNulo(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final text = value.toString().trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String? _textoNulo(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}

class _DependenciaFinanceiraPendente implements Exception {}
