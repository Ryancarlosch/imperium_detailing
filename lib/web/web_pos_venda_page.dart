import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/comercial_growth_cloud_service.dart';
import 'imperium_web_theme.dart';

class WebPosVendaPage extends StatefulWidget {
  const WebPosVendaPage({super.key});

  @override
  State<WebPosVendaPage> createState() => _WebPosVendaPageState();
}

class _WebPosVendaPageState extends State<WebPosVendaPage> {
  final _service = ComercialGrowthCloudService.instance;
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _busca = TextEditingController();

  GrowthPosVendaPainel? _painel;
  bool _carregando = true;
  String? _erro;
  String _filtro = 'Ação';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final painel = await _service.carregarPosVenda();
      if (!mounted) return;
      setState(() => _painel = painel);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _configurar() async {
    final atual =
        _painel?.config ??
        const GrowthPosVendaConfig(
          ativo: true,
          diasRetorno: 90,
          diasReativacao: 180,
        );
    final retorno = TextEditingController(text: '${atual.diasRetorno}');
    final reativacao = TextEditingController(text: '${atual.diasReativacao}');

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regras do pós-venda'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Os status são calculados automaticamente a partir da última OS finalizada.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: retorno,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dias para sugerir retorno',
                  prefixIcon: Icon(Icons.update_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reativacao,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dias para entrar em reativação',
                  prefixIcon: Icon(Icons.restart_alt_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Salvar regras'),
          ),
        ],
      ),
    );

    if (salvar != true) return;

    try {
      await _service.salvarConfigPosVenda(
        diasRetorno: int.tryParse(retorno.text) ?? atual.diasRetorno,
        diasReativacao: int.tryParse(reativacao.text) ?? atual.diasReativacao,
      );
      await _carregar();
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _registrarContato(GrowthPosVendaCliente cliente) async {
    var tipo = 'WhatsApp';
    final descricao = TextEditingController();
    final resultado = TextEditingController();
    DateTime? proximoContato;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Contato · ${cliente.nome}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tipo,
                    decoration: const InputDecoration(
                      labelText: 'Canal de contato',
                    ),
                    items:
                        const [
                              'WhatsApp',
                              'Ligação',
                              'E-mail',
                              'Instagram',
                              'Presencial',
                              'Outro',
                            ]
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => tipo = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descricao,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'O que foi conversado *',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: resultado,
                    decoration: const InputDecoration(
                      labelText: 'Resultado',
                      hintText:
                          'Ex.: respondeu, pediu orçamento, agendou, sem resposta',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('Próximo contato'),
                    subtitle: Text(
                      proximoContato == null
                          ? 'Não definido'
                          : _data.format(proximoContato!),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (proximoContato != null)
                          IconButton(
                            tooltip: 'Limpar',
                            onPressed: () =>
                                setLocal(() => proximoContato = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        OutlinedButton(
                          onPressed: () async {
                            final escolhida = await showDatePicker(
                              context: context,
                              initialDate:
                                  proximoContato ??
                                  DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (escolhida != null) {
                              setLocal(() => proximoContato = escolhida);
                            }
                          },
                          child: const Text('Definir'),
                        ),
                      ],
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
                  Navigator.pop(context, descricao.text.trim().isNotEmpty),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Registrar contato'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    try {
      await _service.registrarInteracaoPosVenda(
        clienteId: cliente.id,
        ordemServicoId: cliente.ultimaOsId,
        tipo: tipo,
        descricao: descricao.text,
        resultado: resultado.text,
        proximoContato: proximoContato,
      );
      await _carregar();
      _snack('Contato registrado no pós-venda.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _historico(GrowthPosVendaCliente cliente) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico · ${cliente.nome}'),
        content: SizedBox(
          width: 680,
          height: 460,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _service.listarInteracoesPosVenda(clienteId: cliente.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(_textoErro(snapshot.error!)));
              }

              final itens = snapshot.data!;
              if (itens.isEmpty) {
                return const Center(
                  child: Text('Nenhum contato de pós-venda registrado.'),
                );
              }

              return ListView.separated(
                itemCount: itens.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = itens[index];
                  final data = _parseData(item['data_interacao']);
                  final proximo = _parseData(item['proximo_contato']);

                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.forum_outlined, size: 18),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (item['tipo'] ?? 'Contato').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (data != null)
                          Text(
                            _data.format(data),
                            style: const TextStyle(
                              color: Color(0xFF89939E),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      [
                        (item['descricao'] ?? '').toString(),
                        (item['resultado'] ?? '').toString(),
                        if (proximo != null)
                          'Próximo contato: ${_data.format(proximo)}',
                      ].where((e) => e.trim().isNotEmpty).join('\n'),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  List<GrowthPosVendaCliente> _filtrar(GrowthPosVendaPainel painel) {
    final termo = _busca.text.trim().toLowerCase();

    return painel.clientes.where((cliente) {
      if (_filtro == 'Ação' && !cliente.precisaAcao) return false;
      if (_filtro != 'Ação' &&
          _filtro != 'Todos' &&
          cliente.status != _filtro) {
        return false;
      }

      if (termo.isEmpty) return true;

      return [
        cliente.nome,
        cliente.telefone,
        cliente.email,
        cliente.ultimaOsNumero,
      ].any((v) => v.toLowerCase().contains(termo));
    }).toList();
  }

  Widget _resumoCard({
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

  Widget _status(String status) {
    final color = switch (status) {
      'Reativação' => Colors.redAccent,
      'Hora do retorno' => Colors.orangeAccent,
      'Agendado' => Colors.lightBlueAccent,
      _ => Colors.greenAccent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _acoes(GrowthPosVendaCliente cliente) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Histórico de contatos',
          onPressed: () => _historico(cliente),
          icon: const Icon(Icons.history_rounded),
        ),
        FilledButton.icon(
          onPressed: () => _registrarContato(cliente),
          icon: const Icon(Icons.forum_outlined, size: 17),
          label: const Text('Contato'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final painel = _painel;

    if (_carregando && painel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null && painel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 12),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final dados = painel!;
    final clientes = _filtrar(dados);
    final valorCarteira = dados.clientes.fold<double>(
      0,
      (total, item) => total + item.valorTotal,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 1050;
        final larguraDisponivel = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final larguraCard =
            (larguraDisponivel - (12 * (colunas - 1))) / colunas;

        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pós-venda',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Retorno em ${dados.config.diasRetorno} dias · '
                          'Reativação em ${dados.config.diasReativacao} dias',
                          style: const TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    tooltip: 'Configurar regras',
                    onPressed: _configurar,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _carregando ? null : _carregar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Precisam de ação',
                    valor: '${dados.precisamAcao}',
                    detalhe: 'Clientes em retorno ou reativação',
                    icone: Icons.campaign_outlined,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Hora do retorno',
                    valor: '${dados.retorno}',
                    detalhe: 'Atingiram o prazo normal de retorno',
                    icone: Icons.update_rounded,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Reativação',
                    valor: '${dados.reativacao}',
                    detalhe: 'Passaram do prazo de reativação',
                    icone: Icons.restart_alt_rounded,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Valor da carteira',
                    valor: _moeda.format(valorCarteira),
                    detalhe: 'Total histórico das OS desses clientes',
                    icone: Icons.payments_outlined,
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
                        width: compacto ? larguraDisponivel - 28 : 390,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText:
                                'Buscar cliente, telefone, e-mail ou última OS',
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
                          ButtonSegment(value: 'Ação', label: Text('Ação')),
                          ButtonSegment(value: 'Todos', label: Text('Todos')),
                          ButtonSegment(
                            value: 'Hora do retorno',
                            label: Text('Retorno'),
                          ),
                          ButtonSegment(
                            value: 'Reativação',
                            label: Text('Reativação'),
                          ),
                          ButtonSegment(
                            value: 'Agendado',
                            label: Text('Agendados'),
                          ),
                          ButtonSegment(value: 'Em dia', label: Text('Em dia')),
                        ],
                        selected: <String>{_filtro},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) {
                          setState(() => _filtro = value.first);
                        },
                      ),
                      Text(
                        '${clientes.length} resultado(s)',
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
              if (clientes.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.replay_circle_filled_outlined,
                          size: 42,
                          color: Color(0xFF89939E),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nenhum cliente neste filtro',
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
                      dataRowMinHeight: 64,
                      dataRowMaxHeight: 82,
                      columns: const [
                        DataColumn(label: Text('CLIENTE')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('ÚLTIMA VISITA')),
                        DataColumn(label: Text('DIAS SEM RETORNO')),
                        DataColumn(label: Text('HISTÓRICO')),
                        DataColumn(label: Text('PRÓXIMO CONTATO')),
                        DataColumn(label: Text('AÇÕES')),
                      ],
                      rows: clientes.map((cliente) {
                        final ultima = cliente.ultimaVisita == null
                            ? '—'
                            : _data.format(cliente.ultimaVisita!);
                        final proximo = cliente.proximoContato == null
                            ? '—'
                            : _data.format(cliente.proximoContato!);

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 240,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cliente.nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      [cliente.telefone, cliente.email]
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
                            DataCell(_status(cliente.status)),
                            DataCell(
                              Text(
                                cliente.ultimaOsNumero.isEmpty
                                    ? ultima
                                    : 'OS ${cliente.ultimaOsNumero} · $ultima',
                              ),
                            ),
                            DataCell(
                              Text(
                                '${cliente.diasSemRetorno} dias',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${cliente.quantidadeOs} OS · '
                                '${_moeda.format(cliente.valorTotal)}',
                              ),
                            ),
                            DataCell(Text(proximo)),
                            DataCell(_acoes(cliente)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                ...clientes.map(
                  (cliente) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  child: Text(
                                    cliente.nome.trim().isEmpty
                                        ? '?'
                                        : cliente.nome.trim()[0].toUpperCase(),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cliente.nome,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${cliente.diasSemRetorno} dias sem retorno · '
                                        '${cliente.quantidadeOs} OS · '
                                        '${_moeda.format(cliente.valorTotal)}',
                                        style: const TextStyle(
                                          color: Color(0xFFAAB3BD),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _status(cliente.status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _acoes(cliente),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _snack(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static DateTime? _parseData(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
