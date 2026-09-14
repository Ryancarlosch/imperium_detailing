import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_dashboard_service.dart';
import '../services/web_cloud_relatorios_service.dart';
import 'imperium_web_theme.dart';
import 'web_contas_financeiras_page.dart';
import 'web_dre_page.dart';
import 'web_relatorios_page.dart';

class WebDashboardGerencialPage extends StatefulWidget {
  const WebDashboardGerencialPage({super.key});

  @override
  State<WebDashboardGerencialPage> createState() =>
      _WebDashboardGerencialPageState();
}

class _WebDashboardGerencialPageState extends State<WebDashboardGerencialPage> {
  final _service = WebCloudDashboardService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  WebDashboardGerencialResumo? _resumo;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resumo = await _service.carregar();
      if (!mounted) return;
      setState(() => _resumo = resumo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _abrir(Widget pagina) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel gerencial'),
        actions: [
          IconButton(
            tooltip: 'Atualizar painel',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _carregando && _resumo == null
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _resumo == null
              ? _ErroDashboard(mensagem: _erro!, onRetry: _carregar)
              : _conteudo(),
    );
  }

  Widget _conteudo() {
    final resumo = _resumo!;
    final operacional = resumo.operacional;
    final financeiro = resumo.financeiro;
    final contas = resumo.contas.take(4).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 42),
          children: [
            _HeroGestao(
              saldo: resumo.saldoConsolidado,
              faturamento: financeiro.vendas,
              resultado: financeiro.competencia.resultadoGerencial,
              moeda: _moeda,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _KpiCard(
                  titulo: 'Vendas líquidas',
                  valor: _moeda.format(financeiro.vendas),
                  detalhe: '${financeiro.quantidadeOrdens} OS finalizadas',
                  icon: Icons.receipt_long_outlined,
                ),
                _KpiCard(
                  titulo: 'Recebido',
                  valor: _moeda.format(financeiro.recebido),
                  detalhe: 'Caixa recebido das OS do período',
                  icon: Icons.payments_outlined,
                ),
                _KpiCard(
                  titulo: 'A receber',
                  valor: _moeda.format(financeiro.aReceber),
                  detalhe: 'Saldo pendente das OS do período',
                  icon: Icons.schedule_rounded,
                  alerta: financeiro.aReceber > 0,
                ),
                _KpiCard(
                  titulo: 'Ticket médio',
                  valor: _moeda.format(financeiro.ticketMedio),
                  detalhe: 'Valor líquido médio por OS',
                  icon: Icons.shopping_bag_outlined,
                ),
                _KpiCard(
                  titulo: 'OS abertas',
                  valor: '${operacional['os_abertas'] ?? 0}',
                  detalhe: 'Aberta ou em andamento',
                  icon: Icons.car_repair_outlined,
                ),
                _KpiCard(
                  titulo: 'Agenda aberta',
                  valor: '${operacional['agenda'] ?? 0}',
                  detalhe: 'Agendamentos ainda ativos',
                  icon: Icons.calendar_month_outlined,
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionTitle(
              titulo: 'Acesso rápido de gestão',
              subtitulo: 'As áreas financeiras usam a mesma fonte cloud da empresa ativa.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QuickAction(
                  icon: Icons.account_balance_wallet_outlined,
                  titulo: 'Contas e caixa',
                  detalhe: 'Saldos, extrato e conciliações',
                  onTap: () => _abrir(const WebContasFinanceirasPage()),
                ),
                _QuickAction(
                  icon: Icons.query_stats_rounded,
                  titulo: 'DRE',
                  detalhe: 'Competência e caixa',
                  onTap: () => _abrir(const WebDrePage()),
                ),
                _QuickAction(
                  icon: Icons.analytics_outlined,
                  titulo: 'Relatórios',
                  detalhe: 'Vendas, executores e indicadores',
                  onTap: () => _abrir(const WebRelatoriosPage()),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionTitle(
              titulo: 'Saldos por conta',
              subtitulo: 'Até quatro contas ativas com o saldo calculado pelo snapshot oficial.',
            ),
            const SizedBox(height: 10),
            if (contas.isEmpty)
              const _EstadoVazio('Nenhuma conta financeira ativa encontrada.')
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final conta in contas)
                    SizedBox(
                      width: 260,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_outlined,
                                    color: ImperiumWebTheme.accentStrong,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      conta.nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _moeda.format(conta.saldoAtual),
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [conta.instituicao, conta.tipo]
                                    .where((e) => e.trim().isNotEmpty)
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFAAB3BD),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 28),
            const _SectionTitle(
              titulo: 'Desempenho da equipe',
              subtitulo: 'Ranking comercial das OS sem expor salário ou custo interno.',
            ),
            const SizedBox(height: 10),
            if (financeiro.executores.isEmpty)
              const _EstadoVazio('Nenhum executor encontrado no mês atual.')
            else
              ...financeiro.executores.take(5).map(
                    (item) => _ExecutorLinha(item: item, moeda: _moeda),
                  ),
          ],
        ),
        if (_carregando)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  static String _textoErro(Object erro) {
    final texto = erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
    return texto.trim().isEmpty
        ? 'Não foi possível carregar o painel gerencial.'
        : texto;
  }
}

class _HeroGestao extends StatelessWidget {
  const _HeroGestao({
    required this.saldo,
    required this.faturamento,
    required this.resultado,
    required this.moeda,
  });

  final double saldo;
  final double faturamento;
  final double resultado;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ImperiumWebTheme.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ImperiumWebTheme.surfaceRaised,
            ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Wrap(
        spacing: 34,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 390,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visão financeira da empresa',
                  style: TextStyle(
                    color: Color(0xFFAAB3BD),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  moeda.format(saldo),
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.05,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Saldo consolidado das contas ativas',
                  style: TextStyle(color: Color(0xFFAAB3BD)),
                ),
              ],
            ),
          ),
          _HeroMini(
            titulo: 'Vendas no mês',
            valor: moeda.format(faturamento),
            icon: Icons.trending_up_rounded,
          ),
          _HeroMini(
            titulo: 'Resultado gerencial',
            valor: moeda.format(resultado),
            icon: Icons.monitoring_outlined,
            alerta: resultado < 0,
          ),
        ],
      ),
    );
  }
}

class _HeroMini extends StatelessWidget {
  const _HeroMini({
    required this.titulo,
    required this.valor,
    required this.icon,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : ImperiumWebTheme.accentStrong;
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          Icon(icon, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
                const SizedBox(height: 3),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.titulo,
    required this.valor,
    required this.detalhe,
    required this.icon,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final String detalhe;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : ImperiumWebTheme.accentStrong;
    return SizedBox(
      width: 250,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cor),
              const SizedBox(height: 13),
              Text(titulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
              const SizedBox(height: 3),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                detalhe,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF89939E), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.titulo,
    required this.detalhe,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String detalhe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 285,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: ImperiumWebTheme.accentStrong),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        detalhe,
                        style: const TextStyle(color: Color(0xFFAAB3BD), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutorLinha extends StatelessWidget {
  const _ExecutorLinha({required this.item, required this.moeda});

  final WebRelatoriosExecutor item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(item.nome, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${item.quantidade} OS · ${moeda.format(item.recebido)} recebido'),
        trailing: Text(
          moeda.format(item.vendas),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
      ],
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: Color(0xFF89939E)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    );
  }
}

class _ErroDashboard extends StatelessWidget {
  const _ErroDashboard({required this.mensagem, required this.onRetry});

  final String mensagem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 38,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(mensagem, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
