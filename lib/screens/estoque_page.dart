import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../repositories/estoque_repository.dart';
import 'item_estoque_detalhes_page.dart';
import 'novo_item_estoque_page.dart';

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() =>
      _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final _repository = EstoqueRepository();
  final _pesquisaController =
      TextEditingController();

  final _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  List<ItemEstoque> _itens = [];
  bool _carregando = true;
  bool _somenteBaixo = false;
  String _pesquisa = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final itens =
          await _repository.listarItens();

      if (!mounted) return;

      setState(() {
        _itens = itens;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar o estoque: $erro',
          ),
        ),
      );
    }
  }

  List<ItemEstoque> get _itensFiltrados {
    final termo = _pesquisa.trim().toLowerCase();

    return _itens.where((item) {
      final correspondePesquisa =
          termo.isEmpty ||
              [
                item.nome,
                item.categoria,
                item.fornecedor,
              ].join(' ').toLowerCase().contains(
                    termo,
                  );

      final correspondeEstoque =
          !_somenteBaixo || item.estoqueBaixo;

      return correspondePesquisa &&
          correspondeEstoque;
    }).toList();
  }

  Future<void> _adicionar() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const NovoItemEstoquePage(),
      ),
    );

    if (salvou == true) {
      setState(() {
        _carregando = true;
      });
      await _carregar();
    }
  }

  Future<void> _abrir(ItemEstoque item) async {
    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ItemEstoqueDetalhesPage(
          itemId: item.id!,
        ),
      ),
    );

    if (alterou == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Item excluído com sucesso.',
          ),
        ),
      );
    }

    setState(() {
      _carregando = true;
    });
    await _carregar();
  }

  String _numero(double valor) {
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _itensFiltrados;

    final valorTotal = _itens.fold<double>(
      0,
      (total, item) => total + item.valorTotal,
    );

    final baixos = _itens
        .where((item) => item.estoqueBaixo)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de estoque'),
        actions: [
          IconButton(
            onPressed:
                _carregando ? null : _carregar,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  90,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Resumo(
                          titulo: 'Itens',
                          valor:
                              _itens.length.toString(),
                          icone: Icons
                              .inventory_2_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Resumo(
                          titulo: 'Estoque baixo',
                          valor: baixos.toString(),
                          icone: Icons
                              .warning_amber_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons
                                .account_balance_wallet_outlined,
                            color:
                                Color(0xFFD6A84B),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Valor total em estoque',
                            ),
                          ),
                          Text(
                            _moeda.format(valorTotal),
                            style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pesquisaController,
                    onChanged: (valor) {
                      setState(() {
                        _pesquisa = valor;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText:
                          'Pesquisar produto ou categoria',
                      prefixIcon:
                          Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilterChip(
                    selected: _somenteBaixo,
                    label: const Text(
                      'Mostrar somente estoque baixo',
                    ),
                    avatar: const Icon(
                      Icons.warning_amber_rounded,
                    ),
                    onSelected: (selecionado) {
                      setState(() {
                        _somenteBaixo =
                            selecionado;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (filtrados.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(
                        vertical: 60,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons
                                .inventory_2_outlined,
                            size: 72,
                            color: Colors.white30,
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Nenhum item encontrado',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtrados.map(
                      (item) => Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 10,
                        ),
                        child: Card(
                          child: ListTile(
                            onTap: () =>
                                _abrir(item),
                            leading: CircleAvatar(
                              backgroundColor:
                                  (item.estoqueBaixo
                                          ? Colors
                                              .orange
                                          : const Color(
                                              0xFFD6A84B,
                                            ))
                                      .withValues(
                                alpha: 0.15,
                              ),
                              child: Icon(
                                item.estoqueBaixo
                                    ? Icons
                                        .warning_amber_rounded
                                    : Icons
                                        .inventory_2_outlined,
                                color:
                                    item.estoqueBaixo
                                        ? Colors
                                            .orange
                                        : const Color(
                                            0xFFD6A84B,
                                          ),
                              ),
                            ),
                            title: Text(
                              item.nome,
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${_numero(item.quantidade)} '
                              '${item.unidade}'
                              '${item.categoria.isEmpty ? '' : ' • ${item.categoria}'}',
                            ),
                            trailing: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .end,
                              children: [
                                Text(
                                  _moeda.format(
                                    item.valorTotal,
                                  ),
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 19,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: _adicionar,
        icon: const Icon(Icons.add),
        label: const Text('Novo item'),
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(
              icone,
              color: const Color(0xFFD6A84B),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
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
