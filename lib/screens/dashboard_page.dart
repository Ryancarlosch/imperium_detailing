import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../repositories/dashboard_repository.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'financeiro_page.dart';
import 'fotos_page.dart';
import 'orcamentos_page.dart';
import 'veiculos_page.dart';
import 'ordens_servico_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'servicos_page.dart';

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

  double _receitaHoje = 0;
  double _faturamentoSemana = 0;
  double _faturamentoMes = 0;
  double _saidasMes = 0;
  double _saldoMes = 0;
  double _lucroBrutoEstimadoMes = 0;
  double _custoProdutosMes = 0;
  double _saldoTotal = 0;

  int _totalClientes = 0;
  int _totalVeiculos = 0;
  int _totalAgendamentos = 0;
  int _agendamentosHoje = 0;
  int _ordensAbertas = 0;
  int _ordensEmAndamento = 0;
  int _ordensFinalizadasMes = 0;
  int _estoqueBaixo = 0;
  int _veiculosAtendidos = 0;

  double _crescimentoMes = 0;
  double _ticketMedio = 0;

  List<Map<String, Object?>> _servicosTop5 = [];
  List<Map<String, Object?>> _clientesTop5 = [];
  List<_FaturamentoDia> _faturamentoDias = [];

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  Future<void> _carregarResumo() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _mensagemErro = null;
      });
    }

    try {
      final dados = await _dashboardRepository.carregarDashboard();

      if (!mounted) {
        return;
      }

      setState(() {
        _totalClientes = dados['totalClientes'] as int? ?? 0;
        _totalVeiculos = dados['totalVeiculos'] as int? ?? 0;
        _totalAgendamentos = dados['totalAgendamentos'] as int? ?? 0;
        _agendamentosHoje = dados['agendamentosHoje'] as int? ?? 0;
        _receitaHoje = (dados['faturamentoHoje'] as num?)?.toDouble() ?? 0;
        _faturamentoSemana = (dados['faturamentoSemana'] as num?)?.toDouble() ?? 0;
        _faturamentoMes = (dados['faturamentoMes'] as num?)?.toDouble() ?? 0;
        _saidasMes = (dados['saidasMes'] as num?)?.toDouble() ?? 0;
        _saldoMes = (dados['saldoMes'] as num?)?.toDouble() ?? 0;
        _lucroBrutoEstimadoMes =
            (dados['lucroBrutoEstimadoMes'] as num?)?.toDouble() ?? 0;
        _custoProdutosMes =
            (dados['custoProdutosMes'] as num?)?.toDouble() ?? 0;
        _ticketMedio = (dados['ticketMedioMes'] as num?)?.toDouble() ?? 0;
        _veiculosAtendidos = dados['veiculosAtendidosMes'] as int? ?? 0;
        _ordensAbertas = dados['ordensAbertas'] as int? ?? 0;
        _ordensEmAndamento = dados['ordensEmAndamento'] as int? ?? 0;
        _ordensFinalizadasMes = dados['ordensFinalizadasMes'] as int? ?? 0;
        _estoqueBaixo = dados['estoqueBaixo'] as int? ?? 0;
        _saldoTotal = (dados['saldoTotal'] as num?)?.toDouble() ?? 0;
        _crescimentoMes = (dados['crescimentoMes'] as num?)?.toDouble() ?? 0;
        _servicosTop5 = (dados['servicosTop5'] as List<dynamic>?)
                ?.cast<Map<String, Object?>>() ??
            [];
        _clientesTop5 = (dados['clientesTop5'] as List<dynamic>?)
                ?.cast<Map<String, Object?>>() ??
            [];
        _faturamentoDias = _montarFaturamentoDias(
          (dados['faturamentoUltimos7Dias'] as List<dynamic>?)
                  ?.cast<Map<String, Object?>>() ??
              [],
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _mensagemErro =
            'Não foi possível carregar o dashboard. Tente novamente.';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível carregar o dashboard: $erro',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  List<_FaturamentoDia> _montarFaturamentoDias(
      List<Map<String, Object?>> resultado,
      ) {
    final agora = DateTime.now();
    final inicio = DateTime(
      agora.year,
      agora.month,
      agora.day,
    ).subtract(const Duration(days: 6));

    final valores = <String, double>{};

    for (final linha in resultado) {
      final dia = linha['dia']?.toString() ?? '';
      final valor = linha['total'];

      valores[dia] = valor is num
          ? valor.toDouble()
          : double.tryParse(
        valor?.toString() ?? '',
      ) ??
          0;
    }

    return List.generate(
      7,
          (indice) {
        final data = inicio.add(
          Duration(days: indice),
        );

        final chave = data
            .toIso8601String()
            .substring(0, 10);

        return _FaturamentoDia(
          data: data,
          valor: valores[chave] ?? 0,
        );
      },
    );
  }

  Future<void> _abrirPagina(
      Widget pagina,
      ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pagina,
      ),
    );

    await _carregarResumo();
  }

  void _mostrarEmDesenvolvimento(
      String modulo,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$modulo será desenvolvido nas próximas etapas.',
          ),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final lucroMes = _faturamentoMes - _saidasMes;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151515),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IMPERIUM',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Color(0xFFD6A84B),
              ),
            ),
            Text(
              'Detailing',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed:
            _carregando ? null : _carregarResumo,
            tooltip: 'Atualizar',
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
          IconButton(
            onPressed: () {
              _mostrarEmDesenvolvimento(
                'Notificações',
              );
            },
            tooltip: 'Notificações',
            icon: const Icon(
              Icons.notifications_outlined,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarResumo,
        child: _carregando
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            30,
          ),
          children: [
            Text(
              '${_saudacao()}, Ryan!',
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Veja o resumo da Imperium Detailing',
              style: TextStyle(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 22),
            _SaldoPrincipalCard(
              saldo: _saldoTotal,
              lucroMes: lucroMes,
              formatoMoeda: _formatoMoeda,
            ),
            const SizedBox(height: 14),
            _ResumoDiaCard(
              receitaHoje: _receitaHoje,
              agendamentosHoje: _agendamentosHoje,
              lucroMes: lucroMes,
              saldo: _saldoTotal,
              formatoMoeda: _formatoMoeda,
              onAbrirAgenda: () {
                _abrirPagina(const AgendaPage());
              },
              onAbrirFinanceiro: () {
                _abrirPagina(const FinanceiroPage());
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ResumoCard(
                    titulo: 'Entradas do mês',
                    valor: _formatoMoeda.format(
                      _faturamentoMes,
                    ),
                    icone:
                    Icons.south_west_rounded,
                    cor: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResumoCard(
                    titulo: 'Saídas do mês',
                    valor: _formatoMoeda.format(
                      _saidasMes,
                    ),
                    icone:
                    Icons.north_east_rounded,
                    cor: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AtencaoCard(
              agendamentosHoje: _agendamentosHoje,
              lucroMes: lucroMes,
              onAbrirAgenda: () {
                _abrirPagina(const AgendaPage());
              },
            ),
            const SizedBox(height: 22),
            _DashboardPremiumCard(
              entradasMes: _faturamentoMes,
              lucroMes: lucroMes,
              crescimentoMes: _crescimentoMes,
              ticketMedio: _ticketMedio,
              ordensAbertas: _ordensAbertas,
              ordensEmAndamento:
              _ordensEmAndamento,
              formatoMoeda: _formatoMoeda,
              onAbrirFinanceiro: () {
                _abrirPagina(
                  const FinanceiroPage(),
                );
              },
              onAbrirOrdens: () {
                _abrirPagina(
                  const OrdensServicoPage(),
                );
              },
            ),
            const SizedBox(height: 22),
            const Text(
              'Faturamento dos últimos 7 dias',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _GraficoFaturamentoCard(
              dados: _faturamentoDias,
              formatoMoeda: _formatoMoeda,
            ),
            const SizedBox(height: 22),
            const Text(
              'Top 5 serviços deste mês',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _RankingCard(
              itens: _servicosTop5,
              descricao: 'Serviço',
              formatoMoeda: null,
            ),
            const SizedBox(height: 18),
            const Text(
              'Top 5 clientes deste mês',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _RankingCard(
              itens: _clientesTop5,
              descricao: 'Cliente',
              formatoMoeda: _formatoMoeda,
            ),
            const SizedBox(height: 22),
            const Text(
              'Visão geral',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics:
              const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _IndicadorCard(
                  titulo: 'Clientes',
                  valor: '$_totalClientes',
                  icone: Icons.people_alt_outlined,
                ),
                _IndicadorCard(
                  titulo: 'Veículos',
                  valor: '$_totalVeiculos',
                  icone:
                  Icons.directions_car_outlined,
                ),
                _IndicadorCard(
                  titulo: 'Ordens finalizadas',
                  valor: '$_ordensFinalizadasMes',
                  icone: Icons.check_circle_outline,
                ),
                _IndicadorCard(
                  titulo: 'Veículos atendidos',
                  valor: '$_veiculosAtendidos',
                  icone: Icons.car_repair_outlined,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Acesso rápido',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics:
              const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _MenuCard(
                  titulo: 'Agenda',
                  icone: Icons.calendar_month,
                  onTap: () {
                    _abrirPagina(
                      const AgendaPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Clientes',
                  icone:
                  Icons.people_alt_outlined,
                  onTap: () {
                    _abrirPagina(
                      const ClientesPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Veículos',
                  icone: Icons.directions_car_outlined,
                  onTap: () {
                    _abrirPagina(
                      const VeiculosPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Financeiro',
                  icone: Icons
                      .account_balance_wallet_outlined,
                  onTap: () {
                    _abrirPagina(
                      const FinanceiroPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Estoque',
                  icone:
                  Icons.inventory_2_outlined,
                  onTap: () {
                    _abrirPagina(
                      const EstoquePage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Fotos',
                  icone:
                  Icons.photo_camera_outlined,
                  onTap: () {
                    _abrirPagina(
                      const FotosPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Orçamentos',
                  icone:
                  Icons.description_outlined,
                  onTap: () {
                    _abrirPagina(
                      const OrcamentosPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Ordens de Serviço',
                  icone: Icons.build_circle_outlined,
                  onTap: () {
                    _abrirPagina(
                      const OrdensServicoPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Serviços',
                  icone:
                  Icons.design_services_outlined,
                  onTap: () {
                    _abrirPagina(
                      const ServicosPage(),
                    );
                  },
                ),
                _MenuCard(
                  titulo: 'Configurações',
                  icone:
                  Icons.settings_outlined,
                  onTap: () {
                    _abrirPagina(
                      const ConfiguracoesPage(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaldoPrincipalCard extends StatelessWidget {
  const _SaldoPrincipalCard({
    required this.saldo,
    required this.lucroMes,
    required this.formatoMoeda,
  });

  final double saldo;
  final double lucroMes;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final saldoPositivo = saldo >= 0;
    final lucroPositivo = lucroMes >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF252525),
            Color(0xFF171717),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFD6A84B)
              .withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.25,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons
                    .account_balance_wallet_outlined,
                color: Color(0xFFD6A84B),
              ),
              SizedBox(width: 8),
              Text(
                'Saldo financeiro',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatoMoeda.format(saldo),
            style: TextStyle(
              color: saldoPositivo
                  ? Colors.white
                  : Colors.redAccent.shade100,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: (lucroPositivo
                  ? Colors.green
                  : Colors.red)
                  .withValues(alpha: 0.13),
              borderRadius:
              BorderRadius.circular(30),
            ),
            child: Text(
              'Resultado do mês: '
                  '${formatoMoeda.format(lucroMes)}',
              style: TextStyle(
                color: lucroPositivo
                    ? Colors.greenAccent.shade100
                    : Colors.redAccent.shade100,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoDiaCard extends StatelessWidget {
  const _ResumoDiaCard({
    required this.receitaHoje,
    required this.agendamentosHoje,
    required this.lucroMes,
    required this.saldo,
    required this.formatoMoeda,
    required this.onAbrirAgenda,
    required this.onAbrirFinanceiro,
  });

  final double receitaHoje;
  final int agendamentosHoje;
  final double lucroMes;
  final double saldo;
  final NumberFormat formatoMoeda;
  final VoidCallback onAbrirAgenda;
  final VoidCallback onAbrirFinanceiro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.today_rounded,
                color: Color(0xFFD6A84B),
              ),
              SizedBox(width: 9),
              Text(
                'Resumo do dia',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ResumoDiaItem(
                  titulo: 'Receita hoje',
                  valor: formatoMoeda.format(receitaHoje),
                  icone: Icons.payments_outlined,
                  onTap: onAbrirFinanceiro,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoDiaItem(
                  titulo: 'Agendamentos',
                  valor: '$agendamentosHoje',
                  icone: Icons.event_available_outlined,
                  onTap: onAbrirAgenda,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoDiaItem(
                  titulo: 'Lucro do mês',
                  valor: formatoMoeda.format(lucroMes),
                  icone: Icons.trending_up_rounded,
                  onTap: onAbrirFinanceiro,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoDiaItem(
                  titulo: 'Saldo total',
                  valor: formatoMoeda.format(saldo),
                  icone: Icons.account_balance_wallet_outlined,
                  onTap: onAbrirFinanceiro,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumoDiaItem extends StatelessWidget {
  const _ResumoDiaItem({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icone,
                size: 21,
                color: const Color(0xFFD6A84B),
              ),
              const SizedBox(height: 10),
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtencaoCard extends StatelessWidget {
  const _AtencaoCard({
    required this.agendamentosHoje,
    required this.lucroMes,
    required this.onAbrirAgenda,
  });

  final int agendamentosHoje;
  final double lucroMes;
  final VoidCallback onAbrirAgenda;

  @override
  Widget build(BuildContext context) {
    final mensagemAgenda = agendamentosHoje == 0
        ? 'Nenhum agendamento marcado para hoje.'
        : agendamentosHoje == 1
        ? 'Você tem 1 agendamento para hoje.'
        : 'Você tem $agendamentosHoje agendamentos para hoje.';

    final resultadoPositivo = lucroMes >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (resultadoPositivo ? Colors.green : Colors.orange)
              .withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: Color(0xFFD6A84B),
              ),
              SizedBox(width: 9),
              Text(
                'Atenção',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          InkWell(
            onTap: onAbrirAgenda,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 19,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mensagemAgenda,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                resultadoPositivo
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 20,
                color: resultadoPositivo
                    ? Colors.greenAccent.shade100
                    : Colors.orangeAccent.shade100,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  resultadoPositivo
                      ? 'O resultado financeiro do mês está positivo.'
                      : 'As saídas do mês estão maiores que as entradas.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius:
              BorderRadius.circular(11),
            ),
            child: Icon(
              icone,
              color: cor,
              size: 21,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _IndicadorCard extends StatelessWidget {
  const _IndicadorCard({
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFD6A84B)
                  .withValues(alpha: 0.12),
              borderRadius:
              BorderRadius.circular(13),
            ),
            child: Icon(
              icone,
              color: const Color(0xFFD6A84B),
              size: 23,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  titulo,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.titulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFD6A84B)
                    .withValues(alpha: 0.11),
                borderRadius:
                BorderRadius.circular(17),
              ),
              child: Icon(
                icone,
                size: 30,
                color: const Color(0xFFD6A84B),
              ),
            ),
            const SizedBox(height: 11),
            Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardPremiumCard extends StatelessWidget {
  const _DashboardPremiumCard({
    required this.entradasMes,
    required this.lucroMes,
    required this.crescimentoMes,
    required this.ticketMedio,
    required this.ordensAbertas,
    required this.ordensEmAndamento,
    required this.formatoMoeda,
    required this.onAbrirFinanceiro,
    required this.onAbrirOrdens,
  });

  final double entradasMes;
  final double lucroMes;
  final double crescimentoMes;
  final double ticketMedio;
  final int ordensAbertas;
  final int ordensEmAndamento;
  final NumberFormat formatoMoeda;
  final VoidCallback onAbrirFinanceiro;
  final VoidCallback onAbrirOrdens;

  @override
  Widget build(BuildContext context) {
    final crescimentoPositivo =
        crescimentoMes >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: const Color(0xFFD6A84B)
              .withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: Color(0xFFD6A84B),
              ),
              SizedBox(width: 9),
              Text(
                'Painel executivo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onAbrirFinanceiro,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF292929),
                    Color(0xFF202020),
                  ],
                ),
                borderRadius:
                BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Faturamento do mês',
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatoMoeda.format(
                      entradasMes,
                    ),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        crescimentoPositivo
                            ? Icons
                            .trending_up_rounded
                            : Icons
                            .trending_down_rounded,
                        size: 18,
                        color: crescimentoPositivo
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${crescimentoPositivo ? '+' : ''}'
                              '${crescimentoMes.toStringAsFixed(1)}% '
                              'em relação ao mês anterior',
                          style: TextStyle(
                            color:
                            crescimentoPositivo
                                ? Colors
                                .greenAccent
                                : Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniIndicadorPremium(
                  titulo: 'Resultado',
                  valor:
                  formatoMoeda.format(lucroMes),
                  icone: Icons.savings_outlined,
                  cor: lucroMes >= 0
                      ? Colors.green
                      : Colors.orange,
                  onTap: onAbrirFinanceiro,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniIndicadorPremium(
                  titulo: 'Ticket médio',
                  valor: formatoMoeda.format(
                    ticketMedio,
                  ),
                  icone: Icons
                      .confirmation_number_outlined,
                  cor: const Color(0xFFD6A84B),
                  onTap: onAbrirFinanceiro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniIndicadorPremium(
                  titulo: 'OS abertas',
                  valor: '$ordensAbertas',
                  icone:
                  Icons.assignment_outlined,
                  cor: Colors.blue,
                  onTap: onAbrirOrdens,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniIndicadorPremium(
                  titulo: 'Em serviço',
                  valor: '$ordensEmAndamento',
                  icone:
                  Icons.car_repair_outlined,
                  cor: Colors.orange,
                  onTap: onAbrirOrdens,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniIndicadorPremium
    extends StatelessWidget {
  const _MiniIndicadorPremium({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF222222),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Icon(
                icone,
                color: cor,
                size: 21,
              ),
              const SizedBox(height: 9),
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GraficoFaturamentoCard extends StatelessWidget {
  const _GraficoFaturamentoCard({
    required this.dados,
    required this.formatoMoeda,
  });

  final List<_FaturamentoDia> dados;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final total = dados.fold<double>(
      0,
      (soma, item) => soma + item.valor,
    );

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatoMoeda.format(total),
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Total faturado no período',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.08),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: false,
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: false,
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      dados.length,
                      (index) => FlSpot(
                        index.toDouble(),
                        dados[index].valor,
                      ),
                    ),
                    isCurved: true,
                    color: const Color(0xFFD6A84B),
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFD6A84B).withOpacity(0.35),
                          const Color(0xFFD6A84B).withOpacity(0.06),
                        ],
                      ),
                    ),
                  ),
                ],
                minY: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: dados.map(
              (item) {
                return Expanded(
                  child: Text(
                    DateFormat('dd/MM').format(item.data),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.itens,
    required this.descricao,
    required this.formatoMoeda,
  });

  final List<Map<String, Object?>> itens;
  final String descricao;
  final NumberFormat? formatoMoeda;

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Sem dados suficientes para exibir.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: itens.map(
              (item) {
            final nome = item['nome']?.toString() ?? '-';
            final total = item['total'];
            final valor = total is num
                ? total.toDouble()
                : double.tryParse(total?.toString() ?? '0') ?? 0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    formatoMoeda != null
                        ? formatoMoeda!.format(valor)
                        : valor.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }
}

class _FaturamentoDia {
  const _FaturamentoDia({
    required this.data,
    required this.valor,
  });

  final DateTime data;
  final double valor;
}

