import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_gestao_service.dart';
import '../services/web_cloud_operacional_service.dart';

class WebNovaOrdemPage extends StatefulWidget {
  const WebNovaOrdemPage({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<WebNovaOrdemPage> createState() => _WebNovaOrdemPageState();
}

class _WebNovaOrdemPageState extends State<WebNovaOrdemPage> {
  final _gestao = WebCloudGestaoService.instance;
  final _operacional = WebCloudOperacionalService.instance;
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

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Nova ordem de serviço',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cria uma OS aberta na nuvem. O Android a importa no próximo ciclo '
          'de sincronização, preservando o fluxo transacional de finalização.',
        ),
        const SizedBox(height: 22),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              _erro!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _clienteId,
                  decoration: const InputDecoration(labelText: 'Cliente *'),
                  items: _clientes
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text((item['nome'] ?? 'Cliente').toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) {
                    setState(() {
                      _clienteId = valor;
                      _ajustarVeiculo();
                    });
                  },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_clienteId),
                  initialValue: _veiculoId,
                  decoration: const InputDecoration(labelText: 'Veículo'),
                  items: _veiculosDoCliente
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text(
                            '${item['marca'] ?? ''} ${item['modelo'] ?? ''} '
                                    '${item['placa'] ?? ''}'
                                .trim(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => setState(() => _veiculoId = valor),
                ),
                TextField(
                  controller: _responsavel,
                  decoration: const InputDecoration(labelText: 'Responsável'),
                ),
                TextField(
                  controller: _observacoes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Serviços',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _adicionarItem,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar serviço'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(_itens.length, (indice) {
          final item = _itens[indice];

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Serviço ${indice + 1}')),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: _itens.length == 1
                            ? null
                            : () => _removerItem(indice),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  TextField(
                    controller: item.servico,
                    decoration: const InputDecoration(labelText: 'Serviço *'),
                  ),
                  TextField(
                    controller: item.descricao,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: item.quantidade,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantidade *',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: item.valor,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor unitário *',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
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
