import '../models/item_estoque.dart';
import 'crm_operacao_repository.dart';
import 'custos_repository.dart';
import 'dashboard_repository.dart';
import 'dre_repository.dart';
import 'estoque_repository.dart';
import 'financeiro_dashboard_repository.dart';
import 'ponto_repository.dart';
import 'precificacao_repository.dart';

class CentralGerencialComparativo {
  const CentralGerencialComparativo({
    required this.titulo,
    required this.atual,
    required this.anterior,
    this.percentual = false,
    this.inteiro = false,
    this.maiorMelhor = true,
  });

  final String titulo;
  final double atual;
  final double anterior;
  final bool percentual;
  final bool inteiro;
  final bool maiorMelhor;

  bool get possuiBaseComparacao => anterior.abs() > 0.000001;

  double? get variacaoPercentual {
    if (!possuiBaseComparacao) {
      return null;
    }
    return (atual - anterior) / anterior.abs() * 100;
  }

  double get diferenca => atual - anterior;

  bool get evoluiu {
    final variacao = diferenca;
    if (variacao.abs() <= 0.000001) {
      return false;
    }
    return maiorMelhor ? variacao > 0 : variacao < 0;
  }
}

class CentralGerencialServico {
  const CentralGerencialServico({
    required this.nome,
    required this.quantidade,
    required this.receita,
    required this.resultado,
    required this.margem,
  });

  final String nome;
  final double quantidade;
  final double receita;
  final double resultado;
  final double margem;
}

class CentralGerencialMes {
  const CentralGerencialMes({
    required this.ano,
    required this.mes,
    required this.receita,
    required this.resultado,
    required this.margem,
  });

  final int ano;
  final int mes;
  final double receita;
  final double resultado;
  final double margem;
}

enum CentralGerencialAlertaNivel { critico, atencao, oportunidade, informacao }

class CentralGerencialAlerta {
  const CentralGerencialAlerta({
    required this.nivel,
    required this.titulo,
    required this.detalhe,
  });

  final CentralGerencialAlertaNivel nivel;
  final String titulo;
  final String detalhe;
}

class CentralGerencialResumo {
  const CentralGerencialResumo({
    required this.inicio,
    required this.fim,
    required this.inicioAnterior,
    required this.fimAnterior,
    required this.indicadores,
    required this.saldoContas,
    required this.aReceber,
    required this.vencido,
    required this.receitaPrevistaMes,
    required this.receitaRealizadaMes,
    required this.despesaPrevistaMes,
    required this.despesaRealizadaMes,
    required this.custoFixoMensal,
    required this.custoMaoObraMensal,
    required this.valorEstoque,
    required this.itensEstoqueBaixo,
    required this.itensEstoqueZerado,
    required this.servicosAbaixoMinimo,
    required this.potencialReajuste,
    required this.horasTrabalhadas,
    required this.horasExtras,
    required this.horasFaltantes,
    required this.faltas,
    required this.topServicos,
    required this.evolucaoMensal,
    required this.alertas,
  });

  final DateTime inicio;
  final DateTime fim;
  final DateTime inicioAnterior;
  final DateTime fimAnterior;
  final List<CentralGerencialComparativo> indicadores;

  final double saldoContas;
  final double aReceber;
  final double vencido;
  final double receitaPrevistaMes;
  final double receitaRealizadaMes;
  final double despesaPrevistaMes;
  final double despesaRealizadaMes;
  final double custoFixoMensal;
  final double custoMaoObraMensal;

  final double valorEstoque;
  final int itensEstoqueBaixo;
  final int itensEstoqueZerado;
  final int servicosAbaixoMinimo;
  final double potencialReajuste;

  final double horasTrabalhadas;
  final double horasExtras;
  final double horasFaltantes;
  final int faltas;

  final List<CentralGerencialServico> topServicos;
  final List<CentralGerencialMes> evolucaoMensal;
  final List<CentralGerencialAlerta> alertas;
}

class CentralGerencialRepository {
  CentralGerencialRepository({
    DashboardRepository? dashboardRepository,
    DreRepository? dreRepository,
    FinanceiroDashboardRepository? financeiroRepository,
    EstoqueRepository? estoqueRepository,
    PrecificacaoRepository? precificacaoRepository,
    CustosRepository? custosRepository,
    PontoRepository? pontoRepository,
    CrmOperacaoRepository? crmRepository,
  }) : _dashboardRepository = dashboardRepository ?? DashboardRepository(),
       _dreRepository = dreRepository ?? DreRepository(),
       _financeiroRepository =
           financeiroRepository ?? FinanceiroDashboardRepository(),
       _estoqueRepository = estoqueRepository ?? EstoqueRepository(),
       _precificacaoRepository =
           precificacaoRepository ?? PrecificacaoRepository(),
       _custosRepository = custosRepository ?? CustosRepository(),
       _pontoRepository = pontoRepository ?? PontoRepository(),
       _crmRepository = crmRepository ?? CrmOperacaoRepository();

  final DashboardRepository _dashboardRepository;
  final DreRepository _dreRepository;
  final FinanceiroDashboardRepository _financeiroRepository;
  final EstoqueRepository _estoqueRepository;
  final PrecificacaoRepository _precificacaoRepository;
  final CustosRepository _custosRepository;
  final PontoRepository _pontoRepository;
  final CrmOperacaoRepository _crmRepository;

  Future<CentralGerencialResumo> carregar({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final periodo = normalizarPeriodo(inicio, fim);
    final anterior = periodoAnterior(periodo.$1, periodo.$2);

    final dashboardAtualFuturo = _dashboardRepository.carregarDashboard(
      periodo: DashboardPeriodo.personalizado,
      inicioPersonalizado: periodo.$1,
      fimPersonalizado: periodo.$2,
    );
    final dashboardAnteriorFuturo = _dashboardRepository.carregarDashboard(
      periodo: DashboardPeriodo.personalizado,
      inicioPersonalizado: anterior.$1,
      fimPersonalizado: anterior.$2,
    );
    final dreAtualFuturo = _dreRepository.calcular(
      inicio: periodo.$1,
      fim: periodo.$2,
      regime: DreRegime.competencia,
    );
    final dreAnteriorFuturo = _dreRepository.calcular(
      inicio: anterior.$1,
      fim: anterior.$2,
      regime: DreRegime.competencia,
    );
    final financeiroFuturo = _financeiroRepository.carregar(mes: periodo.$2);
    final estoqueFuturo = _estoqueRepository.listarItens();
    final precificacaoFuturo = _precificacaoRepository.carregar();
    final custosFuturo = _custosRepository.obterResumoEstruturaCustos();
    final crmAtualFuturo = _crmRepository.carregarDesempenho(
      inicio: periodo.$1,
      fim: periodo.$2,
    );
    final crmAnteriorFuturo = _crmRepository.carregarDesempenho(
      inicio: anterior.$1,
      fim: anterior.$2,
    );
    final servicosFuturo = _dreRepository.listarResultadoServicos(
      inicio: periodo.$1,
      fim: periodo.$2,
    );
    final evolucaoFuturo = _dreRepository.evolucaoMensal(
      ano: periodo.$2.year,
      regime: DreRegime.competencia,
    );
    final pontoFuturo = _carregarPonto(periodo.$1, periodo.$2);

    final resultados = await Future.wait<dynamic>([
      dashboardAtualFuturo,
      dashboardAnteriorFuturo,
      dreAtualFuturo,
      dreAnteriorFuturo,
      financeiroFuturo,
      estoqueFuturo,
      precificacaoFuturo,
      custosFuturo,
      crmAtualFuturo,
      crmAnteriorFuturo,
      servicosFuturo,
      evolucaoFuturo,
      pontoFuturo,
    ]);

    final dashboardAtual = resultados[0] as DashboardData;
    final dashboardAnterior = resultados[1] as DashboardData;
    final dreAtual = resultados[2] as DreResultado;
    final dreAnterior = resultados[3] as DreResultado;
    final financeiro = resultados[4] as FinanceiroDashboardData;
    final estoque = resultados[5] as List<ItemEstoque>;
    final precificacao = resultados[6] as PrecificacaoPainel;
    final custos = resultados[7] as Map<String, double>;
    final crmAtual = resultados[8] as CrmDesempenhoResumo;
    final crmAnterior = resultados[9] as CrmDesempenhoResumo;
    final servicos = resultados[10] as List<DreServicoResultado>;
    final evolucao = resultados[11] as List<DreResultado>;
    final ponto = resultados[12] as _PontoGerencial;

    final valorEstoque = estoque.fold<double>(
      0,
      (total, item) => total + item.valorTotal,
    );
    final estoqueBaixo = estoque.where((item) => item.estoqueBaixo).length;
    final estoqueZerado = estoque.where((item) => item.estoqueZerado).length;

    final abaixoMinimo = precificacao.servicos
        .where(
          (item) =>
              item.precoAtual > 0 &&
              item.precoAtual + 0.005 < item.precoMinimoSeguro,
        )
        .toList();
    final potencialReajuste = abaixoMinimo.fold<double>(
      0,
      (total, item) =>
          total +
          (item.precoSugerido - item.precoAtual)
              .clamp(0, double.infinity)
              .toDouble(),
    );

    final ranking = [...servicos]
      ..sort((a, b) => b.receitaLiquida.compareTo(a.receitaLiquida));

    final topServicos = ranking
        .take(8)
        .map(
          (item) => CentralGerencialServico(
            nome: item.servico,
            quantidade: item.quantidade,
            receita: item.receitaLiquida,
            resultado: item.resultadoGerencialEstimado,
            margem: item.margemGerencial,
          ),
        )
        .toList();

    final meses = evolucao
        .where(
          (item) =>
              item.receitaLiquida.abs() > 0.000001 ||
              item.resultadoGerencial.abs() > 0.000001,
        )
        .map(
          (item) => CentralGerencialMes(
            ano: item.inicio.year,
            mes: item.inicio.month,
            receita: item.receitaLiquida,
            resultado: item.resultadoGerencial,
            margem: item.margemPercentual,
          ),
        )
        .toList();

    final indicadores = <CentralGerencialComparativo>[
      CentralGerencialComparativo(
        titulo: 'Faturamento',
        atual: dreAtual.receitaLiquida,
        anterior: dreAnterior.receitaLiquida,
      ),
      CentralGerencialComparativo(
        titulo: 'Resultado gerencial',
        atual: dreAtual.resultadoGerencial,
        anterior: dreAnterior.resultadoGerencial,
      ),
      CentralGerencialComparativo(
        titulo: 'Margem',
        atual: dreAtual.margemPercentual,
        anterior: dreAnterior.margemPercentual,
        percentual: true,
      ),
      CentralGerencialComparativo(
        titulo: 'Ticket médio',
        atual: dashboardAtual.ticketMedio,
        anterior: dashboardAnterior.ticketMedio,
      ),
      CentralGerencialComparativo(
        titulo: 'OS finalizadas',
        atual: dashboardAtual.ordensFinalizadas.toDouble(),
        anterior: dashboardAnterior.ordensFinalizadas.toDouble(),
        inteiro: true,
      ),
      CentralGerencialComparativo(
        titulo: 'Clientes novos',
        atual: dashboardAtual.clientesNovos.toDouble(),
        anterior: dashboardAnterior.clientesNovos.toDouble(),
        inteiro: true,
      ),
      CentralGerencialComparativo(
        titulo: 'Conversão CRM',
        atual: crmAtual.conversaoLeads,
        anterior: crmAnterior.conversaoLeads,
        percentual: true,
      ),
      CentralGerencialComparativo(
        titulo: 'Aprovação de orçamentos',
        atual: crmAtual.aprovacaoOrcamentos,
        anterior: crmAnterior.aprovacaoOrcamentos,
        percentual: true,
      ),
    ];

    final alertas = gerarAlertasBase(
      resultado: dreAtual.resultadoGerencial,
      margemAtual: dreAtual.margemPercentual,
      margemAnterior: dreAnterior.margemPercentual,
      vencido: financeiro.vencido,
      itensEstoqueBaixo: estoqueBaixo,
      itensEstoqueZerado: estoqueZerado,
      conversaoAtual: crmAtual.conversaoLeads,
      conversaoAnterior: crmAnterior.conversaoLeads,
      servicosAbaixoMinimo: abaixoMinimo.length,
      horasFaltantes: ponto.horasFaltantes,
      receitaPrevista: financeiro.receitaPrevista,
      receitaRealizada: financeiro.receitaRealizada,
    );

    return CentralGerencialResumo(
      inicio: periodo.$1,
      fim: periodo.$2,
      inicioAnterior: anterior.$1,
      fimAnterior: anterior.$2,
      indicadores: indicadores,
      saldoContas: dashboardAtual.saldoTotalContas,
      aReceber: financeiro.aReceber,
      vencido: financeiro.vencido,
      receitaPrevistaMes: financeiro.receitaPrevista,
      receitaRealizadaMes: financeiro.receitaRealizada,
      despesaPrevistaMes: financeiro.despesaPrevista,
      despesaRealizadaMes: financeiro.despesaRealizada,
      custoFixoMensal: custos['custo_fixo_mensal'] ?? 0,
      custoMaoObraMensal: custos['custo_mao_obra_mensal'] ?? 0,
      valorEstoque: valorEstoque,
      itensEstoqueBaixo: estoqueBaixo,
      itensEstoqueZerado: estoqueZerado,
      servicosAbaixoMinimo: abaixoMinimo.length,
      potencialReajuste: potencialReajuste,
      horasTrabalhadas: ponto.horasTrabalhadas,
      horasExtras: ponto.horasExtras,
      horasFaltantes: ponto.horasFaltantes,
      faltas: ponto.faltas,
      topServicos: topServicos,
      evolucaoMensal: meses,
      alertas: alertas,
    );
  }

  Future<_PontoGerencial> _carregarPonto(DateTime inicio, DateTime fim) async {
    try {
      final colaboradores = await _custosRepository.listarColaboradores();
      var trabalhadas = 0.0;
      var extras = 0.0;
      var faltantes = 0.0;
      var faltas = 0;

      for (final colaborador in colaboradores) {
        final id = colaborador.id;
        if (id == null) {
          continue;
        }
        final espelho = await _pontoRepository.obterEspelhoMes(
          colaboradorId: id,
          inicio: inicio,
          fim: fim,
        );
        trabalhadas += _inteiro(espelho['minutos_trabalhados']) / 60.0;
        extras += _inteiro(espelho['minutos_extras']) / 60.0;
        faltantes += _inteiro(espelho['minutos_faltantes']) / 60.0;
        faltas += _inteiro(espelho['faltas']);
      }

      return _PontoGerencial(
        horasTrabalhadas: trabalhadas,
        horasExtras: extras,
        horasFaltantes: faltantes,
        faltas: faltas,
      );
    } catch (_) {
      return const _PontoGerencial();
    }
  }

  static (DateTime, DateTime) normalizarPeriodo(DateTime inicio, DateTime fim) {
    final a = DateTime(inicio.year, inicio.month, inicio.day);
    final b = DateTime(fim.year, fim.month, fim.day);
    return a.isAfter(b) ? (b, a) : (a, b);
  }

  static (DateTime, DateTime) periodoAnterior(DateTime inicio, DateTime fim) {
    final normalizado = normalizarPeriodo(inicio, fim);
    final dias = normalizado.$2.difference(normalizado.$1).inDays + 1;
    final fimAnterior = normalizado.$1.subtract(const Duration(days: 1));
    final inicioAnterior = fimAnterior.subtract(Duration(days: dias - 1));
    return (inicioAnterior, fimAnterior);
  }

  static List<CentralGerencialAlerta> gerarAlertasBase({
    required double resultado,
    required double margemAtual,
    required double margemAnterior,
    required double vencido,
    required int itensEstoqueBaixo,
    required int itensEstoqueZerado,
    required double conversaoAtual,
    required double conversaoAnterior,
    required int servicosAbaixoMinimo,
    required double horasFaltantes,
    required double receitaPrevista,
    required double receitaRealizada,
  }) {
    final alertas = <CentralGerencialAlerta>[];

    if (resultado < 0) {
      alertas.add(
        const CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.critico,
          titulo: 'Resultado negativo no período',
          detalhe:
              'O resultado gerencial ficou abaixo de zero. Revise preço, custos e despesas.',
        ),
      );
    }

    final quedaMargem = margemAnterior - margemAtual;
    if (margemAnterior.abs() > 0.000001 && quedaMargem >= 5) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.atencao,
          titulo: 'Margem caiu ${quedaMargem.toStringAsFixed(1)} p.p.',
          detalhe:
              'Compare serviços, descontos, produtos consumidos e taxas com o período anterior.',
        ),
      );
    }

    if (vencido > 0) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.critico,
          titulo: 'Existem valores vencidos a receber',
          detalhe:
              'Há saldo vencido no financeiro. Priorize cobrança e conciliação.',
        ),
      );
    }

    if (itensEstoqueZerado > 0 || itensEstoqueBaixo > 0) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: itensEstoqueZerado > 0
              ? CentralGerencialAlertaNivel.critico
              : CentralGerencialAlertaNivel.atencao,
          titulo: 'Estoque exige reposição',
          detalhe:
              '$itensEstoqueBaixo item(ns) baixo(s) e $itensEstoqueZerado zerado(s).',
        ),
      );
    }

    final quedaConversao = conversaoAnterior - conversaoAtual;
    if (conversaoAnterior > 0 && quedaConversao >= 10) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.atencao,
          titulo:
              'Conversão do CRM caiu ${quedaConversao.toStringAsFixed(1)} p.p.',
          detalhe: 'Revise origem dos leads, follow-ups e motivos de perda.',
        ),
      );
    }

    if (servicosAbaixoMinimo > 0) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.critico,
          titulo:
              '$servicosAbaixoMinimo serviço(s) abaixo do preço mínimo seguro',
          detalhe:
              'A precificação indica risco de margem. Reavalie preços antes de aplicar novos descontos.',
        ),
      );
    }

    if (horasFaltantes >= 8) {
      alertas.add(
        CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.atencao,
          titulo: 'Horas faltantes relevantes no período',
          detalhe:
              '${horasFaltantes.toStringAsFixed(1)}h faltantes registradas no Ponto.',
        ),
      );
    }

    if (receitaPrevista > 0 && receitaRealizada < receitaPrevista * 0.7) {
      alertas.add(
        const CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.informacao,
          titulo: 'Receita realizada abaixo do previsto',
          detalhe:
              'Menos de 70% da receita prevista para o mês está realizada no financeiro.',
        ),
      );
    }

    if (alertas.isEmpty) {
      alertas.add(
        const CentralGerencialAlerta(
          nivel: CentralGerencialAlertaNivel.oportunidade,
          titulo: 'Nenhum alerta gerencial crítico detectado',
          detalhe:
              'Os indicadores acompanhados estão sem gatilhos de atenção neste momento.',
        ),
      );
    }

    return alertas;
  }

  static int _inteiro(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}

class _PontoGerencial {
  const _PontoGerencial({
    this.horasTrabalhadas = 0,
    this.horasExtras = 0,
    this.horasFaltantes = 0,
    this.faltas = 0,
  });

  final double horasTrabalhadas;
  final double horasExtras;
  final double horasFaltantes;
  final int faltas;
}
