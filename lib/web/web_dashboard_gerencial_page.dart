import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_dashboard_service.dart';
import '../services/web_cloud_relatorios_service.dart';
import 'imperium_web_theme.dart';

class WebDashboardGerencialPage extends StatefulWidget {
  const WebDashboardGerencialPage({
    super.key,
    required this.onAbrirOperacao,
    required this.onAbrirContas,
    required this.onAbrirDre,
    required this.onAbrirRelatorios,
    required this.onAbrirPonto,
  });

  final VoidCallback onAbrirOperacao;
  final VoidCallback onAbrirContas;
  final VoidCallback onAbrirDre;
  final VoidCallback onAbrirRelatorios;
  final VoidCallback onAbrirPonto;

  @override
  State<WebDashboardGerencialPage> createState() =>
      _WebDashboardGerencialPageState();
}

class _WebDashboardGerencialPageState extends State<WebDashboardGerencialPage> {
  final _service = WebCloudDashboardService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  WebDashboardGerencialResumo? _resumo;
  bool _carregando = true;
  bool _ocultarValores = false;
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

  String _valor(double valor) =>
      _ocultarValores ? 'R\$ ••••••' : _moeda.format(valor);

  @override
  Widget build(BuildContext context) {
    if (_carregando && _resumo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null && _resumo == null) {
      return _ErroDashboard(mensagem: _erro!, onRetry: _carregar);
    }

    return _conteudo();
  }

  Widget _conteudo() {
    final resumo = _resumo!;
    final operacional = resumo.operacional;
    final financeiro = resumo.financeiro;
    final contas = resumo.contas.take(4).toList();
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 760;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              compacto ? 16 : 28,
              compacto ? 16 : 24,
              compacto ? 16 : 28,
              44,
            ),
            children: [
              _CabecalhoPainel(
                compacto: compacto,
                ocultarValores: _ocultarValores,
                onAlternarValores: () => setState(
                  () => _ocultarValores = !_ocultarValores,
                ),
                onAtualizar: _carregando ? null : _carregar,
              ),
              const SizedBox(height: 18),
              _HeroGestao(
                saldo: _valor(resumo.saldoConsolidado),
                faturamento: _valor(financeiro.vendas),
                resultado: _valor(financeiro.competencia.resultadoGerencial),
                resultadoNegativo:
                    financeiro.competencia.resultadoGerencial < 0,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KpiCard(
                    titulo: 'Vendas líquidas',
                    valor: _valor(financeiro.vendas),
                    detalhe: '${financeiro.quantidadeOrdens} OS finalizadas',
                    icon: Icons.receipt_long_outlined,
                  ),
                  _KpiCard(
                    titulo: 'Recebido',
                    valor: _valor(financeiro.recebido),
                    detalhe: 'Recebimentos das OS do período',
                    icon: Icons.payments_outlined,
                  ),
                  _KpiCard(
                    titulo: 'A receber',
                    valor: _valor(financeiro.aReceber),
                    detalhe: 'Saldo pendente das OS do período',
                    icon: Icons.schedule_rounded,
                    alerta: financeiro.aReceber > 0,
                  ),
                  _KpiCard(
                    titulo: 'Ticket médio',
                    valor: _valor(financeiro.ticketMedio),
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
              const SizedBox(height: 30),
              const _SectionTitle(
                titulo: 'Acesso rápido',
                subtitulo:
                    'Entre direto nas áreas mais importantes da gestão.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickAction(
                    icon: Icons.grid_view_rounded,
                    titulo: 'Sistema completo',
                    detalhe: 'Clientes, agenda, OS, estoque, CRM e mais',
                    onTap: widget.onAbrirOperacao,
                  ),
                  _QuickAction(
                    icon: Icons.account_balance_wallet_outlined,
                    titulo: 'Contas e caixa',
                    detalhe: 'Saldos, extrato e conciliações',
                    onTap: widget.onAbrirContas,
                  ),
                  _QuickAction(
                    icon: Icons.query_stats_rounded,
                    titulo: 'DRE',
                    detalhe: 'Competência e caixa',
                    onTap: widget.onAbrirDre,
                  ),
                  _QuickAction(
                    icon: Icons.analytics_outlined,
                    titulo: 'Relatórios',
                    detalhe: 'Vendas, executores e indicadores',
                    onTap: widget.onAbrirRelatorios,
                  ),
                  _QuickAction(
                    icon: Icons.badge_outlined,
                    titulo: 'Ponto e equipe',
                    detalhe: 'Funcionários, jornada e batidas',
                    onTap: widget.onAbrirPonto,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionTitle(
                titulo: 'Saldos por conta',
                subtitulo:
                    'Contas ativas usando o snapshot financeiro oficial.',
              ),
              const SizedBox(height: 12),
              if (contas.isEmpty)
                const _EstadoVazio('Nenhuma conta financeira ativa encontrada.')
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final conta in contas)
                      _ContaCard(
                        nome: conta.nome,
                        detalhe: [
                          conta.instituicao,
                          conta.tipo,
                        ].where((e) => e.trim().isNotEmpty).join(' · '),
                        saldo: _valor(conta.saldoAtual),
                      ),
                  ],
                ),
              const SizedBox(height: 30),
              const _SectionTitle(
                titulo: 'Desempenho da equipe',
                subtitulo:
                    'Ranking comercial das OS sem expor salário ou custo interno.',
              ),
              const SizedBox(height: 12),
              if (financeiro.executores.isEmpty)
                const _EstadoVazio('Nenhum executor encontrado no mês atual.')
              else
                ...financeiro.executores.take(5).map(
                      (item) => _ExecutorLinha(
                        item: item,
                        valorVendas: _valor(item.vendas),
                        valorRecebido: _valor(item.recebido),
                      ),
                    ),
            ],
          ),
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

class _CabecalhoPainel extends StatelessWidget {
  const _CabecalhoPainel({
    required this.compacto,
    required this.ocultarValores,
    required this.onAlternarValores,
    required this.onAtualizar,
  });

  final bool compacto;
  final bool ocultarValores;
  final VoidCallback onAlternarValores;
  final VoidCallback? onAtualizar;

  @override
  Widget build(BuildContext context) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visão geral',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Resumo em tempo real da operação e do financeiro.',
          style: TextStyle(color: Color(0xFFAAB3BD)),
        ),
      ],
    );

    final acoes = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: ocultarValores ? 'Mostrar valores' : 'Ocultar valores',
          onPressed: onAlternarValores,
          icon: Icon(
            ocultarValores
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Atualizar painel',
          onPressed: onAtualizar,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );

    if (compacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titulo,
          const SizedBox(height: 12),
          acoes,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titulo),
        acoes,
      ],
    );
  }
}

class _HeroGestao extends StatelessWidget {
  const _HeroGestao({
    required this.saldo,
    required this.faturamento,
    required this.resultado,
    required this.resultadoNegativo,
  });

  final String saldo;
  final String faturamento;
  final String resultado;
  final bool resultadoNegativo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ImperiumWebTheme.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ImperiumWebTheme.surfaceRaised,
            ImperiumWebTheme.accentStrong.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Wrap(
        spacing: 38,
        runSpacing: 22,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 390,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo consolidado',
                  style: TextStyle(
                    color: Color(0xFFAAB3BD),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  saldo,
                  style: const TextStyle(
                    fontSize: 36,
                    height: 1.05,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Soma das contas financeiras ativas',
                  style: TextStyle(color: Color(0xFFAAB3BD)),
                ),
              ],
            ),
          ),
          _HeroMini(
            titulo: 'Vendas no mês',
            valor: faturamento,
            icon: Icons.trending_up_rounded,
          ),
          _HeroMini(
            titulo: 'Resultado gerencial',
            valor: resultado,
            icon: Icons.monitoring_outlined,
            alerta: resultadoNegativo,
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
      width: 220,
      child: Row(
        children: [
          Icon(icon, color: cor),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
                const SizedBox(height: 4),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cor),
              const SizedBox(height: 13),
              Text(titulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
              const SizedBox(height: 4),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
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
      width: 300,
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
                  width: 46,
                  height: 46,
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
                      Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detalhe,
                        style: const TextStyle(
                          color: Color(0xFFAAB3BD),
                          fontSize: 12,
                        ),
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

class _ContaCard extends StatelessWidget {
  const _ContaCard({
    required this.nome,
    required this.detalhe,
    required this.saldo,
  });

  final String nome;
  final String detalhe;
  final String saldo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(17),
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
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                saldo,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detalhe,
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
    );
  }
}

class _ExecutorLinha extends StatelessWidget {
  const _ExecutorLinha({
    required this.item,
    required this.valorVendas,
    required this.valorRecebido,
  });

  final WebRelatoriosExecutor item;
  final String valorVendas;
  final String valorRecebido;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(
          item.nome,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${item.quantidade} OS · $valorRecebido recebido'),
        trailing: Text(
          valorVendas,
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
        Text(
          titulo,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ImperiumWebTheme.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(texto, style: const TextStyle(color: Color(0xFFAAB3BD))),
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 14),
              const Text(
                'Não foi possível carregar o painel',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
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
    );
  }
}
