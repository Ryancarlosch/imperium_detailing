import '../database/app_database.dart';

class FluxoCaixaRepository {
  Future<Map<String, double>> obterResumo({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await AppDatabase.instance.database;
    final saldoInicial = await _saldoAntesDe(inicio);
    final resultado = await database.rawQuery(
      '''
      SELECT
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
      FROM movimentos_financeiros
      WHERE status IN ('Realizado', 'Previsto')
        AND transferencia_id IS NULL
        AND date(
          CASE
            WHEN status = 'Realizado'
              THEN COALESCE(data_pagamento, data)
            ELSE COALESCE(data_vencimento, data_competencia, data)
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
    final entradasPrevistas =
        entradasPrevistasMovimentos + entradasPrevistasOs;
    final saidasPrevistas = _double(mapa['saidas_previstas']);
    final saldoFinal = saldoInicial + entradasRealizadas - saidasRealizadas;
    final saldoProjetado = saldoFinal + entradasPrevistas - saidasPrevistas;

    return {
      'saldo_inicial': saldoInicial,
      'entradas_realizadas': entradasRealizadas,
      'saidas_realizadas': saidasRealizadas,
      'saldo_final': saldoFinal,
      'entradas_previstas': entradasPrevistas,
      'entradas_previstas_os': entradasPrevistasOs,
      'saidas_previstas': saidasPrevistas,
      'saldo_projetado': saldoProjetado,
    };
  }

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
          status,
          tipo,
          valor,
          date(
            CASE
              WHEN status = 'Realizado'
                THEN COALESCE(data_pagamento, data)
              ELSE COALESCE(data_vencimento, data_competencia, data)
            END
          ) AS data_ref
        FROM movimentos_financeiros
        WHERE status IN ('Realizado', 'Previsto')
          AND transferencia_id IS NULL
      ) fluxo
      WHERE data_ref BETWEEN date(?) AND date(?)
      GROUP BY data_ref
      ORDER BY data_ref ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final porData = <String, Map<String, dynamic>>{
      for (final item in resultado)
        item['data_ref'].toString(): Map<String, dynamic>.from(item),
    };

    final recebimentosOs = await _recebimentosOsPrevistos(
      inicio: inicio,
      fim: fim,
    );

    for (final recebimento in recebimentosOs) {
      final dataRef = recebimento['data_ref']?.toString() ?? '';
      if (dataRef.isEmpty) {
        continue;
      }
      final item = porData.putIfAbsent(
        dataRef,
        () => <String, dynamic>{
          'data_ref': dataRef,
          'entradas_realizadas': 0.0,
          'saidas_realizadas': 0.0,
          'entradas_previstas': 0.0,
          'saidas_previstas': 0.0,
        },
      );
      item['entradas_previstas'] =
          _double(item['entradas_previstas']) + _double(recebimento['total']);
      item['entradas_previstas_os'] =
          _double(item['entradas_previstas_os']) + _double(recebimento['total']);
    }

    final itens = porData.values.toList()
      ..sort(
        (a, b) => (a['data_ref'] ?? '')
            .toString()
            .compareTo((b['data_ref'] ?? '').toString()),
      );

    var saldoRealizado = saldoInicial;
    var saldoProjetado = saldoInicial;

    return itens.map((item) {
      final entradasRealizadas = _double(item['entradas_realizadas']);
      final saidasRealizadas = _double(item['saidas_realizadas']);
      final entradasPrevistas = _double(item['entradas_previstas']);
      final saidasPrevistas = _double(item['saidas_previstas']);
      final realizadoDia = entradasRealizadas - saidasRealizadas;
      final previstoDia = entradasPrevistas - saidasPrevistas;

      saldoRealizado += realizadoDia;
      saldoProjetado += realizadoDia + previstoDia;

      return <String, dynamic>{
        ...item,
        'resultado_realizado': realizadoDia,
        'resultado_previsto': previstoDia,
        'saldo_realizado_acumulado': saldoRealizado,
        'saldo_projetado_acumulado': saldoProjetado,
      };
    }).toList();
  }

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
          status,
          tipo,
          valor,
          strftime(
            '%Y-%m',
            CASE
              WHEN status = 'Realizado'
                THEN COALESCE(data_pagamento, data)
              ELSE COALESCE(data_vencimento, data_competencia, data)
            END
          ) AS mes_ref,
          date(
            CASE
              WHEN status = 'Realizado'
                THEN COALESCE(data_pagamento, data)
              ELSE COALESCE(data_vencimento, data_competencia, data)
            END
          ) AS data_ref
        FROM movimentos_financeiros
        WHERE status IN ('Realizado', 'Previsto')
          AND transferencia_id IS NULL
      ) fluxo
      WHERE data_ref BETWEEN date(?) AND date(?)
      GROUP BY mes_ref
      ORDER BY mes_ref ASC
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    final porMes = <String, Map<String, dynamic>>{
      for (final item in resultado)
        item['mes_ref'].toString(): Map<String, dynamic>.from(item),
    };

    final recebimentosOs = await _recebimentosOsPrevistos(
      inicio: inicio,
      fim: fim,
    );

    for (final recebimento in recebimentosOs) {
      final data = DateTime.tryParse(
        recebimento['data_ref']?.toString() ?? '',
      );
      if (data == null) {
        continue;
      }
      final chave =
          '${data.year.toString().padLeft(4, '0')}-'
          '${data.month.toString().padLeft(2, '0')}';
      final item = porMes.putIfAbsent(
        chave,
        () => <String, dynamic>{
          'mes_ref': chave,
          'entradas_realizadas': 0.0,
          'saidas_realizadas': 0.0,
          'entradas_previstas': 0.0,
          'saidas_previstas': 0.0,
        },
      );
      item['entradas_previstas'] =
          _double(item['entradas_previstas']) + _double(recebimento['total']);
      item['entradas_previstas_os'] =
          _double(item['entradas_previstas_os']) + _double(recebimento['total']);
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
      final entradasPrevistas = _double(item['entradas_previstas']);
      final saidasPrevistas = _double(item['saidas_previstas']);
      final realizadoMes = entradasRealizadas - saidasRealizadas;
      final previstoMes = entradasPrevistas - saidasPrevistas;

      saldoRealizado += realizadoMes;
      saldoProjetado += realizadoMes + previstoMes;

      meses.add({
        'mes_ref': chave,
        'entradas_realizadas': entradasRealizadas,
        'saidas_realizadas': saidasRealizadas,
        'entradas_previstas': entradasPrevistas,
        'entradas_previstas_os': _double(item['entradas_previstas_os']),
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

  Future<double> _saldoAntesDe(DateTime data) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE((
          SELECT SUM(saldo_inicial)
          FROM financeiro_contas
          WHERE ativo = 1
        ), 0)
        + COALESCE((
          SELECT SUM(
            CASE
              WHEN LOWER(tipo) = 'entrada' THEN valor
              WHEN LOWER(tipo) IN ('saída', 'saida') THEN -valor
              ELSE 0
            END
          )
          FROM movimentos_financeiros
          WHERE status = 'Realizado'
            AND date(COALESCE(data_pagamento, data)) < date(?)
        ), 0) AS saldo
      ''',
      [_dataDia(data)],
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
