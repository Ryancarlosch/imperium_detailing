import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../repositories/estoque_repository.dart';
import 'novo_item_estoque_page.dart';

class ItemEstoqueDetalhesPage
    extends StatefulWidget {
  const ItemEstoqueDetalhesPage({
    super.key,
    required this.itemId,
  });

  final int itemId;

  @override
  State<ItemEstoqueDetalhesPage> createState() =>
      _ItemEstoqueDetalhesPageState();
}

class _ItemEstoqueDetalhesPageState
    extends State<ItemEstoqueDetalhesPage> {
  final _repository = EstoqueRepository();

  final _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  ItemEstoque? _item;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final item = await _repository.buscarItemPorId(
      widget.itemId,
    );

    if (!mounted) return;

    setState(() {
      _item = item;
      _carregando = false;
    });
  }

  Future<void> _alterarQuantidade(
      bool entrada,
      ) async {
    final item = _item;

    if (item == null) return;

    String textoQuantidade = '';

    final quantidade = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            entrada
                ? 'Adicionar estoque'
                : 'Retirar estoque',
          ),
          content: TextField(
            autofocus: true,
            keyboardType:
            const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onChanged: (valor) {
              textoQuantidade = valor;
            },
            decoration: InputDecoration(
              labelText:
              'Quantidade (${item.unidade})',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final valor = double.tryParse(
                  textoQuantidade.replaceAll(',', '.'),
                );

                if (valor == null || valor <= 0) {
                  return;
                }

                Navigator.pop(dialogContext, valor);
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (quantidade == null) return;

    final novaQuantidade = entrada
        ? item.quantidade + quantidade
        : item.quantidade - quantidade;

    if (novaQuantidade < 0) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A retirada é maior que o estoque disponível.',
          ),
        ),
      );
      return;
    }

    await _repository.atualizarQuantidade(
      item.id!,
      novaQuantidade,
    );

    await _carregar();
  }

  Future<void> _editar() async {
    final item = _item;

    if (item == null) return;

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoItemEstoquePage(
          item: item,
        ),
      ),
    );

    if (alterou == true) {
      setState(() {
        _carregando = true;
      });
      await _carregar();
    }
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir item?'),
          content: const Text(
            'Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _repository.excluirItem(widget.itemId);

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  String _numero(double valor) {
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do estoque'),
        actions: [
          IconButton(
            onPressed: item == null ? null : _editar,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (valor) {
              if (valor == 'excluir') {
                _excluir();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'excluir',
                child: Text('Excluir item'),
              ),
            ],
          ),
        ],
      ),
      body: _carregando
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : item == null
          ? const Center(
        child: Text(
          'Item não encontrado.',
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding:
              const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    item.estoqueBaixo
                        ? Icons
                        .warning_amber_rounded
                        : Icons
                        .inventory_2_outlined,
                    size: 64,
                    color: item.estoqueBaixo
                        ? Colors.orange
                        : const Color(
                      0xFFD6A84B,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.nome,
                    textAlign:
                    TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                  if (item.categoria
                      .isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.categoria,
                      style: const TextStyle(
                        color:
                        Colors.white60,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    '${_numero(item.quantidade)} ${item.unidade}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight:
                      FontWeight.bold,
                      color: item.estoqueBaixo
                          ? Colors.orange
                          : Colors.greenAccent,
                    ),
                  ),
                  if (item.estoqueBaixo)
                    const Padding(
                      padding:
                      EdgeInsets.only(
                        top: 6,
                      ),
                      child: Text(
                        'Estoque baixo',
                        style: TextStyle(
                          color:
                          Colors.orange,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    _alterarQuantidade(
                      true,
                    );
                  },
                  icon: const Icon(
                    Icons.add,
                  ),
                  label:
                  const Text('Entrada'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                OutlinedButton.icon(
                  onPressed: () {
                    _alterarQuantidade(
                      false,
                    );
                  },
                  icon: const Icon(
                    Icons.remove,
                  ),
                  label:
                  const Text('Saída'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding:
              const EdgeInsets.all(18),
              child: Column(
                children: [
                  _Linha(
                    titulo:
                    'Estoque mínimo',
                    valor:
                    '${_numero(item.quantidadeMinima)} ${item.unidade}',
                  ),
                  _Linha(
                    titulo:
                    'Custo unitário',
                    valor: _moeda.format(
                      item.custoUnitario,
                    ),
                  ),
                  _Linha(
                    titulo:
                    'Valor em estoque',
                    valor: _moeda.format(
                      item.valorTotal,
                    ),
                  ),
                  _Linha(
                    titulo: 'Fornecedor',
                    valor: item.fornecedor
                        .isEmpty
                        ? 'Não informado'
                        : item.fornecedor,
                  ),
                ],
              ),
            ),
          ),
          if (item.observacoes
              .isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding:
                const EdgeInsets.all(
                  18,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    const Text(
                      'Observações',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      item.observacoes,
                      style: const TextStyle(
                        color:
                        Colors.white70,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.titulo,
    required this.valor,
  });

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                color: Colors.white60,
              ),
            ),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
