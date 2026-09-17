import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

typedef OperacionalConflitoRemoteFetcher =
    Future<Map<String, dynamic>?> Function(
      String entidade,
      String empresaId,
      String remotoId,
    );

class OperacionalConflitoService {
  OperacionalConflitoService._({
    Future<Database> Function()? databaseProvider,
    this._remoteFetcher,
  }) : _databaseProvider =
           databaseProvider ?? (() => AppDatabase.instance.database);

  static final OperacionalConflitoService instance =
      OperacionalConflitoService._();

  factory OperacionalConflitoService.forTesting({
    required Database database,
    required OperacionalConflitoRemoteFetcher remoteFetcher,
  }) {
    return OperacionalConflitoService._(
      databaseProvider: () async => database,
      remoteFetcher: remoteFetcher,
    );
  }

  final Future<Database> Function() _databaseProvider;
  final OperacionalConflitoRemoteFetcher? _remoteFetcher;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await _databaseProvider();

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
        resolucao TEXT,
        resolucao_detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_operacional_conflitos_pendentes
      ON imperium_sync_operacional_conflitos (
        empresa_id,
        status,
        entidade,
        local_id
      )
    ''');
  }

  Future<int> detectar(String empresaId) async {
    final tenant = empresaId.trim();
    if (tenant.isEmpty) return 0;

    await garantirEstruturaLocal();

    await _detectarEntidade(tenant, 'cliente');
    await _detectarEntidade(tenant, 'veiculo');

    final database = await _databaseProvider();
    final rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM imperium_sync_operacional_conflitos
      WHERE empresa_id = ? AND status = 'Pendente'
      ''',
      [tenant],
    );

    return _int(rows.first['total']);
  }

  Future<bool> possuiConflitosPendentes(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _databaseProvider();

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
    required String empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _databaseProvider();

    return database.query(
      'imperium_sync_operacional_conflitos',
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _databaseProvider();

    Future<int> contar(String tabela) async {
      try {
        final rows = await database.rawQuery(
          'SELECT COUNT(*) AS total FROM $tabela WHERE empresa_id = ?',
          [empresaId],
        );
        return _int(rows.first['total']);
      } catch (_) {
        return 0;
      }
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'clientes_mapeados': await contar('imperium_sync_clientes'),
      'veiculos_mapeados': await contar('imperium_sync_veiculos'),
      'conflitos_pendentes': await contar(
        'imperium_sync_operacional_conflitos',
      ),
    };
  }

  Future<void> _detectarEntidade(String empresaId, String entidade) async {
    final config = _config(entidade);
    final database = await _databaseProvider();

    List<Map<String, Object?>> mapas;
    try {
      mapas = await database.query(
        config.mapa,
        where: 'empresa_id = ?',
        whereArgs: [empresaId],
      );
    } catch (_) {
      return;
    }

    for (final mapa in mapas) {
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
      final localMudou = localHashAtual != localHashBase;

      final remoto = await _buscarRemoto(
        entidade: entidade,
        empresaId: empresaId,
        remotoId: remotoId,
      );

      if (remoto == null) {
        if (localMudou) {
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
        }
        continue;
      }

      final remotoBase = _nuloTexto(mapa['remoto_atualizado_em']);
      final remotoAtual = _nuloTexto(remoto['atualizado_em']);
      final remotoExcluido = _nuloTexto(remoto['excluido_em']) != null;
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
      }
    }
  }

  Future<Map<String, dynamic>?> _buscarRemoto({
    required String entidade,
    required String empresaId,
    required String remotoId,
  }) async {
    final fetcher = _remoteFetcher;
    if (fetcher != null) {
      return fetcher(entidade, empresaId, remotoId);
    }

    final client = _client;
    if (client == null) return null;

    final tabela = entidade == 'cliente'
        ? 'imperium_clientes'
        : 'imperium_veiculos';

    final rows = await client
        .from(tabela)
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', remotoId)
        .limit(1);

    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<bool> _temConflitoPendente({
    required String empresaId,
    required String entidade,
    required int localId,
  }) async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'imperium_sync_operacional_conflitos',
      columns: ['id'],
      where:
          "empresa_id = ? AND entidade = ? AND local_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId, entidade, localId],
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
    required Map<String, Object?>? local,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _databaseProvider();

    await database.insert('imperium_sync_operacional_conflitos', {
      'empresa_id': empresaId,
      'entidade': entidade,
      'local_id': localId,
      'remoto_id': remotoId,
      'motivo': motivo,
      'local_hash_base': _nuloTexto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _nuloTexto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _nuloTexto(remoto['atualizado_em']),
      'local_json': jsonEncode(local ?? const <String, Object?>{}),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'detectado_em': DateTime.now().toIso8601String(),
    });
  }

  _OperacionalConfig _config(String entidade) {
    if (entidade == 'cliente') {
      return const _OperacionalConfig(
        local: 'clientes',
        mapa: 'imperium_sync_clientes',
      );
    }

    if (entidade == 'veiculo') {
      return const _OperacionalConfig(
        local: 'veiculos',
        mapa: 'imperium_sync_veiculos',
      );
    }

    throw ArgumentError.value(entidade, 'entidade');
  }

  String _hashLocal(String entidade, Map<String, Object?> item) {
    if (entidade == 'cliente') {
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

  String _hash(List<Object?> valores) {
    return sha256.convert(utf8.encode(jsonEncode(valores))).toString();
  }

  bool _mesmoTimestamp(String? a, String? b) {
    if (a == b) return true;
    if (a == null || b == null) return false;

    final da = DateTime.tryParse(a)?.toUtc();
    final db = DateTime.tryParse(b)?.toUtc();
    return da != null && db != null && da == db;
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';

  static String? _nuloTexto(dynamic valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }
}

class _OperacionalConfig {
  const _OperacionalConfig({required this.local, required this.mapa});

  final String local;
  final String mapa;
}
