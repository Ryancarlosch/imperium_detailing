import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_dashboard_service.dart';
import '../services/web_cloud_relatorios_service.dart';
import 'imperium_web_theme.dart';
import 'web_contas_financeiras_page.dart';
import 'web_dre_page.dart';
import 'web_ponto_page.dart';
import 'web_relatorios_page.dart';

class WebDashboardGerencialPage extends StatefulWidget {
  const WebDashboardGerencialPage({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  State<WebDashboardGerencialPage> createState() =>
      _WebDashboardGerencialPageState();
}

class _WebDashboardGerencialPageState extends State<WebDashboardGerencialPage> {
  final _service = WebCloudDashboardService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _hora = DateFormat('HH:mm');

  WebDashboardGerencialResumo? _resumo;
  bool _carregando = true;
  bool _ocultarValores = false;
  DateTime? _ultimaAtualizacao;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resumo = await _service.carregar();
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _ultimaAtualizacao = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _valor(double valor) =>
      _ocultarValores ? 'R\$ ••••••' : _moeda.format(valor);

  Future<void> _abrirModulo(String titulo, Widget pagina) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: titulo),
        builder: (context) => pagina,
      ),
    );
    if (mounted) await _carregar();
  }

  Future<void> _irParaModulo(int indice, String titulo, Widget fallback) async {
    final onNavigate = widget.onNavigate;
    if (onNavigate != null) {
      onNavigate(indice);
      return;
    }
    await _abrirModulo(titulo, fallback);
  }

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
    final comercial = resumo.comercial;
    final contas = resumo.contas.take(4).toList();
    final executores = financeiro.executores.take(5).toList();
    final agendaHoje = resumo.agendaHoje.take(6).toList();
    final ordensAbertas = resumo.ordensAbertas.take(6).toList();
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 760;
    final paddingHorizontal = compacto ? 16.0 : 28.0;
    final disponivel = largura - (paddingHorizontal * 2);
    final colunasKpi = disponivel >= 1180
        ? 4
        : disponivel >= 680
        ? 2
        : 1;
    final larguraKpi = (disponivel - (12 * (colunasKpi - 1))) / colunasKpi;
    final colunasAcoes = disponivel >= 980
        ? 4
        : disponivel >= 620
        ? 2
        : 1;
    final larguraAcao = (disponivel - (12 * (colunasAcoes - 1))) / colunasAcoes;
    final maiorVendaEquipe = executores.isEmpty ? 0.0 : executores.first.vendas;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              paddingHorizontal,
              compacto ? 16 : 24,
              paddingHorizontal,
              44,
            ),
            children: [
              _CabecalhoPainel(
                compacto: compacto,
                ultimaAtualizacao: _ultimaAtualizacao == null
                    ? null
                    : _hora.format(_ultimaAtualizacao!),
                ocultarValores: _ocultarValores,
                onAlternarValores: () =>
                    setState(() => _ocultarValores = !_ocultarValores),
                onAtualizar: _carregando ? null : _carregar,
              ),
              const SizedBox(height: 18),
              _HeroGestao(
                saldo: _valor(resumo.saldoConsolidado),
                faturamento: _valor(financeiro.vendas),
                resultado: _valor(financeiro.competencia.resultadoGerencial),
                aReceber: _valor(financeiro.aReceber),
                resultadoNegativo:
                    financeiro.competencia.resultadoGerencial < 0,
              ),
              const SizedBox(height: 24),
              const _SectionTitle(
                titulo: 'Indicadores do mês',
                subtitulo:
                    'Leitura rápida da operação, vendas e recebimentos do período atual.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Vendas líquidas',
                    valor: _valor(financeiro.vendas),
                    detalhe: '${financeiro.quantidadeOrdens} OS finalizadas',
                    icon: Icons.receipt_long_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Recebido',
                    valor: _valor(financeiro.recebido),
                    detalhe: 'Recebimentos registrados nas OS do período',
                    icon: Icons.payments_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'A receber',
                    valor: _valor(financeiro.aReceber),
                    detalhe: 'Saldo pendente das OS do período',
                    icon: Icons.schedule_rounded,
                    alerta: financeiro.aReceber > 0,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Ticket médio',
                    valor: _valor(financeiro.ticketMedio),
                    detalhe: 'Valor líquido médio por OS',
                    icon: Icons.shopping_bag_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'OS abertas',
                    valor: '${operacional['os_abertas'] ?? 0}',
                    detalhe: 'Ordens abertas ou em andamento',
                    icon: Icons.car_repair_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Agenda aberta',
                    valor: '${operacional['agenda'] ?? 0}',
                    detalhe: 'Agendamentos ainda ativos',
                    icon: Icons.calendar_month_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Clientes ativos',
                    valor: '${operacional['clientes'] ?? 0}',
                    detalhe: 'Clientes disponíveis na operação',
                    icon: Icons.people_outline_rounded,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Veículos',
                    valor: '${operacional['veiculos'] ?? 0}',
                    detalhe: 'Veículos cadastrados na empresa',
                    icon: Icons.directions_car_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _SectionTitle(
                titulo: 'Comercial e retenção',
                subtitulo:
                    'CRM, pós-venda e marketing usando os mesmos dados Cloud do restante da plataforma.',
                trailing: compacto
                    ? null
                    : Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => widget.onNavigate?.call(13),
                            child: const Text('CRM'),
                          ),
                          TextButton(
                            onPressed: () => widget.onNavigate?.call(18),
                            child: const Text('Pós-venda'),
                          ),
                          TextButton(
                            onPressed: () => widget.onNavigate?.call(19),
                            child: const Text('Marketing'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Leads abertos',
                    valor: '${comercial.leadsAbertos}',
                    detalhe: '${comercial.leadsGanhos} lead(s) marcado(s) como ganho',
                    icon: Icons.person_search_outlined,
                    alerta: comercial.leadsAbertos > 0,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Potencial do CRM',
                    valor: _valor(comercial.potencial),
                    detalhe: 'Soma das oportunidades ainda não perdidas',
                    icon: Icons.handshake_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Pós-venda pendente',
                    valor: '${comercial.posVendaAcoes}',
                    detalhe:
                        '${comercial.posVendaReativacao} cliente(s) em reativação',
                    icon: Icons.replay_circle_filled_outlined,
                    alerta: comercial.posVendaAcoes > 0,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Campanhas ativas',
                    valor: '${comercial.campanhasAtivas}',
                    detalhe: '${comercial.marketingLeads} lead(s) de marketing',
                    icon: Icons.campaign_outlined,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'Faturamento atribuído',
                    valor: _valor(comercial.marketingFaturamento),
                    detalhe: 'Receita de OS vinculadas às campanhas',
                    icon: Icons.trending_up_rounded,
                  ),
                  _KpiCard(
                    width: larguraKpi,
                    titulo: 'ROAS',
                    valor: comercial.marketingRoas <= 0
                        ? '—'
                        : '${comercial.marketingRoas.toStringAsFixed(2)}x',
                    detalhe: 'Retorno de receita sobre investimento em marketing',
                    icon: Icons.analytics_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionTitle(
                titulo: 'Acesso rápido',
                subtitulo:
                    'Abra as áreas gerenciais mais usadas sem sair do contexto do painel.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.add_business_outlined,
                    titulo: 'Nova OS',
                    detalhe: 'Abra uma nova ordem de serviço',
                    onTap: () => widget.onNavigate?.call(5),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.calendar_month_outlined,
                    titulo: 'Agenda',
                    detalhe: 'Compromissos e serviços programados',
                    onTap: () => widget.onNavigate?.call(3),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.receipt_long_outlined,
                    titulo: 'Ordens de serviço',
                    detalhe: 'Execução, valores e situação das OS',
                    onTap: () => widget.onNavigate?.call(4),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.inventory_2_outlined,
                    titulo: 'Estoque',
                    detalhe: 'Produtos, reservas e movimentações',
                    onTap: () => widget.onNavigate?.call(8),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.account_balance_wallet_outlined,
                    titulo: 'Contas e caixa',
                    detalhe: 'Saldos, extrato e movimentação financeira',
                    onTap: () => _irParaModulo(
                      11,
                      'Contas e caixa',
                      const WebContasFinanceirasPage(),
                    ),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.query_stats_rounded,
                    titulo: 'DRE gerencial',
                    detalhe: 'Resultado por competência e por caixa',
                    onTap: () =>
                        _irParaModulo(10, 'DRE gerencial', const WebDrePage()),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.analytics_outlined,
                    titulo: 'Relatórios',
                    detalhe: 'Vendas, executores e indicadores detalhados',
                    onTap: () => _irParaModulo(
                      12,
                      'Relatórios',
                      const WebRelatoriosPage(),
                    ),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.badge_outlined,
                    titulo: 'Ponto e equipe',
                    detalhe: 'Funcionários, jornada, batidas e ajustes',
                    onTap: () => _irParaModulo(
                      16,
                      'Ponto e equipe',
                      const WebPontoPage(),
                    ),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.handshake_outlined,
                    titulo: 'CRM',
                    detalhe: 'Leads, oportunidades e pipeline comercial',
                    onTap: () => widget.onNavigate?.call(13),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.replay_circle_filled_outlined,
                    titulo: 'Pós-venda',
                    detalhe: 'Retorno, reativação e histórico de contatos',
                    onTap: () => widget.onNavigate?.call(18),
                  ),
                  _QuickAction(
                    width: larguraAcao,
                    icon: Icons.campaign_outlined,
                    titulo: 'Marketing',
                    detalhe: 'Campanhas, conteúdo, atribuição e ROAS',
                    onTap: () => widget.onNavigate?.call(19),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionTitle(
                titulo: 'Operação de hoje',
                subtitulo:
                    'Agenda do dia e veículos que ainda estão em execução.',
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final ladoALado = constraints.maxWidth >= 980;
                  final larguraPainel = ladoALado
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;

                  final agendaCard = SizedBox(
                    width: larguraPainel,
                    child: _AgendaHojePainel(
                      itens: agendaHoje,
                      valor: _valor,
                      onVerTodos: () => widget.onNavigate?.call(3),
                    ),
                  );
                  final ordensCard = SizedBox(
                    width: larguraPainel,
                    child: _OrdensAbertasPainel(
                      itens: ordensAbertas,
                      valor: _valor,
                      onVerTodos: () => widget.onNavigate?.call(4),
                    ),
                  );

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [agendaCard, ordensCard],
                  );
                },
              ),
              const SizedBox(height: 30),
              _SectionTitle(
                titulo: 'Saldos por conta',
                subtitulo:
                    'Contas ativas usando o snapshot financeiro oficial.',
                trailing: TextButton.icon(
                  onPressed: () => _irParaModulo(
                    11,
                    'Contas e caixa',
                    const WebContasFinanceirasPage(),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Ver contas'),
                ),
              ),
              const SizedBox(height: 12),
              if (contas.isEmpty)
                const _EstadoVazio('Nenhuma conta financeira ativa encontrada.')
              else ...[
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
                if (resumo.contas.length > contas.length) ...[
                  const SizedBox(height: 10),
                  Text(
                    '+ ${resumo.contas.length - contas.length} conta(s) disponível(is) em Contas e caixa',
                    style: const TextStyle(
                      color: Color(0xFF89939E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 30),
              _SectionTitle(
                titulo: 'Desempenho da equipe',
                subtitulo:
                    'Ranking comercial das OS sem expor salário ou custo interno.',
                trailing: TextButton.icon(
                  onPressed: () => _irParaModulo(
                    12,
                    'Relatórios',
                    const WebRelatoriosPage(),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Ver relatório'),
                ),
              ),
              const SizedBox(height: 12),
              if (executores.isEmpty)
                const _EstadoVazio('Nenhum executor encontrado no mês atual.')
              else
                ...List.generate(executores.length, (index) {
                  final item = executores[index];
                  final progresso = maiorVendaEquipe <= 0
                      ? 0.0
                      : (item.vendas / maiorVendaEquipe)
                            .clamp(0.0, 1.0)
                            .toDouble();
                  return _ExecutorLinha(
                    posicao: index + 1,
                    progresso: progresso,
                    item: item,
                    valorVendas: _valor(item.vendas),
                    valorRecebido: _valor(item.recebido),
                  );
                }),
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

class _AgendaHojePainel extends StatelessWidget {
  const _AgendaHojePainel({
    required this.itens,
    required this.valor,
    required this.onVerTodos,
  });

  final List<Map<String, dynamic>> itens;
  final String Function(double) valor;
  final VoidCallback onVerTodos;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Agenda de hoje',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: onVerTodos,
                  child: const Text('Ver agenda'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (itens.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'Nenhum agendamento aberto para hoje.',
                    style: TextStyle(color: Color(0xFF89939E)),
                  ),
                ),
              )
            else
              ...itens.map((item) {
                final numero = item['valor'];
                final valorPrevisto = numero is num ? numero.toDouble() : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          (item['hora'] ?? '—').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (item['servico'] ?? 'Serviço').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                (item['_cliente_nome'] ?? '').toString(),
                                (item['_veiculo_nome'] ?? '').toString(),
                              ].where((e) => e.trim().isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF89939E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (valorPrevisto > 0) ...[
                        const SizedBox(width: 10),
                        Text(
                          valor(valorPrevisto),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _OrdensAbertasPainel extends StatelessWidget {
  const _OrdensAbertasPainel({
    required this.itens,
    required this.valor,
    required this.onVerTodos,
  });

  final List<Map<String, dynamic>> itens;
  final String Function(double) valor;
  final VoidCallback onVerTodos;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'OS em aberto',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: onVerTodos,
                  child: const Text('Ver ordens'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (itens.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'Nenhuma ordem aberta ou em andamento.',
                    style: TextStyle(color: Color(0xFF89939E)),
                  ),
                ),
              )
            else
              ...itens.map((item) {
                final bruto = item['_valor_negociado'];
                final negociado = bruto is num ? bruto.toDouble() : 0.0;
                final status = (item['status'] ?? 'Aberta').toString();

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        child: Icon(
                          status == 'Em andamento'
                              ? Icons.pending_actions_outlined
                              : Icons.edit_note_outlined,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OS ${item['numero'] ?? ''} · '
                              '${item['_cliente_nome'] ?? 'Cliente'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                (item['_veiculo_nome'] ?? '').toString(),
                                status,
                                (item['funcionario_responsavel'] ?? '')
                                    .toString(),
                              ].where((e) => e.trim().isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF89939E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (negociado > 0) ...[
                        const SizedBox(width: 10),
                        Text(
                          valor(negociado),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CabecalhoPainel extends StatelessWidget {
  const _CabecalhoPainel({
    required this.compacto,
    required this.ultimaAtualizacao,
    required this.ocultarValores,
    required this.onAlternarValores,
    required this.onAtualizar,
  });

  final bool compacto;
  final String? ultimaAtualizacao;
  final bool ocultarValores;
  final VoidCallback onAlternarValores;
  final VoidCallback? onAtualizar;

  @override
  Widget build(BuildContext context) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard executivo',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Caixa, vendas, operação e equipe em uma visão gerencial.',
          style: TextStyle(color: Color(0xFFAAB3BD)),
        ),
        if (ultimaAtualizacao != null) ...[
          const SizedBox(height: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_done_outlined,
                size: 15,
                color: Color(0xFF7FC8A9),
              ),
              const SizedBox(width: 6),
              Text(
                'Atualizado às $ultimaAtualizacao',
                style: const TextStyle(color: Color(0xFF89939E), fontSize: 12),
              ),
            ],
          ),
        ],
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
        children: [titulo, const SizedBox(height: 12), acoes],
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
    required this.aReceber,
    required this.resultadoNegativo,
  });

  final String saldo;
  final String faturamento;
  final String resultado;
  final String aReceber;
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
            ImperiumWebTheme.accentStrong.withValues(alpha: 0.13),
          ],
        ),
      ),
      child: Wrap(
        spacing: 34,
        runSpacing: 22,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: ImperiumWebTheme.accentStrong.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                        color: ImperiumWebTheme.accentStrong,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Saldo consolidado',
                      style: TextStyle(
                        color: Color(0xFFAAB3BD),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
            icon: Icons.insights_outlined,
            alerta: resultadoNegativo,
          ),
          _HeroMini(
            titulo: 'A receber',
            valor: aReceber,
            icon: Icons.schedule_rounded,
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
      width: 205,
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
    required this.width,
    required this.titulo,
    required this.valor,
    required this.detalhe,
    required this.icon,
    this.alerta = false,
  });

  final double width;
  final String titulo;
  final String valor;
  final String detalhe;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : ImperiumWebTheme.accentStrong;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cor, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(color: Color(0xFFAAB3BD)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detalhe,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
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
    required this.width,
    required this.icon,
    required this.titulo,
    required this.detalhe,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String titulo;
  final String detalhe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ImperiumWebTheme.accentStrong.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    color: ImperiumWebTheme.accentStrong,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detalhe,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: Color(0xFF89939E),
                ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                style: const TextStyle(color: Color(0xFFAAB3BD), fontSize: 12),
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
    required this.posicao,
    required this.progresso,
    required this.item,
    required this.valorVendas,
    required this.valorRecebido,
  });

  final int posicao;
  final double progresso;
  final WebRelatoriosExecutor item;
  final String valorVendas;
  final String valorRecebido;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: ImperiumWebTheme.accentStrong.withValues(
                alpha: 0.10,
              ),
              child: Text(
                '$posicaoº',
                style: const TextStyle(
                  color: ImperiumWebTheme.accentStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        valorVendas,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.quantidade} OS · $valorRecebido recebido',
                    style: const TextStyle(
                      color: Color(0xFFAAB3BD),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progresso,
                      minHeight: 5,
                      backgroundColor: ImperiumWebTheme.border,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.titulo,
    required this.subtitulo,
    this.trailing,
  });

  final String titulo;
  final String subtitulo;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
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
      width: double.infinity,
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
