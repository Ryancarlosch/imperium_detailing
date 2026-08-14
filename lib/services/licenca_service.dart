import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class LicencaStatus {
  const LicencaStatus({
    required this.empresaId,
    required this.empresaNome,
    required this.papel,
    required this.plano,
    required this.statusBase,
    required this.statusEfetivo,
    required this.acessoLiberado,
    required this.hoje,
    required this.validoAte,
    required this.diasRestantes,
    required this.toleranciaDias,
    required this.valorMensal,
    required this.motivo,
  });

  final String empresaId;
  final String empresaNome;
  final String papel;
  final String plano;
  final String statusBase;
  final String statusEfetivo;
  final bool acessoLiberado;
  final DateTime? hoje;
  final DateTime? validoAte;
  final int? diasRestantes;
  final int toleranciaDias;
  final double? valorMensal;
  final String motivo;

  factory LicencaStatus.fromMap(Map<String, dynamic> map) {
    return LicencaStatus(
      empresaId: (map['empresa_id'] ?? '').toString().trim(),
      empresaNome: (map['empresa_nome'] ?? '').toString().trim(),
      papel: (map['papel'] ?? '').toString().trim(),
      plano: (map['plano'] ?? '').toString().trim(),
      statusBase: (map['status_base'] ?? '').toString().trim(),
      statusEfetivo: (map['status_efetivo'] ?? '').toString().trim(),
      acessoLiberado: _bool(map['acesso_liberado']),
      hoje: _data(map['hoje']),
      validoAte: _data(map['valido_ate']),
      diasRestantes: _intOuNull(map['dias_restantes']),
      toleranciaDias: _intOuNull(map['tolerancia_dias']) ?? 0,
      valorMensal: _doubleOuNull(map['valor_mensal']),
      motivo: (map['motivo'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toCacheMap(DateTime consultadoEm) {
    return <String, dynamic>{
      'id': 1,
      'empresa_id': empresaId,
      'empresa_nome': empresaNome,
      'papel': papel,
      'plano': plano,
      'status_base': statusBase,
      'status_efetivo': statusEfetivo,
      'acesso_liberado': acessoLiberado ? 1 : 0,
      'hoje': hoje?.toIso8601String(),
      'valido_ate': validoAte?.toIso8601String(),
      'dias_restantes': diasRestantes,
      'tolerancia_dias': toleranciaDias,
      'valor_mensal': valorMensal,
      'motivo': motivo,
      'consultado_em': consultadoEm.toIso8601String(),
    };
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final texto = valor?.toString().trim().toLowerCase() ?? '';
    return texto == 'true' || texto == '1';
  }

  static DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString().trim());
  }

  static int? _intOuNull(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString().trim());
  }

  static double? _doubleOuNull(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString().trim().replaceAll(',', '.'));
  }
}

class LicencaConsultaResultado {
  const LicencaConsultaResultado({
    required this.status,
    required this.usouCacheOffline,
  });

  final LicencaStatus status;
  final bool usouCacheOffline;
}

class LicencaService {
  const LicencaService();

  static const Duration toleranciaOffline = Duration(hours: 72);

  SupabaseClient? get _client => SupabaseBootstrap.client;

  Future<void> garantirEstruturaLocal() async {
    final database = await AppDatabase.instance.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_dispositivo_empresa (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        empresa_id TEXT NOT NULL,
        user_id TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        vinculado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_licenca_cache_v2 (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        empresa_id TEXT NOT NULL,
        empresa_nome TEXT NOT NULL DEFAULT '',
        papel TEXT NOT NULL DEFAULT '',
        plano TEXT NOT NULL DEFAULT '',
        status_base TEXT NOT NULL DEFAULT '',
        status_efetivo TEXT NOT NULL DEFAULT '',
        acesso_liberado INTEGER NOT NULL DEFAULT 0,
        hoje TEXT,
        valido_ate TEXT,
        dias_restantes INTEGER,
        tolerancia_dias INTEGER NOT NULL DEFAULT 0,
        valor_mensal REAL,
        motivo TEXT NOT NULL DEFAULT '',
        consultado_em TEXT NOT NULL
      )
    ''');
  }

  Future<String?> empresaVinculadaAoDispositivo() async {
    await garantirEstruturaLocal();
    final database = await AppDatabase.instance.database;
    final rows = await database.query(
      'imperium_dispositivo_empresa',
      columns: ['empresa_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final id = (rows.first['empresa_id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<void> vincularDispositivoSeNecessario({
    required String empresaId,
    required String userId,
    required String email,
  }) async {
    final empresaLimpa = empresaId.trim();
    if (empresaLimpa.isEmpty) {
      throw StateError('Empresa inválida para este aparelho.');
    }

    await garantirEstruturaLocal();
    final database = await AppDatabase.instance.database;
    final atual = await database.query(
      'imperium_dispositivo_empresa',
      where: 'id = 1',
      limit: 1,
    );

    final agora = DateTime.now().toIso8601String();

    if (atual.isNotEmpty) {
      final empresaAtual = (atual.first['empresa_id'] ?? '').toString().trim();

      if (empresaAtual.isNotEmpty && empresaAtual != empresaLimpa) {
        throw StateError(
          'Este aparelho já está vinculado a outra empresa. '
          'No beta, cada instalação do Imperium pertence a uma única empresa.',
        );
      }

      await database.update('imperium_dispositivo_empresa', {
        'empresa_id': empresaLimpa,
        'user_id': userId.trim(),
        'email': email.trim().toLowerCase(),
        'atualizado_em': agora,
      }, where: 'id = 1');
      return;
    }

    await database.insert('imperium_dispositivo_empresa', {
      'id': 1,
      'empresa_id': empresaLimpa,
      'user_id': userId.trim(),
      'email': email.trim().toLowerCase(),
      'vinculado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<LicencaStatus> consultar() async {
    final client = _client;

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final usuario = client.auth.currentUser;

    if (usuario == null) {
      throw StateError('Conta da nuvem não conectada.');
    }

    final resposta = await client.rpc('imperium_status_licenca');
    final status = _extrairStatus(resposta);

    await vincularDispositivoSeNecessario(
      empresaId: status.empresaId,
      userId: usuario.id,
      email: usuario.email ?? '',
    );

    return status;
  }

  Future<LicencaConsultaResultado> consultarComCacheOffline() async {
    final client = _client;
    final usuario = client?.auth.currentUser;

    if (usuario != null) {
      try {
        final status = await consultar();
        await _salvarCache(status);

        return LicencaConsultaResultado(
          status: status,
          usouCacheOffline: false,
        );
      } catch (_) {
        final cache = await _lerCacheValido();
        if (cache != null) {
          return LicencaConsultaResultado(
            status: cache,
            usouCacheOffline: true,
          );
        }
        rethrow;
      }
    }

    final cache = await _lerCacheValido();

    if (cache != null) {
      return LicencaConsultaResultado(status: cache, usouCacheOffline: true);
    }

    throw StateError(
      'Conecte a conta da empresa à nuvem para validar a licença.',
    );
  }

  LicencaStatus _extrairStatus(dynamic resposta) {
    if (resposta is List && resposta.isNotEmpty && resposta.first is Map) {
      return LicencaStatus.fromMap(
        Map<String, dynamic>.from(resposta.first as Map),
      );
    }

    if (resposta is Map) {
      return LicencaStatus.fromMap(Map<String, dynamic>.from(resposta));
    }

    throw StateError(
      'Não foi encontrada uma empresa ativa vinculada a esta conta.',
    );
  }

  Future<void> _salvarCache(LicencaStatus status) async {
    await garantirEstruturaLocal();
    final database = await AppDatabase.instance.database;

    await database.insert(
      'imperium_licenca_cache_v2',
      status.toCacheMap(DateTime.now()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LicencaStatus?> _lerCacheValido() async {
    await garantirEstruturaLocal();
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'imperium_licenca_cache_v2',
      where: 'id = 1',
      limit: 1,
    );

    if (resultado.isEmpty) return null;

    final mapa = Map<String, dynamic>.from(resultado.first);
    final consultadoEm = DateTime.tryParse(
      (mapa['consultado_em'] ?? '').toString(),
    );

    if (consultadoEm == null) return null;

    final idade = DateTime.now().difference(consultadoEm);

    if (idade.isNegative || idade > toleranciaOffline) {
      return null;
    }

    final empresaCache = (mapa['empresa_id'] ?? '').toString().trim();
    final empresaLocal = await empresaVinculadaAoDispositivo();

    if (empresaLocal != null &&
        empresaCache.isNotEmpty &&
        empresaLocal != empresaCache) {
      return null;
    }

    return LicencaStatus.fromMap(mapa);
  }
}
