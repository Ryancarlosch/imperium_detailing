import '../database/app_database.dart';

class FluxoCaixaRepository {
  // fluxo-snapshot-resumo-v1
  Future<Map<String, double>> obterResumo({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final saldoInicial = await _saldoAntesDe(inicio);
    final saldosIniciaisPeriodo = await _saldosIniciaisEntre(
      inicio: inicio,
      fim: fim,
    );

    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN m.status = 'Realizado' AND LOWER(m.tipo) = 'entrada'
            THEN m.valor ELSE 0 END), 0) AS entradas_realizadas,
        COALESCE(SUM(CASE
          WHEN m.status = 'Realizado'
            AND LOWER(m.tipo) IN ('saída', 'saida')
            THEN m.valor ELSE 0 END), 0) AS saidas_realizadas,
        COALESCE(SUM(CASE
          WHEN m.status = 'Previsto' AND LOWER(m.tipo) = 'entrada'
            THEN m.valor ELSE 0 END), 0) AS entradas_previstas,
        COALESCE(SUM(CASE
          WHEN m.status = 'Previsto'
            AND LOWER(m.tipo) IN ('saída', 'saida')
            THEN m.valor ELSE 0 END), 0) AS saidas_previstas
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_contas c ON c.id = m.conta_id
      WHERE m.status IN ('Realizado', 'Previsto')
        AND m.transferencia_id IS NULL
        AND (
          m.conta_id IS NULL
          OR c.id IS NULL
          OR c.data_saldo_inicial IS NULL
          OR TRIM(c.data_saldo_inicial) = ''
          OR date(
            CASE
              WHEN m.status = 'Realizado'
                THEN COALESCE(m.data_pagamento, m.data)
              ELSE COALESCE(
                m.data_vencimento,
                m.data_competencia,
                m.data
              )
            END
          ) >= date(c.data_saldo_inicial)
        )
        AND date(
          CASE
            WHEN m.status = 'Realizado'
              THEN COALESCE(m.data_pagamento, m.data)
            ELSE COALESCE(
              m.data_vencimento,
              m.data_competencia,
              m.data
            )
          END
        ) BETWEEN date(?) AND date(?)
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final recebimentosOs = await _recebimentosOsPrevistos(
      inicio: inicio,
      fim: fim,
    );

    final mapa = resultado.first;
    final entradasRealizadas = _double(mapa['entradas_realizadas']);
    final saidasRealizadas = _double(mapa['saidas_realizadas']);
    final entradasPrevistasMovimentos = _double(mapa['entradas_previstas']);
    final entradasPrevistasOs = recebimentosOs.fold<double>(
      0,
      (total, item) => total + _double(item['total']),
    );
    final entradasPrevistas = entradasPrevistasMovimentos + entradasPrevistasOs;
    final saidasPrevistas = _double(mapa['saidas_previstas']);

    final saldoFinal =
        saldoInicial +
        saldosIniciaisPeriodo +
        entradasRealizadas -
        saidasRealizadas;
    final saldoProjetado = saldoFinal + entradasPrevistas - saidasPrevistas;

    return {
      'saldo_inicial': saldoInicial,
      'saldos_iniciais_periodo': saldosIniciaisPeriodo,
      'entradas_realizadas': entradasRealizadas,
      'saidas_realizadas': saidasRealizadas,
      'saldo_final': saldoFinal,
      'entradas_previstas': entradasPrevistas,
      'entradas_previstas_os': entradasPrevistasOs,
      'saidas_previstas': saidasPrevistas,
      'saldo_projetado': saldoProjetado,
    };
  }

  // fluxo-snapshot-diario-v1
  Future<List<Map<String, dynamic>>> listarFluxoDiario({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final saldoInicial = await _saldoAntesDe(inicio);

    final resultado = await database.rawQuery(
      '''
      SELECT
        data_ref,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entradas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saidas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entradas_previstas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saidas_previstas
      FROM (
        SELECT
          m.status,
          m.tipo,
          m.valor,
          date(
            CASE
              WHEN m.status = 'Realizado'
                THEN COALESCE(m.data_pagamento, m.data)
              ELSE COALESCE(
                m.data_vencimento,
                m.data_competencia,
                m.data
              )
            END
          ) AS data_ref
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_contas c ON c.id = m.conta_id
        WHERE m.status IN ('Realizado', 'Previsto')
          AND m.transferencia_id IS NULL
          AND (
            m.conta_id IS NULL
            OR c.id IS NULL
            OR c.data_saldo_inicial IS NULL
            OR TRIM(c.data_saldo_inicial) = ''
            OR date(
              CASE
                WHEN m.status = 'Realizado'
                  THEN COALESCE(m.data_pagamento, m.data)
                ELSE COALESCE(
                  m.data_vencimento,
                  m.data_competencia,
                  m.data
                )
              END
            ) >= date(c.data_saldo_inicial)
          )
      ) fluxo
      WHERE data_ref BETWEEN date(?) AND date(?)
      GROUP BY data_ref
      ORDER BY data_ref ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final recebimentosOs = await _recebimentosOsPrevistos(
      inicio: inicio,
      fim: fim,
    );
    final snapshots = await _saldosIniciaisPorDia(inicio: inicio, fim: fim);

    final porDia = <String, Map<String, dynamic>>{
      for (final item in resultado)
        (item['data_ref'] ?? '').toString(): Map<String, dynamic>.from(item),
    };
    final osPorDia = <String, double>{};
    for (final item in recebimentosOs) {
      final chave = (item['data_ref'] ?? '').toString();
      osPorDia[chave] = (osPorDia[chave] ?? 0) + _double(item['total']);
    }
    final snapshotPorDia = <String, double>{};
    for (final item in snapshots) {
      final chave = (item['data_ref'] ?? '').toString();
      snapshotPorDia[chave] =
          (snapshotPorDia[chave] ?? 0) + _double(item['total']);
    }

    final chaves = <String>{
      ...porDia.keys.where((item) => item.isNotEmpty),
      ...osPorDia.keys.where((item) => item.isNotEmpty),
      ...snapshotPorDia.keys.where((item) => item.isNotEmpty),
    }.toList()..sort();

    var saldoRealizado = saldoInicial;
    var saldoProjetado = saldoInicial;
    final linhas = <Map<String, dynamic>>[];

    for (final chave in chaves) {
      final item = porDia[chave] ?? const <String, dynamic>{};
      final entradasRealizadas = _double(item['entradas_realizadas']);
      final saidasRealizadas = _double(item['saidas_realizadas']);
      final entradasPrevistas =
          _double(item['entradas_previstas']) + (osPorDia[chave] ?? 0);
      final saidasPrevistas = _double(item['saidas_previstas']);
      final saldoAdicionado = snapshotPorDia[chave] ?? 0;
      final realizadoDia = entradasRealizadas - saidasRealizadas;
      final previstoDia = entradasPrevistas - saidasPrevistas;

      saldoRealizado += saldoAdicionado + realizadoDia;
      saldoProjetado += saldoAdicionado + realizadoDia + previstoDia;

      linhas.add({
        'data_ref': chave,
        'saldo_inicial_adicionado': saldoAdicionado,
        'entradas_realizadas': entradasRealizadas,
        'saidas_realizadas': saidasRealizadas,
        'entradas_previstas': entradasPrevistas,
        'saidas_previstas': saidasPrevistas,
        'resultado_realizado': realizadoDia,
        'resultado_previsto': previstoDia,
        'saldo_realizado_acumulado': saldoRealizado,
        'saldo_projetado_acumulado': saldoProjetado,
      });
    }

    return linhas;
  }

  // fluxo-snapshot-mensal-v1
  Future<List<Map<String, dynamic>>> listarFluxoMensal({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final saldoInicial = await _saldoAntesDe(inicio);

    final resultado = await database.rawQuery(
      '''
      SELECT
        mes_ref,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entradas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saidas_realizadas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entradas_previstas,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saidas_previstas
      FROM (
        SELECT
          m.status,
          m.tipo,
          m.valor,
          substr(
            date(
              CASE
                WHEN m.status = 'Realizado'
                  THEN COALESCE(m.data_pagamento, m.data)
                ELSE COALESCE(
                  m.data_vencimento,
                  m.data_competencia,
                  m.data
                )
              END
            ),
            1,
            7
          ) AS mes_ref
        FROM movimentos_financeiros m
        LEFT JOIN financeiro_contas c ON c.id = m.conta_id
        WHERE m.status IN ('Realizado', 'Previsto')
          AND m.transferencia_id IS NULL
          AND (
            m.conta_id IS NULL
            OR c.id IS NULL
            OR c.data_saldo_inicial IS NULL
            OR TRIM(c.data_saldo_inicial) = ''
            OR date(
              CASE
                WHEN m.status = 'Realizado'
                  THEN COALESCE(m.data_pagamento, m.data)
                ELSE COALESCE(
                  m.data_vencimento,
                  m.data_competencia,
                  m.data
                )
              END
            ) >= date(c.data_saldo_inicial)
          )
      ) fluxo
      WHERE date(mes_ref || '-01')
        BETWEEN date(?) AND date(?)
      GROUP BY mes_ref
      ORDER BY mes_ref ASC
      ''',
      [
        _dataDia(DateTime(inicio.year, inicio.month, 1)),
        _dataDia(DateTime(fim.year, fim.month, 1)),
      ],
    );

    final recebimentosOs = await _recebimentosOsPrevistos(
      inicio: inicio,
      fim: fim,
    );
    final snapshots = await _saldosIniciaisPorDia(inicio: inicio, fim: fim);

    final porMes = <String, Map<String, dynamic>>{
      for (final item in resultado)
        (item['mes_ref'] ?? '').toString(): Map<String, dynamic>.from(item),
    };

    final osPorMes = <String, double>{};
    for (final item in recebimentosOs) {
      final dataRef = (item['data_ref'] ?? '').toString();
      final chave = dataRef.length >= 7 ? dataRef.substring(0, 7) : '';
      if (chave.isNotEmpty) {
        osPorMes[chave] = (osPorMes[chave] ?? 0) + _double(item['total']);
      }
    }

    final snapshotPorMes = <String, double>{};
    for (final item in snapshots) {
      final dataRef = (item['data_ref'] ?? '').toString();
      final chave = dataRef.length >= 7 ? dataRef.substring(0, 7) : '';
      if (chave.isNotEmpty) {
        snapshotPorMes[chave] =
            (snapshotPorMes[chave] ?? 0) + _double(item['total']);
      }
    }

    final meses = <Map<String, dynamic>>[];
    var saldoRealizado = saldoInicial;
    var saldoProjetado = saldoInicial;
    var cursor = DateTime(inicio.year, inicio.month, 1);
    final limite = DateTime(fim.year, fim.month, 1);

    while (!cursor.isAfter(limite)) {
      final chave =
          '${cursor.year.toString().padLeft(4, '0')}-'
          '${cursor.month.toString().padLeft(2, '0')}';
      final item = porMes[chave] ?? const <String, dynamic>{};
      final entradasRealizadas = _double(item['entradas_realizadas']);
      final saidasRealizadas = _double(item['saidas_realizadas']);
      final entradasPrevistas =
          _double(item['entradas_previstas']) + (osPorMes[chave] ?? 0);
      final saidasPrevistas = _double(item['saidas_previstas']);
      final saldoAdicionado = snapshotPorMes[chave] ?? 0;
      final realizadoMes = entradasRealizadas - saidasRealizadas;
      final previstoMes = entradasPrevistas - saidasPrevistas;

      saldoRealizado += saldoAdicionado + realizadoMes;
      saldoProjetado += saldoAdicionado + realizadoMes + previstoMes;

      meses.add({
        'mes_ref': chave,
        'saldo_inicial_adicionado': saldoAdicionado,
        'entradas_realizadas': entradasRealizadas,
        'saidas_realizadas': saidasRealizadas,
        'entradas_previstas': entradasPrevistas,
        'saidas_previstas': saidasPrevistas,
        'resultado_realizado': realizadoMes,
        'resultado_previsto': previstoMes,
        'saldo_realizado_acumulado': saldoRealizado,
        'saldo_projetado_acumulado': saldoProjetado,
      });

      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return meses;
  }

  Future<List<Map<String, dynamic>>> listarPrevistoRealizadoPorCategoria({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    return database.rawQuery(
      '''
      SELECT
        COALESCE(pc.id, 0) AS plano_conta_id,
        COALESCE(pc.codigo, '') AS codigo,
        COALESCE(pc.nome, 'Sem categoria') AS categoria,
        CASE
          WHEN LOWER(m.tipo) = 'entrada' THEN 'Entrada'
          ELSE 'Saída'
        END AS tipo,
        COALESCE(SUM(CASE
          WHEN m.status = 'Previsto' THEN m.valor ELSE 0 END), 0) AS previsto,
        COALESCE(SUM(CASE
          WHEN m.status = 'Realizado' THEN m.valor ELSE 0 END), 0) AS realizado
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE m.status IN ('Previsto', 'Realizado')
        AND m.impacta_dre = 1
        AND m.transferencia_id IS NULL
        AND date(COALESCE(m.data_competencia, m.data_vencimento, m.data))
          BETWEEN date(?) AND date(?)
      GROUP BY
        COALESCE(pc.id, 0),
        COALESCE(pc.codigo, ''),
        COALESCE(pc.nome, 'Sem categoria'),
        CASE WHEN LOWER(m.tipo) = 'entrada' THEN 'Entrada' ELSE 'Saída' END
      HAVING previsto > 0 OR realizado > 0
      ORDER BY tipo ASC, categoria COLLATE NOCASE ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );
  }

  Future<Map<String, double>> obterPrevistoRealizado({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entrada_prevista,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) = 'entrada'
            THEN valor ELSE 0 END), 0) AS entrada_realizada,
        COALESCE(SUM(CASE
          WHEN status = 'Previsto' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saida_prevista,
        COALESCE(SUM(CASE
          WHEN status = 'Realizado' AND LOWER(tipo) IN ('saída', 'saida')
            THEN valor ELSE 0 END), 0) AS saida_realizada
      FROM movimentos_financeiros
      WHERE status IN ('Previsto', 'Realizado')
        AND impacta_dre = 1
        AND transferencia_id IS NULL
        AND date(COALESCE(data_competencia, data_vencimento, data))
          BETWEEN date(?) AND date(?)
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final item = resultado.first;
    return {
      'entrada_prevista': _double(item['entrada_prevista']),
      'entrada_realizada': _double(item['entrada_realizada']),
      'saida_prevista': _double(item['saida_prevista']),
      'saida_realizada': _double(item['saida_realizada']),
    };
  }

  Future<List<Map<String, dynamic>>> _recebimentosOsPrevistos({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;

    return database.rawQuery(
      '''
      WITH recebimentos AS (
        SELECT
          date(p.vencimento) AS data_ref,
          COALESCE(p.valor, 0) AS valor
        FROM ordem_servico_pagamentos p
        INNER JOIN ordens_servico os
          ON os.id = p.ordem_servico_id
        WHERE p.status = 'Pendente'
          AND p.vencimento IS NOT NULL
          AND TRIM(p.vencimento) != ''
          AND os.status = 'Finalizada'

        UNION ALL

        SELECT
          date(os.vencimento_pagamento) AS data_ref,
          MAX(
            (
              COALESCE(os.valor_total, 0)
              - COALESCE(os.desconto, 0)
              - COALESCE(os.desconto_negociacao, 0)
              + COALESCE(os.acrescimo_negociacao, 0)
              + COALESCE(os.juros_parcelamento, 0)
            )
            - COALESCE((
              SELECT SUM(pago.valor)
              FROM ordem_servico_pagamentos pago
              WHERE pago.ordem_servico_id = os.id
                AND pago.status = 'Pago'
            ), 0),
            0
          ) AS valor
        FROM ordens_servico os
        WHERE os.status = 'Finalizada'
          AND os.vencimento_pagamento IS NOT NULL
          AND TRIM(os.vencimento_pagamento) != ''
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos pendente
            WHERE pendente.ordem_servico_id = os.id
              AND pendente.status = 'Pendente'
          )
      )
      SELECT
        data_ref,
        COALESCE(SUM(valor), 0) AS total
      FROM recebimentos
      WHERE data_ref IS NOT NULL
        AND valor > 0.000001
        AND data_ref BETWEEN date(?) AND date(?)
      GROUP BY data_ref
      ORDER BY data_ref ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );
  }

  // fluxo-saldo-snapshot-v1
  Future<List<Map<String, dynamic>>> _saldosIniciaisPorDia({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    return database.rawQuery(
      '''
      SELECT
        date(data_saldo_inicial) AS data_ref,
        COALESCE(SUM(saldo_inicial), 0) AS total
      FROM financeiro_contas
      WHERE data_saldo_inicial IS NOT NULL
        AND TRIM(data_saldo_inicial) != ''
        AND date(data_saldo_inicial) BETWEEN date(?) AND date(?)
      GROUP BY date(data_saldo_inicial)
      ORDER BY date(data_saldo_inicial) ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );
  }

  Future<double> _saldosIniciaisEntre({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final itens = await _saldosIniciaisPorDia(inicio: inicio, fim: fim);
    return itens.fold<double>(
      0,
      (total, item) => total + _double(item['total']),
    );
  }

  Future<double> _saldoAntesDe(DateTime data) async {
    final database = await AppDatabase.instance.database;
    final dataRef = _dataDia(data);

    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE((
          SELECT SUM(
            CASE
              WHEN data_saldo_inicial IS NULL
                OR TRIM(data_saldo_inicial) = ''
                OR date(data_saldo_inicial) < date(?)
              THEN saldo_inicial
              ELSE 0
            END
          )
          FROM financeiro_contas
        ), 0)
        + COALESCE((
          SELECT SUM(
            CASE
              WHEN LOWER(m.tipo) = 'entrada' THEN m.valor
              WHEN LOWER(m.tipo) IN ('saída', 'saida') THEN -m.valor
              ELSE 0
            END
          )
          FROM movimentos_financeiros m
          LEFT JOIN financeiro_contas c ON c.id = m.conta_id
          WHERE m.status = 'Realizado'
            AND m.transferencia_id IS NULL
            AND date(COALESCE(m.data_pagamento, m.data)) < date(?)
            AND (
              m.conta_id IS NULL
              OR c.id IS NULL
              OR c.data_saldo_inicial IS NULL
              OR TRIM(c.data_saldo_inicial) = ''
              OR date(COALESCE(m.data_pagamento, m.data))
                   >= date(c.data_saldo_inicial)
            )
        ), 0) AS saldo
      ''',
      [dataRef, dataRef],
    );

    return _double(resultado.first['saldo']);
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }
}
