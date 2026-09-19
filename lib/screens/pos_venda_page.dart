import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/comercial_growth_cloud_service.dart';

class PosVendaPage extends StatefulWidget {
  const PosVendaPage({super.key});

  @override
  State<PosVendaPage> createState() => _PosVendaPageState();
}

class _PosVendaPageState extends State<PosVendaPage> {
  final _service = ComercialGrowthCloudService.instance;
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  GrowthPosVendaPainel? _painel;
  bool _carregando = true;
  String? _erro;
  String _filtro = 'Ação';

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
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'O status é calculado automaticamente a partir da última OS finalizada.',
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
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
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: tipo,
                    decoration: const InputDecoration(labelText: 'Canal'),
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
                    minLines: 2,
                    maxLines: 4,
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
                      hintText: 'Ex.: respondeu, pediu orçamento, sem resposta',
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
                    trailing: OutlinedButton(
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
              label: const Text('Registrar'),
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
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico · ${cliente.nome}'),
        content: SizedBox(
          width: 560,
          height: 400,
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
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = itens[index];
                  final data = _parseData(item['data_interacao']);
                  final proximo = _parseData(item['proximo_contato']);
                  return ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text((item['tipo'] ?? 'Contato').toString()),
                    subtitle: Text(
                      [
                        (item['descricao'] ?? '').toString(),
                        (item['resultado'] ?? '').toString(),
                        if (data != null) 'Em ${_data.format(data)}',
                        if (proximo != null)
                          'Próximo: ${_data.format(proximo)}',
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

  @override
  Widget build(BuildContext context) {
    final painel = _painel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pós-venda'),
        actions: [
          IconButton(
            tooltip: 'Configurar regras',
            onPressed: painel == null ? null : _configurar,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando && painel == null
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && painel == null
          ? _ErroPosVenda(mensagem: _erro!, onTentar: _carregar)
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                children: [
                  _cabecalho(painel!),
                  const SizedBox(height: 14),
                  _resumo(painel),
                  const SizedBox(height: 14),
                  _filtros(),
                  const SizedBox(height: 10),
                  ..._clientesFiltrados(painel).map(_clienteCard),
                ],
              ),
            ),
    );
  }

  Widget _cabecalho(GrowthPosVendaPainel painel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: Color(0x22D6A84B),
              child: Icon(Icons.replay_circle_filled_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Retenção de clientes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Retorno em ${painel.config.diasRetorno} dias · '
                    'Reativação em ${painel.config.diasReativacao} dias',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumo(GrowthPosVendaPainel painel) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ResumoChip('Precisam de ação', painel.precisamAcao, Icons.campaign),
        _ResumoChip('Retorno', painel.retorno, Icons.update_rounded),
        _ResumoChip('Reativação', painel.reativacao, Icons.restart_alt_rounded),
        _ResumoChip('Agendados', painel.agendados, Icons.event_available),
      ],
    );
  }

  Widget _filtros() {
    const itens = <String>[
      'Ação',
      'Todos',
      'Hora do retorno',
      'Reativação',
      'Em dia',
      'Agendado',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: itens
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: _filtro == item,
                  label: Text(item),
                  onSelected: (_) => setState(() => _filtro = item),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  List<GrowthPosVendaCliente> _clientesFiltrados(GrowthPosVendaPainel painel) {
    if (_filtro == 'Todos') return painel.clientes;
    if (_filtro == 'Ação') {
      return painel.clientes.where((e) => e.precisaAcao).toList();
    }
    return painel.clientes.where((e) => e.status == _filtro).toList();
  }

  Widget _clienteCard(GrowthPosVendaCliente cliente) {
    final ultima = cliente.ultimaVisita == null
        ? 'Sem data'
        : _data.format(cliente.ultimaVisita!);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nome,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (cliente.ultimaOsNumero.isNotEmpty)
                            'OS ${cliente.ultimaOsNumero}',
                          'Última visita $ultima',
                          '${cliente.diasSemRetorno} dias',
                        ].join(' · '),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPosVenda(cliente.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${cliente.quantidadeOs} OS · ${_moeda.format(cliente.valorTotal)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
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
            ),
          ],
        ),
      ),
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

class _ResumoChip extends StatelessWidget {
  const _ResumoChip(this.titulo, this.valor, this.icone);

  final String titulo;
  final int valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icone, size: 17), label: Text('$titulo: $valor'));
  }
}

class _StatusPosVenda extends StatelessWidget {
  const _StatusPosVenda(this.status);

  final String status;

  Color _cor() {
    return switch (status) {
      'Reativação' => Colors.redAccent,
      'Hora do retorno' => Colors.orangeAccent,
      'Agendado' => Colors.lightBlueAccent,
      _ => Colors.greenAccent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cor = _cor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.45)),
      ),
      child: Text(
        status,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErroPosVenda extends StatelessWidget {
  const _ErroPosVenda({required this.mensagem, required this.onTentar});

  final String mensagem;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onTentar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
