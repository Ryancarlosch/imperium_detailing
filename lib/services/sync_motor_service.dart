import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'operacional_cloud_v2_service.dart';

typedef SyncMotorCallback = Future<void> Function();

class SyncMotorBloqueadoException implements Exception {
  const SyncMotorBloqueadoException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class SyncMotorEtapa {
  const SyncMotorEtapa({
    required this.modulo,
    required this.prioridade,
    required this.executar,
    this.dependencias = const <String>[],
  });

  final String modulo;
  final int prioridade;
  final List<String> dependencias;
  final SyncMotorCallback executar;
}

class SyncMotorResultado {
  const SyncMotorResultado({
    required this.cicloId,
    required this.status,
    required this.sucessos,
    required this.erros,
    required this.aguardando,
    required this.bloqueados,
  });

  final int cicloId;
  final String status;
  final int sucessos;
  final int erros;
  final int aguardando;
  final int bloqueados;

  bool get temProblemas => erros > 0 || bloqueados > 0;
}

class SyncMotorException implements Exception {
  const SyncMotorException(this.resultado);

  final SyncMotorResultado resultado;

  @override
  String toString() {
    return 'Sincronização ${resultado.status}: '
        '${resultado.sucessos} sucesso(s), '
        '${resultado.erros} erro(s), '
        '${resultado.bloqueados} bloqueado(s), '
        '${resultado.aguardando} aguardando retry.';
  }
}

/// Motor local de fila, retry/backoff e observabilidade.
///
/// Não substitui as regras de cada módulo. Ele orquestra os serviços Cloud
/// existentes e mantém estado por empresa no próprio SQLite do tenant.
class SyncMotorService {
  SyncMotorService._();

  static final SyncMotorService instance = SyncMotorService._();

  final AppDatabase _appDatabase = AppDatabase.instance;

  // sync-motor-unificado-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_motor_fila (
        empresa_id TEXT NOT NULL,
        modulo TEXT NOT NULL,
        prioridade INTEGER NOT NULL DEFAULT 100,
        status TEXT NOT NULL DEFAULT 'Pendente',
        tentativas_consecutivas INTEGER NOT NULL DEFAULT 0,
        ultima_tentativa_em TEXT,
        proxima_tentativa_em TEXT,
        ultimo_sucesso_em TEXT,
        ultimo_erro TEXT,
        duracao_ms INTEGER,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (empresa_id, modulo)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_motor_ciclos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        origem TEXT NOT NULL,
        status TEXT NOT NULL,
        iniciado_em TEXT NOT NULL,
        finalizado_em TEXT,
        total_modulos INTEGER NOT NULL DEFAULT 0,
        sucessos INTEGER NOT NULL DEFAULT 0,
        erros INTEGER NOT NULL DEFAULT 0,
        aguardando INTEGER NOT NULL DEFAULT 0,
        bloqueados INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_motor_eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ciclo_id INTEGER NOT NULL,
        empresa_id TEXT NOT NULL,
        modulo TEXT NOT NULL,
        status TEXT NOT NULL,
        iniciado_em TEXT NOT NULL,
        finalizado_em TEXT NOT NULL,
        duracao_ms INTEGER NOT NULL DEFAULT 0,
        erro TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_motor_eventos_empresa_data
      ON imperium_sync_motor_eventos (
        empresa_id,
        id DESC
      )
    ''');
  }

  Future<SyncMotorResultado> executar({
    required String empresaId,
    required String origem,
    required List<SyncMotorEtapa> etapas,
    bool ignorarBackoff = false,
  }) async {
    await garantirEstruturaLocal();

    final ordenadas = [...etapas]
      ..sort((a, b) => a.prioridade.compareTo(b.prioridade));

    final database = await _appDatabase.database;
    final inicio = DateTime.now();

    for (final etapa in ordenadas) {
      await database.insert('imperium_sync_motor_fila', {
        'empresa_id': empresaId,
        'modulo': etapa.modulo,
        'prioridade': etapa.prioridade,
        'status': 'Pendente',
        'tentativas_consecutivas': 0,
        'atualizado_em': inicio.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await database.update(
        'imperium_sync_motor_fila',
        {
          'prioridade': etapa.prioridade,
          'atualizado_em': inicio.toIso8601String(),
        },
        where: 'empresa_id = ? AND modulo = ?',
        whereArgs: [empresaId, etapa.modulo],
      );
    }

    final cicloId = await database.insert('imperium_sync_motor_ciclos', {
      'empresa_id': empresaId,
      'origem': origem,
      'status': 'Executando',
      'iniciado_em': inicio.toIso8601String(),
      'total_modulos': ordenadas.length,
    });

    final estados = <String, String>{};
    var sucessos = 0;
    var erros = 0;
    var aguardando = 0;
    var bloqueados = 0;

    for (final etapa in ordenadas) {
      final dependenciaFalhou = etapa.dependencias.any((dependencia) {
        final status = estados[dependencia];
        return status == 'Erro' ||
            status == 'Bloqueado' ||
            status == 'Aguardando';
      });

      if (dependenciaFalhou) {
        bloqueados++;
        estados[etapa.modulo] = 'Bloqueado';

        await _atualizarFila(
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Bloqueado',
          erro: 'Dependência do módulo não concluiu.',
        );

        await _registrarEvento(
          cicloId: cicloId,
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Bloqueado',
          iniciadoEm: DateTime.now(),
          finalizadoEm: DateTime.now(),
          duracaoMs: 0,
          erro: 'Dependência do módulo não concluiu.',
        );
        continue;
      }

      final fila = await _filaModulo(empresaId, etapa.modulo);
      final proxima = DateTime.tryParse(
        (fila?['proxima_tentativa_em'] ?? '').toString(),
      );

      if (!ignorarBackoff &&
          proxima != null &&
          proxima.isAfter(DateTime.now())) {
        aguardando++;
        estados[etapa.modulo] = 'Aguardando';

        await _atualizarFila(
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Aguardando',
        );

        await _registrarEvento(
          cicloId: cicloId,
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Aguardando',
          iniciadoEm: DateTime.now(),
          finalizadoEm: DateTime.now(),
          duracaoMs: 0,
          erro: 'Backoff até ${proxima.toIso8601String()}.',
        );
        continue;
      }

      final iniciado = DateTime.now();
      final relogio = Stopwatch()..start();

      await _atualizarFila(
        empresaId: empresaId,
        modulo: etapa.modulo,
        status: 'Executando',
        ultimaTentativaEm: iniciado,
      );

      try {
        // operacional-cloud-conflitos-v2
        // Clientes, veículos e agenda eram os últimos módulos-base sem
        // proteção de edição concorrente. Reconciliamos antes do callback para
        // impedir que o upload V1 sobrescreva silenciosamente outra versão.
        if (etapa.modulo == 'operacional') {
          final seguro = await OperacionalCloudV2Service.instance
              .prepararUpload(empresaId);
          if (!seguro) {
            throw const SyncMotorBloqueadoException(
              'Conflitos pendentes em Clientes, Veículos ou Agenda.',
            );
          }
        }

        await etapa.executar();
        relogio.stop();

        final agora = DateTime.now();
        sucessos++;
        estados[etapa.modulo] = 'Sucesso';

        await database.update(
          'imperium_sync_motor_fila',
          {
            'status': 'Sucesso',
            'tentativas_consecutivas': 0,
            'ultima_tentativa_em': iniciado.toIso8601String(),
            'proxima_tentativa_em': null,
            'ultimo_sucesso_em': agora.toIso8601String(),
            'ultimo_erro': null,
            'duracao_ms': relogio.elapsedMilliseconds,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'empresa_id = ? AND modulo = ?',
          whereArgs: [empresaId, etapa.modulo],
        );

        await _registrarEvento(
          cicloId: cicloId,
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Sucesso',
          iniciadoEm: iniciado,
          finalizadoEm: agora,
          duracaoMs: relogio.elapsedMilliseconds,
        );
      } on SyncMotorBloqueadoException catch (error) {
        relogio.stop();

        final agora = DateTime.now();
        bloqueados++;
        estados[etapa.modulo] = 'Bloqueado';

        await database.update(
          'imperium_sync_motor_fila',
          {
            'status': 'Bloqueado',
            'ultima_tentativa_em': iniciado.toIso8601String(),
            'proxima_tentativa_em': null,
            'ultimo_erro': error.mensagem,
            'duracao_ms': relogio.elapsedMilliseconds,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'empresa_id = ? AND modulo = ?',
          whereArgs: [empresaId, etapa.modulo],
        );

        await _registrarEvento(
          cicloId: cicloId,
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Bloqueado',
          iniciadoEm: iniciado,
          finalizadoEm: agora,
          duracaoMs: relogio.elapsedMilliseconds,
          erro: error.mensagem,
        );
      } catch (error) {
        relogio.stop();

        final agora = DateTime.now();
        final tentativas = _int(fila?['tentativas_consecutivas']) + 1;
        final proximaTentativa = agora.add(_backoff(tentativas));
        final mensagem = error.toString();

        erros++;
        estados[etapa.modulo] = 'Erro';

        await database.update(
          'imperium_sync_motor_fila',
          {
            'status': 'Erro',
            'tentativas_consecutivas': tentativas,
            'ultima_tentativa_em': iniciado.toIso8601String(),
            'proxima_tentativa_em': proximaTentativa.toIso8601String(),
            'ultimo_erro': mensagem,
            'duracao_ms': relogio.elapsedMilliseconds,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'empresa_id = ? AND modulo = ?',
          whereArgs: [empresaId, etapa.modulo],
        );

        await _registrarEvento(
          cicloId: cicloId,
          empresaId: empresaId,
          modulo: etapa.modulo,
          status: 'Erro',
          iniciadoEm: iniciado,
          finalizadoEm: agora,
          duracaoMs: relogio.elapsedMilliseconds,
          erro: mensagem,
        );
      }
    }

    final status = _statusCiclo(
      total: ordenadas.length,
      sucessos: sucessos,
      erros: erros,
      aguardando: aguardando,
      bloqueados: bloqueados,
    );

    await database.update(
      'imperium_sync_motor_ciclos',
      {
        'status': status,
        'finalizado_em': DateTime.now().toIso8601String(),
        'sucessos': sucessos,
        'erros': erros,
        'aguardando': aguardando,
        'bloqueados': bloqueados,
      },
      where: 'id = ?',
      whereArgs: [cicloId],
    );

    return SyncMotorResultado(
      cicloId: cicloId,
      status: status,
      sucessos: sucessos,
      erros: erros,
      aguardando: aguardando,
      bloqueados: bloqueados,
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final ultimoCiclo = await database.query(
      'imperium_sync_motor_ciclos',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'id DESC',
      limit: 1,
    );

    final contagens = await database.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN status = 'Sucesso' THEN 1 ELSE 0 END) AS sucesso,
        SUM(CASE WHEN status = 'Erro' THEN 1 ELSE 0 END) AS erro,
        SUM(CASE WHEN status = 'Aguardando' THEN 1 ELSE 0 END) AS aguardando,
        SUM(CASE WHEN status = 'Bloqueado' THEN 1 ELSE 0 END) AS bloqueado,
        COUNT(*) AS total
      FROM imperium_sync_motor_fila
      WHERE empresa_id = ?
      ''',
      [empresaId],
    );

    final ultimaExecucao = await database.query(
      'imperium_sync_motor_fila',
      columns: ['MAX(ultimo_sucesso_em) AS ultimo_sucesso_em'],
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
    );

    final fila = contagens.isEmpty
        ? const <String, Object?>{}
        : contagens.first;

    return <String, Object?>{
      'empresa_id': empresaId,
      'ultimo_ciclo_id': ultimoCiclo.isEmpty ? null : ultimoCiclo.first['id'],
      'ultimo_ciclo_status': ultimoCiclo.isEmpty
          ? 'Nunca executado'
          : ultimoCiclo.first['status'],
      'ultimo_ciclo_inicio': ultimoCiclo.isEmpty
          ? null
          : ultimoCiclo.first['iniciado_em'],
      'ultimo_ciclo_fim': ultimoCiclo.isEmpty
          ? null
          : ultimoCiclo.first['finalizado_em'],
      'modulos_total': _int(fila['total']),
      'modulos_sucesso': _int(fila['sucesso']),
      'modulos_erro': _int(fila['erro']),
      'modulos_aguardando': _int(fila['aguardando']),
      'modulos_bloqueados': _int(fila['bloqueado']),
      'ultimo_sucesso_em': ultimaExecucao.isEmpty
          ? null
          : ultimaExecucao.first['ultimo_sucesso_em'],
    };
  }

  Future<List<Map<String, Object?>>> listarFila(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_motor_fila',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'prioridade ASC, modulo ASC',
    );
  }

  Future<List<Map<String, Object?>>> listarEventosRecentes(
    String empresaId, {
    int limite = 12,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_motor_eventos',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      orderBy: 'id DESC',
      limit: limite,
    );
  }

  Future<void> liberarBackoff(String empresaId, {String? modulo}) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    await database.update(
      'imperium_sync_motor_fila',
      {
        'status': 'Pendente',
        'proxima_tentativa_em': null,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: modulo == null
          ? 'empresa_id = ?'
          : 'empresa_id = ? AND modulo = ?',
      whereArgs: modulo == null ? [empresaId] : [empresaId, modulo],
    );
  }

  Future<Map<String, Object?>?> _filaModulo(
    String empresaId,
    String modulo,
  ) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_motor_fila',
      where: 'empresa_id = ? AND modulo = ?',
      whereArgs: [empresaId, modulo],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _atualizarFila({
    required String empresaId,
    required String modulo,
    required String status,
    DateTime? ultimaTentativaEm,
    String? erro,
  }) async {
    final database = await _appDatabase.database;

    final valores = <String, Object?>{
      'status': status,
      'atualizado_em': DateTime.now().toIso8601String(),
    };

    if (ultimaTentativaEm != null) {
      valores['ultima_tentativa_em'] = ultimaTentativaEm.toIso8601String();
    }

    if (erro != null) {
      valores['ultimo_erro'] = erro;
    }

    await database.update(
      'imperium_sync_motor_fila',
      valores,
      where: 'empresa_id = ? AND modulo = ?',
      whereArgs: [empresaId, modulo],
    );
  }

  Future<void> _registrarEvento({
    required int cicloId,
    required String empresaId,
    required String modulo,
    required String status,
    required DateTime iniciadoEm,
    required DateTime finalizadoEm,
    required int duracaoMs,
    String? erro,
  }) async {
    final database = await _appDatabase.database;

    await database.insert('imperium_sync_motor_eventos', {
      'ciclo_id': cicloId,
      'empresa_id': empresaId,
      'modulo': modulo,
      'status': status,
      'iniciado_em': iniciadoEm.toIso8601String(),
      'finalizado_em': finalizadoEm.toIso8601String(),
      'duracao_ms': duracaoMs,
      'erro': erro,
    });
  }

  Duration _backoff(int tentativa) {
    const segundos = <int>[15, 30, 60, 120, 300, 600, 1200, 1800];

    final indice = tentativa <= 1
        ? 0
        : tentativa >= segundos.length
        ? segundos.length - 1
        : tentativa - 1;

    return Duration(seconds: segundos[indice]);
  }

  String _statusCiclo({
    required int total,
    required int sucessos,
    required int erros,
    required int aguardando,
    required int bloqueados,
  }) {
    if (total == 0) return 'Vazio';

    if (sucessos == total) return 'Sucesso';

    if (sucessos == 0 && erros > 0) return 'Erro';

    if (sucessos == 0 && erros == 0 && (aguardando + bloqueados) > 0) {
      return 'Aguardando';
    }

    return 'Parcial';
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }
}
