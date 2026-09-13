import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';

import '../services/web_cloud_operacional_service.dart';
import 'web_gestao_pages.dart';
import 'web_expansao_pages.dart';

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

class _WebNavItem {
  const _WebNavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _WebOperacionalShellState extends State<WebOperacionalShell> {
  final _service = WebCloudOperacionalService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  int _indice = 0;
  int _revisao = 0;

  static const _navegacao = <_WebNavItem>[
    _WebNavItem('Dashboard', Icons.dashboard_outlined),
    _WebNavItem('Clientes', Icons.people_outline),
    _WebNavItem('Veículos', Icons.directions_car_outlined),
    _WebNavItem('Agenda', Icons.calendar_month_outlined),
    _WebNavItem('Ordens de serviço', Icons.receipt_long_outlined),
    _WebNavItem('Nova OS', Icons.add_business_outlined),
    _WebNavItem('Estoque', Icons.inventory_2_outlined),
    _WebNavItem('Financeiro', Icons.account_balance_wallet_outlined),
    _WebNavItem('CRM', Icons.hub_outlined),
    _WebNavItem('Orçamentos', Icons.request_quote_outlined),
    _WebNavItem('Precificação', Icons.price_change_outlined),
    _WebNavItem('Central Cloud', Icons.cloud_outlined),
  ];

  void _atualizar() => setState(() => _revisao++);

  void _selecionar(int indice, {bool fecharDrawer = false}) {
    setState(() => _indice = indice);
    if (fecharDrawer && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Widget _pagina() {
    return switch (_indice) {
      0 => _DashboardPage(
        key: ValueKey('dashboard-$_revisao'),
        service: _service,
        moeda: _moeda,
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
      6 => WebEstoquePage(key: ValueKey('estoque-$_revisao')),
      7 => WebFinanceiroPage(key: ValueKey('financeiro-$_revisao')),
      8 => WebCrmPage(key: ValueKey('crm-$_revisao')),
      9 => WebOrcamentosPage(key: ValueKey('orcamentos-$_revisao')),
      10 => WebPrecificacaoPage(key: ValueKey('precificacao-$_revisao')),
      _ => WebCentralCloudPage(key: ValueKey('central-$_revisao')),
    };
  }

  Widget _menuLateral({required bool fecharDrawer}) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (var i = 0; i < _navegacao.length; i++)
          ListTile(
            selected: i == _indice,
            leading: Icon(_navegacao[i].icon),
            title: Text(_navegacao[i].label),
            onTap: () => _selecionar(i, fecharDrawer: fecharDrawer),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ampla = MediaQuery.sizeOf(context).width >= 1050;
    final itemAtual = _navegacao[_indice];

    final drawer = ampla
        ? null
        : Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_mosaic_outlined),
                    title: const Text(
                      'Imperium Manager',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(widget.usuarioEmail),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _menuLateral(fecharDrawer: true)),
                ],
              ),
            ),
          );

    return Scaffold(
      drawer: drawer,
      appBar: AppBar(
        title: Text('Imperium Web · ${itemAtual.label}'),
        actions: [
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
                  (e) => PopupMenuItem<String>(
                    value: (e['empresa_id'] ?? '').toString(),
                    child: Text((e['nome'] ?? 'Empresa').toString()),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.business_rounded),
          ),
          IconButton(
            tooltip: 'Sair · ${widget.usuarioEmail}',
            onPressed: widget.onSair,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ampla
          ? Row(
              children: [
                SizedBox(width: 250, child: _menuLateral(fecharDrawer: false)),
                const VerticalDivider(width: 1),
                Expanded(child: _pagina()),
              ],
            )
          : _pagina(),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({super.key, required this.service, required this.moeda});

  final WebCloudOperacionalService service;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: service.carregarResumo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Erro(snapshot.error.toString());
        }

        final d = snapshot.data!;
        final cards = <(String, String, IconData)>[
          ('Clientes ativos', '${d['clientes']}', Icons.people_rounded),
          ('Veículos', '${d['veiculos']}', Icons.directions_car_rounded),
          ('Agenda aberta', '${d['agenda']}', Icons.calendar_month_rounded),
          ('OS abertas', '${d['os_abertas']}', Icons.receipt_long_rounded),
          (
            'Faturamento do mês',
            moeda.format(_double(d['faturamento_mes'])),
            Icons.trending_up_rounded,
          ),
          (
            'A receber em OS',
            moeda.format(_double(d['a_receber'])),
            Icons.account_balance_wallet_rounded,
          ),
        ];

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Visão geral',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('Dados online do mesmo tenant usado no Android.'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map(
                    (c) => SizedBox(
                      width: 245,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(c.$3),
                              const SizedBox(height: 14),
                              Text(c.$1),
                              const SizedBox(height: 5),
                              Text(
                                c.$2,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
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
