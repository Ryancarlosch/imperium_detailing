import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';
import '../services/web_cloud_operacional_service.dart';
import 'imperium_web_theme.dart';
import 'web_contas_financeiras_page.dart';
import 'web_dashboard_gerencial_page.dart';
import 'web_dre_page.dart';
import 'web_expansao_pages.dart';
import 'web_gestao_pages.dart';
import 'web_ordens_v3_page.dart';
import 'web_os_finalizacao_v4_page.dart';
import 'web_ponto_page.dart';
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

  int _indice = 0;
  int _revisao = 0;

  String get _nomeEmpresaAtual {
    for (final empresa in widget.empresas) {
      if ('${empresa['empresa_id']}' == widget.empresaAtualId) {
        final nome = (empresa['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Empresa';
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
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(builder: (_) => paginaRoteada),
          )
          .then((_) {
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
      ),
      5 => WebNovaOrdemPage(
        key: ValueKey('nova-os-$_revisao'),
        onCreated: _atualizar,
      ),
      6 => WebOrdensV3Page(key: ValueKey('editar-os-$_revisao')),
      7 => WebOsFinalizacaoV4Page(key: ValueKey('finalizar-os-$_revisao')),
      8 => WebEstoquePage(key: ValueKey('estoque-$_revisao')),
      9 => WebFinanceiroPage(key: ValueKey('financeiro-$_revisao')),
      10 => WebDrePage(key: ValueKey('dre-$_revisao')),
      11 => WebContasFinanceirasPage(key: ValueKey('contas-$_revisao')),
      12 => WebRelatoriosPage(key: ValueKey('relatorios-$_revisao')),
      13 => WebCrmPage(key: ValueKey('crm-$_revisao')),
      14 => WebOrcamentosPage(key: ValueKey('orcamentos-$_revisao')),
      15 => WebPrecificacaoPage(key: ValueKey('precificacao-$_revisao')),
      16 => WebPontoPage(key: ValueKey('ponto-$_revisao')),
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
          indices: const {13, 14, 15},
          filhos: [
            _itemMenu(indice: 13, titulo: 'CRM', icone: Icons.hub_outlined),
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
              if (valor == 'sair') await widget.onSair();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'email',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    widget.usuarioEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const PopupMenuDivider(),
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
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                decoration: const InputDecoration(labelText: 'Nome *'),
              ),
              TextField(
                controller: telefone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(
                controller: endereco,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
              TextField(
                controller: obs,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, nome.text.trim().isNotEmpty),
            child: const Text('Salvar'),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.service.listarClientes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final termo = busca.text.trim().toLowerCase();
        final itens = snapshot.data!.where((e) {
          if (termo.isEmpty) return true;
          return [
            'nome',
            'telefone',
            'email',
          ].any((k) => '${e[k] ?? ''}'.toLowerCase().contains(termo));
        }).toList();

        return Column(
          children: [
            _Topo(
              campo: TextField(
                controller: busca,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar cliente',
                  border: OutlineInputBorder(),
                ),
              ),
              botao: FilledButton.icon(
                onPressed: () => _editar(null),
                icon: const Icon(Icons.add),
                label: const Text('Novo cliente'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: itens.length,
                itemBuilder: (context, i) {
                  final e = itens[i];
                  final ativo = e['ativo'] != false;
                  return Card(
                    child: ListTile(
                      title: Text('${e['nome'] ?? ''}'),
                      subtitle: Text(
                        [
                          '${e['telefone'] ?? ''}',
                          '${e['email'] ?? ''}',
                          if (!ativo) 'Arquivado',
                        ].where((x) => x.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => _editar(e),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: ativo ? 'Arquivar' : 'Reativar',
                            onPressed: () async {
                              await widget.service.arquivarCliente(
                                e['id'].toString(),
                                ativo,
                              );
                              widget.onChanged();
                            },
                            icon: Icon(
                              ativo
                                  ? Icons.archive_outlined
                                  : Icons.unarchive_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VeiculosPage extends StatelessWidget {
  const _VeiculosPage({
    super.key,
    required this.service,
    required this.onChanged,
  });

  final WebCloudOperacionalService service;
  final VoidCallback onChanged;

  Future<void> _editar(
    BuildContext context,
    Map<String, dynamic>? atual,
    List<Map<String, dynamic>> clientes,
  ) async {
    if (clientes.isEmpty) return;

    var clienteId = '${atual?['cliente_id'] ?? clientes.first['id']}';
    final marca = TextEditingController(text: '${atual?['marca'] ?? ''}');
    final modelo = TextEditingController(text: '${atual?['modelo'] ?? ''}');
    final placa = TextEditingController(text: '${atual?['placa'] ?? ''}');
    final cor = TextEditingController(text: '${atual?['cor'] ?? ''}');
    final ano = TextEditingController(text: '${atual?['ano'] ?? ''}');

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo veículo' : 'Editar veículo'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: clientes.any((c) => '${c['id']}' == clienteId)
                      ? clienteId
                      : '${clientes.first['id']}',
                  items: clientes
                      .where((c) => c['ativo'] != false)
                      .map(
                        (c) => DropdownMenuItem(
                          value: '${c['id']}',
                          child: Text('${c['nome']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => clienteId = v ?? clienteId),
                  decoration: const InputDecoration(labelText: 'Cliente'),
                ),
                TextField(
                  controller: marca,
                  decoration: const InputDecoration(labelText: 'Marca *'),
                ),
                TextField(
                  controller: modelo,
                  decoration: const InputDecoration(labelText: 'Modelo *'),
                ),
                TextField(
                  controller: placa,
                  decoration: const InputDecoration(labelText: 'Placa'),
                ),
                TextField(
                  controller: cor,
                  decoration: const InputDecoration(labelText: 'Cor'),
                ),
                TextField(
                  controller: ano,
                  decoration: const InputDecoration(labelText: 'Ano'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                marca.text.trim().isNotEmpty && modelo.text.trim().isNotEmpty,
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    await service.salvarVeiculo(
      id: atual?['id']?.toString(),
      clienteId: clienteId,
      marca: marca.text,
      modelo: modelo.text,
      placa: placa.text,
      cor: cor.text,
      ano: ano.text,
      observacoes: '${atual?['observacoes'] ?? ''}',
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([service.listarVeiculos(), service.listarClientes()]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final veiculos = snapshot.data![0];
        final clientes = snapshot.data![1];
        final nomes = {for (final c in clientes) '${c['id']}': '${c['nome']}'};

        return Column(
          children: [
            _Topo(
              campo: const Text(
                'Veículos',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              botao: FilledButton.icon(
                onPressed: () => _editar(context, null, clientes),
                icon: const Icon(Icons.add),
                label: const Text('Novo veículo'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: veiculos.length,
                itemBuilder: (context, i) {
                  final e = veiculos[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.directions_car_rounded),
                      title: Text('${e['marca'] ?? ''} ${e['modelo'] ?? ''}'),
                      subtitle: Text(
                        [
                          '${e['placa'] ?? ''}',
                          nomes['${e['cliente_id']}'] ?? '',
                        ].where((x) => x.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            onPressed: () => _editar(context, e, clientes),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            onPressed: () async {
                              await service.excluirVeiculo(e['id'].toString());
                              onChanged();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AgendaPage extends StatelessWidget {
  const _AgendaPage({
    super.key,
    required this.service,
    required this.moeda,
    required this.onChanged,
  });

  final WebCloudOperacionalService service;
  final NumberFormat moeda;
  final VoidCallback onChanged;

  Future<void> _novo(
    BuildContext context,
    List<Map<String, dynamic>> clientes,
    List<Map<String, dynamic>> veiculos,
  ) async {
    if (clientes.isEmpty || veiculos.isEmpty) return;

    var clienteId = '${clientes.first['id']}';
    var disponiveis = veiculos
        .where((v) => '${v['cliente_id']}' == clienteId)
        .toList();
    if (disponiveis.isEmpty) return;
    var veiculoId = '${disponiveis.first['id']}';

    final servico = TextEditingController();
    final data = TextEditingController();
    final hora = TextEditingController();
    final valor = TextEditingController();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          disponiveis = veiculos
              .where((v) => '${v['cliente_id']}' == clienteId)
              .toList();
          return AlertDialog(
            title: const Text('Novo agendamento'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: clienteId,
                    items: clientes
                        .map(
                          (c) => DropdownMenuItem(
                            value: '${c['id']}',
                            child: Text('${c['nome']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      clienteId = v ?? clienteId;
                      final lista = veiculos
                          .where((x) => '${x['cliente_id']}' == clienteId)
                          .toList();
                      veiculoId = lista.isEmpty ? '' : '${lista.first['id']}';
                    }),
                    decoration: const InputDecoration(labelText: 'Cliente'),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(clienteId),
                    initialValue:
                        disponiveis.any((v) => '${v['id']}' == veiculoId)
                        ? veiculoId
                        : null,
                    items: disponiveis
                        .map(
                          (v) => DropdownMenuItem(
                            value: '${v['id']}',
                            child: Text(
                              '${v['marca']} ${v['modelo']} ${v['placa']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => veiculoId = v ?? ''),
                    decoration: const InputDecoration(labelText: 'Veículo'),
                  ),
                  TextField(
                    controller: servico,
                    decoration: const InputDecoration(labelText: 'Serviço *'),
                  ),
                  TextField(
                    controller: data,
                    decoration: const InputDecoration(labelText: 'Data *'),
                  ),
                  TextField(
                    controller: hora,
                    decoration: const InputDecoration(labelText: 'Hora *'),
                  ),
                  TextField(
                    controller: valor,
                    decoration: const InputDecoration(labelText: 'Valor'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  clienteId.isNotEmpty &&
                      veiculoId.isNotEmpty &&
                      servico.text.trim().isNotEmpty &&
                      data.text.trim().isNotEmpty &&
                      hora.text.trim().isNotEmpty,
                ),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    if (salvar != true) return;

    await service.salvarAgendamento(
      clienteId: clienteId,
      veiculoId: veiculoId,
      servico: servico.text,
      data: data.text,
      hora: hora.text,
      valor: _double(valor.text),
      status: 'Agendado',
      observacoes: '',
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        service.listarAgendamentos(),
        service.listarClientes(),
        service.listarVeiculos(),
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
            '${v['id']}': '${v['marca']} ${v['modelo']} ${v['placa']}',
        };

        return Column(
          children: [
            _Topo(
              campo: const Text(
                'Agenda',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              botao: FilledButton.icon(
                onPressed: () => _novo(context, clientes, veiculos),
                icon: const Icon(Icons.add),
                label: const Text('Novo agendamento'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: agenda.length,
                itemBuilder: (context, i) {
                  final e = agenda[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_rounded),
                      title: Text(
                        '${e['data']} ${e['hora']} · ${e['servico']}',
                      ),
                      subtitle: Text(
                        [
                          nomes['${e['cliente_id']}'] ?? '',
                          carros['${e['veiculo_id']}'] ?? '',
                          '${e['status'] ?? ''}',
                          moeda.format(_double(e['valor'])),
                        ].where((x) => x.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: IconButton(
                        onPressed: () async {
                          await service.excluirAgendamento(e['id'].toString());
                          onChanged();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrdensPage extends StatelessWidget {
  const _OrdensPage({super.key, required this.service, required this.moeda});

  final WebCloudOperacionalService service;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        service.listarOrdens(),
        service.listarClientes(),
        service.listarVeiculos(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _Erro(snapshot.error.toString());

        final ordens = snapshot.data![0].reversed.toList();
        final clientes = snapshot.data![1];
        final veiculos = snapshot.data![2];
        final nomes = {for (final c in clientes) '${c['id']}': '${c['nome']}'};
        final carros = {
          for (final v in veiculos)
            '${v['id']}': '${v['marca']} ${v['modelo']} ${v['placa']}',
        };

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Ordens de serviço',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Consulta Web V1. Criação/finalização entra no próximo lote.',
            ),
            const SizedBox(height: 16),
            ...ordens.map((e) {
              final negociado = OrdemServicoValor.valorNegociado(
                valorTotal: _double(e['valor_total']),
                desconto: _double(e['desconto']),
                descontoNegociacao: _double(e['desconto_negociacao']),
                acrescimoNegociacao: _double(e['acrescimo_negociacao']),
                jurosParcelamento: _double(e['juros_parcelamento']),
              );
              final pendente = (negociado - _double(e['valor_recebido'])).clamp(
                0,
                double.infinity,
              );

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: Text(
                    'OS ${e['numero'] ?? ''} · ${nomes['${e['cliente_id']}'] ?? ''}',
                  ),
                  subtitle: Text(
                    [
                      carros['${e['veiculo_id']}'] ?? '',
                      '${e['status'] ?? ''}',
                      '${e['status_pagamento'] ?? ''}',
                    ].where((x) => x.trim().isNotEmpty).join(' · '),
                  ),
                  trailing: Text(
                    '${moeda.format(negociado)}\nPendente ${moeda.format(pendente)}',
                    textAlign: TextAlign.right,
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({required this.campo, required this.botao});
  final Widget campo;
  final Widget botao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(child: campo),
          const SizedBox(width: 16),
          botao,
        ],
      ),
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
