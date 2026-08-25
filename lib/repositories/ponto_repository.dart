import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';

class PontoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  static const List<String> situacoes = <String>[
    'Trabalhado',
    'Falta',
    'Atestado',
    'Folga',
  ];

  Future<void> garantirEstrutura() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);
  }

  Future<void> _garantirEstrutura(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_jornada (
        dia_semana INTEGER PRIMARY KEY,
        ativo INTEGER NOT NULL DEFAULT 0,
        entrada TEXT,
        intervalo_inicio TEXT,
        intervalo_fim TEXT,
        saida TEXT,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        situacao TEXT NOT NULL DEFAULT 'Trabalhado',
        entrada TEXT,
        intervalo_inicio TEXT,
        intervalo_fim TEXT,
        saida TEXT,
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        UNIQUE (colaborador_id, data),
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_ponto_registros_colaborador_data
      ON financeiro_ponto_registros (colaborador_id, data)
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_ajustes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        acao TEXT NOT NULL,
        motivo TEXT NOT NULL,
        antes_json TEXT,
        depois_json TEXT,
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        adicional_hora_extra REAL NOT NULL DEFAULT 50,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await database.rawInsert(
      '''
      INSERT OR IGNORE INTO financeiro_ponto_config (
        id,
        adicional_hora_extra,
        atualizado_em
      ) VALUES (1, 50, ?)
      ''',
      [DateTime.now().toIso8601String()],
    );

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_fechamentos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        competencia TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Aberto',
        snapshot_json TEXT,
        fechado_em TEXT,
        reaberto_em TEXT,
        motivo_reabertura TEXT NOT NULL DEFAULT '',
        atualizado_em TEXT NOT NULL,
        UNIQUE (colaborador_id, competencia),
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_ponto_fechamentos_competencia
      ON financeiro_ponto_fechamentos (
        competencia,
        status
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_ponto_fechamento_historico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        competencia TEXT NOT NULL,
        acao TEXT NOT NULL,
        motivo TEXT NOT NULL DEFAULT '',
        snapshot_json TEXT,
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');

    final quantidade =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM financeiro_ponto_jornada',
          ),
        ) ??
        0;

    if (quantidade == 0) {
      final agora = DateTime.now().toIso8601String();

      for (var dia = DateTime.monday; dia <= DateTime.friday; dia++) {
        await database.insert('financeiro_ponto_jornada', {
          'dia_semana': dia,
          'ativo': 1,
          'entrada': '08:00',
          'intervalo_inicio': '12:00',
          'intervalo_fim': '13:00',
          'saida': '17:00',
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await database.insert('financeiro_ponto_jornada', {
        'dia_semana': DateTime.saturday,
        'ativo': 1,
        'entrada': '08:00',
        'intervalo_inicio': null,
        'intervalo_fim': null,
        'saida': '12:00',
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await database.insert('financeiro_ponto_jornada', {
        'dia_semana': DateTime.sunday,
        'ativo': 0,
        'entrada': null,
        'intervalo_inicio': null,
        'intervalo_fim': null,
        'saida': null,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<double> obterAdicionalHoraExtra() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_ponto_config',
      columns: ['adicional_hora_extra'],
      where: 'id = 1',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return 50.0;
    }

    return _double(
      resultado.first['adicional_hora_extra'],
      50.0,
    ).clamp(0.0, 500.0).toDouble();
  }

  Future<void> salvarAdicionalHoraExtra(double percentual) async {
    if (percentual < 0 || percentual > 500) {
      throw ArgumentError(
        'O adicional de hora extra deve ficar entre 0% e 500%.',
      );
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.update('financeiro_ponto_config', {
      'adicional_hora_extra': percentual,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
  }

  Future<List<Map<String, dynamic>>> listarJornada() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_ponto_jornada',
      orderBy: 'dia_semana ASC',
    );

    final porDia = <int, Map<String, dynamic>>{
      for (final item in resultado)
        _int(item['dia_semana']): Map<String, dynamic>.from(item),
    };

    return List.generate(7, (indice) {
      final dia = indice + 1;
      return porDia[dia] ??
          {
            'dia_semana': dia,
            'ativo': 0,
            'entrada': null,
            'intervalo_inicio': null,
            'intervalo_fim': null,
            'saida': null,
          };
    });
  }

  Future<void> salvarJornadaDia({
    required int diaSemana,
    required bool ativo,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
  }) async {
    if (diaSemana < 1 || diaSemana > 7) {
      throw ArgumentError('Dia da semana inválido.');
    }

    if (ativo) {
      _validarPeriodo(
        entrada: entrada,
        intervaloInicio: intervaloInicio,
        intervaloFim: intervaloFim,
        saida: saida,
        exigirPontoCompleto: true,
      );
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.insert('financeiro_ponto_jornada', {
      'dia_semana': diaSemana,
      'ativo': ativo ? 1 : 0,
      'entrada': ativo ? _horaNula(entrada) : null,
      'intervalo_inicio': ativo ? _horaNula(intervaloInicio) : null,
      'intervalo_fim': ativo ? _horaNula(intervaloFim) : null,
      'saida': ativo ? _horaNula(saida) : null,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> obterFechamentoCompetencia({
    required int colaboradorId,
    required DateTime competencia,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_ponto_fechamentos',
      where: 'colaborador_id = ? AND competencia = ?',
      whereArgs: [colaboradorId, _competencia(competencia)],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<List<Map<String, dynamic>>> listarHistoricoFechamento({
    required int colaboradorId,
    required DateTime competencia,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    return database.query(
      'financeiro_ponto_fechamento_historico',
      where: 'colaborador_id = ? AND competencia = ?',
      whereArgs: [colaboradorId, _competencia(competencia)],
      orderBy: 'id DESC',
    );
  }

  Future<void> fecharCompetencia({
    required int colaboradorId,
    required DateTime competencia,
  }) async {
    final inicio = DateTime(competencia.year, competencia.month, 1);
    final fim = DateTime(competencia.year, competencia.month + 1, 0);
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);

    if (!hojeDia.isAfter(fim)) {
      throw StateError(
        'O mês só pode ser fechado depois que a competência terminar.',
      );
    }

    final resumo = await obterFechamentoMes(
      colaboradorId: colaboradorId,
      inicio: inicio,
      fim: fim,
    );

    if ((resumo['fechamento_status'] ?? '').toString() == 'Fechado') {
      return;
    }

    final pendencias = _int(resumo['pendencias']);
    final incompletos = _int(resumo['incompletos']);

    if (pendencias > 0 || incompletos > 0) {
      final partes = <String>[];
      if (pendencias > 0) {
        partes.add(
          '$pendencias ${pendencias == 1 ? 'dia pendente' : 'dias pendentes'}',
        );
      }
      if (incompletos > 0) {
        partes.add(
          '$incompletos ${incompletos == 1 ? 'ponto incompleto' : 'pontos incompletos'}',
        );
      }

      throw StateError('Resolva ${partes.join(' e ')} antes de fechar o mês.');
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirEstrutura(transaction);

      final colaborador = await transaction.query(
        'financeiro_colaboradores_custo',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [colaboradorId],
        limit: 1,
      );

      if (colaborador.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final competenciaBanco = _competencia(competencia);
      final agora = DateTime.now().toIso8601String();
      final snapshot = jsonEncode(resumo);

      await transaction.insert(
        'financeiro_ponto_fechamentos',
        {
          'colaborador_id': colaboradorId,
          'competencia': competenciaBanco,
          'status': 'Fechado',
          'snapshot_json': snapshot,
          'fechado_em': agora,
          'reaberto_em': null,
          'motivo_reabertura': '',
          'atualizado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await transaction.insert(
        'financeiro_ponto_fechamento_historico',
        {
          'colaborador_id': colaboradorId,
          'competencia': competenciaBanco,
          'acao': 'Fechamento',
          'motivo': 'Competência aprovada pelo administrador',
          'snapshot_json': snapshot,
          'criado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<void> reabrirCompetencia({
    required int colaboradorId,
    required DateTime competencia,
    required String motivo,
  }) async {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe o motivo da reabertura com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirEstrutura(transaction);

      final resultado = await transaction.query(
        'financeiro_ponto_fechamentos',
        where: 'colaborador_id = ? AND competencia = ? AND status = ?',
        whereArgs: [colaboradorId, _competencia(competencia), 'Fechado'],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Esta competência não está fechada.');
      }

      final agora = DateTime.now().toIso8601String();
      final snapshot = resultado.first['snapshot_json']?.toString();

      await transaction.update(
        'financeiro_ponto_fechamentos',
        {
          'status': 'Aberto',
          'reaberto_em': agora,
          'motivo_reabertura': motivoLimpo,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [_int(resultado.first['id'])],
      );

      await transaction.insert(
        'financeiro_ponto_fechamento_historico',
        {
          'colaborador_id': colaboradorId,
          'competencia': _competencia(competencia),
          'acao': 'Reabertura',
          'motivo': motivoLimpo,
          'snapshot_json': snapshot,
          'criado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<void> _garantirCompetenciaAberta(
    DatabaseExecutor executor, {
    required int colaboradorId,
    required DateTime data,
  }) async {
    final resultado = await executor.query(
      'financeiro_ponto_fechamentos',
      columns: ['id'],
      where: 'colaborador_id = ? AND competencia = ? AND status = ?',
      whereArgs: [colaboradorId, _competencia(data), 'Fechado'],
      limit: 1,
    );

    if (resultado.isNotEmpty) {
      throw StateError(
        'O ponto desta competência está fechado. '
        'Reabra o mês antes de alterar os registros.',
      );
    }
  }

  Future<Map<String, dynamic>> obterEstadoBatidaHoje(
    int colaboradorId, {
    DateTime? agora,
  }) async {
    final momento = agora ?? DateTime.now();
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final jornadaResultado = await database.query(
      'financeiro_ponto_jornada',
      where: 'dia_semana = ?',
      whereArgs: [momento.weekday],
      limit: 1,
    );

    final jornada = jornadaResultado.isEmpty
        ? <String, dynamic>{
            'dia_semana': momento.weekday,
            'ativo': 0,
            'entrada': null,
            'intervalo_inicio': null,
            'intervalo_fim': null,
            'saida': null,
          }
        : Map<String, dynamic>.from(jornadaResultado.first);

    final jornadaAtiva = _int(jornada['ativo']) == 1;

    final registroResultado = await database.query(
      'financeiro_ponto_registros',
      where: 'colaborador_id = ? AND data = ?',
      whereArgs: [colaboradorId, _data(momento)],
      limit: 1,
    );

    final registro = registroResultado.isEmpty
        ? null
        : Map<String, dynamic>.from(registroResultado.first);

    if (registro == null) {
      if (!jornadaAtiva) {
        return {
          'colaborador_id': colaboradorId,
          'data': _data(momento),
          'jornada_ativa': 0,
          'jornada': jornada,
          'registro': null,
          'proxima_acao': null,
          'rotulo': 'Sem expediente',
          'concluido': 1,
        };
      }

      return {
        'colaborador_id': colaboradorId,
        'data': _data(momento),
        'jornada_ativa': 1,
        'jornada': jornada,
        'registro': null,
        'proxima_acao': 'entrada',
        'rotulo': 'Registrar entrada',
        'concluido': 0,
      };
    }

    final situacao = (registro['situacao'] ?? '').toString();

    if (situacao != 'Trabalhado') {
      return {
        'colaborador_id': colaboradorId,
        'data': _data(momento),
        'jornada_ativa': jornadaAtiva ? 1 : 0,
        'jornada': jornada,
        'registro': registro,
        'proxima_acao': null,
        'rotulo': situacao,
        'concluido': 1,
      };
    }

    final entrada = _horaNula(registro['entrada']?.toString());
    final saida = _horaNula(registro['saida']?.toString());

    if (saida != null) {
      return {
        'colaborador_id': colaboradorId,
        'data': _data(momento),
        'jornada_ativa': jornadaAtiva ? 1 : 0,
        'jornada': jornada,
        'registro': registro,
        'proxima_acao': null,
        'rotulo': 'Ponto concluído',
        'concluido': 1,
      };
    }

    if (entrada == null) {
      return {
        'colaborador_id': colaboradorId,
        'data': _data(momento),
        'jornada_ativa': jornadaAtiva ? 1 : 0,
        'jornada': jornada,
        'registro': registro,
        'proxima_acao': null,
        'rotulo': 'Ponto precisa de correção',
        'concluido': 1,
      };
    }

    return {
      'colaborador_id': colaboradorId,
      'data': _data(momento),
      'jornada_ativa': jornadaAtiva ? 1 : 0,
      'jornada': jornada,
      'registro': registro,
      'proxima_acao': 'saida',
      'rotulo': 'Registrar saída',
      'concluido': 0,
    };
  }

  Future<Map<String, dynamic>> registrarBatida({
    required int colaboradorId,
    DateTime? momento,
  }) async {
    final agora = momento ?? DateTime.now();
    final database = await _appDatabase.database;

    return database.transaction<Map<String, dynamic>>((transaction) async {
      await _garantirEstrutura(transaction);

      final colaborador = await transaction.query(
        'financeiro_colaboradores_custo',
        columns: ['id', 'nome', 'ativo'],
        where: 'id = ?',
        whereArgs: [colaboradorId],
        limit: 1,
      );

      if (colaborador.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      if (_int(colaborador.first['ativo']) != 1) {
        throw StateError('O funcionário está inativo.');
      }

      final dataBanco = _data(agora);
      final horaBanco = _hora(agora);

      await _garantirCompetenciaAberta(
        transaction,
        colaboradorId: colaboradorId,
        data: agora,
      );

      final jornadaResultado = await transaction.query(
        'financeiro_ponto_jornada',
        where: 'dia_semana = ?',
        whereArgs: [agora.weekday],
        limit: 1,
      );

      final jornada = jornadaResultado.isEmpty
          ? <String, dynamic>{
              'ativo': 0,
              'entrada': null,
              'intervalo_inicio': null,
              'intervalo_fim': null,
              'saida': null,
            }
          : Map<String, dynamic>.from(jornadaResultado.first);

      final jornadaAtiva = _int(jornada['ativo']) == 1;

      final existente = await transaction.query(
        'financeiro_ponto_registros',
        where: 'colaborador_id = ? AND data = ?',
        whereArgs: [colaboradorId, dataBanco],
        limit: 1,
      );

      Map<String, dynamic>? antes;
      late Map<String, dynamic> depois;
      late String acao;

      var intervaloAutomatico = false;
      var requerConferencia = false;

      if (existente.isEmpty) {
        if (!jornadaAtiva) {
          throw StateError('Hoje não há jornada de trabalho configurada.');
        }

        acao = 'Entrada';
        final criadoEm = agora.toIso8601String();

        final id = await transaction.insert('financeiro_ponto_registros', {
          'colaborador_id': colaboradorId,
          'data': dataBanco,
          'situacao': 'Trabalhado',
          'entrada': horaBanco,
          'intervalo_inicio': null,
          'intervalo_fim': null,
          'saida': null,
          'observacoes': '',
          'criado_em': criadoEm,
          'atualizado_em': criadoEm,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        depois = {
          'id': id,
          'colaborador_id': colaboradorId,
          'data': dataBanco,
          'situacao': 'Trabalhado',
          'entrada': horaBanco,
          'intervalo_inicio': null,
          'intervalo_fim': null,
          'saida': null,
          'observacoes': '',
          'criado_em': criadoEm,
          'atualizado_em': criadoEm,
        };
      } else {
        antes = Map<String, dynamic>.from(existente.first);

        final situacao = (antes['situacao'] ?? '').toString();

        if (situacao != 'Trabalhado') {
          throw StateError(
            'Este dia está marcado como '
            '"$situacao". Use a edição manual.',
          );
        }

        final entrada = _horaNula(antes['entrada']?.toString());
        final saidaAtual = _horaNula(antes['saida']?.toString());

        if (entrada == null) {
          throw StateError(
            'Este ponto está sem entrada. '
            'Use a correção administrativa.',
          );
        }

        if (saidaAtual != null) {
          throw StateError('O ponto de hoje já foi concluído.');
        }

        acao = 'Saída';

        final alteracoes = <String, dynamic>{
          'saida': horaBanco,
          'atualizado_em': agora.toIso8601String(),
        };

        final intervaloInicioAtual = _horaNula(
          antes['intervalo_inicio']?.toString(),
        );
        final intervaloFimAtual = _horaNula(antes['intervalo_fim']?.toString());

        final intervaloInicioPrevisto = _horaNula(
          jornada['intervalo_inicio']?.toString(),
        );
        final intervaloFimPrevisto = _horaNula(
          jornada['intervalo_fim']?.toString(),
        );

        final temIntervaloPrevisto =
            intervaloInicioPrevisto != null && intervaloFimPrevisto != null;

        if (temIntervaloPrevisto) {
          final entradaMin = _minutosHora(entrada);
          final saidaMin = _minutosHora(horaBanco);
          final inicioPrevistoMin = _minutosHora(intervaloInicioPrevisto);
          final fimPrevistoMin = _minutosHora(intervaloFimPrevisto);

          if (intervaloInicioAtual == null &&
              intervaloFimAtual == null &&
              entradaMin != null &&
              saidaMin != null &&
              inicioPrevistoMin != null &&
              fimPrevistoMin != null &&
              entradaMin <= inicioPrevistoMin &&
              saidaMin >= fimPrevistoMin) {
            alteracoes['intervalo_inicio'] = intervaloInicioPrevisto;
            alteracoes['intervalo_fim'] = intervaloFimPrevisto;
            intervaloAutomatico = true;
          } else if (intervaloInicioAtual != null &&
              intervaloFimAtual == null &&
              saidaMin != null &&
              fimPrevistoMin != null &&
              saidaMin >= fimPrevistoMin) {
            final inicioAtualMin = _minutosHora(intervaloInicioAtual);

            if (inicioAtualMin != null && inicioAtualMin < fimPrevistoMin) {
              alteracoes['intervalo_fim'] = intervaloFimPrevisto;
              intervaloAutomatico = true;
            }
          }
        }

        _validarSequenciaBatida(anterior: antes, alteracoes: alteracoes);

        await transaction.update(
          'financeiro_ponto_registros',
          alteracoes,
          where: 'id = ?',
          whereArgs: [_int(antes['id'])],
        );

        depois = {...antes, ...alteracoes};

        final inicioDepois = _horaNula(depois['intervalo_inicio']?.toString());
        final fimDepois = _horaNula(depois['intervalo_fim']?.toString());

        requerConferencia =
            temIntervaloPrevisto && (inicioDepois == null || fimDepois == null);
      }

      await transaction.insert('financeiro_ponto_ajustes', {
        'colaborador_id': colaboradorId,
        'data': dataBanco,
        'acao': 'Batida - $acao',
        'motivo': 'Batida registrada no controle de ponto',
        'antes_json': antes == null ? null : jsonEncode(antes),
        'depois_json': jsonEncode(depois),
        'criado_em': agora.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      return {
        'acao': acao,
        'hora': horaBanco,
        'intervalo_automatico': intervaloAutomatico,
        'requer_conferencia': requerConferencia,
        'registro': depois,
      };
    });
  }

  void _validarSequenciaBatida({
    required Map<String, dynamic> anterior,
    required Map<String, dynamic> alteracoes,
  }) {
    final entrada = _minutosHora(
      (alteracoes['entrada'] ?? anterior['entrada'])?.toString(),
    );
    final intervaloInicio = _minutosHora(
      (alteracoes['intervalo_inicio'] ?? anterior['intervalo_inicio'])
          ?.toString(),
    );
    final intervaloFim = _minutosHora(
      (alteracoes['intervalo_fim'] ?? anterior['intervalo_fim'])?.toString(),
    );
    final saida = _minutosHora(
      (alteracoes['saida'] ?? anterior['saida'])?.toString(),
    );

    if (entrada == null) {
      throw StateError('Registre a entrada antes das demais batidas.');
    }

    if (intervaloInicio != null && intervaloInicio <= entrada) {
      throw StateError(
        'O início do intervalo precisa ser posterior à entrada.',
      );
    }

    if (intervaloFim != null) {
      if (intervaloInicio == null) {
        throw StateError('Registre o início do intervalo antes da volta.');
      }
      if (intervaloFim <= intervaloInicio) {
        throw StateError(
          'A volta do intervalo precisa ser posterior ao início.',
        );
      }
    }

    if (saida != null) {
      final referencia = intervaloFim ?? intervaloInicio ?? entrada;
      if (saida <= referencia) {
        throw StateError(
          'A saída precisa ser posterior às batidas anteriores.',
        );
      }
    }
  }

  Future<Map<String, dynamic>?> buscarRegistro({
    required int colaboradorId,
    required DateTime data,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_ponto_registros',
      where: 'colaborador_id = ? AND data = ?',
      whereArgs: [colaboradorId, _data(data)],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<int> salvarRegistro({
    required int colaboradorId,
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    String motivoAjuste = '',
  }) async {
    if (!situacoes.contains(situacao)) {
      throw ArgumentError('Situação do ponto inválida.');
    }

    if (situacao == 'Trabalhado') {
      _validarPeriodo(
        entrada: entrada,
        intervaloInicio: intervaloInicio,
        intervaloFim: intervaloFim,
        saida: saida,
        exigirPontoCompleto: true,
      );
    }

    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirEstrutura(transaction);

      final colaborador = await transaction.query(
        'financeiro_colaboradores_custo',
        columns: ['id', 'ativo'],
        where: 'id = ?',
        whereArgs: [colaboradorId],
        limit: 1,
      );

      if (colaborador.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final dataBanco = _data(data);

      await _garantirCompetenciaAberta(
        transaction,
        colaboradorId: colaboradorId,
        data: data,
      );

      final anterior = await transaction.query(
        'financeiro_ponto_registros',
        where: 'colaborador_id = ? AND data = ?',
        whereArgs: [colaboradorId, dataBanco],
        limit: 1,
      );

      final agora = DateTime.now().toIso8601String();
      final dados = <String, dynamic>{
        'colaborador_id': colaboradorId,
        'data': dataBanco,
        'situacao': situacao,
        'entrada': situacao == 'Trabalhado' ? _horaNula(entrada) : null,
        'intervalo_inicio': situacao == 'Trabalhado'
            ? _horaNula(intervaloInicio)
            : null,
        'intervalo_fim': situacao == 'Trabalhado'
            ? _horaNula(intervaloFim)
            : null,
        'saida': situacao == 'Trabalhado' ? _horaNula(saida) : null,
        'observacoes': observacoes.trim(),
        'atualizado_em': agora,
      };

      int id;
      String acao;

      if (anterior.isEmpty) {
        dados['criado_em'] = agora;
        id = await transaction.insert(
          'financeiro_ponto_registros',
          dados,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        acao = 'Criacao';
      } else {
        final motivo = motivoAjuste.trim();
        if (motivo.length < 5) {
          throw ArgumentError(
            'Informe o motivo da alteração com pelo menos 5 caracteres.',
          );
        }

        id = _int(anterior.first['id']);
        await transaction.update(
          'financeiro_ponto_registros',
          dados,
          where: 'id = ?',
          whereArgs: [id],
        );
        acao = 'Edicao';
      }

      await transaction.insert('financeiro_ponto_ajustes', {
        'colaborador_id': colaboradorId,
        'data': dataBanco,
        'acao': acao,
        'motivo': anterior.isEmpty
            ? 'Lançamento manual pelo administrador'
            : motivoAjuste.trim(),
        'antes_json': anterior.isEmpty ? null : jsonEncode(anterior.first),
        'depois_json': jsonEncode({...dados, 'id': id}),
        'criado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      return id;
    });
  }

  Future<void> removerRegistro({
    required int registroId,
    required String motivo,
  }) async {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe o motivo da exclusão com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirEstrutura(transaction);

      final anterior = await transaction.query(
        'financeiro_ponto_registros',
        where: 'id = ?',
        whereArgs: [registroId],
        limit: 1,
      );

      if (anterior.isEmpty) {
        throw StateError('Registro de ponto não encontrado.');
      }

      final colaboradorId = _int(anterior.first['colaborador_id']);
      final data = (anterior.first['data'] ?? '').toString();
      final dataRegistro = DateTime.tryParse(data);

      if (dataRegistro != null) {
        await _garantirCompetenciaAberta(
          transaction,
          colaboradorId: colaboradorId,
          data: dataRegistro,
        );
      }

      await transaction.delete(
        'financeiro_ponto_registros',
        where: 'id = ?',
        whereArgs: [registroId],
      );

      await transaction.insert('financeiro_ponto_ajustes', {
        'colaborador_id': colaboradorId,
        'data': data,
        'acao': 'Exclusao',
        'motivo': motivoLimpo,
        'antes_json': jsonEncode(anterior.first),
        'depois_json': null,
        'criado_em': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<List<Map<String, dynamic>>> listarHistoricoAjustes({
    required int colaboradorId,
    required DateTime data,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    return database.query(
      'financeiro_ponto_ajustes',
      where: 'colaborador_id = ? AND data = ?',
      whereArgs: [colaboradorId, _data(data)],
      orderBy: 'id DESC',
    );
  }

  Future<Set<String>> listarDiasCorrigidos({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.rawQuery(
      '''
      SELECT DISTINCT data
      FROM financeiro_ponto_ajustes
      WHERE colaborador_id = ?
        AND date(data) BETWEEN date(?) AND date(?)
        AND acao IN ('Criacao', 'Edicao', 'Exclusao')
      ORDER BY data ASC
      ''',
      [colaboradorId, _data(inicio), _data(fim)],
    );

    return resultado
        .map((item) => item['data']?.toString().trim() ?? '')
        .where((data) => data.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>> obterEspelhoMes({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final jornada = await listarJornada();
    final jornadaPorDia = <int, Map<String, dynamic>>{
      for (final item in jornada) _int(item['dia_semana']): item,
    };

    final registros = await database.query(
      'financeiro_ponto_registros',
      where: 'colaborador_id = ? AND date(data) BETWEEN date(?) AND date(?)',
      whereArgs: [colaboradorId, _data(inicio), _data(fim)],
      orderBy: 'data ASC',
    );

    final porData = <String, Map<String, dynamic>>{
      for (final item in registros)
        (item['data'] ?? '').toString(): Map<String, dynamic>.from(item),
    };

    var previstosMes = 0;
    var trabalhados = 0;
    var extras = 0;
    var faltantes = 0;
    var atrasos = 0;
    var faltas = 0;
    var atestados = 0;
    var folgas = 0;
    var pendencias = 0;
    var incompletos = 0;

    final dias = <Map<String, dynamic>>[];
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);

    var cursor = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day);

    while (!cursor.isAfter(fimDia)) {
      final jornadaDia =
          jornadaPorDia[cursor.weekday] ?? <String, dynamic>{'ativo': 0};
      final ativo = _int(jornadaDia['ativo']) == 1;
      final previsto = ativo ? _minutosJornada(jornadaDia) : 0;

      previstosMes += previsto;

      final dataBanco = _data(cursor);
      final registro = porData[dataBanco];
      final situacao = (registro?['situacao'] ?? '').toString();
      final passado = cursor.isBefore(hojeDia);
      final hojeMesmo = cursor == hojeDia;

      var trabalhadoDia = 0;
      var extraDia = 0;
      var faltanteDia = 0;
      var atrasoDia = 0;
      var statusExibido = situacao;

      if (registro != null) {
        if (situacao == 'Trabalhado') {
          final entradaRegistrada = _horaNula(registro['entrada']?.toString());
          final saidaRegistrada = _horaNula(registro['saida']?.toString());
          final inicioIntervaloRegistrado = _horaNula(
            registro['intervalo_inicio']?.toString(),
          );
          final fimIntervaloRegistrado = _horaNula(
            registro['intervalo_fim']?.toString(),
          );

          final jornadaTemIntervalo =
              _horaNula(jornadaDia['intervalo_inicio']?.toString()) != null &&
              _horaNula(jornadaDia['intervalo_fim']?.toString()) != null;

          final pontoIncompleto =
              entradaRegistrada == null ||
              saidaRegistrada == null ||
              (jornadaTemIntervalo &&
                  (inicioIntervaloRegistrado == null ||
                      fimIntervaloRegistrado == null));

          if (pontoIncompleto) {
            if (passado) {
              incompletos++;
              statusExibido = 'Incompleto';
            } else if (hojeMesmo) {
              statusExibido = 'Em andamento';
            }
          }

          trabalhadoDia = _minutosRegistro(registro);
          extraDia = ativo && trabalhadoDia > previsto
              ? trabalhadoDia - previsto
              : 0;
          faltanteDia = ativo && trabalhadoDia < previsto
              ? previsto - trabalhadoDia
              : 0;

          atrasoDia = ativo
              ? _atrasoMinutos(
                  jornadaDia['entrada']?.toString(),
                  registro['entrada']?.toString(),
                )
              : 0;
        } else if (situacao == 'Falta') {
          faltas++;
          faltanteDia = ativo ? previsto : 0;
        } else if (situacao == 'Atestado') {
          atestados++;
        } else if (situacao == 'Folga') {
          folgas++;
        }
      } else if (ativo && passado) {
        statusExibido = 'Pendente';
        pendencias++;
      } else if (ativo && hojeMesmo) {
        statusExibido = 'Hoje';
      } else if (ativo) {
        statusExibido = 'Previsto';
      } else {
        statusExibido = 'Sem jornada';
      }

      trabalhados += trabalhadoDia;
      extras += extraDia;
      faltantes += faltanteDia;
      atrasos += atrasoDia;

      dias.add({
        'data': dataBanco,
        'dia_semana': cursor.weekday,
        'jornada_ativa': ativo ? 1 : 0,
        'jornada_entrada': jornadaDia['entrada'],
        'jornada_intervalo_inicio': jornadaDia['intervalo_inicio'],
        'jornada_intervalo_fim': jornadaDia['intervalo_fim'],
        'jornada_saida': jornadaDia['saida'],
        'minutos_previstos': previsto,
        'minutos_trabalhados': trabalhadoDia,
        'minutos_extras': extraDia,
        'minutos_faltantes': faltanteDia,
        'minutos_atraso': atrasoDia,
        'status_exibido': statusExibido,
        'registro': registro,
      });

      cursor = cursor.add(const Duration(days: 1));
    }

    return {
      'colaborador_id': colaboradorId,
      'minutos_previstos_mes': previstosMes,
      'minutos_trabalhados': trabalhados,
      'minutos_extras': extras,
      'minutos_faltantes': faltantes,
      'minutos_atraso': atrasos,
      'faltas': faltas,
      'atestados': atestados,
      'folgas': folgas,
      'pendencias': pendencias,
      'incompletos': incompletos,
      'dias': dias,
    };
  }

  Future<Map<String, dynamic>> obterFechamentoMes({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final colaborador = await database.query(
      'financeiro_colaboradores_custo',
      columns: [
        'id',
        'nome',
        'remuneracao_mensal',
        'horas_produtivas_mes',
        'ativo',
      ],
      where: 'id = ?',
      whereArgs: [colaboradorId],
      limit: 1,
    );

    if (colaborador.isEmpty) {
      throw StateError('Funcionário não encontrado.');
    }

    final espelho = await obterEspelhoMes(
      colaboradorId: colaboradorId,
      inicio: inicio,
      fim: fim,
    );

    final salarioBase = _double(colaborador.first['remuneracao_mensal']);
    // ponto-base-mensal-220-v2
    const horasBaseMensal = ImperiumRegrasNegocio.horasMensaisPadrao;

    final valorHora = horasBaseMensal > 0 ? salarioBase / horasBaseMensal : 0.0;

    final adicionalPercentual = await obterAdicionalHoraExtra();
    final minutosExtras = _int(espelho['minutos_extras']);
    final minutosFaltantes = _int(espelho['minutos_faltantes']);

    final valorExtras =
        (minutosExtras / 60.0) * valorHora * (1 + adicionalPercentual / 100.0);

    final descontoHorasFaltantes = (minutosFaltantes / 60.0) * valorHora;

    final valorEstimado = (salarioBase - descontoHorasFaltantes + valorExtras)
        .clamp(0, double.infinity)
        .toDouble();

    var jaPago = 0.0;

    final tabelaPagamentos = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = 'financeiro_pagamentos_colaboradores'
      LIMIT 1
      ''');

    if (tabelaPagamentos.isNotEmpty) {
      final pagamentos = await database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM financeiro_pagamentos_colaboradores
        WHERE colaborador_id = ?
          AND date(data_pagamento) BETWEEN date(?) AND date(?)
        ''',
        [colaboradorId, _data(inicio), _data(fim)],
      );

      if (pagamentos.isNotEmpty) {
        jaPago = _double(pagamentos.first['total']);
      }
    }

    final restante = (valorEstimado - jaPago)
        .clamp(0, double.infinity)
        .toDouble();
    final pagoAcimaEstimado = (jaPago - valorEstimado)
        .clamp(0, double.infinity)
        .toDouble();

    final resultadoAtual = <String, dynamic>{
      ...espelho,
      'salario_base': salarioBase,
      'horas_base_mensal': horasBaseMensal,
      'valor_hora': valorHora,
      'adicional_hora_extra_percentual': adicionalPercentual,
      'valor_horas_extras': valorExtras,
      'desconto_horas_faltantes': descontoHorasFaltantes,
      'valor_estimado_pagar': valorEstimado,
      'ja_pago_mes': jaPago,
      'restante_estimado': restante,
      'pago_acima_estimado': pagoAcimaEstimado,
      'fechamento_status': 'Aberto',
      'fechado_em': null,
    };

    final fechamento = await database.query(
      'financeiro_ponto_fechamentos',
      where: 'colaborador_id = ? AND competencia = ? AND status = ?',
      whereArgs: [colaboradorId, _competencia(inicio), 'Fechado'],
      limit: 1,
    );

    if (fechamento.isEmpty) {
      return resultadoAtual;
    }

    Map<String, dynamic> snapshot = <String, dynamic>{};
    final textoSnapshot = fechamento.first['snapshot_json']?.toString() ?? '';

    if (textoSnapshot.isNotEmpty) {
      try {
        final decodificado = jsonDecode(textoSnapshot);
        if (decodificado is Map) {
          snapshot = Map<String, dynamic>.from(decodificado);
        }
      } catch (_) {
        snapshot = <String, dynamic>{};
      }
    }

    final baseFechada = snapshot.isEmpty ? resultadoAtual : snapshot;
    final estimadoFechado = _double(
      baseFechada['valor_estimado_pagar'],
      valorEstimado,
    );
    final restanteFechado = (estimadoFechado - jaPago)
        .clamp(0, double.infinity)
        .toDouble();
    final pagoAcimaFechado = (jaPago - estimadoFechado)
        .clamp(0, double.infinity)
        .toDouble();

    return <String, dynamic>{
      ...baseFechada,
      'valor_estimado_pagar': estimadoFechado,
      'ja_pago_mes': jaPago,
      'restante_estimado': restanteFechado,
      'pago_acima_estimado': pagoAcimaFechado,
      'fechamento_status': 'Fechado',
      'fechado_em': fechamento.first['fechado_em'],
    };
  }

  int _minutosJornada(Map<String, dynamic> item) {
    final entrada = _minutosHora(item['entrada']?.toString());
    final saida = _minutosHora(item['saida']?.toString());

    if (entrada == null || saida == null || saida <= entrada) {
      return 0;
    }

    final inicioIntervalo = _minutosHora(item['intervalo_inicio']?.toString());
    final fimIntervalo = _minutosHora(item['intervalo_fim']?.toString());

    var total = saida - entrada;

    if (inicioIntervalo != null &&
        fimIntervalo != null &&
        fimIntervalo > inicioIntervalo) {
      total -= fimIntervalo - inicioIntervalo;
    }

    return total < 0 ? 0 : total;
  }

  int _minutosRegistro(Map<String, dynamic> item) {
    final entrada = _minutosHora(item['entrada']?.toString());
    final saida = _minutosHora(item['saida']?.toString());

    if (entrada == null || saida == null || saida <= entrada) {
      return 0;
    }

    final inicioIntervalo = _minutosHora(item['intervalo_inicio']?.toString());
    final fimIntervalo = _minutosHora(item['intervalo_fim']?.toString());

    var total = saida - entrada;

    if (inicioIntervalo != null &&
        fimIntervalo != null &&
        fimIntervalo > inicioIntervalo) {
      total -= fimIntervalo - inicioIntervalo;
    }

    return total < 0 ? 0 : total;
  }

  int _atrasoMinutos(String? esperado, String? realizado) {
    final a = _minutosHora(esperado);
    final b = _minutosHora(realizado);

    if (a == null || b == null || b <= a) {
      return 0;
    }

    return b - a;
  }

  void _validarPeriodo({
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    required bool exigirPontoCompleto,
  }) {
    final entradaMin = _minutosHora(entrada);
    final saidaMin = _minutosHora(saida);

    if (exigirPontoCompleto && (entradaMin == null || saidaMin == null)) {
      throw ArgumentError('Informe horário de entrada e saída.');
    }

    if (entradaMin != null && saidaMin != null && saidaMin <= entradaMin) {
      throw ArgumentError('A saída precisa ser posterior à entrada.');
    }

    final inicioIntervalo = _minutosHora(intervaloInicio);
    final fimIntervalo = _minutosHora(intervaloFim);

    if ((inicioIntervalo == null) != (fimIntervalo == null)) {
      throw ArgumentError(
        'Informe início e fim do intervalo, ou deixe ambos vazios.',
      );
    }

    if (inicioIntervalo != null && fimIntervalo != null) {
      if (fimIntervalo <= inicioIntervalo) {
        throw ArgumentError(
          'O fim do intervalo precisa ser posterior ao início.',
        );
      }

      if (entradaMin != null &&
          (inicioIntervalo <= entradaMin ||
              fimIntervalo >= (saidaMin ?? 24 * 60))) {
        throw ArgumentError(
          'O intervalo precisa ficar entre a entrada e a saída.',
        );
      }
    }
  }

  static int? _minutosHora(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return null;
    }

    final partes = texto.split(':');
    if (partes.length < 2) {
      return null;
    }

    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);

    if (hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }

    return hora * 60 + minuto;
  }

  static String? _horaNula(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static String _competencia(DateTime valor) {
    final ano = valor.year.toString().padLeft(4, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    return '$ano-$mes';
  }

  static String _hora(DateTime valor) {
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  static String _data(DateTime valor) {
    final ano = valor.year.toString().padLeft(4, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final dia = valor.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  static double _double(dynamic valor, [double padrao = 0.0]) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ??
        padrao;
  }

  static int _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
