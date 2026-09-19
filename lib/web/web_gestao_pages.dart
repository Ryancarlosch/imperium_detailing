import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_gestao_service.dart';
import '../services/web_cloud_operacional_service.dart';
import 'imperium_web_theme.dart';

class WebNovaOrdemPage extends StatefulWidget {
  const WebNovaOrdemPage({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<WebNovaOrdemPage> createState() => _WebNovaOrdemPageState();
}

class _WebNovaOrdemPageState extends State<WebNovaOrdemPage> {
  final _gestao = WebCloudGestaoService.instance;
  final _operacional = WebCloudOperacionalService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _responsavel = TextEditingController();
  final _observacoes = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  List<Map<String, dynamic>> _clientes = const [];
  List<Map<String, dynamic>> _veiculos = const [];
  String? _clienteId;
  String? _veiculoId;

  final List<_ItemOsDraft> _itens = [_ItemOsDraft()];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _responsavel.dispose();
    _observacoes.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _operacional.listarClientes(),
        _operacional.listarVeiculos(),
      ]);

      final clientes = resultados[0]
          .where((item) => item['ativo'] != false)
          .toList();

      if (!mounted) return;

      setState(() {
        _clientes = clientes;
        _veiculos = resultados[1];
        _clienteId = clientes.isEmpty ? null : clientes.first['id'].toString();
        _ajustarVeiculo();
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _ajustarVeiculo() {
    final disponiveis = _veiculos
        .where((item) => item['cliente_id'].toString() == _clienteId)
        .toList();

    if (_veiculoId == null ||
        !disponiveis.any((item) => item['id'].toString() == _veiculoId)) {
      _veiculoId = disponiveis.isEmpty
          ? null
          : disponiveis.first['id'].toString();
    }
  }

  List<Map<String, dynamic>> get _veiculosDoCliente {
    return _veiculos
        .where((item) => item['cliente_id'].toString() == _clienteId)
        .toList();
  }

  void _adicionarItem() {
    setState(() => _itens.add(_ItemOsDraft()));
  }

  void _removerItem(int indice) {
    if (_itens.length == 1) return;
    final removido = _itens.removeAt(indice);
    removido.dispose();
    setState(() {});
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    if (_clienteId == null) {
      setState(() => _erro = 'Selecione um cliente.');
      return;
    }

    final itens = <Map<String, Object?>>[];

    for (final item in _itens) {
      final servico = item.servico.text.trim();
      final quantidade = _double(item.quantidade.text);
      final valor = _double(item.valor.text);

      if (servico.isEmpty || quantidade <= 0 || valor < 0) {
        setState(() {
          _erro = 'Preencha serviço, quantidade e valor de todos os itens.';
        });
        return;
      }

      itens.add(<String, Object?>{
        'servico': servico,
        'descricao': item.descricao.text.trim(),
        'quantidade': quantidade,
        'valor_unitario': valor,
      });
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      final numero = await _gestao.criarOrdemAberta(
        clienteId: _clienteId!,
        veiculoId: _veiculoId,
        funcionarioResponsavel: _responsavel.text,
        observacoes: _observacoes.text,
        itens: itens,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OS $numero criada na nuvem. O Android importará no próximo sync.',
          ),
        ),
      );

      for (final item in _itens) {
        item.dispose();
      }
      _itens
        ..clear()
        ..add(_ItemOsDraft());

      _responsavel.clear();
      _observacoes.clear();
      widget.onCreated();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  double get _totalPrevisto {
    return _itens.fold<double>(0, (total, item) {
      return total + (_double(item.quantidade.text) * _double(item.valor.text));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final desktop = constraints.maxWidth >= 1040;
        final padding = compacto ? 16.0 : 24.0;
        final largura = constraints.maxWidth - (padding * 2);

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            compacto ? 18 : 24,
            padding,
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
                        'Nova ordem de serviço',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Abra a OS na nuvem e organize cliente, veículo, responsável e serviços antes da execução.',
                        style: TextStyle(color: Color(0xFFAAB3BD)),
                      ),
                    ],
                  ),
                ),
                if (!compacto) ...[
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ImperiumWebTheme.accentStrong.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: ImperiumWebTheme.accentStrong.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          size: 17,
                          color: ImperiumWebTheme.accentStrong,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Cloud',
                          style: TextStyle(
                            color: ImperiumWebTheme.accentStrong,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _erro!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_clientes.isEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 34,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.person_off_outlined,
                        size: 42,
                        color: Color(0xFF89939E),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhum cliente ativo encontrado',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Cadastre um cliente antes de abrir uma ordem de serviço.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFAAB3BD)),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (desktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _dadosOsCard(),
                          const SizedBox(height: 16),
                          _servicosCard(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(width: 310, child: _resumoCard()),
                  ],
                )
              else ...[
                _dadosOsCard(),
                const SizedBox(height: 16),
                _servicosCard(),
                const SizedBox(height: 16),
                _resumoCard(width: largura),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _dadosOsCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_ind_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Dados da OS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final ladoALado = constraints.maxWidth >= 680;
                final cliente = DropdownButtonFormField<String>(
                  initialValue: _clienteId,
                  decoration: const InputDecoration(
                    labelText: 'Cliente *',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: _clientes
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text(
                            (item['nome'] ?? 'Cliente').toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) {
                    setState(() {
                      _clienteId = valor;
                      _ajustarVeiculo();
                    });
                  },
                );
                final veiculo = DropdownButtonFormField<String>(
                  key: ValueKey(_clienteId),
                  initialValue: _veiculoId,
                  decoration: const InputDecoration(
                    labelText: 'Veículo',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                  items: _veiculosDoCliente
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text(
                            '${item['marca'] ?? ''} ${item['modelo'] ?? ''} '
                                    '${item['placa'] ?? ''}'
                                .trim(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => setState(() => _veiculoId = valor),
                );

                if (!ladoALado) {
                  return Column(
                    children: [cliente, const SizedBox(height: 12), veiculo],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: cliente),
                    const SizedBox(width: 12),
                    Expanded(child: veiculo),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _responsavel,
              decoration: const InputDecoration(
                labelText: 'Responsável pela execução',
                prefixIcon: Icon(Icons.badge_outlined),
                helperText:
                    'A OS mostra apenas quem executa o serviço, sem custo/hora.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacoes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observações',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _servicosCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Serviços',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Adicione todos os serviços que farão parte desta OS.',
                        style: TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _adicionarItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar serviço'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...List.generate(_itens.length, (indice) {
              final item = _itens[indice];
              final subtotal =
                  _double(item.quantidade.text) * _double(item.valor.text);

              return Container(
                margin: EdgeInsets.only(
                  bottom: indice == _itens.length - 1 ? 0 : 12,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: ImperiumWebTheme.border),
                  borderRadius: BorderRadius.circular(12),
                  color: ImperiumWebTheme.surface,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: ImperiumWebTheme.accentStrong
                              .withValues(alpha: 0.10),
                          child: Text(
                            '${indice + 1}',
                            style: const TextStyle(
                              color: ImperiumWebTheme.accentStrong,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            item.servico.text.trim().isEmpty
                                ? 'Serviço ${indice + 1}'
                                : item.servico.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (subtotal > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              _moeda.format(subtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Remover serviço',
                          onPressed: _itens.length == 1
                              ? null
                              : () => _removerItem(indice),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: item.servico,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Serviço *',
                        prefixIcon: Icon(Icons.design_services_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: item.descricao,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        prefixIcon: Icon(Icons.subject_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final ladoALado = constraints.maxWidth >= 520;
                        final quantidade = TextField(
                          controller: item.quantidade,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantidade *',
                            prefixIcon: Icon(Icons.numbers_rounded),
                          ),
                        );
                        final valor = TextField(
                          controller: item.valor,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor unitário *',
                            prefixText: 'R\$ ',
                          ),
                        );

                        if (!ladoALado) {
                          return Column(
                            children: [
                              quantidade,
                              const SizedBox(height: 10),
                              valor,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: quantidade),
                            const SizedBox(width: 12),
                            Expanded(child: valor),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _resumoCard({double? width}) {
    final total = _totalPrevisto;

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resumo da OS',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              _linhaResumo('Cliente', _nomeClienteSelecionado()),
              const SizedBox(height: 8),
              _linhaResumo('Serviços', '${_itens.length}'),
              const SizedBox(height: 8),
              _linhaResumo(
                'Valor previsto',
                _moeda.format(total),
                destaque: true,
              ),
              const Divider(height: 28),
              const Text(
                'O valor final ainda poderá receber descontos, acréscimos e condições de pagamento no fluxo de edição/finalização.',
                style: TextStyle(color: Color(0xFF89939E), fontSize: 12),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Criar OS aberta'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nomeClienteSelecionado() {
    for (final cliente in _clientes) {
      if (cliente['id'].toString() == _clienteId) {
        final nome = (cliente['nome'] ?? '').toString().trim();
        return nome.isEmpty ? 'Cliente' : nome;
      }
    }
    return '—';
  }

  Widget _linhaResumo(String titulo, String valor, {bool destaque = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(titulo, style: const TextStyle(color: Color(0xFFAAB3BD))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.w900 : FontWeight.w800,
              fontSize: destaque ? 18 : 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemOsDraft {
  final servico = TextEditingController();
  final descricao = TextEditingController();
  final quantidade = TextEditingController(text: '1');
  final valor = TextEditingController();

  void dispose() {
    servico.dispose();
    descricao.dispose();
    quantidade.dispose();
    valor.dispose();
  }
}

class WebEstoquePage extends StatelessWidget {
  WebEstoquePage({super.key});

  final _service = WebCloudGestaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        _service.resumoEstoque(),
        _service.listarItensEstoque(),
        _service.listarAlertasEstoque(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErroGestao(snapshot.error.toString());
        }

        final resumo = snapshot.data![0] as Map<String, Object?>;
        final itens = snapshot.data![1] as List<Map<String, dynamic>>;
        final alertas = snapshot.data![2] as List<Map<String, dynamic>>;

        itens.sort((a, b) {
          final aBaixo =
              _double(a['quantidade']) <= _double(a['quantidade_minima']);
          final bBaixo =
              _double(b['quantidade']) <= _double(b['quantidade_minima']);

          if (aBaixo != bBaixo) return aBaixo ? -1 : 1;
          return '${a['nome']}'.compareTo('${b['nome']}');
        });

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Estoque Cloud',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CardNumero('Itens ativos', '${resumo['itens']}'),
                _CardNumero('Abaixo do mínimo', '${resumo['abaixo_minimo']}'),
                _CardNumero('Alertas ativos', '${resumo['alertas_ativos']}'),
                _CardNumero(
                  'Valor estimado',
                  _moeda.format(_double(resumo['valor_estoque'])),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (alertas.any(
              (item) =>
                  (item['status'] ?? 'Ativo').toString().toLowerCase() ==
                  'ativo',
            )) ...[
              const Text(
                'Alertas',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...alertas
                  .where(
                    (item) =>
                        (item['status'] ?? 'Ativo').toString().toLowerCase() ==
                        'ativo',
                  )
                  .take(10)
                  .map(
                    (item) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: Text(
                          (item['mensagem'] ?? 'Estoque baixo').toString(),
                        ),
                        subtitle: Text(
                          'Saldo ${_double(item['saldo_atual']).toStringAsFixed(2)} '
                          '· Limite ${_double(item['limite']).toStringAsFixed(2)}',
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
            ],
            const Text(
              'Itens',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...itens.map((item) {
              final quantidade = _double(item['quantidade']);
              final minimo = _double(item['quantidade_minima']);
              final baixo = minimo > 0 && quantidade <= minimo;

              return Card(
                child: ListTile(
                  leading: Icon(
                    baixo
                        ? Icons.inventory_2_outlined
                        : Icons.inventory_2_rounded,
                  ),
                  title: Text((item['nome'] ?? 'Item').toString()),
                  subtitle: Text(
                    [
                      (item['categoria'] ?? '').toString(),
                      'Saldo ${quantidade.toStringAsFixed(2)} '
                          '${item['unidade'] ?? ''}',
                      if (minimo > 0) 'Mínimo ${minimo.toStringAsFixed(2)}',
                    ].where((e) => e.trim().isNotEmpty).join(' · '),
                  ),
                  trailing: baixo ? const Chip(label: Text('Baixo')) : null,
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class WebFinanceiroPage extends StatelessWidget {
  WebFinanceiroPage({super.key});

  final _service = WebCloudGestaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        _service.resumoFinanceiro(),
        _service.listarContasFinanceiras(),
        _service.listarMovimentosFinanceiros(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErroGestao(snapshot.error.toString());
        }

        final resumo = snapshot.data![0] as Map<String, Object?>;
        final contas = snapshot.data![1] as List<Map<String, dynamic>>;
        final movimentos = snapshot.data![2] as List<Map<String, dynamic>>;
        final saldos = resumo['saldos'] as Map<String, double>? ?? const {};

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Financeiro Cloud',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Visão gerencial online. Lançamentos continuam no fluxo '
              'transacional Android até o contrato Web de escrita ser fechado.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _CardNumero(
                  'Saldo total',
                  _moeda.format(_double(resumo['saldo_total'])),
                ),
                _CardNumero(
                  'Entradas do mês',
                  _moeda.format(_double(resumo['entradas_mes'])),
                ),
                _CardNumero(
                  'Saídas do mês',
                  _moeda.format(_double(resumo['saidas_mes'])),
                ),
                _CardNumero(
                  'Resultado caixa',
                  _moeda.format(_double(resumo['resultado_caixa_mes'])),
                ),
                _CardNumero(
                  'A receber',
                  _moeda.format(_double(resumo['a_receber'])),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Contas',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...contas.map(
              (conta) => Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text((conta['nome'] ?? 'Conta').toString()),
                  subtitle: Text(
                    [
                      (conta['tipo'] ?? '').toString(),
                      (conta['instituicao'] ?? '').toString(),
                    ].where((e) => e.trim().isNotEmpty).join(' · '),
                  ),
                  trailing: Text(
                    _moeda.format(
                      saldos[conta['id'].toString()] ??
                          _double(conta['saldo_inicial']),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Movimentos recentes',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...movimentos
                .take(30)
                .map(
                  (mov) => Card(
                    child: ListTile(
                      leading: Icon(
                        _entrada(mov['tipo'])
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                      ),
                      title: Text((mov['descricao'] ?? 'Movimento').toString()),
                      subtitle: Text(
                        [
                          (mov['data'] ?? '').toString(),
                          (mov['status'] ?? '').toString(),
                          (mov['forma_pagamento'] ?? '').toString(),
                        ].where((e) => e.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        _moeda.format(_double(mov['valor'])),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _CardNumero extends StatelessWidget {
  const _CardNumero(this.titulo, this.valor);

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo),
              const SizedBox(height: 6),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 22,
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

class _ErroGestao extends StatelessWidget {
  const _ErroGestao(this.texto);

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

bool _entrada(dynamic tipo) {
  final texto = tipo?.toString().toLowerCase() ?? '';
  return texto.contains('entrada') || texto.contains('receita');
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
