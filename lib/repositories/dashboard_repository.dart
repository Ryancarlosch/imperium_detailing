import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

enum DashboardPeriodo { hoje, ultimos7Dias, mesAtual, anoAtual, personalizado }

enum DashboardAgrupamento { diario, mensal }

enum DashboardAlertaTipo { agendamento, ordemServico, estoque }

class DashboardData {
  const DashboardData({
    required this.periodo,
    required this.inicio,
    required this.fimExclusivo,
    required this.agrupamento,
    required this.clientesTotal,
    required this.veiculosTotal,
    required this.faturamento,
    required this.saidas,
    required this.saldo,
    required this.lucroBrutoEstimado,
    required this.ticketMedio,
    required this.clientesAtendidos,
    required this.veiculosAtendidos,
    required this.ordensAbertas,
    required this.ordensEmAndamento,
    required this.ordensFinalizadas,
    required this.agendamentos,
    required this.clientesNovos,
    required this.clientesRecorrentes,
    required this.serieFinanceira,
    required this.topServicos,
    required this.topClientes,
    required this.alertas,
    required this.agendamentosHoje,
    required this.ordensAbertasAntigas,
    required this.ordensEmAndamentoAntigas,
    required this.produtosBaixoEstoque,
    required this.produtosZerados,
  });

  final DashboardPeriodo periodo;
  final DateTime inicio;
  final DateTime fimExclusivo;
  final DashboardAgrupamento agrupamento;

  final int clientesTotal;
  final int veiculosTotal;

  final double faturamento;
  final double saidas;
  final double saldo;
  final double lucroBrutoEstimado;
  final double ticketMedio;

  final int clientesAtendidos;
  final int veiculosAtendidos;
  final int ordensAbertas;
  final int ordensEmAndamento;
  final int ordensFinalizadas;
  final int agendamentos;
  final int clientesNovos;
  final int clientesRecorrentes;

  final List<DashboardSeriePonto> serieFinanceira;
  final List<DashboardRankingItem> topServicos;
  final List<DashboardRankingCliente> topClientes;
  final List<DashboardAlertaItem> alertas;

  final int agendamentosHoje;
  final int ordensAbertasAntigas;
  final int ordensEmAndamentoAntigas;
  final int produtosBaixoEstoque;
  final int produtosZerados;

  bool get temSeries => serieFinanceira.isNotEmpty;

  bool get temAlertas => alertas.isNotEmpty;
}

class DashboardSeriePonto {
  const DashboardSeriePonto({
    required this.data,
    required this.entradas,
    required this.saidas,
  });

  final DateTime data;
  final double entradas;
  final double saidas;

  double get faturamento => entradas;
}

class DashboardRankingItem {
  const DashboardRankingItem({
    required this.nome,
    required this.quantidade,
    required this.total,
  });

  final String nome;
  final int quantidade;
  final double total;
}

class DashboardRankingCliente {
  const DashboardRankingCliente({
    required this.nome,
    required this.quantidade,
    required this.total,
  });

  final String nome;
  final int quantidade;
  final double total;
}

class DashboardAlertaItem {
  const DashboardAlertaItem({
    required this.tipo,
    required this.titulo,
    required this.descricao,
    required this.quantidade,
  });

  final DashboardAlertaTipo tipo;
  final String titulo;
  final String descricao;
  final int quantidade;
}

class DashboardRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<DashboardData> carregarDashboard({
    DashboardPeriodo periodo = DashboardPeriodo.mesAtual,
    DateTime? inicioPersonalizado,
    DateTime? fimPersonalizado,
  }) async {
    final database = await _appDatabase.database;
    final consultaPeriodo = _resolverPeriodo(
      periodo: periodo,
      inicioPersonalizado: inicioPersonalizado,
      fimPersonalizado: fimPersonalizado,
    );

    final resumoFinanceiroFuturo = _consultarResumoFinanceiro(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );
    final resumoOrdensFuturo = _consultarResumoOrdens(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );
    final resumoClientesFuturo = _consultarResumoClientes(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );
    final serieFinanceiraFuturo = _consultarSerieFinanceira(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
      consultaPeriodo.agrupamento,
    );
    final topServicosFuturo = _consultarTopServicos(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );
    final topClientesFuturo = _consultarTopClientes(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );
    final alertasFuturo = _consultarAlertas(database);
    final totaisFuturo = Future.wait<List<Map<String, Object?>>>([
      database.rawQuery('SELECT COUNT(*) AS total FROM clientes'),
      database.rawQuery('SELECT COUNT(*) AS total FROM veiculos'),
    ]);
    final custoProdutosFuturo = _consultarCustoProdutos(
      database,
      consultaPeriodo.inicio,
      consultaPeriodo.fimExclusivo,
    );

    final resultados = await Future.wait([
      resumoFinanceiroFuturo,
      resumoOrdensFuturo,
      resumoClientesFuturo,
      serieFinanceiraFuturo,
      topServicosFuturo,
      topClientesFuturo,
      alertasFuturo,
      totaisFuturo,
      custoProdutosFuturo,
    ]);

    final resumoFinanceiro = resultados[0] as _ResumoFinanceiro;
    final resumoOrdens = resultados[1] as _ResumoOrdens;
    final resumoClientes = resultados[2] as _ResumoClientes;
    final serieFinanceira = resultados[3] as List<DashboardSeriePonto>;
    final topServicos = resultados[4] as List<DashboardRankingItem>;
    final topClientes = resultados[5] as List<DashboardRankingCliente>;
    final alertas = resultados[6] as List<DashboardAlertaItem>;
    final totais = resultados[7] as List<List<Map<String, Object?>>>;
    final custoProdutos = resultados[8] as double;

    return DashboardData(
      periodo: periodo,
      inicio: consultaPeriodo.inicio,
      fimExclusivo: consultaPeriodo.fimExclusivo,
      agrupamento: consultaPeriodo.agrupamento,
      clientesTotal: _lerInteiro(totais[0]),
      veiculosTotal: _lerInteiro(totais[1]),
      faturamento: resumoFinanceiro.entradas,
      saidas: resumoFinanceiro.saidas,
      saldo: resumoFinanceiro.saldo,
      lucroBrutoEstimado: resumoFinanceiro.entradas - custoProdutos,
      ticketMedio: resumoOrdens.ticketMedio,
      clientesAtendidos: resumoOrdens.clientesAtendidos,
      veiculosAtendidos: resumoOrdens.veiculosAtendidos,
      ordensAbertas: resumoOrdens.ordensAbertas,
      ordensEmAndamento: resumoOrdens.ordensEmAndamento,
      ordensFinalizadas: resumoOrdens.ordensFinalizadas,
      agendamentos: resumoOrdens.agendamentos,
      clientesNovos: resumoClientes.novos,
      clientesRecorrentes: resumoClientes.recorrentes,
      serieFinanceira: serieFinanceira,
      topServicos: topServicos,
      topClientes: topClientes,
      alertas: alertas,
      agendamentosHoje: resumoOrdens.agendamentosHoje,
      ordensAbertasAntigas: resumoOrdens.ordensAbertasAntigas,
      ordensEmAndamentoAntigas: resumoOrdens.ordensEmAndamentoAntigas,
      produtosBaixoEstoque: resumoOrdens.produtosBaixoEstoque,
      produtosZerados: resumoOrdens.produtosZerados,
    );
  }

  _PeriodoConsulta _resolverPeriodo({
    required DashboardPeriodo periodo,
    required DateTime? inicioPersonalizado,
    required DateTime? fimPersonalizado,
  }) {
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);

    switch (periodo) {
      case DashboardPeriodo.hoje:
        return _PeriodoConsulta(
          inicio: inicioHoje,
          fimExclusivo: inicioHoje.add(const Duration(days: 1)),
          agrupamento: DashboardAgrupamento.diario,
        );
      case DashboardPeriodo.ultimos7Dias:
        return _PeriodoConsulta(
          inicio: inicioHoje.subtract(const Duration(days: 6)),
          fimExclusivo: inicioHoje.add(const Duration(days: 1)),
          agrupamento: DashboardAgrupamento.diario,
        );
      case DashboardPeriodo.mesAtual:
        return _PeriodoConsulta(
          inicio: DateTime(hoje.year, hoje.month, 1),
          fimExclusivo: DateTime(hoje.year, hoje.month + 1, 1),
          agrupamento: DashboardAgrupamento.diario,
        );
      case DashboardPeriodo.anoAtual:
        return _PeriodoConsulta(
          inicio: DateTime(hoje.year, 1, 1),
          fimExclusivo: DateTime(hoje.year + 1, 1, 1),
          agrupamento: DashboardAgrupamento.mensal,
        );
      case DashboardPeriodo.personalizado:
        final inicio = _normalizarData(inicioPersonalizado) ?? inicioHoje;
        final fim = _normalizarData(fimPersonalizado) ?? inicioHoje;
        final inicioNormalizado = inicio.isBefore(fim) ? inicio : fim;
        final fimNormalizado = inicio.isBefore(fim) ? fim : inicio;
        final fimExclusivo = fimNormalizado.add(const Duration(days: 1));

        return _PeriodoConsulta(
          inicio: inicioNormalizado,
          fimExclusivo: fimExclusivo,
          agrupamento: _deveAgruparPorMeses(inicioNormalizado, fimExclusivo)
              ? DashboardAgrupamento.mensal
              : DashboardAgrupamento.diario,
        );
    }
  }

  bool _deveAgruparPorMeses(DateTime inicio, DateTime fimExclusivo) {
    return fimExclusivo.difference(inicio).inDays > 62;
  }

  DateTime? _normalizarData(DateTime? data) {
    if (data == null) {
      return null;
    }

    return DateTime(data.year, data.month, data.day);
  }

  Future<_ResumoFinanceiro> _consultarResumoFinanceiro(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN LOWER(tipo) = 'entrada' THEN valor ELSE 0 END), 0) AS entradas,
        COALESCE(SUM(CASE WHEN LOWER(tipo) IN ('saída', 'saida') THEN valor ELSE 0 END), 0) AS saidas
      FROM movimentos_financeiros
      WHERE data >= ?
        AND data < ?
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
    );

    final entradas = _lerDoubleMap(resultado.firstOrNull, 'entradas');
    final saidas = _lerDoubleMap(resultado.firstOrNull, 'saidas');

    return _ResumoFinanceiro(
      entradas: entradas,
      saidas: saidas,
      saldo: entradas - saidas,
    );
  }

  Future<_ResumoOrdens> _consultarResumoOrdens(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        COUNT(CASE WHEN LOWER(status) = 'aberta' AND data_abertura >= ? AND data_abertura < ? THEN 1 END) AS ordens_abertas,
        COUNT(CASE WHEN LOWER(status) = 'em andamento' AND COALESCE(data_inicio, data_abertura) >= ? AND COALESCE(data_inicio, data_abertura) < ? THEN 1 END) AS ordens_em_andamento,
        COUNT(CASE WHEN LOWER(status) = 'finalizada' AND data_finalizacao >= ? AND data_finalizacao < ? THEN 1 END) AS ordens_finalizadas,
        COUNT(DISTINCT CASE WHEN LOWER(status) = 'finalizada' AND data_finalizacao >= ? AND data_finalizacao < ? THEN cliente_id END) AS clientes_atendidos,
        COUNT(DISTINCT CASE WHEN LOWER(status) = 'finalizada' AND data_finalizacao >= ? AND data_finalizacao < ? AND veiculo_id IS NOT NULL THEN veiculo_id END) AS veiculos_atendidos,
        COALESCE(AVG(CASE WHEN LOWER(status) = 'finalizada' AND data_finalizacao >= ? AND data_finalizacao < ? THEN CASE WHEN (valor_total - desconto) > 0 THEN (valor_total - desconto) ELSE 0 END END), 0) AS ticket_medio
      FROM ordens_servico
      ''',
      [
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
      ],
    );

    final agendamentos = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM agendamentos
      WHERE (
        substr(data, 7, 4) || '-' || substr(data, 4, 2) || '-' || substr(data, 1, 2)
      ) >= ?
        AND (
          substr(data, 7, 4) || '-' || substr(data, 4, 2) || '-' || substr(data, 1, 2)
        ) < ?
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
    );

    final agendamentosHoje = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM agendamentos
      WHERE data = ?
      ''',
      [_toAgendamentoDateString(DateTime.now())],
    );

    final ordensAbertasAntigas = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordens_servico
      WHERE LOWER(status) = 'aberta'
        AND data_abertura < ?
      ''',
      [_toIsoDateString(DateTime.now().subtract(const Duration(days: 7)))],
    );

    final ordensEmAndamentoAntigas = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordens_servico
      WHERE LOWER(status) = 'em andamento'
        AND COALESCE(data_inicio, data_abertura) < ?
      ''',
      [_toIsoDateString(DateTime.now().subtract(const Duration(days: 7)))],
    );

    final produtosBaixoEstoque = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM itens_estoque
      WHERE quantidade_minima > 0
        AND quantidade <= quantidade_minima
      ''');

    final produtosZerados = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM itens_estoque
      WHERE quantidade = 0
      ''');

    return _ResumoOrdens(
      ordensAbertas: _lerInteiroMap(resultado.firstOrNull, 'ordens_abertas'),
      ordensEmAndamento: _lerInteiroMap(
        resultado.firstOrNull,
        'ordens_em_andamento',
      ),
      ordensFinalizadas: _lerInteiroMap(
        resultado.firstOrNull,
        'ordens_finalizadas',
      ),
      clientesAtendidos: _lerInteiroMap(
        resultado.firstOrNull,
        'clientes_atendidos',
      ),
      veiculosAtendidos: _lerInteiroMap(
        resultado.firstOrNull,
        'veiculos_atendidos',
      ),
      ticketMedio: _lerDoubleMap(resultado.firstOrNull, 'ticket_medio'),
      agendamentos: _lerInteiro(agendamentos),
      agendamentosHoje: _lerInteiro(agendamentosHoje),
      ordensAbertasAntigas: _lerInteiro(ordensAbertasAntigas),
      ordensEmAndamentoAntigas: _lerInteiro(ordensEmAndamentoAntigas),
      produtosBaixoEstoque: _lerInteiro(produtosBaixoEstoque),
      produtosZerados: _lerInteiro(produtosZerados),
    );
  }

  Future<_ResumoClientes> _consultarResumoClientes(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      WITH primeira_finalizacao AS (
        SELECT
          cliente_id,
          MIN(data_finalizacao) AS primeira_data
        FROM ordens_servico
        WHERE cliente_id IS NOT NULL
          AND LOWER(status) = 'finalizada'
        GROUP BY cliente_id
      ),
      clientes_periodo AS (
        SELECT DISTINCT cliente_id
        FROM ordens_servico
        WHERE cliente_id IS NOT NULL
          AND LOWER(status) = 'finalizada'
          AND data_finalizacao >= ?
          AND data_finalizacao < ?
      )
      SELECT
        COUNT(*) AS atendidos,
        COALESCE(SUM(CASE WHEN p.primeira_data >= ? AND p.primeira_data < ? THEN 1 ELSE 0 END), 0) AS novos,
        COALESCE(SUM(CASE WHEN p.primeira_data < ? AND c.cliente_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS recorrentes
      FROM primeira_finalizacao p
      LEFT JOIN clientes_periodo c
        ON c.cliente_id = p.cliente_id
      ''',
      [
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
        _toIsoDateString(fimExclusivo),
        _toIsoDateString(inicio),
      ],
    );

    return _ResumoClientes(
      atendidos: _lerInteiro(resultado, 'atendidos'),
      novos: _lerInteiro(resultado, 'novos'),
      recorrentes: _lerInteiro(resultado, 'recorrentes'),
    );
  }

  Future<List<DashboardSeriePonto>> _consultarSerieFinanceira(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
    DashboardAgrupamento agrupamento,
  ) async {
    final resultado = await database.rawQuery(
      agrupamento == DashboardAgrupamento.diario
          ? '''
            SELECT
              substr(data, 1, 10) AS periodo,
              LOWER(tipo) AS tipo,
              COALESCE(SUM(valor), 0) AS total
            FROM movimentos_financeiros
            WHERE data >= ?
              AND data < ?
            GROUP BY periodo, tipo
            ORDER BY periodo ASC
            '''
          : '''
            SELECT
              substr(data, 1, 7) AS periodo,
              LOWER(tipo) AS tipo,
              COALESCE(SUM(valor), 0) AS total
            FROM movimentos_financeiros
            WHERE data >= ?
              AND data < ?
            GROUP BY periodo, tipo
            ORDER BY periodo ASC
            ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
    );

    final acumulados = <String, _SerieAcumulada>{};

    for (final linha in resultado) {
      final periodo = (linha['periodo'] ?? '').toString();
      final tipo = (linha['tipo'] ?? '').toString().trim().toLowerCase();
      final total = _converterDouble(linha['total']);

      final acumulado = acumulados.putIfAbsent(
        periodo,
        () => _SerieAcumulada(),
      );
      if (tipo == 'entrada') {
        acumulado.entradas = total;
      } else if (tipo == 'saída' || tipo == 'saida') {
        acumulado.saidas = total;
      }
    }

    final pontos = <DashboardSeriePonto>[];
    if (agrupamento == DashboardAgrupamento.diario) {
      for (
        var data = inicio;
        data.isBefore(fimExclusivo);
        data = data.add(const Duration(days: 1))
      ) {
        final chave = _toIsoDateString(data).substring(0, 10);
        final acumulado = acumulados[chave] ?? _SerieAcumulada();
        pontos.add(
          DashboardSeriePonto(
            data: data,
            entradas: acumulado.entradas,
            saidas: acumulado.saidas,
          ),
        );
      }
    } else {
      var data = DateTime(inicio.year, inicio.month, 1);
      final limite = DateTime(fimExclusivo.year, fimExclusivo.month, 1);

      while (data.isBefore(limite)) {
        final chave =
            '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}';
        final acumulado = acumulados[chave] ?? _SerieAcumulada();
        pontos.add(
          DashboardSeriePonto(
            data: data,
            entradas: acumulado.entradas,
            saidas: acumulado.saidas,
          ),
        );
        data = DateTime(data.year, data.month + 1, 1);
      }
    }

    return pontos;
  }

  Future<List<DashboardRankingItem>> _consultarTopServicos(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        TRIM(item.servico) AS nome,
        COUNT(*) AS quantidade,
        COALESCE(SUM(item.quantidade * item.valor_unitario), 0) AS total
      FROM ordem_servico_itens item
      INNER JOIN ordens_servico os
        ON os.id = item.ordem_servico_id
      WHERE LOWER(os.status) = 'finalizada'
        AND os.data_finalizacao >= ?
        AND os.data_finalizacao < ?
        AND TRIM(COALESCE(item.servico, '')) != ''
      GROUP BY TRIM(item.servico)
      ORDER BY quantidade DESC, total DESC, nome ASC
      LIMIT 5
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
    );

    return resultado
        .map(
          (linha) => DashboardRankingItem(
            nome: (linha['nome'] ?? '-').toString(),
            quantidade: _converterInteiro(linha['quantidade']),
            total: _converterDouble(linha['total']),
          ),
        )
        .toList();
  }

  Future<List<DashboardRankingCliente>> _consultarTopClientes(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT
        c.nome AS nome,
        COUNT(*) AS quantidade,
        COALESCE(SUM(CASE WHEN (os.valor_total - os.desconto) > 0 THEN (os.valor_total - os.desconto) ELSE 0 END), 0) AS total
      FROM ordens_servico os
      INNER JOIN clientes c
        ON c.id = os.cliente_id
      WHERE LOWER(os.status) = 'finalizada'
        AND os.data_finalizacao >= ?
        AND os.data_finalizacao < ?
      GROUP BY c.id, c.nome
      ORDER BY total DESC, quantidade DESC
      LIMIT 5
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
    );

    return resultado
        .map(
          (linha) => DashboardRankingCliente(
            nome: (linha['nome'] ?? '-').toString(),
            quantidade: _converterInteiro(linha['quantidade']),
            total: _converterDouble(linha['total']),
          ),
        )
        .toList();
  }

  Future<List<DashboardAlertaItem>> _consultarAlertas(Database database) async {
    final hoje = DateTime.now();
    final hojeString = _toAgendamentoDateString(hoje);
    final limiteAntigo = _toIsoDateString(
      hoje.subtract(const Duration(days: 7)),
    );

    final resultados = await Future.wait<List<Map<String, Object?>>>([
      database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM agendamentos
        WHERE data = ?
        ''',
        [hojeString],
      ),
      database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM ordens_servico
        WHERE LOWER(status) = 'aberta'
          AND data_abertura < ?
        ''',
        [limiteAntigo],
      ),
      database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM ordens_servico
        WHERE LOWER(status) = 'em andamento'
          AND COALESCE(data_inicio, data_abertura) < ?
        ''',
        [limiteAntigo],
      ),
      database.rawQuery('''
        SELECT COUNT(*) AS total
        FROM itens_estoque
        WHERE quantidade_minima > 0
          AND quantidade <= quantidade_minima
        '''),
      database.rawQuery('''
        SELECT COUNT(*) AS total
        FROM itens_estoque
        WHERE quantidade = 0
        '''),
    ]);

    final alertas = <DashboardAlertaItem>[];

    final agendamentosHoje = _lerInteiro(resultados[0]);
    if (agendamentosHoje > 0) {
      alertas.add(
        DashboardAlertaItem(
          tipo: DashboardAlertaTipo.agendamento,
          titulo: 'Agendamentos de hoje',
          descricao: 'Compromissos previstos para a data atual.',
          quantidade: agendamentosHoje,
        ),
      );
    }

    final ordensAbertasAntigas = _lerInteiro(resultados[1]);
    if (ordensAbertasAntigas > 0) {
      alertas.add(
        DashboardAlertaItem(
          tipo: DashboardAlertaTipo.ordemServico,
          titulo: 'OS abertas antigas',
          descricao: 'Ordens em aberto há mais de 7 dias.',
          quantidade: ordensAbertasAntigas,
        ),
      );
    }

    final ordensEmAndamentoAntigas = _lerInteiro(resultados[2]);
    if (ordensEmAndamentoAntigas > 0) {
      alertas.add(
        DashboardAlertaItem(
          tipo: DashboardAlertaTipo.ordemServico,
          titulo: 'OS em andamento há muito tempo',
          descricao: 'Ordens iniciadas há mais de 7 dias.',
          quantidade: ordensEmAndamentoAntigas,
        ),
      );
    }

    final produtosBaixoEstoque = _lerInteiro(resultados[3]);
    if (produtosBaixoEstoque > 0) {
      alertas.add(
        DashboardAlertaItem(
          tipo: DashboardAlertaTipo.estoque,
          titulo: 'Produtos com estoque baixo',
          descricao: 'Itens abaixo ou no limite mínimo configurado.',
          quantidade: produtosBaixoEstoque,
        ),
      );
    }

    final produtosZerados = _lerInteiro(resultados[4]);
    if (produtosZerados > 0) {
      alertas.add(
        DashboardAlertaItem(
          tipo: DashboardAlertaTipo.estoque,
          titulo: 'Produtos zerados',
          descricao: 'Itens com quantidade igual a zero.',
          quantidade: produtosZerados,
        ),
      );
    }

    return alertas;
  }

  Future<double> _consultarCustoProdutos(
    Database database,
    DateTime inicio,
    DateTime fimExclusivo,
  ) async {
    final resultado = await database.rawQuery(
      '''
      SELECT COALESCE(
        SUM(
          COALESCE(
            NULLIF(produtos.custo_total_no_momento, 0),
            produtos.quantidade * COALESCE(
              produtos.custo_unitario_no_momento,
              produtos.custo_unitario,
              0
            )
          )
        ),
        0
      ) AS total
      FROM ordem_servico_produtos produtos
      INNER JOIN ordens_servico os
        ON os.id = produtos.ordem_servico_id
      WHERE LOWER(os.status) = 'finalizada'
        AND os.data_finalizacao >= ?
        AND os.data_finalizacao < ?
      ''',
      [_toIsoDateString(inicio), _toIsoDateString(fimExclusivo)],
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

  int _lerInteiro(
    List<Map<String, Object?>> resultado, [
    String chave = 'total',
  ]) {
    if (resultado.isEmpty) {
      return 0;
    }

    return _converterInteiro(resultado.first[chave]);
  }

  double _lerDouble(
    List<Map<String, Object?>> resultado, [
    String chave = 'total',
  ]) {
    if (resultado.isEmpty) {
      return 0;
    }

    return _converterDouble(resultado.first[chave]);
  }

  int _lerInteiroMap(Map<String, Object?>? mapa, String chave) {
    if (mapa == null) {
      return 0;
    }

    return _converterInteiro(mapa[chave]);
  }

  double _lerDoubleMap(Map<String, Object?>? mapa, String chave) {
    if (mapa == null) {
      return 0;
    }

    return _converterDouble(mapa[chave]);
  }

  int _converterInteiro(Object? valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _converterDouble(Object? valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) {
      return 0;
    }

    return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(texto) ??
        0;
  }
}

class _PeriodoConsulta {
  const _PeriodoConsulta({
    required this.inicio,
    required this.fimExclusivo,
    required this.agrupamento,
  });

  final DateTime inicio;
  final DateTime fimExclusivo;
  final DashboardAgrupamento agrupamento;
}

class _ResumoFinanceiro {
  const _ResumoFinanceiro({
    required this.entradas,
    required this.saidas,
    required this.saldo,
  });

  final double entradas;
  final double saidas;
  final double saldo;
}

class _ResumoOrdens {
  const _ResumoOrdens({
    required this.ordensAbertas,
    required this.ordensEmAndamento,
    required this.ordensFinalizadas,
    required this.clientesAtendidos,
    required this.veiculosAtendidos,
    required this.ticketMedio,
    required this.agendamentos,
    required this.agendamentosHoje,
    required this.ordensAbertasAntigas,
    required this.ordensEmAndamentoAntigas,
    required this.produtosBaixoEstoque,
    required this.produtosZerados,
  });

  final int ordensAbertas;
  final int ordensEmAndamento;
  final int ordensFinalizadas;
  final int clientesAtendidos;
  final int veiculosAtendidos;
  final double ticketMedio;
  final int agendamentos;
  final int agendamentosHoje;
  final int ordensAbertasAntigas;
  final int ordensEmAndamentoAntigas;
  final int produtosBaixoEstoque;
  final int produtosZerados;
}

class _ResumoClientes {
  const _ResumoClientes({
    required this.atendidos,
    required this.novos,
    required this.recorrentes,
  });

  final int atendidos;
  final int novos;
  final int recorrentes;
}

class _SerieAcumulada {
  double entradas = 0;
  double saidas = 0;
}

extension on List<Map<String, Object?>> {
  Map<String, Object?>? get firstOrNull {
    if (isEmpty) {
      return null;
    }

    return first;
  }
}
