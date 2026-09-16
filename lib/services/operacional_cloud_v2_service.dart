import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Proteção de concorrência para o núcleo operacional (Clientes, Veículos e
/// Agenda).
///
/// O mapa local/remoto já guardava `local_hash` e `remoto_atualizado_em`, mas
/// até a V1 eles eram usados apenas para decidir se havia upload. Isso podia
/// fazer um aparelho sobrescrever silenciosamente uma edição mais nova feita
/// em outro dispositivo.
///
/// Regras V2:
/// - local mudou e remoto não mudou: upload normal pode seguir;
/// - local não mudou e remoto mudou: a versão remota é aplicada localmente;
/// - ambos mudaram: registra conflito e bloqueia o módulo Operacional;
/// - exclusão remota concorrente também vira conflito;
/// - resolver "usar nuvem" aplica a versão remota e atualiza o baseline;
/// - resolver "usar aparelho" usa CAS por `atualizado_em`; se a nuvem mudar
///   novamente durante a decisão, a resolução é recusada.
class OperacionalCloudV2Service {
  OperacionalCloudV2Service._();

  static final OperacionalCloudV2Service instance =
      OperacionalCloudV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // operacional-cloud-conflitos-v2
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_operacional_conflitos (
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
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_operacional_conflitos_pendentes
      ON imperium_sync_operacional_conflitos (
        empresa_id,
        entidade,
        status,
        local_id
      )
    ''');
  }

  Future<bool> prepararUpload(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return true;

    await garantirEstruturaLocal();

    try {
      await _reconciliarEntidade(
        empresaId: empresaId,
        entidade: 'cliente',
        tabelaLocal: 'clientes',
        tabelaMapa: 'imperium_sync_clientes',
        tabelaRemota: 'imperium_clientes',
        hashLocal: _hashCliente,
      );
      await _reconciliarEntidade(
        empresaId: empresaId,
        entidade: 'veiculo',
        tabelaLocal: 'veiculos',
        tabelaMapa: 'imperium_sync_veiculos',
        tabelaRemota: 'imperium_veiculos',
        hashLocal: _hashVeiculo,
      );
      await _reconciliarEntidade(
        empresaId: empresaId,
        entidade: 'agendamento',
        tabelaLocal: 'agendamentos',
        tabelaMapa: 'imperium_sync_agendamentos',
        tabelaRemota: 'imperium_agendamentos',
        hashLocal: _hashAgendamento,
      );
    } on PostgrestException catch (error) {
      // Sem acesso ao módulo, o serviço base preserva o comportamento
      // offline-first e deixa o RLS decidir o que o usuário pode enxergar.
      if (error.code != '42501') rethrow;
    }

    return !await possuiConflitosPendentes(empresaId);
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_operacional_conflitos',
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
      'imperium_sync_operacional_conflitos',
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
      return _int(rows.firstOrNull?['total']);
    }

    final conflitos = await database.rawQuery(
      '''
      SELECT entidade, COUNT(*) AS total
      FROM imperium_sync_operacional_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      GROUP BY entidade
      ''',
      [empresaId],
    );

    return <String, Object?>{
      'empresa_id': empresaId,
      'clientes_mapeados': await contar('imperium_sync_clientes'),
      'veiculos_mapeados': await contar('imperium_sync_veiculos'),
      'agendamentos_mapeados': await contar('imperium_sync_agendamentos'),
      'conflitos_pendentes': conflitos.fold<int>(
        0,
        (total, item) => total + _int(item['total']),
      ),
      'conflitos_clientes': _totalEntidade(conflitos, 'cliente'),
      'conflitos_veiculos': _totalEntidade(conflitos, 'veiculo'),
      'conflitos_agenda': _totalEntidade(conflitos, 'agendamento'),
    };
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    if (conflito == null) return;

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível para resolver o conflito.');
    }

    final empresaId = (conflito['empresa_id'] ?? '').toString();
    final entidade = (conflito['entidade'] ?? '').toString();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString();
    final spec = _spec(entidade);

    final remotoRaw = await client
        .from(spec.tabelaRemota)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    if (remotoRaw == null) {
      throw StateError(
        'O registro remoto não existe mais. Sincronize novamente.',
      );
    }

    await _aplicarRemoto(
      empresaId: empresaId,
      spec: spec,
      localId: localId,
      remoto: Map<String, dynamic>.from(remotoRaw),
    );
    await _marcarResolvido(conflitoId, 'Nuvem');
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    if (conflito == null) return;

    final client = _client;
    if (client == null) {
      throw StateError('Supabase indisponível para resolver o conflito.');
    }

    final empresaId = (conflito['empresa_id'] ?? '').toString();
    final entidade = (conflito['entidade'] ?? '').toString();
    final localId = _int(conflito['local_id']);
    final remotoId = (conflito['remoto_id'] ?? '').toString();
    final remotoEsperado = (conflito['remoto_atualizado_atual'] ?? '')
        .toString()
        .trim();
    final spec = _spec(entidade);
    final database = await _appDatabase.database;

    final locais = await database.query(
      spec.tabelaLocal,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (locais.isEmpty) {
      throw StateError('O registro local não existe mais.');
    }

    final local = Map<String, Object?>.from(locais.first);
    final payload = await _payloadLocal(
      empresaId: empresaId,
      entidade: entidade,
      local: local,
    );

    var query = client
        .from(spec.tabelaRemota)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', remotoId);

    if (remotoEsperado.isNotEmpty) {
      query = query.eq('atualizado_em', remotoEsperado);
    }

    final atualizadoRaw = await query.select('id,atualizado_em').maybeSingle();

    if (atualizadoRaw == null) {
      await _atualizarSnapshotConflito(conflitoId, empresaId, spec, remotoId);
      throw StateError(
        'A versão na nuvem mudou novamente. Revise o conflito antes de salvar.',
      );
    }

    final atualizado = Map<String, dynamic>.from(atualizadoRaw);
    await _salvarMapa(
      tabelaMapa: spec.tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: spec.hashLocal(local),
      remotoAtualizadoEm: atualizado['atualizado_em']?.toString(),
    );
    await _marcarResolvido(conflitoId, 'Aparelho');
  }

  Future<void> _reconciliarEntidade({
    required String empresaId,
    required String entidade,
    required String tabelaLocal,
    required String tabelaMapa,
    required String tabelaRemota,
    required String Function(Map<String, Object?>) hashLocal,
  }) async {
    final client = _client;
    if (client == null) return;
    final database = await _appDatabase.database;

    final mapas = await database.query(
      tabelaMapa,
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    final spec = _OperacionalSpec(
      entidade: entidade,
      tabelaLocal: tabelaLocal,
      tabelaMapa: tabelaMapa,
      tabelaRemota: tabelaRemota,
      hashLocal: hashLocal,
    );

    for (final mapa in mapas) {
      final localId = _int(mapa['local_id']);
      final remotoId = (mapa['remoto_id'] ?? '').toString().trim();
      if (localId <= 0 || remotoId.isEmpty) continue;

      if (await _temConflito(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
        remotoId: remotoId,
      )) {
        continue;
      }

      final locais = await database.query(
        tabelaLocal,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (locais.isEmpty) continue;

      final local = Map<String, Object?>.from(locais.first);
      final localBase = (mapa['local_hash'] ?? '').toString();
      final localAtual = hashLocal(local);
      final localMudou = localBase != localAtual;

      final remotoRaw = await client
          .from(tabelaRemota)
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', remotoId)
          .maybeSingle();

      if (remotoRaw == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'remoto_ausente',
          mapa: mapa,
          localHashAtual: localAtual,
          local: local,
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final remotoBase = (mapa['remoto_atualizado_em'] ?? '').toString().trim();
      final remotoAtual = (remoto['atualizado_em'] ?? '').toString().trim();
      final remotoExcluido = _texto(remoto['excluido_em']).isNotEmpty;
      final remotoMudou =
          remotoExcluido ||
          remotoBase.isEmpty ||
          remotoAtual.isEmpty ||
          remotoAtual != remotoBase;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: remotoExcluido
              ? 'alteracao_local_e_exclusao_remota'
              : 'alteracao_concorrente',
          mapa: mapa,
          localHashAtual: localAtual,
          local: local,
          remoto: remoto,
        );
        continue;
      }

      if (!localMudou && remotoMudou) {
        await _aplicarRemoto(
          empresaId: empresaId,
          spec: spec,
          localId: localId,
          remoto: remoto,
        );
      }
    }
  }

  Future<void> _aplicarRemoto({
    required String empresaId,
    required _OperacionalSpec spec,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final remotoId = (remoto['id'] ?? '').toString();
    final excluido = _texto(remoto['excluido_em']).isNotEmpty;

    if (excluido) {
      await database.delete(
        spec.tabelaLocal,
        where: 'id = ?',
        whereArgs: [localId],
      );
      await database.delete(
        spec.tabelaMapa,
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
      return;
    }

    final dadosLocais = await _dadosLocaisRemoto(
      empresaId: empresaId,
      entidade: spec.entidade,
      remoto: remoto,
    );

    await database.update(
      spec.tabelaLocal,
      dadosLocais,
      where: 'id = ?',
      whereArgs: [localId],
    );

    final atualizados = await database.query(
      spec.tabelaLocal,
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (atualizados.isEmpty) return;

    await _salvarMapa(
      tabelaMapa: spec.tabelaMapa,
      empresaId: empresaId,
      localId: localId,
      remotoId: remotoId,
      localHash: spec.hashLocal(Map<String, Object?>.from(atualizados.first)),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );
  }

  Future<Map<String, Object?>> _dadosLocaisRemoto({
    required String empresaId,
    required String entidade,
    required Map<String, dynamic> remoto,
  }) async {
    if (entidade == 'cliente') {
      return <String, Object?>{
        'nome': _texto(remoto['nome']),
        'telefone': _texto(remoto['telefone']),
        'email': _texto(remoto['email']),
        'endereco': _texto(remoto['endereco']),
        'observacoes': _texto(remoto['observacoes']),
        'ativo': remoto['ativo'] == true ? 1 : 0,
        'arquivado_em': _nuloTexto(remoto['arquivado_em']),
      };
    }

    final clienteLocalId = await _localPorRemoto(
      tabelaMapa: 'imperium_sync_clientes',
      empresaId: empresaId,
      remotoId: _texto(remoto['cliente_id']),
    );
    if (clienteLocalId == null) {
      throw StateError('Cliente remoto ainda não possui vínculo local.');
    }

    if (entidade == 'veiculo') {
      return <String, Object?>{
        'cliente_id': clienteLocalId,
        'marca': _texto(remoto['marca']),
        'modelo': _texto(remoto['modelo']),
        'placa': _texto(remoto['placa']),
        'cor': _texto(remoto['cor']),
        'ano': _texto(remoto['ano']),
        'observacoes': _texto(remoto['observacoes']),
      };
    }

    final veiculoLocalId = await _localPorRemoto(
      tabelaMapa: 'imperium_sync_veiculos',
      empresaId: empresaId,
      remotoId: _texto(remoto['veiculo_id']),
    );
    if (veiculoLocalId == null) {
      throw StateError('Veículo remoto ainda não possui vínculo local.');
    }

    return <String, Object?>{
      'cliente_id': clienteLocalId,
      'veiculo_id': veiculoLocalId,
      'servico': _texto(remoto['servico']),
      'data': _texto(remoto['data']),
      'hora': _texto(remoto['hora']),
      'valor': _double(remoto['valor']),
      'status': _texto(remoto['status']).isEmpty
          ? 'Agendado'
          : _texto(remoto['status']),
      'observacoes': _texto(remoto['observacoes']),
    };
  }

  Future<Map<String, dynamic>> _payloadLocal({
    required String empresaId,
    required String entidade,
    required Map<String, Object?> local,
  }) async {
    if (entidade == 'cliente') {
      return <String, dynamic>{
        'empresa_id': empresaId,
        'nome': _texto(local['nome']),
        'telefone': _texto(local['telefone']),
        'email': _texto(local['email']),
        'endereco': _texto(local['endereco']),
        'observacoes': _texto(local['observacoes']),
        'ativo': _int(local['ativo']) != 0,
        'arquivado_em': _nuloTexto(local['arquivado_em']),
        'excluido_em': null,
      };
    }

    final clienteRemotoId = await _remotoPorLocal(
      tabelaMapa: 'imperium_sync_clientes',
      empresaId: empresaId,
      localId: _int(local['cliente_id']),
    );
    if (clienteRemotoId == null) {
      throw StateError('Cliente local ainda não possui vínculo remoto.');
    }

    if (entidade == 'veiculo') {
      return <String, dynamic>{
        'empresa_id': empresaId,
        'cliente_id': clienteRemotoId,
        'marca': _texto(local['marca']),
        'modelo': _texto(local['modelo']),
        'placa': _texto(local['placa']),
        'cor': _texto(local['cor']),
        'ano': _texto(local['ano']),
        'observacoes': _texto(local['observacoes']),
        'excluido_em': null,
      };
    }

    final veiculoRemotoId = await _remotoPorLocal(
      tabelaMapa: 'imperium_sync_veiculos',
      empresaId: empresaId,
      localId: _int(local['veiculo_id']),
    );
    if (veiculoRemotoId == null) {
      throw StateError('Veículo local ainda não possui vínculo remoto.');
    }

    return <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteRemotoId,
      'veiculo_id': veiculoRemotoId,
      'servico': _texto(local['servico']),
      'data': _texto(local['data']),
      'hora': _texto(local['hora']),
      'valor': _double(local['valor']),
      'status': _texto(local['status']).isEmpty
          ? 'Agendado'
          : _texto(local['status']),
      'observacoes': _texto(local['observacoes']),
      'excluido_em': null,
    };
  }

  Future<Map<String, Object?>?> _conflitoPendente(int id) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_operacional_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<bool> _temConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_operacional_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required Map<String, Object?> mapa,
    required String localHashAtual,
    required Map<String, Object?> local,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    final existente = await database.query(
      'imperium_sync_operacional_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND remoto_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId, remotoId],
      limit: 1,
    );

    final dados = <String, Object?>{
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
      'detectado_em': agora,
      'resolvido_em': null,
    };

    if (existente.isEmpty) {
      await database.insert(
        'imperium_sync_operacional_conflitos',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      await database.update(
        'imperium_sync_operacional_conflitos',
        dados,
        where: 'id = ?',
        whereArgs: [_int(existente.first['id'])],
      );
    }
  }

  Future<void> _atualizarSnapshotConflito(
    int conflitoId,
    String empresaId,
    _OperacionalSpec spec,
    String remotoId,
  ) async {
    final client = _client;
    if (client == null) return;
    final remotoRaw = await client
        .from(spec.tabelaRemota)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();
    if (remotoRaw == null) return;

    final remoto = Map<String, dynamic>.from(remotoRaw);
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_operacional_conflitos',
      {
        'remoto_atualizado_atual': _texto(remoto['atualizado_em']),
        'remoto_json': jsonEncode(remoto),
        'detectado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conflitoId],
    );
  }

  Future<void> _marcarResolvido(int id, String escolha) async {
    final database = await _appDatabase.database;
    await database.update(
      'imperium_sync_operacional_conflitos',
      {
        'status': 'Resolvido - $escolha',
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _salvarMapa({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    required String? remotoAtualizadoEm,
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

  Future<int?> _localPorRemoto({
    required String tabelaMapa,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.trim().isEmpty) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    final id = rows.isEmpty ? 0 : _int(rows.first['local_id']);
    return id > 0 ? id : null;
  }

  Future<String?> _remotoPorLocal({
    required String tabelaMapa,
    required String empresaId,
    required int localId,
  }) async {
    if (localId <= 0) return null;
    final database = await _appDatabase.database;
    final rows = await database.query(
      tabelaMapa,
      columns: ['remoto_id'],
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = _texto(rows.first['remoto_id']).trim();
    return id.isEmpty ? null : id;
  }

  _OperacionalSpec _spec(String entidade) {
    return switch (entidade) {
      'cliente' => _OperacionalSpec(
        entidade: entidade,
        tabelaLocal: 'clientes',
        tabelaMapa: 'imperium_sync_clientes',
        tabelaRemota: 'imperium_clientes',
        hashLocal: _hashCliente,
      ),
      'veiculo' => _OperacionalSpec(
        entidade: entidade,
        tabelaLocal: 'veiculos',
        tabelaMapa: 'imperium_sync_veiculos',
        tabelaRemota: 'imperium_veiculos',
        hashLocal: _hashVeiculo,
      ),
      'agendamento' => _OperacionalSpec(
        entidade: entidade,
        tabelaLocal: 'agendamentos',
        tabelaMapa: 'imperium_sync_agendamentos',
        tabelaRemota: 'imperium_agendamentos',
        hashLocal: _hashAgendamento,
      ),
      _ => throw ArgumentError('Entidade operacional inválida: $entidade'),
    };
  }

  static int _totalEntidade(List<Map<String, Object?>> rows, String entidade) {
    for (final row in rows) {
      if (_texto(row['entidade']) == entidade) return _int(row['total']);
    }
    return 0;
  }

  static String _hashCliente(Map<String, Object?> item) {
    return _hash(<Object?>[
      _texto(item['nome']),
      _texto(item['telefone']),
      _texto(item['email']),
      _texto(item['endereco']),
      _texto(item['observacoes']),
      _int(item['ativo']) != 0,
      _nuloTexto(item['arquivado_em']),
    ]);
  }

  static String _hashVeiculo(Map<String, Object?> item) {
    return _hash(<Object?>[
      _int(item['cliente_id']),
      _texto(item['marca']),
      _texto(item['modelo']),
      _texto(item['placa']),
      _texto(item['cor']),
      _texto(item['ano']),
      _texto(item['observacoes']),
    ]);
  }

  static String _hashAgendamento(Map<String, Object?> item) {
    return _hash(<Object?>[
      _int(item['cliente_id']),
      _int(item['veiculo_id']),
      _texto(item['servico']),
      _texto(item['data']),
      _texto(item['hora']),
      _double(item['valor']).toStringAsFixed(2),
      _texto(item['status']),
      _texto(item['observacoes']),
    ]);
  }

  static String _hash(List<Object?> valores) {
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

  static String _texto(dynamic valor) => (valor ?? '').toString();

  static String? _nuloTexto(dynamic valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }
}

class _OperacionalSpec {
  const _OperacionalSpec({
    required this.entidade,
    required this.tabelaLocal,
    required this.tabelaMapa,
    required this.tabelaRemota,
    required this.hashLocal,
  });

  final String entidade;
  final String tabelaLocal;
  final String tabelaMapa;
  final String tabelaRemota;
  final String Function(Map<String, Object?>) hashLocal;
}
