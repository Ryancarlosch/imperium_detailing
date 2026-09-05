import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'os_cloud_upload_service.dart';
import 'supabase_bootstrap.dart';

typedef OsCloudRemoteRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(String empresaId);

/// OS Cloud V2.1: importa somente OS e itens remotos ainda sem mapa local.
class OsCloudDownloadService {
  OsCloudDownloadService._({
    Future<Database> Function()? databaseProvider,
    this._ordensFetcher,
    this._itensFetcher,
    this._garantirEstrutura = true,
  }) : _databaseProvider =
           databaseProvider ?? (() => AppDatabase.instance.database);

  static final OsCloudDownloadService instance = OsCloudDownloadService._();

  final Future<Database> Function() _databaseProvider;
  final OsCloudRemoteRowsFetcher? _ordensFetcher;
  final OsCloudRemoteRowsFetcher? _itensFetcher;
  final bool _garantirEstrutura;

  factory OsCloudDownloadService.forTesting({
    required Database database,
    required OsCloudRemoteRowsFetcher ordensFetcher,
    required OsCloudRemoteRowsFetcher itensFetcher,
  }) {
    return OsCloudDownloadService._(
      databaseProvider: () async => database,
      ordensFetcher: ordensFetcher,
      itensFetcher: itensFetcher,
      garantirEstrutura: false,
    );
  }

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizarDownloadNovos(String empresaId) async {
    if (empresaId.trim().isEmpty ||
        (_client == null && _ordensFetcher == null && _itensFetcher == null)) {
      return;
    }

    if (_garantirEstrutura) {
      await OsCloudUploadService.instance.garantirEstruturaLocal();
    }
    await _baixarOrdensNovas(empresaId);
    await _baixarItensNovos(empresaId);
  }

  Future<void> _baixarOrdensNovas(String empresaId) async {
    final dados = _ordensFetcher == null
        ? await _buscarOrdensSupabase(empresaId)
        : await _ordensFetcher(empresaId);

    for (final item in dados) {
      try {
        await _importarOrdem(
          empresaId: empresaId,
          remoto: Map<String, dynamic>.from(item),
        );
      } catch (error) {
        _registrarFalha('OS', error);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _buscarOrdensSupabase(
    String empresaId,
  ) async {
    final client = _client;
    if (client == null) return const [];

    final dados = await client
        .from('imperium_ordens_servico')
        .select(
          'id,cliente_id,veiculo_id,agendamento_id,numero,status,'
          'data_abertura,data_inicio,data_finalizacao,hora_entrada,hora_saida,'
          'funcionario_responsavel,observacoes,valor_total,desconto,'
          'forma_pagamento,quilometragem_entrada,combustivel_entrada,'
          'revisada_em,motivo_ultima_revisao,quantidade_revisoes,'
          'assinatura_desatualizada,status_pagamento,valor_recebido,'
          'vencimento_pagamento,pagamento_atualizado_em,desconto_negociacao,'
          'acrescimo_negociacao,juros_parcelamento,excluido_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('atualizado_em');
    return dados
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _importarOrdem({
    required String empresaId,
    required Map<String, dynamic> remoto,
  }) async {
    if (_nuloTexto(remoto['excluido_em']) != null) return;

    final remotoId = _texto(remoto['id']);
    if (remotoId.isEmpty) return;

    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final mapa = await _mapaRemoto(
        database: transaction,
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: remotoId,
      );

      if (mapa != null) return;

      final clienteLocalId = await _localPorRemoto(
        database: transaction,
        tabela: 'imperium_sync_clientes',
        empresaId: empresaId,
        remotoId: _texto(remoto['cliente_id']),
      );

      if (clienteLocalId == null) return;

      final veiculoLocalId = await _dependenciaOpcional(
        database: transaction,
        tabela: 'imperium_sync_veiculos',
        empresaId: empresaId,
        remotoId: remoto['veiculo_id'],
      );
      final agendamentoLocalId = await _dependenciaOpcional(
        database: transaction,
        tabela: 'imperium_sync_agendamentos',
        empresaId: empresaId,
        remotoId: remoto['agendamento_id'],
      );

      if (remoto['veiculo_id'] != null && veiculoLocalId == null) return;
      if (remoto['agendamento_id'] != null && agendamentoLocalId == null) {
        return;
      }

      final dadosLocais = <String, Object?>{
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
        'assinatura_desatualizada': _boolInt(
          remoto['assinatura_desatualizada'],
        ),
        'status_pagamento': _textoOu(remoto['status_pagamento'], 'Pendente'),
        'valor_recebido': _double(remoto['valor_recebido']),
        'vencimento_pagamento': _nuloTexto(remoto['vencimento_pagamento']),
        'pagamento_atualizado_em': _nuloTexto(
          remoto['pagamento_atualizado_em'],
        ),
        'desconto_negociacao': _double(remoto['desconto_negociacao']),
        'acrescimo_negociacao': _double(remoto['acrescimo_negociacao']),
        'juros_parcelamento': _double(remoto['juros_parcelamento']),
      };

      final localId = await transaction.insert(
        'ordens_servico',
        dadosLocais,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _salvarMapa(
        database: transaction,
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashOrdemServico(dadosLocais),
        remotoAtualizadoEm: _nuloTexto(remoto['atualizado_em']),
      );
    });
  }

  Future<void> _baixarItensNovos(String empresaId) async {
    final dados = _itensFetcher == null
        ? await _buscarItensSupabase(empresaId)
        : await _itensFetcher(empresaId);

    for (final item in dados) {
      try {
        await _importarItem(
          empresaId: empresaId,
          remoto: Map<String, dynamic>.from(item),
        );
      } catch (error) {
        _registrarFalha('item de OS', error);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _buscarItensSupabase(
    String empresaId,
  ) async {
    final client = _client;
    if (client == null) return const [];

    final dados = await client
        .from('imperium_ordem_servico_itens')
        .select(
          'id,ordem_servico_id,servico,descricao,quantidade,valor_unitario,'
          'concluido,ordem,excluido_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('atualizado_em');
    return dados
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _importarItem({
    required String empresaId,
    required Map<String, dynamic> remoto,
  }) async {
    if (_nuloTexto(remoto['excluido_em']) != null) return;

    final remotoId = _texto(remoto['id']);
    final database = await _databaseProvider();

    await database.transaction((transaction) async {
      if (remotoId.isEmpty) return;

      final itemMap = await _mapaRemoto(
        database: transaction,
        tabela: 'imperium_sync_ordem_servico_itens',
        empresaId: empresaId,
        remotoId: remotoId,
      );
      if (itemMap != null) return;

      final ordemLocalId = await _localPorRemoto(
        database: transaction,
        tabela: 'imperium_sync_ordens_servico',
        empresaId: empresaId,
        remotoId: _texto(remoto['ordem_servico_id']),
      );
      if (ordemLocalId == null) return;

      final dadosLocais = <String, Object?>{
        'ordem_servico_id': ordemLocalId,
        'servico': _texto(remoto['servico']),
        'descricao': _texto(remoto['descricao']),
        'quantidade': _double(remoto['quantidade']),
        'valor_unitario': _double(remoto['valor_unitario']),
        'concluido': _boolInt(remoto['concluido']),
        'ordem': _int(remoto['ordem']),
      };

      final localId = await transaction.insert(
        'ordem_servico_itens',
        dadosLocais,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _salvarMapa(
        database: transaction,
        tabela: 'imperium_sync_ordem_servico_itens',
        empresaId: empresaId,
        localId: localId,
        remotoId: remotoId,
        localHash: _hashItem(dadosLocais),
        remotoAtualizadoEm: _nuloTexto(remoto['atualizado_em']),
      );
    });
  }

  Future<int?> _dependenciaOpcional({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required dynamic remotoId,
  }) async {
    if (remotoId == null || _texto(remotoId).isEmpty) return null;
    return _localPorRemoto(
      database: database,
      tabela: tabela,
      empresaId: empresaId,
      remotoId: _texto(remotoId),
    );
  }

  Future<Map<String, Object?>?> _mapaRemoto({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    final resultado = await database.query(
      tabela,
      where: 'empresa_id = ? AND remoto_id = ?',
      whereArgs: [empresaId, remotoId],
      limit: 1,
    );
    return resultado.isEmpty
        ? null
        : Map<String, Object?>.from(resultado.first);
  }

  Future<int?> _localPorRemoto({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required String remotoId,
  }) async {
    if (remotoId.isEmpty) return null;
    final mapa = await _mapaRemoto(
      database: database,
      tabela: tabela,
      empresaId: empresaId,
      remotoId: remotoId,
    );
    final localId = _int(mapa?['local_id']);
    return localId > 0 ? localId : null;
  }

  Future<void> _salvarMapa({
    required DatabaseExecutor database,
    required String tabela,
    required String empresaId,
    required int localId,
    required String remotoId,
    required String localHash,
    required String? remotoAtualizadoEm,
  }) async {
    await database.insert(tabela, {
      'empresa_id': empresaId,
      'local_id': localId,
      'remoto_id': remotoId,
      'local_hash': localHash,
      'remoto_atualizado_em': remotoAtualizadoEm,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  void _registrarFalha(String entidade, Object error) {
    developer.log(
      'Falha ao importar $entidade (${error.runtimeType}).',
      name: 'imperium.os_cloud_download',
      level: 1000,
    );
  }

  String _hashOrdemServico(Map<String, Object?> item) => _hash([
    _int(item['cliente_id']),
    _int(item['veiculo_id']),
    _int(item['agendamento_id']),
    _texto(item['numero']),
    _texto(item['status']),
    _texto(item['data_abertura']),
    _nuloTexto(item['data_inicio']),
    _nuloTexto(item['data_finalizacao']),
    _nuloTexto(item['hora_entrada']),
    _nuloTexto(item['hora_saida']),
    _texto(item['funcionario_responsavel']),
    _texto(item['observacoes']),
    _double(item['valor_total']).toStringAsFixed(2),
    _double(item['desconto']).toStringAsFixed(2),
    _nuloTexto(item['forma_pagamento']),
    _texto(item['quilometragem_entrada']),
    _texto(item['combustivel_entrada']),
    _nuloTexto(item['revisada_em']),
    _texto(item['motivo_ultima_revisao']),
    _int(item['quantidade_revisoes']),
    _int(item['assinatura_desatualizada']) != 0,
    _texto(item['status_pagamento']),
    _double(item['valor_recebido']).toStringAsFixed(2),
    _nuloTexto(item['vencimento_pagamento']),
    _nuloTexto(item['pagamento_atualizado_em']),
    _double(item['desconto_negociacao']).toStringAsFixed(2),
    _double(item['acrescimo_negociacao']).toStringAsFixed(2),
    _double(item['juros_parcelamento']).toStringAsFixed(2),
  ]);

  String _hashItem(Map<String, Object?> item) => _hash([
    _int(item['ordem_servico_id']),
    _texto(item['servico']),
    _texto(item['descricao']),
    _double(item['quantidade']).toStringAsFixed(6),
    _double(item['valor_unitario']).toStringAsFixed(2),
    _int(item['concluido']) != 0,
    _int(item['ordem']),
  ]);

  String _hash(List<Object?> valores) =>
      sha256.convert(utf8.encode(jsonEncode(valores))).toString();

  static String _texto(dynamic valor) => (valor ?? '').toString();

  static String _textoOu(dynamic valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(_texto(valor)) ?? 0;
  }

  static int _boolInt(dynamic valor) {
    if (valor is bool) return valor ? 1 : 0;
    return _int(valor) != 0 ? 1 : 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(_texto(valor).replaceAll(',', '.')) ?? 0;
  }

  static String? _nuloTexto(dynamic valor) {
    final texto = _texto(valor).trim();
    return texto.isEmpty ? null : texto;
  }
}
