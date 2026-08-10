import '../database/app_database.dart';
import 'custos_repository.dart';
import 'dre_repository.dart';
import 'financeiro_repository.dart';
import 'meta_financeira_repository.dart';
import 'pagamento_repository.dart';

class FinanceiroDashboardData {
  const FinanceiroDashboardData({
    required this.inicio,
    required this.fim,
    required this.dreCompetencia,
    required this.dreCaixa,
    required this.aReceber,
    required this.vencido,
    required this.recebido,
    required this.taxas,
    required this.custoFixoMensal,
    required this.custoMaoObraMensal,
    required this.metaReceita,
    required this.metaDespesa,
    required this.metaResultado,
    this.receitaPrevista = 0,
    this.receitaRealizada = 0,
    this.despesaPrevista = 0,
    this.despesaRealizada = 0,
    required this.topResultadosOs,
    required this.evolucao,
  });

  final DateTime inicio;
  final DateTime fim;
  final DreResultado dreCompetencia;
  final DreResultado dreCaixa;
  final double aReceber;
  final double vencido;
  final double recebido;
  final double taxas;
  final double custoFixoMensal;
  final double custoMaoObraMensal;
  final double metaReceita;
  final double metaDespesa;
  final double metaResultado;
  final double receitaPrevista;
  final double receitaRealizada;
  final double despesaPrevista;
  final double despesaRealizada;
  final List<Map<String, dynamic>> topResultadosOs;
  final List<Map<String, dynamic>> evolucao;

  double get progressoReceita =>
      metaReceita <= 0 ? 0 : dreCompetencia.receitaLiquida / metaReceita;

  double get progressoDespesa {
    final referencia = despesaPrevista > despesaRealizada
        ? despesaPrevista
        : despesaRealizada;
    return metaDespesa <= 0 ? 0 : referencia / metaDespesa;
  }

  double get progressoResultado => metaResultado <= 0
      ? 0
      : dreCompetencia.resultadoGerencial / metaResultado;
}

class FinanceiroDashboardRepository {
  final DreRepository _dreRepository = DreRepository();
  final PagamentoRepository _pagamentoRepository = PagamentoRepository();
  final CustosRepository _custosRepository = CustosRepository();
  final MetaFinanceiraRepository _metaRepository = MetaFinanceiraRepository();
  final FinanceiroRepository _financeiroRepository = FinanceiroRepository();
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<FinanceiroDashboardData> carregar({required DateTime mes}) async {
    final inicio = DateTime(mes.year, mes.month, 1);
    final fim = DateTime(mes.year, mes.month + 1, 0, 23, 59, 59);

    final resultados = await Future.wait<dynamic>([
      _dreRepository.calcular(
        inicio: inicio,
        fim: fim,
        regime: DreRegime.competencia,
      ),
      _dreRepository.calcular(
        inicio: inicio,
        fim: fim,
        regime: DreRegime.caixa,
      ),
      _pagamentoRepository.obterResumoGeral(),
      _resumoPagamentosPeriodo(inicio, fim),
      _custosRepository.obterResumoEstruturaCustos(),
      _metaRepository.obterResumoMes(mes.year, mes.month),
      _custosRepository.listarResultadoOrdens(),
      _carregarEvolucao(mes),
      _financeiroRepository.obterPrevistoRealizado(
        inicio: inicio,
        fim: fim,
      ),
    ]);

    final pagamentos = Map<String, double>.from(
      resultados[2] as Map<String, double>,
    );
    final pagamentosPeriodo = Map<String, double>.from(
      resultados[3] as Map<String, double>,
    );
    final custos = Map<String, double>.from(
      resultados[4] as Map<String, double>,
    );
    final metas = Map<String, double>.from(
      resultados[5] as Map<String, double>,
    );
    final ordens = List<Map<String, dynamic>>.from(
      resultados[6] as List<dynamic>,
    );
    final previstoRealizado = Map<String, double>.from(
      resultados[8] as Map<String, double>,
    );

    final filtradas =
        ordens.where((item) {
          final data = DateTime.tryParse(
            (item['data_finalizacao'] ?? '').toString(),
          );
          return data != null &&
              data.year == mes.year &&
              data.month == mes.month;
        }).toList()..sort(
          (a, b) =>
              _double(b['resultado_os']).compareTo(_double(a['resultado_os'])),
        );

    return FinanceiroDashboardData(
      inicio: inicio,
      fim: fim,
      dreCompetencia: resultados[0] as DreResultado,
      dreCaixa: resultados[1] as DreResultado,
      aReceber: pagamentos['a_receber'] ?? 0,
      vencido: pagamentos['vencido'] ?? 0,
      recebido: pagamentosPeriodo['recebido'] ?? 0,
      taxas: pagamentosPeriodo['taxas'] ?? 0,
      custoFixoMensal: custos['custo_fixo_mensal'] ?? 0,
      custoMaoObraMensal: custos['custo_mao_obra_mensal'] ?? 0,
      metaReceita: metas['Receita'] ?? 0,
      metaDespesa: metas['Despesa'] ?? 0,
      metaResultado: metas['Resultado'] ?? 0,
      receitaPrevista: previstoRealizado['entrada_prevista'] ?? 0,
      receitaRealizada: previstoRealizado['entrada_realizada'] ?? 0,
      despesaPrevista: previstoRealizado['saida_prevista'] ?? 0,
      despesaRealizada: previstoRealizado['saida_realizada'] ?? 0,
      topResultadosOs: filtradas.take(5).toList(),
      evolucao: List<Map<String, dynamic>>.from(resultados[7] as List<dynamic>),
    );
  }

  Future<Map<String, double>> _resumoPagamentosPeriodo(
    DateTime inicio,
    DateTime fim,
  ) async {
    final database = await _appDatabase.database;
    final resultado = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN p.status = 'Pago' THEN p.valor ELSE 0 END), 0)
          AS recebido,
        COALESCE(SUM(CASE
          WHEN p.status = 'Pago' THEN p.taxa_operacao
          WHEN p.status = 'Estornado'
            AND EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = p.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
          THEN p.taxa_operacao
          ELSE 0
        END), 0) AS taxas
      FROM ordem_servico_pagamentos p
      WHERE p.data_pagamento IS NOT NULL
        AND date(p.data_pagamento) BETWEEN date(?) AND date(?)
      ''',
      [_dataDia(inicio), _dataDia(fim)],
    );

    return {
      'recebido': _double(resultado.first['recebido']),
      'taxas': _double(resultado.first['taxas']),
    };
  }

  Future<List<Map<String, dynamic>>> _carregarEvolucao(
    DateTime mesFinal,
  ) async {
    final itens = <Map<String, dynamic>>[];
    for (var deslocamento = 5; deslocamento >= 0; deslocamento--) {
      final mes = DateTime(mesFinal.year, mesFinal.month - deslocamento, 1);
      final fim = DateTime(mes.year, mes.month + 1, 0, 23, 59, 59);
      final dre = await _dreRepository.calcular(
        inicio: mes,
        fim: fim,
        regime: DreRegime.competencia,
      );
      itens.add({
        'ano': mes.year,
        'mes': mes.month,
        'receita': dre.receitaLiquida,
        'resultado': dre.resultadoGerencial,
        'margem': dre.margemPercentual,
      });
    }
    return itens;
  }

  Future<Map<String, double>> saldosContas() async {
    final database = await _appDatabase.database;
    final resultado = await database.rawQuery('''
      SELECT
        c.id,
        c.nome,
        COALESCE(c.saldo_inicial, 0) +
        COALESCE(SUM(CASE
          WHEN m.status = 'Realizado' AND LOWER(m.tipo) = 'entrada' THEN m.valor
          WHEN m.status = 'Realizado' AND LOWER(m.tipo) IN ('saída', 'saida') THEN -m.valor
          ELSE 0
        END), 0) AS saldo
      FROM financeiro_contas c
      LEFT JOIN movimentos_financeiros m ON m.conta_id = c.id
      WHERE c.ativo = 1
      GROUP BY c.id, c.nome, c.saldo_inicial
      ORDER BY c.nome COLLATE NOCASE ASC
    ''');
    return {
      for (final item in resultado)
        (item['nome'] ?? '').toString(): _double(item['saldo']),
    };
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
