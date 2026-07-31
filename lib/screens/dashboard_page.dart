import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
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
  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;

  double _receitaHoje = 0;
  double _entradasMes = 0;
  double _saidasMes = 0;
  double _saldo = 0;

  int _totalClientes = 0;
  int _totalVeiculos = 0;
  int _totalAgendamentos = 0;
  int _agendamentosHoje = 0;
  int _ordensAbertas = 0;
  int _ordensEmAndamento = 0;

  double _entradasMesAnterior = 0;
  double _ticketMedio = 0;

  List<_FaturamentoDia> _faturamentoDias = [];

  double get _crescimentoMes {
    if (_entradasMesAnterior == 0) {
      return _entradasMes > 0 ? 100 : 0;
    }

    return ((_entradasMes - _entradasMesAnterior) /
        _entradasMesAnterior) *
        100;
  }

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  Future<void> _carregarResumo() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final database = await AppDatabase.instance.database;
      final agora = DateTime.now();

      final inicioMes = DateTime(
        agora.year,
        agora.month,
        1,
      ).toIso8601String();

      final inicioProximoMes = DateTime(
        agora.year,
        agora.month + 1,
        1,
      ).toIso8601String();

      final inicioHoje = DateTime(
        agora.year,
        agora.month,
        agora.day,
      ).toIso8601String();

      final inicioAmanha = DateTime(
        agora.year,
        agora.month,
        agora.day + 1,
      ).toIso8601String();

      final inicioMesAnterior = DateTime(
        agora.year,
        agora.month - 1,
        1,
      ).toIso8601String();

      final inicioGrafico = DateTime(
        agora.year,
        agora.month,
        agora.day,
      )
          .subtract(const Duration(days: 6))
          .toIso8601String();

      final resultados = await Future.wait([
        database.rawQuery(
          'SELECT COUNT(*) AS total FROM clientes',
        ),
        database.rawQuery(
          'SELECT COUNT(*) AS total FROM veiculos',
        ),
        database.rawQuery(
          'SELECT COUNT(*) AS total FROM agendamentos',
        ),
        database.rawQuery(
          '''
          SELECT COUNT(*) AS total
          FROM agendamentos
          WHERE data >= ? AND data < ?
          ''',
          [
            inicioHoje,
            inicioAmanha,
          ],
        ),
        database.rawQuery(
          '''
          SELECT COALESCE(SUM(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) = 'entrada'
            AND data >= ?
            AND data < ?
          ''',
          [
            inicioHoje,
            inicioAmanha,
          ],
        ),
        database.rawQuery(
          '''
          SELECT COALESCE(SUM(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) = 'entrada'
            AND data >= ?
            AND data < ?
          ''',
          [
            inicioMes,
            inicioProximoMes,
          ],
        ),
        database.rawQuery(
          '''
          SELECT COALESCE(SUM(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) IN ('saída', 'saida')
            AND data >= ?
            AND data < ?
          ''',
          [
            inicioMes,
            inicioProximoMes,
          ],
        ),
        database.rawQuery(
          '''
          SELECT
            COALESCE(SUM(
              CASE
                WHEN LOWER(tipo) = 'entrada' THEN valor
                WHEN LOWER(tipo) IN ('saída', 'saida') THEN -valor
                ELSE 0
              END
            ), 0) AS total
          FROM movimentos_financeiros
          ''',
        ),
        database.rawQuery(
          '''
          SELECT COALESCE(SUM(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) = 'entrada'
            AND data >= ?
            AND data < ?
          ''',
          [
            inicioMesAnterior,
            inicioMes,
          ],
        ),
        database.rawQuery(
          '''
          SELECT COALESCE(AVG(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) = 'entrada'
            AND data >= ?
            AND data < ?
          ''',
          [
            inicioMes,
            inicioProximoMes,
          ],
        ),
        _consultaSegura(
          database,
          '''
          SELECT COUNT(*) AS total
          FROM ordens_servico
          WHERE LOWER(status) = 'aberta'
          ''',
        ),
        _consultaSegura(
          database,
          '''
          SELECT COUNT(*) AS total
          FROM ordens_servico
          WHERE LOWER(status) = 'em andamento'
          ''',
        ),
        database.rawQuery(
          '''
          SELECT
            substr(data, 1, 10) AS dia,
            COALESCE(SUM(valor), 0) AS total
          FROM movimentos_financeiros
          WHERE LOWER(tipo) = 'entrada'
            AND data >= ?
            AND data < ?
          GROUP BY substr(data, 1, 10)
          ORDER BY dia ASC
          ''',
          [
            inicioGrafico,
            inicioAmanha,
          ],
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _totalClientes = _lerInteiro(resultados[0]);
        _totalVeiculos = _lerInteiro(resultados[1]);
        _totalAgendamentos = _lerInteiro(resultados[2]);
        _agendamentosHoje = _lerInteiro(resultados[3]);
        _receitaHoje = _lerDouble(resultados[4]);
        _entradasMes = _lerDouble(resultados[5]);
        _saidasMes = _lerDouble(resultados[6]);
        _saldo = _lerDouble(resultados[7]);
        _entradasMesAnterior =
            _lerDouble(resultados[8]);
        _ticketMedio =
            _lerDouble(resultados[9]);
        _ordensAbertas =
            _lerInteiro(resultados[10]);
        _ordensEmAndamento =
            _lerInteiro(resultados[11]);
        _faturamentoDias =
            _montarFaturamentoDias(
              resultados[12],
            );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
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

  Future<List<Map<String, Object?>>> _consultaSegura(
      dynamic database,
      String sql,
      ) async {
    try {
      return await database.rawQuery(sql);
    } catch (_) {
      return <Map<String, Object?>>[];
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

  int _lerInteiro(
      List<Map<String, Object?>> resultado,
      ) {
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

    return int.tryParse(
      valor?.toString() ?? '',
    ) ??
        0;
  }

  double _lerDouble(
      List<Map<String, Object?>> resultado,
      ) {
    if (resultado.isEmpty) {
      return 0;
    }

    final valor = resultado.first['total'];

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
      valor?.toString() ?? '',
    ) ??
        0;
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
    final lucroMes = _entradasMes - _saidasMes;

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
              saldo: _saldo,
              lucroMes: lucroMes,
              formatoMoeda: _formatoMoeda,
            ),
            const SizedBox(height: 14),
            _ResumoDiaCard(
              receitaHoje: _receitaHoje,
              agendamentosHoje: _agendamentosHoje,
              lucroMes: lucroMes,
              saldo: _saldo,
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
                      _entradasMes,
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
              entradasMes: _entradasMes,
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
                  titulo: 'Agendamentos',
                  valor: '$_totalAgendamentos',
                  icone: Icons.calendar_month,
                ),
                _IndicadorCard(
                  titulo: 'Hoje',
                  valor: '$_agendamentosHoje',
                  icone: Icons.today_rounded,
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

class _GraficoFaturamentoCard
    extends StatelessWidget {
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
        crossAxisAlignment:
        CrossAxisAlignment.start,
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
            child: CustomPaint(
              painter: _DashboardGraficoPainter(
                dados,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: dados.map(
                  (item) {
                return Expanded(
                  child: Text(
                    DateFormat('dd/MM').format(
                      item.data,
                    ),
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

class _DashboardGraficoPainter
    extends CustomPainter {
  _DashboardGraficoPainter(this.dados);

  final List<_FaturamentoDia> dados;

  @override
  void paint(Canvas canvas, Size size) {
    if (dados.isEmpty) {
      return;
    }

    final maior = dados.fold<double>(
      0,
          (atual, item) =>
          math.max(atual, item.valor),
    );

    final grade = Paint()
      ..color =
      Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grade,
      );
    }

    final larguraColuna =
        size.width / dados.length;
    final larguraBarra =
        larguraColuna * 0.48;

    for (var i = 0; i < dados.length; i++) {
      final valor = dados[i].valor;

      final altura = maior <= 0
          ? 4.0
          : math.max(
        4.0,
        (valor / maior) *
            (size.height - 8),
      );

      final esquerda =
          larguraColuna * i +
              (larguraColuna -
                  larguraBarra) /
                  2;

      final barra =
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          esquerda,
          size.height - altura,
          larguraBarra,
          altura,
        ),
        const Radius.circular(7),
      );

      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xFF8D6B28),
            Color(0xFFD6A84B),
          ],
        ).createShader(
          Rect.fromLTWH(
            esquerda,
            0,
            larguraBarra,
            size.height,
          ),
        );

      canvas.drawRRect(barra, paint);
    }
  }

  @override
  bool shouldRepaint(
      covariant _DashboardGraficoPainter
      oldDelegate,
      ) {
    return oldDelegate.dados != dados;
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

