import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'os_cloud_upload_service.dart';
import 'supabase_bootstrap.dart';

typedef OsCloudV3RemoteFetcher =
    Future<Map<String, dynamic>?> Function(String empresaId, String remotoId);

class OsCloudV3Service {
  OsCloudV3Service._({
    Future<Database> Function()? databaseProvider,
    this._ordemFetcher,
    this._itemFetcher,
    this._garantirMapas = true,
  }) : _databaseProvider =
           databaseProvider ?? (() => AppDatabase.instance.database);

  static final OsCloudV3Service instance = OsCloudV3Service._();

  factory OsCloudV3Service.forTesting({
    required Database database,
    required OsCloudV3RemoteFetcher ordemFetcher,
    required OsCloudV3RemoteFetcher itemFetcher,
  }) {
    return OsCloudV3Service._(
      databaseProvider: () async => database,
      ordemFetcher: ordemFetcher,
      itemFetcher: itemFetcher,
      garantirMapas: false,
    );
  }

  final Future<Database> Function() _databaseProvider;
  final OsCloudV3RemoteFetcher? _ordemFetcher;
  final OsCloudV3RemoteFetcher? _itemFetcher;
  final bool _garantirMapas;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  bool get _temFonteRemota =>
      _client != null || _ordemFetcher != null || _itemFetcher != null;

  Future<void> garantirEstruturaLocal() async {
    if (_garantirMapas) {
      await OsCloudUploadService.instance.garantirEstruturaLocal();
    }

    final database = await _databaseProvider();

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_os_conflitos (
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
      CREATE INDEX IF NOT EXISTS idx_sync_os_conflitos_pendentes
      ON imperium_sync_os_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');
  }

  Future<bool> prepararUpload(String empresaId) async {
    if (empresaId.trim().isEmpty || !_temFonteRemota) return false;

    await garantirEstruturaLocal();

    if (await possuiConflitosPendentes(empresaId)) return false;

    await _reconciliarEntidade(empresaId, 'ordem');
    await _reconciliarEntidade(empresaId, 'item');

    return !await possuiConflitosPendentes(empresaId);
  }

  Future<void> sincronizarDepoisDoDownload(String empresaId) async {
    if (empresaId.trim().isEmpty || !_temFonteRemota) return;

    await garantirEstruturaLocal();
    await _reconciliarEntidade(empresaId, 'ordem');
    await _reconciliarEntidade(empresaId, 'item');
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _databaseProvider();

    final rows = await database.query(
      'imperium_sync_os_conflitos',
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
    final database = await _databaseProvider();

    return database.query(
      'imperium_sync_os_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _databaseProvider();

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
      FROM imperium_sync_os_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [empresaId],
    );

    return <String, Object?>{
      'empresa_id': empresaId,
      'ordens_mapeadas': await contar('imperium_sync_ordens_servico'),
      'itens_mapeados': await contar('imperium_sync_ordem_servico_itens'),
      'conflitos_pendentes': _int(conflitos.first['total']),
    };
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    await garantirEstruturaLocal();

    final conflito = await _conflitoPendente(conflitoId);
    final entidade = _texto(conflito['entidade']);
    final empresaId = _texto(conflito['empresa_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final config = _config(entidade);

    final remoto = await _buscarRemoto(
      empresaId: empresaId,
      remotoId: remotoId,
      entidade: entidade,
    );

    if (remoto == null) {
      throw StateError(
        'O registro remoto não existe mais. A resolução local exige uma '
        'versão remota para CAS.',
      );
    }

    final database = await _databaseProvider();

    await database.update(
      config.mapa,
      {'remoto_atualizado_em': _nuloTexto(remoto['atualizado_em'])},
      where: 'empresa_id = ? AND local_id = ?',
      whereArgs: [empresaId, _int(conflito['local_id'])],
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'local',
      detalhe:
          'Versão remota atual adotada como nova base; o próximo upload '
          'publicará a versão local com CAS.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    await garantirEstruturaLocal();

    final conflito = await _conflitoPendente(conflitoId);
    final entidade = _texto(conflito['entidade']);
    final empresaId = _texto(conflito['empresa_id']);
    final remotoId = _texto(conflito['remoto_id']);
    final localId = _int(conflito['local_id']);

    final remoto = await _buscarRemoto(
      empresaId: empresaId,
      remotoId: remotoId,
      entidade: entidade,
    );

    if (remoto == null) {
      throw StateError('O registro remoto não existe mais.');
    }

    if (entidade == 'ordem' && _nuloTexto(remoto['excluido_em']) != null) {
      throw StateError(
        'Exclusão remota de uma OS não é aplicada automaticamente no '
        'SQLite. Use "manter este aparelho" para restaurar a OS na nuvem.',
      );
    }

    await _aplicarRemoto(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
      remoto: remoto,
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Versão da nuvem aplicada no SQLite.',
    );
  }

  Future<void> _reconciliarEntidade(String empresaId, String entidade) async {
    final config = _config(entidade);
    final database = await _databaseProvider();

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

      if (await _temConflitoPendente(
        empresaId: empresaId,
        entidade: entidade,
        localId: localId,
      )) {
        continue;
      }

      final locais = await database.query(
        config.local,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      final local = locais.isEmpty
          ? null
          : Map<String, Object?>.from(locais.first);

      final localHashBase = _texto(mapa['local_hash']);
      final localHashAtual = local == null
          ? '__excluido__'
          : _hashLocal(entidade, local);

      final remoto = await _buscarRemoto(
        empresaId: empresaId,
        remotoId: remotoId,
        entidade: entidade,
      );

      if (remoto == null) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'registro_remoto_ausente',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: const <String, dynamic>{},
        );
        continue;
      }

      final remotoBase = _nuloTexto(mapa['remoto_atualizado_em']);
      final remotoAtual = _nuloTexto(remoto['atualizado_em']);
      final remotoExcluido = _nuloTexto(remoto['excluido_em']) != null;

      final localMudou = localHashAtual != localHashBase;
      final remotoMudou =
          !_mesmoTimestamp(remotoBase, remotoAtual) || remotoExcluido;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: remotoExcluido
              ? 'exclusao_remota_e_alteracao_local'
              : 'alteracao_concorrente',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: remoto,
        );
        continue;
      }

      if (localMudou) {
        // O upload V1 fará a publicação com CAS.
        continue;
      }

      if (!remotoMudou) continue;

      if (entidade == 'ordem' && remotoExcluido) {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'exclusao_remota_os',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: remoto,
        );
        continue;
      }

      try {
        await _aplicarRemoto(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remoto: remoto,
        );
      } on StateError {
        await _registrarConflito(
          empresaId: empresaId,
          entidade: entidade,
          localId: localId,
          remotoId: remotoId,
          motivo: 'dependencia_remota_ausente',
          mapa: mapa,
          localHashAtual: localHashAtual,
          local: local,
          remoto: remoto,
        );
      }
    }
  }

  Future<void> _aplicarRemoto({
    required String empresaId,
    required String entidade,
    required int localId,
    required Map<String, dynamic> remoto,
  }) async {
    final config = _config(entidade);
    final database = await _databaseProvider();
    final remotoId = _texto(remoto['id']);
    final remotoTs = _nuloTexto(remoto['atualizado_em']);

    if (entidade == 'item' && _nuloTexto(remoto['excluido_em']) != null) {
      await database.transaction((tx) async {
        await tx.delete(config.local, where: 'id = ?', whereArgs: [localId]);

        await tx.update(
          config.mapa,
          {'local_hash': '__excluido__', 'remoto_atualizado_em': remotoTs},
          where: 'empresa_id = ? AND local_id = ?',
          whereArgs: [empresaId, localId],
        );
      });
      return;
    }

    if (_nuloTexto(remoto['excluido_em']) != null) {
      throw StateError(
        'Exclusão remota não pode ser aplicada automaticamente.',
      );
    }

    final dados = entidade == 'ordem'
        ? await _dadosOrdemLocal(empresaId, remoto)
        : await _dadosItemLocal(empresaId, remoto);

    await database.transaction((tx) async {
      final alterados = await tx.update(
        config.local,
        dados,
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (alterados == 0) {
        throw StateError('Registro local mapeado não foi encontrado.');
      }

      final rows = await tx.query(
        config.local,
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Registro local desapareceu durante a reconciliação.');
      }

      final localAtual = Map<String, Object?>.from(rows.first);
      final hashAtual = _hashLocal(entidade, localAtual);

      await tx.update(
        config.mapa,
        {
          'remoto_id': remotoId,
          'local_hash': hashAtual,
          'remoto_atualizado_em': remotoTs,
        },
        where: 'empresa_id = ? AND local_id = ?',
        whereArgs: [empresaId, localId],
      );
    });
  }

  Future<Map<String, Object?>> _dadosOrdemLocal(
    String empresaId,
    Map<String, dynamic> remoto,
  ) async {
    final database = await _databaseProvider();

    final clienteLocalId = await _localPorRemoto(
      database: database,
      tabela: 'imperium_sync_clientes',
      empresaId: empresaId,
      remotoId: _texto(remoto['cliente_id']),
    );

    if (clienteLocalId == null) {
      throw StateError('Cliente remoto da OS ainda não foi mapeado.');
    }

    final veiculoLocalId = await _dependenciaOpcional(
      database: database,
      tabela: 'imperium_sync_veiculos',
      empresaId: empresaId,
      remotoId: remoto['veiculo_id'],
    );

    if (remoto['veiculo_id'] != null && veiculoLocalId == null) {
      throw StateError('Veículo remoto da OS ainda não foi mapeado.');
    }

    final agendamentoLocalId = await _dependenciaOpcional(
      database: database,
      tabela: 'imperium_sync_agendamentos',
      empresaId: empresaId,
      remotoId: remoto['agendamento_id'],
    );

    if (remoto['agendamento_id'] != null && agendamentoLocalId == null) {
      throw StateError('Agendamento remoto da OS ainda não foi mapeado.');
    }

    return <String, Object?>{
      'agendamento_id': agendamentoLocalId,
      'cliente_id': clienteLocalId,
      'veiculo_id': veiculoLocalId,
      'numero': _texto(remoto['numero']),
      'status': _textoOu(remoto['status'], 'Aberta'),
      'data_abertura': _texto(remoto['data_abertura']),
      'data_inicio': _nuloTexto(remoto['data_inicio']),
      'data_finalizacao': _nuloTexto(remoto['data_finalizacao']),
      'hora_entrada': _nuloTexto(remoto['hora_entrada']),
      'hora_saida': _nuloTexto(remoto['hora_saida']),
      'funcionario_responsavel': _texto(remoto['funcionario_responsavel']),
      'observacoes': _texto(remoto['observacoes']),
      'valor_total': _double(remoto['valor_total']),
      'desconto': _double(remoto['desconto']),
      'forma_pagamento': _nuloTexto(remoto['forma_pagamento']),
      'quilometragem_entrada': _texto(remoto['quilometragem_entrada']),
      'combustivel_entrada': _texto(remoto['combustivel_entrada']),
      'revisada_em': _nuloTexto(remoto['revisada_em']),
      'motivo_ultima_revisao': _texto(remoto['motivo_ultima_revisao']),
      'quantidade_revisoes': _int(remoto['quantidade_revisoes']),
      'assinatura_desatualizada': _boolInt(remoto['assinatura_desatualizada']),
      'status_pagamento': _textoOu(remoto['status_pagamento'], 'Pendente'),
      'valor_recebido': _double(remoto['valor_recebido']),
      'vencimento_pagamento': _nuloTexto(remoto['vencimento_pagamento']),
      'pagamento_atualizado_em': _nuloTexto(remoto['pagamento_atualizado_em']),
      'desconto_negociacao': _double(remoto['desconto_negociacao']),
      'acrescimo_negociacao': _double(remoto['acrescimo_negociacao']),
      'juros_parcelamento': _double(remoto['juros_parcelamento']),
    };
  }

  Future<Map<String, Object?>> _dadosItemLocal(
    String empresaId,
    Map<String, dynamic> remoto,
  ) async {
    final database = await _databaseProvider();

    final ordemLocalId = await _localPorRemoto(
      database: database,
      tabela: 'imperium_sync_ordens_servico',
      empresaId: empresaId,
      remotoId: _texto(remoto['ordem_servico_id']),
    );

    if (ordemLocalId == null) {
      throw StateError('OS remota do item ainda não foi mapeada.');
    }

    return <String, Object?>{
      'ordem_servico_id': ordemLocalId,
      'servico': _texto(remoto['servico']),
      'descricao': _texto(remoto['descricao']),
      'quantidade': _double(remoto['quantidade']),
      'valor_unitario': _double(remoto['valor_unitario']),
      'concluido': _boolInt(remoto['concluido']),
      'ordem': _int(remoto['ordem']),
    };
  }

  Future<Map<String, dynamic>?> _buscarRemoto({
    required String empresaId,
    required String remotoId,
    required String entidade,
  }) async {
    if (entidade == 'ordem' && _ordemFetcher != null) {
      return _ordemFetcher(empresaId, remotoId);
    }

    if (entidade == 'item' && _itemFetcher != null) {
      return _itemFetcher(empresaId, remotoId);
    }

    final client = _client;
    if (client == null) return null;

    final tabela = entidade == 'ordem'
        ? 'imperium_ordens_servico'
        : 'imperium_ordem_servico_itens';

    final raw = await client
        .from(tabela)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .maybeSingle();

    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<int?> _dependenciaOpcional({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required dynamic remotoId,
  }) async {
    final id = _texto(remotoId);
    if (id.isEmpty) return null;

    return _localPorRemoto(
      database: database,
      tabela: tabela,
      empresaId: empresaId,
      remotoId: id,
    );
  }

  Future<int?> _localPorRemoto({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;

    final rows = await database.query(
      tabela,
      columns: ['local_id'],
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final id = _int(rows.first['local_id']);
    return id > 0 ? id : null;
  }

  String _hashLocal(String entidade, Map<String, Object?> local) {
    if (entidade == 'ordem') {
      return OsCloudUploadService.instance.calcularHashOrdemServico(local);
    }

    return OsCloudUploadService.instance.calcularHashOrdemServicoItem(local);
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String entidade,
    required int localId,
    required String remotoId,
    required String motivo,
    required Map<String, Object?> mapa,
    required String localHashAtual,
    required Map<String, Object?>? local,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _databaseProvider();

    if (await _temConflitoPendente(
      empresaId: empresaId,
      entidade: entidade,
      localId: localId,
    )) {
      return;
    }

    await database.insert('imperium_sync_os_conflitos', {
      'empresa_id': empresaId,
      'entidade': entidade,
      'local_id': localId,
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': _texto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _nuloTexto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _nuloTexto(remoto['atualizado_em']),
      'local_json': jsonEncode(local ?? const <String, Object?>{}),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'detectado_em': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool> _temConflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
  }) async {
    final database = await _databaseProvider();

    final rows = await database.query(
      'imperium_sync_os_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? "
          "AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>> _conflitoPendente(int id) async {
    final database = await _databaseProvider();

    final rows = await database.query(
      'imperium_sync_os_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito de OS não encontrado ou já resolvido.');
    }

    return Map<String, Object?>.from(rows.first);
  }

  Future<void> _encerrarConflito(
    int id, {
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _databaseProvider();

    await database.update(
      'imperium_sync_os_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  _OsCloudConfig _config(String entidade) {
    return switch (entidade) {
      'ordem' => const _OsCloudConfig(
        local: 'ordens_servico',
        mapa: 'imperium_sync_ordens_servico',
      ),
      'item' => const _OsCloudConfig(
        local: 'ordem_servico_itens',
        mapa: 'imperium_sync_ordem_servico_itens',
      ),
      _ => throw ArgumentError('Entidade de OS inválida: $entidade'),
    };
  }

  bool _mesmoTimestamp(String? a, String? b) {
    final ta = a?.trim() ?? '';
    final tb = b?.trim() ?? '';

    if (ta.isEmpty || tb.isEmpty) return ta == tb;

    final da = DateTime.tryParse(ta);
    final db = DateTime.tryParse(tb);

    if (da == null || db == null) return ta == tb;

    return da.toUtc().microsecondsSinceEpoch ==
        db.toUtc().microsecondsSinceEpoch;
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String _textoOu(dynamic valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }

  static String? _nuloTexto(dynamic valor) {
    final texto = _texto(valor);
    return texto.isEmpty ? null : texto;
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

  static int _boolInt(dynamic valor) {
    if (valor is bool) return valor ? 1 : 0;
    if (valor is num) return valor.toInt() == 0 ? 0 : 1;
    final texto = valor?.toString().toLowerCase() ?? '';
    return texto == 'true' || texto == '1' ? 1 : 0;
  }
}

class _OsCloudConfig {
  const _OsCloudConfig({required this.local, required this.mapa});

  final String local;
  final String mapa;
}
