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

  double _entradasMes = 0;
  double _saidasMes = 0;
  double _saldo = 0;

  int _totalClientes = 0;
  int _totalVeiculos = 0;
  int _totalAgendamentos = 0;
  int _agendamentosHoje = 0;

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
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _totalClientes = _lerInteiro(resultados[0]);
        _totalVeiculos = _lerInteiro(resultados[1]);
        _totalAgendamentos = _lerInteiro(resultados[2]);
        _agendamentosHoje = _lerInteiro(resultados[3]);
        _entradasMes = _lerDouble(resultados[4]);
        _saidasMes = _lerDouble(resultados[5]);
        _saldo = _lerDouble(resultados[6]);
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
            const Text(
              'Olá, Ryan!',
              style: TextStyle(
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
                    _mostrarEmDesenvolvimento(
                      'Estoque',
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
