import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dashboard_repository.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'fotos_page.dart';
import 'orcamentos_page.dart';
import 'ordens_servico_page.dart';
import 'servicos_page.dart';
import 'veiculos_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashboardRepository _dashboardRepository = DashboardRepository();
  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String? _mensagemErro;

  DashboardPeriodo _periodoSelecionado = DashboardPeriodo.mesAtual;
  DateTimeRange? _periodoPersonalizado;
  DashboardData? _dados;

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  Future<void> _carregarResumo() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _carregando = true;
      _mensagemErro = null;
    });

    try {
      final dados = await _dashboardRepository.carregarDashboard(
        periodo: _periodoSelecionado,
        inicioPersonalizado: _periodoPersonalizado?.start,
        fimPersonalizado: _periodoPersonalizado?.end,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _dados = dados;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _mensagemErro = 'Não foi possível carregar o dashboard.';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Falha ao carregar o dashboard: $erro'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Future<void> _selecionarPeriodo(DashboardPeriodo periodo) async {
    if (_periodoSelecionado == periodo &&
        periodo != DashboardPeriodo.personalizado) {
      return;
    }

    if (periodo == DashboardPeriodo.personalizado) {
      final resultado = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange:
            _periodoPersonalizado ??
            DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 6)),
              end: DateTime.now(),
            ),
        helpText: 'Selecionar período personalizado',
        saveText: 'Aplicar',
        cancelText: 'Cancelar',
      );

      if (resultado == null) {
        return;
      }

      setState(() {
        _periodoSelecionado = periodo;
        _periodoPersonalizado = resultado;
      });
    } else {
      setState(() {
        _periodoSelecionado = periodo;
        _periodoPersonalizado = null;
      });
    }

    await _carregarResumo();
  }

  Future<void> _abrirPagina(Widget pagina) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
    await _carregarResumo();
  }

  String _saudacao() {
    final hora = DateTime.now().hour;

    if (hora < 12) {
      return 'Bom dia';
    }

    if (hora < 18) {
      return 'Boa tarde';
    }

    return 'Boa noite';
  }

  String _labelPeriodo() {
    switch (_periodoSelecionado) {
      case DashboardPeriodo.hoje:
        return 'Hoje';
      case DashboardPeriodo.ultimos7Dias:
        return 'Últimos 7 dias';
      case DashboardPeriodo.mesAtual:
        return 'Mês atual';
      case DashboardPeriodo.anoAtual:
        return 'Ano atual';
      case DashboardPeriodo.personalizado:
        if (_periodoPersonalizado == null) {
          return 'Período personalizado';
        }

        final formato = DateFormat('dd/MM/yyyy');
        return '${formato.format(_periodoPersonalizado!.start)} - ${formato.format(_periodoPersonalizado!.end)}';
    }
  }

  List<_PontoGrafico> _montarPontosGrafico(DashboardData dados) {
    return dados.serieFinanceira
        .map(
          (item) => _PontoGrafico(
            data: item.data,
            valor: item.entradas - item.saidas,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IMPERIUM',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Color(0xFFD6A84B),
              ),
            ),
            Text(
              _labelPeriodo(),
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _carregarResumo,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarResumo,
        color: const Color(0xFFD6A84B),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeroCabecalho(saudacao: _saudacao(), periodo: _labelPeriodo()),
            const SizedBox(height: 14),
            _FiltrosPeriodo(
              periodoSelecionado: _periodoSelecionado,
              onSelecionar: _selecionarPeriodo,
            ),
            const SizedBox(height: 14),
            if (_carregando)
              const _LoadingCard()
            else if (_mensagemErro != null)
              _ErroCard(
                mensagem: _mensagemErro!,
                onTentarNovamente: _carregarResumo,
              )
            else if (dados != null) ...[
              _IndicadoresPrincipais(dados: dados, formatoMoeda: _formatoMoeda),
              const SizedBox(height: 14),
              _ResumoExecutivoCard(dados: dados),
              const SizedBox(height: 14),
              _GraficoReceitaCard(
                pontos: _montarPontosGrafico(dados),
                formatoMoeda: _formatoMoeda,
              ),
              const SizedBox(height: 14),
              _AlertaCard(dados: dados),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _RankingCard(
                      titulo: 'Top serviços',
                      itens: dados.topServicos
                          .map(
                            (item) => _RankingLinha(
                              nome: item.nome,
                              quantidade: item.quantidade,
                              total: item.total,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RankingCard(
                      titulo: 'Top clientes',
                      itens: dados.topClientes
                          .map(
                            (item) => _RankingLinha(
                              nome: item.nome,
                              quantidade: item.quantidade,
                              total: item.total,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AtalhosRapidos(
                onAbrirAgenda: () => _abrirPagina(const AgendaPage()),
                onAbrirClientes: () => _abrirPagina(const ClientesPage()),
                onAbrirVeiculos: () => _abrirPagina(const VeiculosPage()),
                onAbrirFinanceiro: () => _abrirPagina(const FinanceiroPage()),
                onAbrirEstoque: () => _abrirPagina(const EstoquePage()),
                onAbrirFotos: () => _abrirPagina(const FotosPage()),
                onAbrirOrcamentos: () => _abrirPagina(const OrcamentosPage()),
                onAbrirOrdens: () => _abrirPagina(const OrdensServicoPage()),
                onAbrirServicos: () => _abrirPagina(const ServicosPage()),
                onAbrirConfiguracoes: () =>
                    _abrirPagina(const ConfiguracoesPage()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCabecalho extends StatelessWidget {
  const _HeroCabecalho({required this.saudacao, required this.periodo});

  final String saudacao;
  final String periodo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF121212)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            saudacao,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Dashboard premium pronta para uso diário.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              periodo,
              style: const TextStyle(
                color: Color(0xFFD6A84B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltrosPeriodo extends StatelessWidget {
  const _FiltrosPeriodo({
    required this.periodoSelecionado,
    required this.onSelecionar,
  });

  final DashboardPeriodo periodoSelecionado;
  final Future<void> Function(DashboardPeriodo periodo) onSelecionar;

  @override
  Widget build(BuildContext context) {
    final opcoes = <DashboardPeriodo, String>{
      DashboardPeriodo.hoje: 'Hoje',
      DashboardPeriodo.ultimos7Dias: 'Últimos 7 dias',
      DashboardPeriodo.mesAtual: 'Mês atual',
      DashboardPeriodo.anoAtual: 'Ano atual',
      DashboardPeriodo.personalizado: 'Período personalizado',
    };

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: opcoes.entries.map((entry) {
        final selecionado = entry.key == periodoSelecionado;
        return ChoiceChip(
          label: Text(entry.value),
          selected: selecionado,
          selectedColor: const Color(0xFFD6A84B),
          backgroundColor: const Color(0xFF1B1B1B),
          labelStyle: TextStyle(
            color: selecionado ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(
            color: selecionado
                ? const Color(0xFFD6A84B)
                : Colors.white.withValues(alpha: 0.12),
          ),
          onSelected: (_) => onSelecionar(entry.key),
        );
      }).toList(),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFFD6A84B)),
      ),
    );
  }
}

class _ErroCard extends StatelessWidget {
  const _ErroCard({required this.mensagem, required this.onTentarNovamente});

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1717),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Falha ao carregar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(mensagem, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onTentarNovamente,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _IndicadoresPrincipais extends StatelessWidget {
  const _IndicadoresPrincipais({
    required this.dados,
    required this.formatoMoeda,
  });

  final DashboardData dados;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final indicadores = <_IndicadorResumo>[
      _IndicadorResumo(
        'Faturamento',
        formatoMoeda.format(dados.faturamento),
        Icons.payments_outlined,
        const Color(0xFFD6A84B),
      ),
      _IndicadorResumo(
        'Saídas',
        formatoMoeda.format(dados.saidas),
        Icons.remove_circle_outline,
        Colors.redAccent,
      ),
      _IndicadorResumo(
        'Saldo',
        formatoMoeda.format(dados.saldo),
        Icons.account_balance_wallet_outlined,
        dados.saldo >= 0 ? Colors.greenAccent : Colors.orangeAccent,
      ),
      _IndicadorResumo(
        'Lucro bruto estimado',
        formatoMoeda.format(dados.lucroBrutoEstimado),
        Icons.trending_up_rounded,
        Colors.lightGreenAccent,
      ),
      _IndicadorResumo(
        'Ticket médio',
        formatoMoeda.format(dados.ticketMedio),
        Icons.confirmation_number_outlined,
        const Color(0xFFD6A84B),
      ),
      _IndicadorResumo(
        'Clientes atendidos',
        dados.clientesAtendidos.toString(),
        Icons.people_outline,
        Colors.lightBlueAccent,
      ),
      _IndicadorResumo(
        'Veículos atendidos',
        dados.veiculosAtendidos.toString(),
        Icons.directions_car_outlined,
        Colors.tealAccent,
      ),
      _IndicadorResumo(
        'OS abertas',
        dados.ordensAbertas.toString(),
        Icons.assignment_outlined,
        Colors.blueAccent,
      ),
      _IndicadorResumo(
        'Em andamento',
        dados.ordensEmAndamento.toString(),
        Icons.car_repair_outlined,
        Colors.orangeAccent,
      ),
      _IndicadorResumo(
        'Finalizadas',
        dados.ordensFinalizadas.toString(),
        Icons.verified_outlined,
        Colors.greenAccent,
      ),
      _IndicadorResumo(
        'Agendamentos',
        dados.agendamentos.toString(),
        Icons.event_available_outlined,
        Colors.purpleAccent,
      ),
      _IndicadorResumo(
        'Clientes novos',
        dados.clientesNovos.toString(),
        Icons.person_add_alt_1_outlined,
        Colors.cyanAccent,
      ),
      _IndicadorResumo(
        'Clientes recorrentes',
        dados.clientesRecorrentes.toString(),
        Icons.repeat_rounded,
        Colors.deepPurpleAccent,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: indicadores.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
      ),
      itemBuilder: (context, index) {
        final item = indicadores[index];
        return _IndicadorCard(item: item);
      },
    );
  }
}

class _IndicadorResumo {
  const _IndicadorResumo(this.titulo, this.valor, this.icone, this.cor);

  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;
}

class _IndicadorCard extends StatelessWidget {
  const _IndicadorCard({required this.item});

  final _IndicadorResumo item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: item.cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icone, color: item.cor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoExecutivoCard extends StatelessWidget {
  const _ResumoExecutivoCard({required this.dados});

  final DashboardData dados;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo executivo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Clientes',
                  valor: dados.clientesTotal.toString(),
                  icone: Icons.groups_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Veículos',
                  valor: dados.veiculosTotal.toString(),
                  icone: Icons.directions_car_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'OS antigas abertas',
                  valor: dados.ordensAbertasAntigas.toString(),
                  icone: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'OS antigas em andamento',
                  valor: dados.ordensEmAndamentoAntigas.toString(),
                  icone: Icons.timelapse_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Produtos baixo estoque',
                  valor: dados.produtosBaixoEstoque.toString(),
                  icone: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Produtos zerados',
                  valor: dados.produtosZerados.toString(),
                  icone: Icons.do_not_disturb_on_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumoPequeno extends StatelessWidget {
  const _ResumoPequeno({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: const Color(0xFFD6A84B), size: 20),
          const SizedBox(height: 10),
          Text(
            valor,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _GraficoReceitaCard extends StatelessWidget {
  const _GraficoReceitaCard({required this.pontos, required this.formatoMoeda});

  final List<_PontoGrafico> pontos;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final total = pontos.fold<double>(0, (soma, item) => soma + item.valor);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatoMoeda.format(total),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Faturamento líquido do período',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: pontos.isEmpty
                ? const Center(
                    child: Text(
                      'Sem movimentação para o período selecionado.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white.withValues(alpha: 0.08),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= pontos.length) {
                                return const SizedBox.shrink();
                              }

                              final data = pontos[index].data;
                              final texto = pontos.length > 7
                                  ? DateFormat('MM/yy').format(data)
                                  : DateFormat('dd/MM').format(data);

                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  texto,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < pontos.length; i++)
                              FlSpot(i.toDouble(), pontos[i].valor),
                          ],
                          isCurved: true,
                          color: const Color(0xFFD6A84B),
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFD6A84B).withValues(alpha: 0.35),
                                const Color(0xFFD6A84B).withValues(alpha: 0.03),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.dados});

  final DashboardData dados;

  @override
  Widget build(BuildContext context) {
    if (!dados.temAlertas) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Text(
          'Nenhum alerta relevante para o momento.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alertas operacionais',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...dados.alertas.map(
            (alerta) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: alerta.tipo == DashboardAlertaTipo.estoque
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: alerta.tipo == DashboardAlertaTipo.estoque
                        ? Colors.orange.withValues(alpha: 0.22)
                        : Colors.red.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      alerta.tipo == DashboardAlertaTipo.agendamento
                          ? Icons.event_available_outlined
                          : alerta.tipo == DashboardAlertaTipo.estoque
                          ? Icons.inventory_2_outlined
                          : Icons.warning_amber_rounded,
                      color: const Color(0xFFD6A84B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alerta.titulo,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            alerta.descricao,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      alerta.quantidade.toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD6A84B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.titulo, required this.itens});

  final String titulo;
  final List<_RankingLinha> itens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (itens.isEmpty)
            const Text(
              'Sem dados suficientes.',
              style: TextStyle(color: Colors.white60),
            )
          else
            ...itens.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.quantidade.toString(),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      NumberFormat.currency(
                        locale: 'pt_BR',
                        symbol: 'R\$',
                      ).format(item.total),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingLinha {
  const _RankingLinha({
    required this.nome,
    required this.quantidade,
    required this.total,
  });

  final String nome;
  final int quantidade;
  final double total;
}

class _AtalhosRapidos extends StatelessWidget {
  const _AtalhosRapidos({
    required this.onAbrirAgenda,
    required this.onAbrirClientes,
    required this.onAbrirVeiculos,
    required this.onAbrirFinanceiro,
    required this.onAbrirEstoque,
    required this.onAbrirFotos,
    required this.onAbrirOrcamentos,
    required this.onAbrirOrdens,
    required this.onAbrirServicos,
    required this.onAbrirConfiguracoes,
  });

  final VoidCallback onAbrirAgenda;
  final VoidCallback onAbrirClientes;
  final VoidCallback onAbrirVeiculos;
  final VoidCallback onAbrirFinanceiro;
  final VoidCallback onAbrirEstoque;
  final VoidCallback onAbrirFotos;
  final VoidCallback onAbrirOrcamentos;
  final VoidCallback onAbrirOrdens;
  final VoidCallback onAbrirServicos;
  final VoidCallback onAbrirConfiguracoes;

  @override
  Widget build(BuildContext context) {
    final itens = <_AtalhoItem>[
      _AtalhoItem('Agenda', Icons.calendar_month_outlined, onAbrirAgenda),
      _AtalhoItem('Clientes', Icons.people_outline, onAbrirClientes),
      _AtalhoItem('Veículos', Icons.directions_car_outlined, onAbrirVeiculos),
      _AtalhoItem('Financeiro', Icons.payments_outlined, onAbrirFinanceiro),
      _AtalhoItem('Estoque', Icons.inventory_2_outlined, onAbrirEstoque),
      _AtalhoItem('Fotos', Icons.photo_library_outlined, onAbrirFotos),
      _AtalhoItem(
        'Orçamentos',
        Icons.request_quote_outlined,
        onAbrirOrcamentos,
      ),
      _AtalhoItem('Ordens', Icons.assignment_outlined, onAbrirOrdens),
      _AtalhoItem(
        'Serviços',
        Icons.miscellaneous_services_outlined,
        onAbrirServicos,
      ),
      _AtalhoItem(
        'Configurações',
        Icons.settings_outlined,
        onAbrirConfiguracoes,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acesso rápido',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itens.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5,
            ),
            itemBuilder: (context, index) {
              final item = itens[index];
              return InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(item.icone, color: const Color(0xFFD6A84B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AtalhoItem {
  const _AtalhoItem(this.titulo, this.icone, this.onTap);

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;
}

class _PontoGrafico {
  const _PontoGrafico({required this.data, required this.valor});

  final DateTime data;
  final double valor;
}
