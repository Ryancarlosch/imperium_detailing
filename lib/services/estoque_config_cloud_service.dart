import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Sincroniza as preferências do módulo de Estoque entre Android e Web.
///
/// A configuração é única por empresa. O campo [atualizado_em] local indica
/// quando o usuário alterou a preferência no aparelho; o servidor mantém CAS
/// para evitar sobrescrita silenciosa em concorrência.
class EstoqueConfigCloudService {
  EstoqueConfigCloudService._();

  static final EstoqueConfigCloudService instance =
      EstoqueConfigCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      final local = await _configLocal();
      final remotoRaw = await client
          .from('imperium_estoque_config')
          .select()
          .eq('empresa_id', empresaId)
          .maybeSingle();

      if (remotoRaw == null) {
        await _publicar(
          empresaId: empresaId,
          local: local,
          atualizadoEmBase: null,
        );
        return;
      }

      final remoto = Map<String, dynamic>.from(remotoRaw);
      final localAtualizado = _data(local['atualizado_em']);
      final remotoOrigem = _data(remoto['origem_atualizado_em']);
      final remotoServidor = _data(remoto['atualizado_em']);
      final referenciaRemota = remotoOrigem ?? remotoServidor;

      if (localAtualizado != null &&
          (referenciaRemota == null ||
              localAtualizado.isAfter(referenciaRemota))) {
        try {
          await _publicar(
            empresaId: empresaId,
            local: local,
            atualizadoEmBase: remoto['atualizado_em']?.toString(),
          );
          return;
        } on PostgrestException {
          final atual = await client
              .from('imperium_estoque_config')
              .select()
              .eq('empresa_id', empresaId)
              .single();
          await _aplicarRemoto(Map<String, dynamic>.from(atual));
          return;
        }
      }

      await _aplicarRemoto(remoto);
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<Map<String, Object?>> _configLocal() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'configuracoes_estoque',
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first;

    final agora = DateTime.now().toIso8601String();
    final id = await database.insert('configuracoes_estoque', <String, Object?>{
      'controlar_estoque': 1,
      'controlar_produtos_ordem_servico': 0,
      'baixa_automatica': 0,
      'exigir_quantidade': 0,
      'alertar_estoque_baixo': 1,
      'estoque_minimo_padrao': 1.0,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    final criado = await database.query(
      'configuracoes_estoque',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return criado.first;
  }

  Future<void> _publicar({
    required String empresaId,
    required Map<String, Object?> local,
    required String? atualizadoEmBase,
  }) async {
    final client = _client;
    if (client == null) return;
    final dispositivoId = await _dispositivoId();
    final origemAtualizado =
        (local['atualizado_em'] ?? DateTime.now().toIso8601String()).toString();

    final raw = await client.rpc(
      'imperium_estoque_salvar_config',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_controlar_estoque': _boolLocal(local['controlar_estoque']),
        'p_controlar_produtos_ordem_servico': _boolLocal(
          local['controlar_produtos_ordem_servico'],
        ),
        'p_baixa_automatica': _boolLocal(local['baixa_automatica']),
        'p_exigir_quantidade': _boolLocal(local['exigir_quantidade']),
        'p_alertar_estoque_baixo': _boolLocal(local['alertar_estoque_baixo']),
        'p_estoque_minimo_padrao': _double(local['estoque_minimo_padrao']),
        'p_origem_dispositivo': dispositivoId,
        'p_origem_atualizado_em': origemAtualizado,
        'p_atualizado_em_base': _nulo(atualizadoEmBase),
      },
    );

    if (raw is Map) {
      await _aplicarRemoto(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _aplicarRemoto(Map<String, dynamic> remoto) async {
    final database = await _appDatabase.database;
    final local = await _configLocal();
    final localId = _int(local['id']);
    if (localId <= 0) return;

    await database.update(
      'configuracoes_estoque',
      <String, Object?>{
        'controlar_estoque': remoto['controlar_estoque'] == true ? 1 : 0,
        'controlar_produtos_ordem_servico':
            remoto['controlar_produtos_ordem_servico'] == true ? 1 : 0,
        'baixa_automatica': remoto['baixa_automatica'] == true ? 1 : 0,
        'exigir_quantidade': remoto['exigir_quantidade'] == true ? 1 : 0,
        'alertar_estoque_baixo': remoto['alertar_estoque_baixo'] == true
            ? 1
            : 0,
        'estoque_minimo_padrao': _double(remoto['estoque_minimo_padrao']),
        'atualizado_em': _textoPreferido(
          remoto['origem_atualizado_em'],
          remoto['atualizado_em'],
        ),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );
    final id = rows.isEmpty
        ? ''
        : (rows.first['dispositivo_id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw StateError('Dispositivo de sincronização não inicializado.');
    }
    return id;
  }

  static bool _boolLocal(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final texto = value?.toString().toLowerCase() ?? '';
    return texto == 'true' || texto == '1';
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static DateTime? _data(Object? value) {
    final texto = value?.toString().trim() ?? '';
    return texto.isEmpty ? null : DateTime.tryParse(texto)?.toUtc();
  }

  static String? _nulo(Object? value) {
    final texto = value?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static String _textoPreferido(Object? primeiro, Object? segundo) {
    final a = primeiro?.toString().trim() ?? '';
    if (a.isNotEmpty) return a;
    final b = segundo?.toString().trim() ?? '';
    return b.isNotEmpty ? b : DateTime.now().toIso8601String();
  }
}
