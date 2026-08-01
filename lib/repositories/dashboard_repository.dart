import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class DashboardRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<Map<String, dynamic>> carregarDashboard() async {
    final database = await _appDatabase.database;
    final agora = DateTime.now();

    final inicioHoje = DateTime(agora.year, agora.month, agora.day);
    final inicioAmanha = inicioHoje.add(const Duration(days: 1));

    final inicioSemana = inicioHoje.subtract(
      Duration(days: inicioHoje.weekday - 1),
    );
    final inicioProximaSemana = inicioSemana.add(const Duration(days: 7));

    final inicioMes = DateTime(agora.year, agora.month, 1);
    final inicioProximoMes = DateTime(agora.year, agora.month + 1, 1);

    final inicioMesAnterior = DateTime(agora.year, agora.month - 1, 1);
    final inicioProximoMesAnterior = inicioMes;

    final inicioSeteDias = inicioHoje.subtract(const Duration(days: 6));

    final resultados = await Future.wait<List<Map<String, Object?>>>([
      database.rawQuery('SELECT COUNT(*) AS total FROM clientes'),
      database.rawQuery('SELECT COUNT(*) AS total FROM veiculos'),
      database.rawQuery('SELECT COUNT(*) AS total FROM agendamentos'),
      database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM agendamentos
        WHERE data = ?
        ''',
        [_toAgendamentoDateString(inicioHoje)],
      ),
      database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(tipo) = 'entrada'
          AND data >= ?
          AND data < ?
        ''',
        [_toIsoDateString(inicioHoje), _toIsoDateString(inicioAmanha)],
      ),
      database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(tipo) = 'entrada'
          AND data >= ?
          AND data < ?
        ''',
        [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
      ),
      database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(tipo) IN ('saída', 'saida')
          AND data >= ?
          AND data < ?
        ''',
        [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
      ),
      database.rawQuery('''
        SELECT COUNT(*) AS total
        FROM ordens_servico
        WHERE LOWER(status) = 'aberta'
        '''),
      database.rawQuery('''
        SELECT COUNT(*) AS total
        FROM ordens_servico
        WHERE LOWER(status) = 'em andamento'
        '''),
      database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM ordens_servico
        WHERE status = 'Finalizada'
          AND data_finalizacao >= ?
          AND data_finalizacao < ?
        ''',
        [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
      ),
      database.rawQuery('''
        SELECT COUNT(*) AS total
        FROM itens_estoque
        WHERE quantidade <= quantidade_minima
        '''),
      database.rawQuery(
        '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(tipo) = 'entrada'
          AND data >= ?
          AND data < ?
        ''',
        [
          _toIsoDateString(inicioMesAnterior),
          _toIsoDateString(inicioProximoMesAnterior),
        ],
      ),
    ]);

    final faturamentoUltimos7Dias = await _consultarFaturamentoUltimos7Dias(
      database,
      inicioSeteDias,
      inicioAmanha,
    );

    final topServicos = await _consultarTopServicos(
      database,
      inicioMes,
      inicioProximoMes,
    );

    final topClientes = await _consultarTopClientes(
      database,
      inicioMes,
      inicioProximoMes,
    );

    final custoProdutosMes = await _consultarCustoProdutosMes(
      database,
      inicioMes,
      inicioProximoMes,
    );

    final faturamentoMes = _lerDouble(resultados[5]);
    final saidasMes = _lerDouble(resultados[6]);

    return {
      'totalClientes': _lerInteiro(resultados[0]),
      'totalVeiculos': _lerInteiro(resultados[1]),
      'totalAgendamentos': _lerInteiro(resultados[2]),
      'agendamentosHoje': _lerInteiro(resultados[3]),
      'faturamentoHoje': _lerDouble(resultados[4]),
      'faturamentoSemana': await _somarEntradas(
        inicioSemana,
        inicioProximaSemana,
      ),
      'faturamentoMes': faturamentoMes,
      'saidasMes': saidasMes,
      'saldoMes': faturamentoMes - saidasMes,
      'saldoTotal': await _consultarSaldoTotal(database),
      'ticketMedioMes': await _consultarTicketMedioMes(
        database,
        inicioMes,
        inicioProximoMes,
      ),
      'clientesAtendidosMes': await _consultarClientesAtendidosMes(
        database,
        inicioMes,
        inicioProximoMes,
      ),
      'veiculosAtendidosMes': await _consultarVeiculosAtendidosMes(
        database,
        inicioMes,
        inicioProximoMes,
      ),
      'ordensAbertas': _lerInteiro(resultados[7]),
      'ordensEmAndamento': _lerInteiro(resultados[8]),
      'ordensFinalizadasMes': _lerInteiro(resultados[9]),
      'estoqueBaixo': _lerInteiro(resultados[10]),
      'servicosTop5': topServicos,
      'clientesTop5': topClientes,
      'faturamentoUltimos7Dias': faturamentoUltimos7Dias,
      'custoProdutosMes': custoProdutosMes,
      'lucroBrutoEstimadoMes': faturamentoMes - custoProdutosMes,
      'crescimentoMes': _calcularCrescimentoPercentual(
        _lerDouble(resultados[5]),
        _lerDouble(resultados[11]),
      ),
    };
  }

  double _calcularCrescimentoPercentual(double atual, double anterior) {
    if (anterior == 0) {
      return atual > 0 ? 100 : 0;
    }

    return ((atual - anterior) / anterior) * 100;
  }

  Future<double> _consultarSaldoTotal(Database database) async {
    final resultado = await database.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN LOWER(tipo) = 'entrada' THEN valor
          WHEN LOWER(tipo) IN ('saída', 'saida') THEN -valor
          ELSE 0
        END
      ), 0) AS total
      FROM movimentos_financeiros
      ''');

    return _lerDouble(resultado);
  }

  Future<double> _consultarTicketMedioMes(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(AVG(valor), 0) AS total
      FROM movimentos_financeiros
      WHERE LOWER(tipo) = 'entrada'
        AND data >= ?
        AND data < ?
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );

    return _lerDouble(resultado);
  }

  Future<int> _consultarClientesAtendidosMes(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT cliente_id) AS total
      FROM ordens_servico
      WHERE data_abertura >= ?
        AND data_abertura < ?
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );

    return _lerInteiro(resultado);
  }

  Future<int> _consultarVeiculosAtendidosMes(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT veiculo_id) AS total
      FROM ordens_servico
      WHERE veiculo_id IS NOT NULL
        AND data_abertura >= ?
        AND data_abertura < ?
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );

    return _lerInteiro(resultado);
  }

  Future<List<Map<String, Object?>>> _consultarFaturamentoUltimos7Dias(
    Database database,
    DateTime inicio,
    DateTime fim,
  ) async {
    return database.rawQuery(
      '''
      SELECT
        substr(data, 1, 10) AS dia,
        COALESCE(SUM(valor), 0) AS total
      FROM movimentos_financeiros
      WHERE LOWER(tipo) = 'entrada'
        AND data >= ?
        AND data < ?
      GROUP BY dia
      ORDER BY dia ASC
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fim)],
    );
  }

  Future<List<Map<String, Object?>>> _consultarTopServicos(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    return database.rawQuery(
      '''
      SELECT
        item.servico AS nome,
        COUNT(*) AS total
      FROM ordem_servico_itens item
      INNER JOIN ordens_servico os
        ON os.id = item.ordem_servico_id
      WHERE os.status = 'Finalizada'
        AND os.data_finalizacao >= ?
        AND os.data_finalizacao < ?
      GROUP BY item.servico
      ORDER BY total DESC
      LIMIT 5
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );
  }

  Future<List<Map<String, Object?>>> _consultarTopClientes(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    return database.rawQuery(
      '''
      SELECT
        c.nome AS nome,
        COALESCE(SUM(
          CASE
            WHEN (os.valor_total - os.desconto) > 0
              THEN (os.valor_total - os.desconto)
            ELSE 0
          END
        ), 0) AS total
      FROM ordens_servico os
      INNER JOIN clientes c
        ON c.id = os.cliente_id
      WHERE LOWER(os.status) = 'finalizada'
        AND os.data_finalizacao >= ?
        AND os.data_finalizacao < ?
      GROUP BY c.id, c.nome
      ORDER BY total DESC
      LIMIT 5
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );
  }

  Future<double> _consultarCustoProdutosMes(
    Database database,
    DateTime inicioMes,
    DateTime inicioProximoMes,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(
        ordem_servico_produtos.quantidade *
        ordem_servico_produtos.custo_unitario
      ), 0) AS total
      FROM ordem_servico_produtos
      INNER JOIN ordens_servico
        ON ordens_servico.id =
          ordem_servico_produtos.ordem_servico_id
      WHERE LOWER(ordens_servico.status) = 'finalizada'
        AND ordens_servico.data_finalizacao >= ?
        AND ordens_servico.data_finalizacao < ?
      ''',
      [_toIsoDateString(inicioMes), _toIsoDateString(inicioProximoMes)],
    );

    return _lerDouble(resultado);
  }

  Future<double> _somarEntradas(DateTime inicio, DateTime fim) async {
    final database = await _appDatabase.database;
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(valor), 0) AS total
      FROM movimentos_financeiros
      WHERE LOWER(tipo) = 'entrada'
        AND data >= ?
        AND data < ?
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fim)],
    );

    return _lerDouble(resultado);
  }

  String _toIsoDateString(DateTime date) {
    return DateTime(date.year, date.month, date.day).toIso8601String();
  }

  String _toAgendamentoDateString(DateTime date) {
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final ano = date.year.toString().padLeft(4, '0');

    return '$dia/$mes/$ano';
  }

  double _lerDouble(List<Map<String, Object?>> resultado) {
    if (resultado.isEmpty) {
      return 0;
    }

    final valor = resultado.first['total'];

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int _lerInteiro(List<Map<String, Object?>> resultado) {
    if (resultado.isEmpty) {
      return 0;
    }

    final valor = resultado.first['total'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
