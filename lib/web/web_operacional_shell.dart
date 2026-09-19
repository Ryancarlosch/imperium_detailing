import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';
import '../screens/imperium_planos_page.dart';
import '../screens/licenca_status_page.dart';
import '../services/web_cloud_operacional_service.dart';
import 'imperium_web_theme.dart';
import 'web_contas_financeiras_page.dart';
import 'web_dashboard_gerencial_page.dart';
import 'web_dre_page.dart';
import 'web_expansao_pages.dart';
import 'web_financeiro_lancamentos_page.dart';
import 'web_gestao_pages.dart';
import 'web_marketing_page.dart';
import 'web_ordens_v3_page.dart';
import 'web_estoque_gestao_page.dart';
import 'web_os_arquivos_page.dart';
import 'web_os_finalizacao_v4_page.dart';
import 'web_ponto_page.dart';
import 'web_pos_venda_page.dart';
import 'web_relatorios_page.dart';

class WebOperacionalShell extends StatefulWidget {
  const WebOperacionalShell({
    super.key,
    required this.usuarioEmail,
    required this.empresas,
    required this.empresaAtualId,
    required this.onTrocarEmpresa,
    required this.onSair,
  });

  final String usuarioEmail;
  final List<Map<String, dynamic>> empresas;
  final String empresaAtualId;
  final Future<void> Function(String empresaId) onTrocarEmpresa;
  final Future<void> Function() onSair;

  @override
  State<WebOperacionalShell> createState() => _WebOperacionalShellState();
}

class _WebOperacionalShellState extends State<WebOperacionalShell> {
  final _service = WebCloudOperacionalService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const String _empresaImperiumId =
      'dbbf4114-06fa-46b8-a2f6-50b3f3ead436';

  int _indice = 0;
  int _revisao = 0;

  bool get _empresaImperium => widget.empresaAtualId == _empresaImperiumId;

  String get _nomeEmpresaAtual {
    for (final empresa in widget.empresas) {
      if ('${empresa['empresa_id']}' == widget.empresaAtualId) {
        final nome = (empresa['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Empresa';
  }

  Future<void> _abrirPlano() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LicencaStatusPage(empresaId: widget.empresaAtualId),
      ),
    );
  }

  Future<void> _abrirGerenciarPlanos() async {
    if (!_empresaImperium) return;

    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ImperiumPlanosPage()));
  }

  String get _tituloAtual => switch (_indice) {
    0 => 'Dashboard',
    1 => 'Clientes',
    2 => 'Veículos',
    3 => 'Agenda',
    4 => 'Ordens de serviço',
    5 => 'Nova OS',
    6 => 'Editar OS',
    7 => 'Finalizar OS',
    8 => 'Estoque',
    9 => 'Fluxo de caixa',
    10 => 'DRE',
    11 => 'Contas bancárias',
    12 => 'Relatórios',
    13 => 'CRM',
    14 => 'Orçamentos',
    15 => 'Precificação',
    16 => 'Ponto e funcionários',
    18 => 'Pós-venda',
    19 => 'Marketing',
    _ => 'Central Cloud',
  };

  void _atualizar() => setState(() => _revisao++);

  Widget? _paginaRoteada(int indice) => switch (indice) {
    10 => WebDrePage(key: ValueKey('dre-rota-$_revisao')),
    11 => WebContasFinanceirasPage(key: ValueKey('contas-rota-$_revisao')),
    12 => WebRelatoriosPage(key: ValueKey('relatorios-rota-$_revisao')),
    16 => WebPontoPage(key: ValueKey('ponto-rota-$_revisao')),
    _ => null,
  };

  void _selecionar(int indice, {bool fecharMenu = true}) {
    if (fecharMenu && _scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }

    final paginaRoteada = _paginaRoteada(indice);
    if (paginaRoteada != null) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => paginaRoteada)).then((_) {
        if (mounted) _atualizar();
      });
      return;
    }

    setState(() => _indice = indice);
  }

  Widget _pagina() {
    return switch (_indice) {
      0 => WebDashboardGerencialPage(
        key: ValueKey('dashboard-premium-${widget.empresaAtualId}-$_revisao'),
      ),
      1 => _ClientesPage(
        key: ValueKey('clientes-$_revisao'),
        service: _service,
        onChanged: _atualizar,
      ),
      2 => _VeiculosPage(
        key: ValueKey('veiculos-$_revisao'),
        service: _service,
        onChanged: _atualizar,
      ),
      3 => _AgendaPage(
        key: ValueKey('agenda-$_revisao'),
        service: _service,
        moeda: _moeda,
        onChanged: _atualizar,
      ),
      4 => _OrdensPage(
        key: ValueKey('os-$_revisao'),
        service: _service,
        moeda: _moeda,
        onNavigate: (indice) => _selecionar(indice, fecharMenu: false),
      ),
      5 => WebNovaOrdemPage(
        key: ValueKey('nova-os-$_revisao'),
        onCreated: _atualizar,
      ),
      6 => WebOrdensV3Page(key: ValueKey('editar-os-$_revisao')),
      7 => WebOsFinalizacaoV4Page(key: ValueKey('finalizar-os-$_revisao')),
      8 => WebEstoqueGestaoPage(key: ValueKey('estoque-$_revisao')),
      9 => WebFinanceiroLancamentosPage(key: ValueKey('financeiro-$_revisao')),
      10 => WebDrePage(key: ValueKey('dre-$_revisao')),
      11 => WebContasFinanceirasPage(key: ValueKey('contas-$_revisao')),
      12 => WebRelatoriosPage(key: ValueKey('relatorios-$_revisao')),
      13 => WebCrmPage(key: ValueKey('crm-$_revisao')),
      14 => WebOrcamentosPage(key: ValueKey('orcamentos-$_revisao')),
      15 => WebPrecificacaoPage(key: ValueKey('precificacao-$_revisao')),
      16 => WebPontoPage(key: ValueKey('ponto-$_revisao')),
      18 => WebPosVendaPage(key: ValueKey('pos-venda-$_revisao')),
      19 => WebMarketingPage(key: ValueKey('marketing-$_revisao')),
      _ => WebCentralCloudPage(key: ValueKey('central-$_revisao')),
    };
  }

  Widget _itemMenu({
    required int indice,
    required String titulo,
    required IconData icone,
  }) {
    final selecionado = _indice == indice;
    return ListTile(
      selected: selecionado,
      selectedTileColor: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
      selectedColor: ImperiumWebTheme.accentStrong,
      leading: Icon(icone, size: 21),
      title: Text(
        titulo,
        style: TextStyle(
          fontWeight: selecionado ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => _selecionar(indice),
    );
  }

  Widget _grupoMenu({
    required String titulo,
    required IconData icone,
    required List<Widget> filhos,
    required Set<int> indices,
  }) {
    return ExpansionTile(
      key: ValueKey('$titulo-${indices.contains(_indice)}'),
      initiallyExpanded: indices.contains(_indice),
      leading: Icon(icone, size: 21),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
      childrenPadding: const EdgeInsets.only(left: 14, right: 8, bottom: 6),
      children: filhos,
    );
  }

  Widget _menu() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
      children: [
        _itemMenu(
          indice: 0,
          titulo: 'Dashboard',
          icone: Icons.dashboard_outlined,
        ),
        const SizedBox(height: 4),
        _grupoMenu(
          titulo: 'Operação',
          icone: Icons.car_repair_outlined,
          indices: const {1, 2, 3, 4, 5, 6, 7},
          filhos: [
            _itemMenu(
              indice: 1,
              titulo: 'Clientes',
              icone: Icons.people_outline,
            ),
            _itemMenu(
              indice: 2,
              titulo: 'Veículos',
              icone: Icons.directions_car_outlined,
            ),
            _itemMenu(
              indice: 3,
              titulo: 'Agenda',
              icone: Icons.calendar_month_outlined,
            ),
            _itemMenu(
              indice: 4,
              titulo: 'Ordens de serviço',
              icone: Icons.receipt_long_outlined,
            ),
            _itemMenu(
              indice: 5,
              titulo: 'Nova OS',
              icone: Icons.add_business_outlined,
            ),
            _itemMenu(
              indice: 6,
              titulo: 'Editar OS',
              icone: Icons.edit_note_outlined,
            ),
            _itemMenu(
              indice: 7,
              titulo: 'Finalizar OS',
              icone: Icons.task_alt_outlined,
            ),
          ],
        ),
        _grupoMenu(
          titulo: 'Financeiro',
          icone: Icons.account_balance_wallet_outlined,
          indices: const {9, 10, 11, 12},
          filhos: [
            _itemMenu(
              indice: 9,
              titulo: 'Fluxo de caixa',
              icone: Icons.swap_vert_circle_outlined,
            ),
            _itemMenu(
              indice: 10,
              titulo: 'DRE',
              icone: Icons.query_stats_rounded,
            ),
            _itemMenu(
              indice: 11,
              titulo: 'Contas bancárias',
              icone: Icons.account_balance_outlined,
            ),
            _itemMenu(
              indice: 12,
              titulo: 'Relatórios',
              icone: Icons.analytics_outlined,
            ),
          ],
        ),
        _itemMenu(
          indice: 8,
          titulo: 'Estoque',
          icone: Icons.inventory_2_outlined,
        ),
        _grupoMenu(
          titulo: 'Comercial',
          icone: Icons.storefront_outlined,
          indices: const {13, 14, 15, 18, 19},
          filhos: [
            _itemMenu(indice: 13, titulo: 'CRM', icone: Icons.hub_outlined),
            _itemMenu(
              indice: 18,
              titulo: 'Pós-venda',
              icone: Icons.replay_circle_filled_outlined,
            ),
            _itemMenu(
              indice: 19,
              titulo: 'Marketing',
              icone: Icons.campaign_outlined,
            ),
            _itemMenu(
              indice: 14,
              titulo: 'Orçamentos',
              icone: Icons.request_quote_outlined,
            ),
            _itemMenu(
              indice: 15,
              titulo: 'Precificação',
              icone: Icons.price_change_outlined,
            ),
          ],
        ),
        _grupoMenu(
          titulo: 'Equipe',
          icone: Icons.groups_2_outlined,
          indices: const {16},
          filhos: [
            _itemMenu(
              indice: 16,
              titulo: 'Ponto e funcionários',
              icone: Icons.badge_outlined,
            ),
          ],
        ),
        _grupoMenu(
          titulo: 'Administração',
          icone: Icons.admin_panel_settings_outlined,
          indices: const {17},
          filhos: [
            _itemMenu(
              indice: 17,
              titulo: 'Central Cloud',
              icone: Icons.cloud_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _conteudoMenuLateral() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_mosaic_outlined,
                  color: ImperiumWebTheme.accentStrong,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Imperium Manager',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _nomeEmpresaAtual,
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
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _menu()),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: ListTile(
            leading: const CircleAvatar(
              radius: 17,
              child: Icon(Icons.person_outline_rounded, size: 18),
            ),
            title: const Text(
              'Conta',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              widget.usuarioEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Sair',
              onPressed: widget.onSair,
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 760;
    final desktop = largura >= 1180;

    return Scaffold(
      key: _scaffoldKey,
      drawer: desktop
          ? null
          : Drawer(
              width: compacto ? 310 : 340,
              child: SafeArea(child: _conteudoMenuLateral()),
            ),
      appBar: AppBar(
        toolbarHeight: compacto ? 62 : 68,
        automaticallyImplyLeading: false,
        leading: desktop
            ? null
            : Builder(
                builder: (context) => IconButton(
                  tooltip: 'Abrir menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
        titleSpacing: desktop ? 24 : 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              desktop
                  ? _tituloAtual
                  : compacto
                  ? _tituloAtual
                  : 'Imperium Manager · $_tituloAtual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            if (!compacto)
              Text(
                _nomeEmpresaAtual,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFAAB3BD),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (Navigator.canPop(context))
            IconButton(
              tooltip: 'Voltar ao painel',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.dashboard_outlined),
            ),
          IconButton(
            tooltip: 'Atualizar página',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Trocar empresa',
            onSelected: widget.onTrocarEmpresa,
            itemBuilder: (context) => widget.empresas
                .map(
                  (empresa) => PopupMenuItem<String>(
                    value: (empresa['empresa_id'] ?? '').toString(),
                    child: Row(
                      children: [
                        if ('${empresa['empresa_id']}' ==
                            widget.empresaAtualId) ...[
                          const Icon(Icons.check_rounded, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            (empresa['nome'] ?? 'Empresa').toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.business_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: widget.usuarioEmail,
            onSelected: (valor) async {
              if (valor == 'plano') {
                await _abrirPlano();
              } else if (valor == 'planos_admin') {
                await _abrirGerenciarPlanos();
              } else if (valor == 'sair') {
                await widget.onSair();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'email',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Conta conectada',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.usuarioEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'plano',
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Plano e assinatura'),
                  ],
                ),
              ),
              if (_empresaImperium)
                const PopupMenuItem<String>(
                  value: 'planos_admin',
                  child: Row(
                    children: [
                      Icon(Icons.sell_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Gerenciar planos'),
                    ],
                  ),
                ),
              const PopupMenuItem<String>(
                value: 'sair',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Sair'),
                  ],
                ),
              ),
            ],
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person_outline_rounded, size: 18),
            ),
          ),
          SizedBox(width: compacto ? 4 : 12),
        ],
      ),
      body: desktop
          ? Row(
              children: [
                Container(
                  width: 300,
                  decoration: const BoxDecoration(
                    color: ImperiumWebTheme.surface,
                    border: Border(
                      right: BorderSide(color: ImperiumWebTheme.border),
                    ),
                  ),
                  child: _conteudoMenuLateral(),
                ),
                Expanded(child: _pagina()),
              ],
            )
          : _pagina(),
    );
  }
}

class _ClientesPage extends StatefulWidget {
  const _ClientesPage({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final WebCloudOperacionalService service;
  final VoidCallback onChanged;

  @override
  State<_ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<_ClientesPage> {
  final busca = TextEditingController();
  bool _mostrarArquivados = false;

  @override
  void dispose() {
    busca.dispose();
    super.dispose();
  }

  Future<void> _editar(Map<String, dynamic>? atual) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final telefone = TextEditingController(text: '${atual?['telefone'] ?? ''}');
    final email = TextEditingController(text: '${atual?['email'] ?? ''}');
    final endereco = TextEditingController(text: '${atual?['endereco'] ?? ''}');
    final obs = TextEditingController(text: '${atual?['observacoes'] ?? ''}');

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(atual == null ? 'Novo cliente' : 'Editar cliente'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nome,
                  autofocus: atual == null,
                  decoration: const InputDecoration(
                    labelText: 'Nome *',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: telefone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: endereco,
                  decoration: const InputDecoration(
                    labelText: 'Endereço',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: obs,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, nome.text.trim().isNotEmpty),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Salvar cliente'),
          ),
        ],
      ),
    );

    if (salvar != true) return;

    await widget.service.salvarCliente(
      id: atual?['id']?.toString(),
      nome: nome.text,
      telefone: telefone.text,
      email: email.text,
      endereco: endereco.text,
      observacoes: obs.text,
      ativo: atual?['ativo'] != false,
    );
    widget.onChanged();
  }

  Future<void> _alternarArquivo(Map<String, dynamic> cliente) async {
    final ativo = cliente['ativo'] != false;
    await widget.service.arquivarCliente(cliente['id'].toString(), ativo);
    widget.onChanged();
  }

  Widget _acoesCliente(Map<String, dynamic> cliente) {
    final ativo = cliente['ativo'] != false;
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Editar cliente',
          onPressed: () => _editar(cliente),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: ativo ? 'Arquivar cliente' : 'Reativar cliente',
          onPressed: () => _alternarArquivo(cliente),
          icon: Icon(ativo ? Icons.archive_outlined : Icons.unarchive_outlined),
        ),
      ],
    );
  }

  Widget _resumoCard({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icon,
    bool destaque = false,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: destaque
                      ? ImperiumWebTheme.accentStrong.withValues(alpha: 0.13)
                      : ImperiumWebTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ImperiumWebTheme.border),
                ),
                child: Icon(
                  icon,
                  color: destaque
                      ? ImperiumWebTheme.accentStrong
                      : const Color(0xFFB7C0CA),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
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

  Widget _tabelaClientes(List<Map<String, dynamic>> itens) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('CLIENTE')),
            DataColumn(label: Text('TELEFONE')),
            DataColumn(label: Text('E-MAIL')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('AÇÕES')),
          ],
          rows: itens.map((cliente) {
            final ativo = cliente['ativo'] != false;
            final nome = (cliente['nome'] ?? '').toString().trim();
            final telefone = (cliente['telefone'] ?? '').toString().trim();
            final email = (cliente['email'] ?? '').toString().trim();

            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 260,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: ImperiumWebTheme.accentStrong
                              .withValues(alpha: 0.10),
                          child: Text(
                            nome.isEmpty ? '?' : nome[0].toUpperCase(),
                            style: const TextStyle(
                              color: ImperiumWebTheme.accentStrong,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nome.isEmpty ? 'Cliente sem nome' : nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(telefone.isEmpty ? '—' : telefone),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 230,
                    child: Text(
                      email.isEmpty ? '—' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Chip(
                    avatar: Icon(
                      ativo
                          ? Icons.check_circle_outline
                          : Icons.archive_outlined,
                      size: 16,
                    ),
                    label: Text(ativo ? 'Ativo' : 'Arquivado'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                DataCell(_acoesCliente(cliente)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _cardsClientes(List<Map<String, dynamic>> itens) {
    return Column(
      children: [
        for (final cliente in itens) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: ImperiumWebTheme.accentStrong.withValues(
                      alpha: 0.10,
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: ImperiumWebTheme.accentStrong,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (cliente['nome'] ?? 'Cliente').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            (cliente['telefone'] ?? '').toString(),
                            (cliente['email'] ?? '').toString(),
                            if (cliente['ativo'] == false) 'Arquivado',
                          ].where((e) => e.trim().isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAB3BD),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _acoesCliente(cliente),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.service.listarClientes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final todos = snapshot.data!;
        final ativos = todos.where((e) => e['ativo'] != false).length;
        final arquivados = todos.length - ativos;
        final comEmail = todos.where((e) {
          return (e['email'] ?? '').toString().trim().isNotEmpty;
        }).length;

        final termo = busca.text.trim().toLowerCase();
        final itens =
            todos.where((e) {
              final ativo = e['ativo'] != false;
              if (!_mostrarArquivados && !ativo) return false;
              if (termo.isEmpty) return true;

              return [
                'nome',
                'telefone',
                'email',
                'endereco',
              ].any((k) => '${e[k] ?? ''}'.toLowerCase().contains(termo));
            }).toList()..sort(
              (a, b) => (a['nome'] ?? '').toString().toLowerCase().compareTo(
                (b['nome'] ?? '').toString().toLowerCase(),
              ),
            );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 760;
            final tabela = constraints.maxWidth >= 900;
            final conteudo = constraints.maxWidth - (compacto ? 32 : 48);
            final colunasResumo = constraints.maxWidth >= 1080
                ? 3
                : constraints.maxWidth >= 640
                ? 2
                : 1;
            final larguraResumo =
                (conteudo - (12 * (colunasResumo - 1))) / colunasResumo;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                compacto ? 16 : 24,
                compacto ? 18 : 24,
                compacto ? 16 : 24,
                40,
              ),
              children: [
                if (compacto) ...[
                  const Text(
                    'Clientes',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cadastros, contatos e situação da carteira.',
                    style: TextStyle(color: Color(0xFFAAB3BD)),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _editar(null),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Novo cliente'),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clientes',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Visão geral da carteira, contatos e situação dos cadastros.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      FilledButton.icon(
                        onPressed: () => _editar(null),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Novo cliente'),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _resumoCard(
                      width: larguraResumo,
                      titulo: 'Clientes ativos',
                      valor: '$ativos',
                      detalhe: 'Cadastros disponíveis para operação',
                      icon: Icons.people_outline_rounded,
                      destaque: true,
                    ),
                    _resumoCard(
                      width: larguraResumo,
                      titulo: 'Arquivados',
                      valor: '$arquivados',
                      detalhe: 'Cadastros fora da operação atual',
                      icon: Icons.archive_outlined,
                    ),
                    _resumoCard(
                      width: larguraResumo,
                      titulo: 'Com e-mail',
                      valor: '$comEmail',
                      detalhe: 'Clientes com contato digital cadastrado',
                      icon: Icons.alternate_email_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: compacto ? conteudo - 28 : 430,
                          child: TextField(
                            controller: busca,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText:
                                  'Buscar por nome, telefone, e-mail ou endereço',
                              suffixIcon: busca.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar busca',
                                      onPressed: () {
                                        busca.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ),
                        FilterChip(
                          selected: _mostrarArquivados,
                          onSelected: (valor) {
                            setState(() => _mostrarArquivados = valor);
                          },
                          avatar: const Icon(Icons.archive_outlined, size: 17),
                          label: const Text('Mostrar arquivados'),
                        ),
                        Text(
                          '${itens.length} resultado(s)',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (itens.isEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 42,
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_search_outlined,
                            size: 42,
                            color: Color(0xFF89939E),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhum cliente encontrado',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            termo.isEmpty
                                ? 'Cadastre um cliente para começar sua carteira.'
                                : 'Tente alterar a busca ou os filtros.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFAAB3BD)),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (tabela)
                  _tabelaClientes(itens)
                else
                  _cardsClientes(itens),
              ],
            );
          },
        );
      },
    );
  }
}

class _VeiculosPage extends StatefulWidget {
  const _VeiculosPage({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final WebCloudOperacionalService service;
  final VoidCallback onChanged;

  @override
  State<_VeiculosPage> createState() => _VeiculosPageState();
}

class _VeiculosPageState extends State<_VeiculosPage> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _editar(
    Map<String, dynamic>? atual,
    List<Map<String, dynamic>> clientes,
  ) async {
    final ativos = clientes.where((c) => c['ativo'] != false).toList();
    if (ativos.isEmpty) {
      _snack('Cadastre um cliente ativo antes de adicionar um veículo.');
      return;
    }

    var clienteId = '${atual?['cliente_id'] ?? ativos.first['id']}';
    if (!ativos.any((c) => '${c['id']}' == clienteId)) {
      clienteId = '${ativos.first['id']}';
    }

    final marca = TextEditingController(text: '${atual?['marca'] ?? ''}');
    final modelo = TextEditingController(text: '${atual?['modelo'] ?? ''}');
    final placa = TextEditingController(text: '${atual?['placa'] ?? ''}');
    final cor = TextEditingController(text: '${atual?['cor'] ?? ''}');
    final ano = TextEditingController(text: '${atual?['ano'] ?? ''}');
    final observacoes = TextEditingController(
      text: '${atual?['observacoes'] ?? ''}',
    );

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo veículo' : 'Editar veículo'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: clienteId,
                    isExpanded: true,
                    items: ativos
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: '${c['id']}',
                            child: Text(
                              '${c['nome']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => clienteId = v);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Cliente *',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: marca,
                          decoration: const InputDecoration(
                            labelText: 'Marca *',
                            prefixIcon: Icon(Icons.factory_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: modelo,
                          decoration: const InputDecoration(
                            labelText: 'Modelo *',
                            prefixIcon: Icon(Icons.directions_car_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: placa,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Placa',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: cor,
                          decoration: const InputDecoration(
                            labelText: 'Cor',
                            prefixIcon: Icon(Icons.palette_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: ano,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Ano',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: observacoes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                marca.text.trim().isNotEmpty && modelo.text.trim().isNotEmpty,
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar veículo'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    await widget.service.salvarVeiculo(
      id: atual?['id']?.toString(),
      clienteId: clienteId,
      marca: marca.text,
      modelo: modelo.text,
      placa: placa.text,
      cor: cor.text,
      ano: ano.text,
      observacoes: observacoes.text,
    );
    widget.onChanged();
  }

  Future<void> _excluir(Map<String, dynamic> veiculo) async {
    final descricao = '${veiculo['marca'] ?? ''} ${veiculo['modelo'] ?? ''}'
        .trim();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir veículo?'),
        content: Text(
          descricao.isEmpty
              ? 'Este veículo será removido da operação.'
              : 'O veículo "$descricao" será removido da operação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    await widget.service.excluirVeiculo(veiculo['id'].toString());
    widget.onChanged();
  }

  void _snack(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required IconData icone,
    required String detalhe,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
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

  Widget _tabela(
    List<Map<String, dynamic>> itens,
    Map<String, String> nomes,
    List<Map<String, dynamic>> clientes,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('VEÍCULO')),
            DataColumn(label: Text('PLACA')),
            DataColumn(label: Text('CLIENTE')),
            DataColumn(label: Text('DETALHES')),
            DataColumn(label: Text('AÇÕES')),
          ],
          rows: itens.map((e) {
            final marcaModelo = '${e['marca'] ?? ''} ${e['modelo'] ?? ''}'
                .trim();
            final placa = (e['placa'] ?? '').toString().trim();
            final detalhe = [
              (e['ano'] ?? '').toString(),
              (e['cor'] ?? '').toString(),
            ].where((x) => x.trim().isNotEmpty).join(' · ');

            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 250,
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 17,
                          child: Icon(Icons.directions_car_outlined, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            marcaModelo.isEmpty ? 'Veículo' : marcaModelo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 120,
                    child: Text(
                      placa.isEmpty ? '—' : placa,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(
                      nomes['${e['cliente_id']}'] ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(detalhe.isEmpty ? '—' : detalhe),
                  ),
                ),
                DataCell(
                  Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Editar veículo',
                        onPressed: () => _editar(e, clientes),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Excluir veículo',
                        onPressed: () => _excluir(e),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        widget.service.listarVeiculos(),
        widget.service.listarClientes(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final veiculos = snapshot.data![0];
        final clientes = snapshot.data![1];
        final nomes = {for (final c in clientes) '${c['id']}': '${c['nome']}'};

        final termo = _busca.text.trim().toLowerCase();
        final itens =
            veiculos.where((e) {
              if (termo.isEmpty) return true;
              final cliente = nomes['${e['cliente_id']}'] ?? '';
              return [
                e['marca'],
                e['modelo'],
                e['placa'],
                e['cor'],
                e['ano'],
                cliente,
              ].any((v) => '${v ?? ''}'.toLowerCase().contains(termo));
            }).toList()..sort((a, b) {
              final aa = '${a['marca'] ?? ''} ${a['modelo'] ?? ''}'
                  .toLowerCase();
              final bb = '${b['marca'] ?? ''} ${b['modelo'] ?? ''}'
                  .toLowerCase();
              return aa.compareTo(bb);
            });

        final comPlaca = veiculos
            .where((e) => (e['placa'] ?? '').toString().trim().isNotEmpty)
            .length;
        final proprietarios = veiculos
            .map((e) => (e['cliente_id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .length;

        return LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 760;
            final tabela = constraints.maxWidth >= 920;
            final larguraDisponivel =
                constraints.maxWidth - (compacto ? 32 : 48);
            final colunas = constraints.maxWidth >= 1080
                ? 3
                : constraints.maxWidth >= 640
                ? 2
                : 1;
            final larguraCard =
                (larguraDisponivel - (12 * (colunas - 1))) / colunas;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                compacto ? 16 : 24,
                compacto ? 18 : 24,
                compacto ? 16 : 24,
                40,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Veículos',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Frota cadastrada, proprietário e identificação do veículo.',
                            style: TextStyle(color: Color(0xFFAAB3BD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    FilledButton.icon(
                      onPressed: () => _editar(null, clientes),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(compacto ? 'Novo' : 'Novo veículo'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _resumo(
                      width: larguraCard,
                      titulo: 'Veículos cadastrados',
                      valor: '${veiculos.length}',
                      icone: Icons.directions_car_outlined,
                      detalhe: 'Total disponível na operação',
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Com placa',
                      valor: '$comPlaca',
                      icone: Icons.pin_outlined,
                      detalhe: 'Cadastros com identificação de placa',
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Proprietários',
                      valor: '$proprietarios',
                      icone: Icons.people_outline_rounded,
                      detalhe: 'Clientes com veículo vinculado',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _busca,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText:
                                  'Buscar por veículo, placa, cliente, cor ou ano',
                              suffixIcon: _busca.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar busca',
                                      onPressed: () {
                                        _busca.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ),
                        if (!compacto) ...[
                          const SizedBox(width: 14),
                          Text(
                            '${itens.length} resultado(s)',
                            style: const TextStyle(
                              color: Color(0xFF89939E),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (itens.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 42,
                        horizontal: 24,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.car_crash_outlined,
                            size: 42,
                            color: Color(0xFF89939E),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum veículo encontrado',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (tabela)
                  _tabela(itens, nomes, clientes)
                else
                  ...itens.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.directions_car_outlined),
                          ),
                          title: Text(
                            '${e['marca'] ?? ''} ${e['modelo'] ?? ''}'.trim(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            [
                              (e['placa'] ?? '').toString(),
                              nomes['${e['cliente_id']}'] ?? '',
                              (e['ano'] ?? '').toString(),
                              (e['cor'] ?? '').toString(),
                            ].where((x) => x.trim().isNotEmpty).join(' · '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (acao) {
                              if (acao == 'editar') {
                                _editar(e, clientes);
                              } else if (acao == 'excluir') {
                                _excluir(e);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'editar',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'excluir',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AgendaPage extends StatefulWidget {
  const _AgendaPage({
    super.key,
    required this.service,
    required this.moeda,
    required this.onChanged,
  });

  final WebCloudOperacionalService service;
  final NumberFormat moeda;
  final VoidCallback onChanged;

  @override
  State<_AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<_AgendaPage> {
  final _busca = TextEditingController();
  String _filtroStatus = 'Todos';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  DateTime? _parseData(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso.toLocal();

    final partes = texto.split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      final a = int.tryParse(partes[2]);
      if (d != null && m != null && a != null) {
        return DateTime(a, m, d);
      }
    }

    final hifen = texto.split('-');
    if (hifen.length == 3) {
      final a = int.tryParse(hifen[0]);
      final m = int.tryParse(hifen[1]);
      final d = int.tryParse(hifen[2]);
      if (d != null && m != null && a != null) {
        return DateTime(a, m, d);
      }
    }
    return null;
  }

  String _formatarData(DateTime data) {
    final d = data.day.toString().padLeft(2, '0');
    final m = data.month.toString().padLeft(2, '0');
    return '$d/$m/${data.year}';
  }

  TimeOfDay? _parseHora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    final partes = texto.split(':');
    if (partes.length < 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatarHora(TimeOfDay hora) {
    return '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
  }

  bool _statusAberto(dynamic status) {
    final texto = (status ?? '').toString().trim().toLowerCase();
    return !{
      'cancelado',
      'cancelada',
      'concluído',
      'concluido',
      'finalizado',
      'finalizada',
    }.contains(texto);
  }

  Future<void> _editar(
    Map<String, dynamic>? atual,
    List<Map<String, dynamic>> clientes,
    List<Map<String, dynamic>> veiculos,
  ) async {
    final ativos = clientes.where((c) => c['ativo'] != false).toList();
    if (ativos.isEmpty || veiculos.isEmpty) {
      _snack('Cadastre cliente e veículo antes de criar um agendamento.');
      return;
    }

    var clienteId = '${atual?['cliente_id'] ?? ativos.first['id']}';
    if (!ativos.any((c) => '${c['id']}' == clienteId)) {
      clienteId = '${ativos.first['id']}';
    }

    List<Map<String, dynamic>> disponiveis() =>
        veiculos.where((v) => '${v['cliente_id']}' == clienteId).toList();

    var lista = disponiveis();
    if (lista.isEmpty) {
      _snack('O cliente selecionado não possui veículo cadastrado.');
      return;
    }

    var veiculoId = '${atual?['veiculo_id'] ?? lista.first['id']}';
    if (!lista.any((v) => '${v['id']}' == veiculoId)) {
      veiculoId = '${lista.first['id']}';
    }

    final servico = TextEditingController(
      text: (atual?['servico'] ?? '').toString(),
    );
    final valor = TextEditingController(
      text: _double(atual?['valor']).toStringAsFixed(2),
    );
    final observacoes = TextEditingController(
      text: (atual?['observacoes'] ?? '').toString(),
    );

    DateTime dataSelecionada = _parseData(atual?['data']) ?? DateTime.now();
    TimeOfDay horaSelecionada = _parseHora(atual?['hora']) ?? TimeOfDay.now();
    var status = (atual?['status'] ?? 'Agendado').toString();
    const statuses = [
      'Agendado',
      'Confirmado',
      'Em andamento',
      'Concluído',
      'Cancelado',
    ];
    if (!statuses.contains(status)) status = 'Agendado';

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          lista = disponiveis();
          if (!lista.any((v) => '${v['id']}' == veiculoId)) {
            veiculoId = lista.isEmpty ? '' : '${lista.first['id']}';
          }

          return AlertDialog(
            title: Text(
              atual == null ? 'Novo agendamento' : 'Editar agendamento',
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: clienteId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Cliente *',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      items: ativos
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: '${c['id']}',
                              child: Text(
                                '${c['nome']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          clienteId = v;
                          final novaLista = disponiveis();
                          veiculoId = novaLista.isEmpty
                              ? ''
                              : '${novaLista.first['id']}';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey('agenda-veiculo-$clienteId'),
                      initialValue: lista.any((v) => '${v['id']}' == veiculoId)
                          ? veiculoId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Veículo *',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      items: lista
                          .map(
                            (v) => DropdownMenuItem<String>(
                              value: '${v['id']}',
                              child: Text(
                                '${v['marca'] ?? ''} ${v['modelo'] ?? ''} ${v['placa'] ?? ''}'
                                    .trim(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => veiculoId = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: servico,
                      decoration: const InputDecoration(
                        labelText: 'Serviço *',
                        prefixIcon: Icon(Icons.design_services_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final escolhida = await showDatePicker(
                                context: context,
                                initialDate: dataSelecionada,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 1095),
                                ),
                              );
                              if (escolhida != null) {
                                setLocal(() => dataSelecionada = escolhida);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Data *',
                                prefixIcon: Icon(Icons.calendar_month_outlined),
                              ),
                              child: Text(_formatarData(dataSelecionada)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final escolhida = await showTimePicker(
                                context: context,
                                initialTime: horaSelecionada,
                              );
                              if (escolhida != null) {
                                setLocal(() => horaSelecionada = escolhida);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Hora *',
                                prefixIcon: Icon(Icons.schedule_outlined),
                              ),
                              child: Text(_formatarHora(horaSelecionada)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: valor,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Valor previsto',
                              prefixText: 'R\$ ',
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              prefixIcon: Icon(Icons.flag_outlined),
                            ),
                            items: statuses
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setLocal(() => status = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: observacoes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  clienteId.isNotEmpty &&
                      veiculoId.isNotEmpty &&
                      servico.text.trim().isNotEmpty,
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Salvar agendamento'),
              ),
            ],
          );
        },
      ),
    );

    if (salvar != true) return;

    await widget.service.salvarAgendamento(
      id: atual?['id']?.toString(),
      clienteId: clienteId,
      veiculoId: veiculoId,
      servico: servico.text,
      data: _formatarData(dataSelecionada),
      hora: _formatarHora(horaSelecionada),
      valor: _double(valor.text),
      status: status,
      observacoes: observacoes.text,
    );
    widget.onChanged();
  }

  Future<void> _excluir(Map<String, dynamic> agendamento) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir agendamento?'),
        content: Text(
          'O agendamento de ${agendamento['data'] ?? ''} '
          '${agendamento['hora'] ?? ''} será removido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    await widget.service.excluirAgendamento(agendamento['id'].toString());
    widget.onChanged();
  }

  void _snack(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required IconData icone,
    required String detalhe,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
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

  Widget _statusChip(String status) {
    final normalizado = status.toLowerCase();
    IconData icone = Icons.event_outlined;
    if (normalizado.contains('confirm')) {
      icone = Icons.event_available_outlined;
    } else if (normalizado.contains('conclu') ||
        normalizado.contains('finaliz')) {
      icone = Icons.task_alt_outlined;
    } else if (normalizado.contains('cancel')) {
      icone = Icons.event_busy_outlined;
    } else if (normalizado.contains('andamento')) {
      icone = Icons.pending_actions_outlined;
    }
    return Chip(
      avatar: Icon(icone, size: 16),
      label: Text(status.isEmpty ? 'Agendado' : status),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        widget.service.listarAgendamentos(),
        widget.service.listarClientes(),
        widget.service.listarVeiculos(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final agenda = snapshot.data![0];
        final clientes = snapshot.data![1];
        final veiculos = snapshot.data![2];
        final nomes = {for (final c in clientes) '${c['id']}': '${c['nome']}'};
        final carros = {
          for (final v in veiculos)
            '${v['id']}':
                '${v['marca'] ?? ''} ${v['modelo'] ?? ''} ${v['placa'] ?? ''}'
                    .trim(),
        };

        final hojeAgora = DateTime.now();
        final hoje = DateTime(hojeAgora.year, hojeAgora.month, hojeAgora.day);
        final termo = _busca.text.trim().toLowerCase();

        final itens =
            agenda.where((e) {
              final status = (e['status'] ?? 'Agendado').toString();
              if (_filtroStatus == 'Abertos' && !_statusAberto(status)) {
                return false;
              }
              if (_filtroStatus == 'Concluídos' &&
                  !status.toLowerCase().contains('conclu') &&
                  !status.toLowerCase().contains('finaliz')) {
                return false;
              }
              if (_filtroStatus == 'Cancelados' &&
                  !status.toLowerCase().contains('cancel')) {
                return false;
              }

              if (termo.isEmpty) return true;
              return [
                e['servico'],
                e['data'],
                e['hora'],
                e['status'],
                nomes['${e['cliente_id']}'] ?? '',
                carros['${e['veiculo_id']}'] ?? '',
              ].any((v) => '${v ?? ''}'.toLowerCase().contains(termo));
            }).toList()..sort((a, b) {
              final da = _parseData(a['data']) ?? DateTime(2099);
              final db = _parseData(b['data']) ?? DateTime(2099);
              final cmp = da.compareTo(db);
              if (cmp != 0) return cmp;
              return (a['hora'] ?? '').toString().compareTo(
                (b['hora'] ?? '').toString(),
              );
            });

        final abertos = agenda
            .where((e) => _statusAberto(e['status']))
            .toList();
        final hojeQtd = abertos.where((e) {
          final d = _parseData(e['data']);
          return d != null &&
              d.year == hoje.year &&
              d.month == hoje.month &&
              d.day == hoje.day;
        }).length;
        final proximos = abertos.where((e) {
          final d = _parseData(e['data']);
          if (d == null) return false;
          final dia = DateTime(d.year, d.month, d.day);
          return dia.isAfter(hoje);
        }).length;
        final valorPrevisto = abertos.fold<double>(
          0,
          (total, e) => total + _double(e['valor']),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 760;
            final tabela = constraints.maxWidth >= 980;
            final larguraDisponivel =
                constraints.maxWidth - (compacto ? 32 : 48);
            final colunas = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 760
                ? 2
                : 1;
            final larguraCard =
                (larguraDisponivel - (12 * (colunas - 1))) / colunas;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                compacto ? 16 : 24,
                compacto ? 18 : 24,
                compacto ? 16 : 24,
                40,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agenda',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Compromissos, retornos e serviços programados da operação.',
                            style: TextStyle(color: Color(0xFFAAB3BD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    FilledButton.icon(
                      onPressed: () => _editar(null, clientes, veiculos),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(compacto ? 'Novo' : 'Novo agendamento'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _resumo(
                      width: larguraCard,
                      titulo: 'Hoje',
                      valor: '$hojeQtd',
                      icone: Icons.today_outlined,
                      detalhe: 'Agendamentos abertos para hoje',
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Próximos',
                      valor: '$proximos',
                      icone: Icons.upcoming_outlined,
                      detalhe: 'Compromissos futuros em aberto',
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Em aberto',
                      valor: '${abertos.length}',
                      icone: Icons.event_note_outlined,
                      detalhe: 'Agendamentos ainda ativos',
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Valor previsto',
                      valor: widget.moeda.format(valorPrevisto),
                      icone: Icons.payments_outlined,
                      detalhe: 'Soma dos agendamentos em aberto',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: compacto ? larguraDisponivel - 28 : 430,
                          child: TextField(
                            controller: _busca,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText:
                                  'Buscar por cliente, veículo, serviço ou data',
                              suffixIcon: _busca.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar busca',
                                      onPressed: () {
                                        _busca.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'Todos', label: Text('Todos')),
                            ButtonSegment(
                              value: 'Abertos',
                              label: Text('Abertos'),
                            ),
                            ButtonSegment(
                              value: 'Concluídos',
                              label: Text('Concluídos'),
                            ),
                            ButtonSegment(
                              value: 'Cancelados',
                              label: Text('Cancelados'),
                            ),
                          ],
                          selected: <String>{_filtroStatus},
                          showSelectedIcon: false,
                          onSelectionChanged: (valor) {
                            setState(() => _filtroStatus = valor.first);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (itens.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 42,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            size: 42,
                            color: Color(0xFF89939E),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum agendamento encontrado',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (tabela)
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 52,
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 76,
                        columns: const [
                          DataColumn(label: Text('DATA / HORA')),
                          DataColumn(label: Text('CLIENTE')),
                          DataColumn(label: Text('VEÍCULO')),
                          DataColumn(label: Text('SERVIÇO')),
                          DataColumn(label: Text('STATUS')),
                          DataColumn(label: Text('VALOR')),
                          DataColumn(label: Text('AÇÕES')),
                        ],
                        rows: itens.map((e) {
                          final status = (e['status'] ?? 'Agendado').toString();
                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    '${e['data'] ?? ''}\n${e['hora'] ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 210,
                                  child: Text(
                                    nomes['${e['cliente_id']}'] ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 230,
                                  child: Text(
                                    carros['${e['veiculo_id']}'] ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    (e['servico'] ?? '—').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(_statusChip(status)),
                              DataCell(
                                Text(
                                  widget.moeda.format(_double(e['valor'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              DataCell(
                                Wrap(
                                  spacing: 2,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar agendamento',
                                      onPressed: () =>
                                          _editar(e, clientes, veiculos),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Excluir agendamento',
                                      onPressed: () => _excluir(e),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  )
                else
                  ...itens.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.event_outlined),
                          ),
                          title: Text(
                            '${e['data'] ?? ''} ${e['hora'] ?? ''} · ${e['servico'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            [
                              nomes['${e['cliente_id']}'] ?? '',
                              carros['${e['veiculo_id']}'] ?? '',
                              widget.moeda.format(_double(e['valor'])),
                            ].where((x) => x.trim().isNotEmpty).join(' · '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (acao) {
                              if (acao == 'editar') {
                                _editar(e, clientes, veiculos);
                              } else if (acao == 'excluir') {
                                _excluir(e);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'editar',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'excluir',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _OrdensPage extends StatefulWidget {
  const _OrdensPage({
    super.key,
    required this.service,
    required this.moeda,
    required this.onNavigate,
  });

  final WebCloudOperacionalService service;
  final NumberFormat moeda;
  final ValueChanged<int> onNavigate;

  @override
  State<_OrdensPage> createState() => _OrdensPageState();
}

class _OrdensPageState extends State<_OrdensPage> {
  final _busca = TextEditingController();
  String _status = 'Todos';
  String _pagamento = 'Todos';
  String _periodo = 'Todos';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  DateTime? _parseData(dynamic raw) {
    final texto = raw?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso.toLocal();

    final partes = texto.split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      final a = int.tryParse(partes[2]);
      if (d != null && m != null && a != null) {
        return DateTime(a, m, d);
      }
    }
    return null;
  }

  double _valorNegociado(Map<String, dynamic> e) {
    return OrdemServicoValor.valorNegociado(
      valorTotal: _double(e['valor_total']),
      desconto: _double(e['desconto']),
      descontoNegociacao: _double(e['desconto_negociacao']),
      acrescimoNegociacao: _double(e['acrescimo_negociacao']),
      jurosParcelamento: _double(e['juros_parcelamento']),
    );
  }

  double _pendente(Map<String, dynamic> e) {
    return (_valorNegociado(e) - _double(e['valor_recebido'])).clamp(
      0,
      double.infinity,
    );
  }

  bool _estaNoPeriodo(Map<String, dynamic> e) {
    if (_periodo == 'Todos') return true;

    final agora = DateTime.now();
    final data =
        _parseData(e['data_finalizacao']) ??
        _parseData(e['data_abertura']) ??
        _parseData(e['data_inicio']);
    if (data == null) return false;

    if (_periodo == 'Este mês') {
      return data.year == agora.year && data.month == agora.month;
    }

    if (_periodo == '30 dias') {
      return !data.isBefore(agora.subtract(const Duration(days: 30)));
    }

    return true;
  }

  Future<void> _abrirArquivos(Map<String, dynamic> ordem) async {
    final id = (ordem['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WebOsArquivosPage(
          ordemId: id,
          numero: (ordem['numero'] ?? '').toString(),
        ),
      ),
    );
  }

  Widget _statusChip(String valor) {
    final texto = valor.trim().isEmpty ? 'Sem status' : valor.trim();
    final normalizado = texto.toLowerCase();
    IconData icon = Icons.receipt_long_outlined;

    if (normalizado.contains('final')) {
      icon = Icons.task_alt_outlined;
    } else if (normalizado.contains('andamento')) {
      icon = Icons.pending_actions_outlined;
    } else if (normalizado.contains('cancel')) {
      icon = Icons.cancel_outlined;
    } else if (normalizado.contains('aberta')) {
      icon = Icons.edit_note_outlined;
    }

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(texto),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _pagamentoChip(String valor) {
    final texto = valor.trim().isEmpty ? 'Não informado' : valor.trim();
    return Chip(
      avatar: const Icon(Icons.payments_outlined, size: 16),
      label: Text(texto),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
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

  Widget _acoes(Map<String, dynamic> ordem) {
    final status = (ordem['status'] ?? '').toString();
    final editavel = status == 'Aberta' || status == 'Em andamento';
    final finalizavel = editavel;

    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Fotos, avarias, arquivos e assinatura',
          onPressed: () => _abrirArquivos(ordem),
          icon: const Icon(Icons.photo_library_outlined),
        ),
        IconButton(
          tooltip: editavel ? 'Abrir edição segura' : 'OS não editável',
          onPressed: editavel ? () => widget.onNavigate(6) : null,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: finalizavel ? 'Abrir finalização' : 'OS já encerrada',
          onPressed: finalizavel ? () => widget.onNavigate(7) : null,
          icon: const Icon(Icons.task_alt_outlined),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        widget.service.listarOrdens(),
        widget.service.listarClientes(),
        widget.service.listarVeiculos(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final ordens = snapshot.data![0];
        final clientes = snapshot.data![1];
        final veiculos = snapshot.data![2];
        final nomes = {for (final c in clientes) '${c['id']}': '${c['nome']}'};
        final carros = {
          for (final v in veiculos)
            '${v['id']}':
                '${v['marca'] ?? ''} ${v['modelo'] ?? ''} ${v['placa'] ?? ''}'
                    .trim(),
        };

        final termo = _busca.text.trim().toLowerCase();
        final filtradas =
            ordens.where((os) {
              final status = (os['status'] ?? '').toString();
              final statusPagamento = (os['status_pagamento'] ?? '').toString();

              if (_status != 'Todos' && status != _status) return false;
              if (_pagamento != 'Todos' && statusPagamento != _pagamento) {
                return false;
              }
              if (!_estaNoPeriodo(os)) return false;

              if (termo.isEmpty) return true;

              return [
                os['numero'],
                nomes['${os['cliente_id']}'] ?? '',
                carros['${os['veiculo_id']}'] ?? '',
                os['funcionario_responsavel'],
                status,
                statusPagamento,
              ].any((v) => '${v ?? ''}'.toLowerCase().contains(termo));
            }).toList()..sort((a, b) {
              final da =
                  _parseData(a['data_finalizacao']) ??
                  _parseData(a['data_abertura']) ??
                  DateTime(2000);
              final db =
                  _parseData(b['data_finalizacao']) ??
                  _parseData(b['data_abertura']) ??
                  DateTime(2000);
              return db.compareTo(da);
            });

        final abertas = ordens.where((e) => e['status'] == 'Aberta').length;
        final emAndamento = ordens
            .where((e) => e['status'] == 'Em andamento')
            .length;
        final finalizadas = ordens
            .where((e) => e['status'] == 'Finalizada')
            .toList();
        final faturamentoFinalizado = finalizadas.fold<double>(
          0,
          (total, e) => total + _valorNegociado(e),
        );
        final pendenteTotal = ordens.fold<double>(
          0,
          (total, e) => total + _pendente(e),
        );

        final statusesPagamento =
            ordens
                .map((e) => (e['status_pagamento'] ?? '').toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        return LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 760;
            final tabela = constraints.maxWidth >= 1050;
            final larguraDisponivel =
                constraints.maxWidth - (compacto ? 32 : 48);
            final colunas = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 760
                ? 2
                : 1;
            final larguraCard =
                (larguraDisponivel - (12 * (colunas - 1))) / colunas;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                compacto ? 16 : 24,
                compacto ? 18 : 24,
                compacto ? 16 : 24,
                40,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ordens de serviço',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Central da operação: acompanhe execução, valores, pagamentos e arquivos.',
                            style: TextStyle(color: Color(0xFFAAB3BD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (!compacto) ...[
                      OutlinedButton.icon(
                        onPressed: () => widget.onNavigate(6),
                        icon: const Icon(Icons.edit_note_outlined),
                        label: const Text('Editar OS'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => widget.onNavigate(7),
                        icon: const Icon(Icons.task_alt_outlined),
                        label: const Text('Finalizar'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: () => widget.onNavigate(5),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(compacto ? 'Nova' : 'Nova OS'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _resumo(
                      width: larguraCard,
                      titulo: 'Abertas',
                      valor: '$abertas',
                      detalhe: 'Aguardando início ou execução',
                      icone: Icons.edit_note_outlined,
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Em andamento',
                      valor: '$emAndamento',
                      detalhe: 'Veículos em execução',
                      icone: Icons.car_repair_outlined,
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Faturamento finalizado',
                      valor: widget.moeda.format(faturamentoFinalizado),
                      detalhe: '${finalizadas.length} OS finalizada(s)',
                      icone: Icons.trending_up_rounded,
                    ),
                    _resumo(
                      width: larguraCard,
                      titulo: 'Pendente de recebimento',
                      valor: widget.moeda.format(pendenteTotal),
                      detalhe: 'Saldo comercial ainda não recebido',
                      icone: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: compacto ? larguraDisponivel - 28 : 400,
                          child: TextField(
                            controller: _busca,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText:
                                  'Buscar OS, cliente, veículo ou responsável',
                              suffixIcon: _busca.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar busca',
                                      onPressed: () {
                                        _busca.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 175,
                          child: DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items:
                                const [
                                      'Todos',
                                      'Aberta',
                                      'Em andamento',
                                      'Finalizada',
                                      'Cancelada',
                                    ]
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) =>
                                setState(() => _status = v ?? 'Todos'),
                          ),
                        ),
                        SizedBox(
                          width: 195,
                          child: DropdownButtonFormField<String>(
                            initialValue: _pagamento,
                            decoration: const InputDecoration(
                              labelText: 'Pagamento',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'Todos',
                                child: Text('Todos'),
                              ),
                              ...statusesPagamento.map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _pagamento = v ?? 'Todos'),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: _periodo,
                            decoration: const InputDecoration(
                              labelText: 'Período',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Todos',
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: 'Este mês',
                                child: Text('Este mês'),
                              ),
                              DropdownMenuItem(
                                value: '30 dias',
                                child: Text('Últimos 30 dias'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _periodo = v ?? 'Todos'),
                          ),
                        ),
                        Text(
                          '${filtradas.length} resultado(s)',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (filtradas.isEmpty)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 42,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 42,
                            color: Color(0xFF89939E),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Nenhuma OS encontrada',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Altere a busca ou os filtros para visualizar outras ordens.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFFAAB3BD)),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (tabela)
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 52,
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 80,
                        columns: const [
                          DataColumn(label: Text('OS / CLIENTE')),
                          DataColumn(label: Text('VEÍCULO')),
                          DataColumn(label: Text('STATUS')),
                          DataColumn(label: Text('PAGAMENTO')),
                          DataColumn(label: Text('VALOR')),
                          DataColumn(label: Text('RECEBIDO')),
                          DataColumn(label: Text('PENDENTE')),
                          DataColumn(label: Text('AÇÕES')),
                        ],
                        rows: filtradas.map((e) {
                          final negociado = _valorNegociado(e);
                          final recebido = _double(e['valor_recebido']);
                          final pendente = _pendente(e);
                          final status = (e['status'] ?? '').toString();
                          final statusPagamento = (e['status_pagamento'] ?? '')
                              .toString();

                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 255,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'OS ${e['numero'] ?? ''}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        nomes['${e['cliente_id']}'] ?? '—',
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
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    carros['${e['veiculo_id']}'] ?? '—',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(_statusChip(status)),
                              DataCell(_pagamentoChip(statusPagamento)),
                              DataCell(
                                Text(
                                  widget.moeda.format(negociado),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              DataCell(Text(widget.moeda.format(recebido))),
                              DataCell(
                                Text(
                                  widget.moeda.format(pendente),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: pendente > 0
                                        ? Colors.orangeAccent
                                        : null,
                                  ),
                                ),
                              ),
                              DataCell(_acoes(e)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  )
                else
                  ...filtradas.map((e) {
                    final negociado = _valorNegociado(e);
                    final pendente = _pendente(e);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                child: Icon(Icons.receipt_long_outlined),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'OS ${e['numero'] ?? ''} · '
                                      '${nomes['${e['cliente_id']}'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                            carros['${e['veiculo_id']}'] ?? '',
                                            (e['status'] ?? '').toString(),
                                            (e['status_pagamento'] ?? '')
                                                .toString(),
                                          ]
                                          .where((x) => x.trim().isNotEmpty)
                                          .join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFAAB3BD),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${widget.moeda.format(negociado)} · '
                                      'Pendente ${widget.moeda.format(pendente)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _acoes(e),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texto,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
