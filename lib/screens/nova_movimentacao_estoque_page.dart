import 'package:flutter/material.dart';

import '../models/item_estoque.dart';
import '../models/movimentacao_estoque.dart';
import '../repositories/estoque_repository.dart';

class NovaMovimentacaoEstoquePage extends StatefulWidget {
  const NovaMovimentacaoEstoquePage({super.key, required this.itens});

  final List<ItemEstoque> itens;

  @override
  State<NovaMovimentacaoEstoquePage> createState() =>
      _NovaMovimentacaoEstoquePageState();
}

class _NovaMovimentacaoEstoquePageState
    extends State<NovaMovimentacaoEstoquePage> {
  final EstoqueRepository _repository = EstoqueRepository();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _quantidadeController = TextEditingController();

  final TextEditingController _observacaoController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  final TextEditingController _valorTotalPagoController =
      TextEditingController();
  final TextEditingController _fornecedorController = TextEditingController();

  String _unidadeCompra = 'unidade';

  int? _itemIdSelecionado;
  String _tipoSelecionado = 'ENTRADA';

  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    if (widget.itens.isNotEmpty) {
      _itemIdSelecionado = widget.itens.first.id;
    }
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    _observacaoController.dispose();
    _motivoController.dispose();
    _valorTotalPagoController.dispose();
    _fornecedorController.dispose();
    super.dispose();
  }

  ItemEstoque? get _itemSelecionado {
    final itemId = _itemIdSelecionado;

    if (itemId == null) {
      return null;
    }

    for (final item in widget.itens) {
      if (item.id == itemId) {
        return item;
      }
    }

    return null;
  }

  double? _lerQuantidade() {
    final texto = _quantidadeController.text.trim().replaceAll(',', '.');

    return double.tryParse(texto);
  }

  String _numero(double valor) {
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<void> _salvar() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final item = _itemSelecionado;
    final quantidade = _lerQuantidade();

    if (item == null || item.id == null) {
      _mostrarMensagem('Selecione um produto válido.', erro: true);

      return;
    }

    if (quantidade == null) {
      _mostrarMensagem('Informe uma quantidade válida.', erro: true);

      return;
    }

    if (_tipoSelecionado == 'SAIDA' && quantidade > item.quantidade) {
      _mostrarMensagem(
        'A quantidade de saída é maior que o estoque disponível.',
        erro: true,
      );

      return;
    }

    if (_tipoSelecionado == 'AJUSTE' && _motivoController.text.trim().isEmpty) {
      _mostrarMensagem('Informe o motivo do ajuste manual.', erro: true);

      return;
    }

    if (_tipoSelecionado == 'ENTRADA') {
      final valorPago = double.tryParse(
        _valorTotalPagoController.text.trim().replaceAll(',', '.'),
      );

      if (valorPago == null || valorPago <= 0) {
        _mostrarMensagem('Informe o valor total pago da compra.', erro: true);

        return;
      }
    }

    setState(() {
      _salvando = true;
    });

    try {
      if (_tipoSelecionado == 'ENTRADA') {
        final valorPago =
            double.tryParse(
              _valorTotalPagoController.text.trim().replaceAll(',', '.'),
            ) ??
            0;

        await _repository.adicionarEntradaEstoque(
          itemId: item.id!,
          valorTotalPago: valorPago,
          quantidadeTotal: quantidade,
          unidadeInformada: _unidadeCompra,
          fornecedor: _fornecedorController.text.trim(),
          observacao: _observacaoController.text.trim(),
        );
      } else {
        final movimentacao = MovimentacaoEstoque(
          itemId: item.id!,
          tipo: _tipoSelecionado,
          quantidade: quantidade,
          motivo: _motivoController.text.trim(),
          observacao: _observacaoController.text.trim(),
          data: DateTime.now().toIso8601String(),
        );

        await _repository.registrarMovimentacao(movimentacao);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem('Erro ao registrar movimentação: $erro', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _itemSelecionado;

    return Scaffold(
      appBar: AppBar(title: const Text('Nova movimentação de estoque')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _itemIdSelecionado,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Produto',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: widget.itens
                            .where((item) => item.id != null)
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item.id!,
                                child: Text(
                                  item.nome,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _salvando
                            ? null
                            : (valor) {
                                setState(() {
                                  _itemIdSelecionado = valor;
                                });
                              },
                        validator: (valor) {
                          if (valor == null) {
                            return 'Selecione um produto.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _tipoSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de movimentação',
                          prefixIcon: Icon(Icons.swap_vert_rounded),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem<String>(
                            value: 'ENTRADA',
                            child: Text('Entrada'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'SAIDA',
                            child: Text('Saída'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'AJUSTE',
                            child: Text('Ajustar quantidade total'),
                          ),
                        ],
                        onChanged: _salvando
                            ? null
                            : (valor) {
                                if (valor == null) {
                                  return;
                                }

                                setState(() {
                                  _tipoSelecionado = valor;
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _quantidadeController,
                        enabled: !_salvando,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _tipoSelecionado == 'AJUSTE'
                              ? 'Nova quantidade total'
                              : _tipoSelecionado == 'ENTRADA'
                              ? 'Quantidade da embalagem'
                              : 'Quantidade',
                          prefixIcon: const Icon(Icons.numbers_rounded),
                          suffixText: _tipoSelecionado == 'ENTRADA'
                              ? _unidadeCompra
                              : item?.unidade ?? '',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (_) {
                          final quantidade = _lerQuantidade();

                          if (quantidade == null) {
                            return 'Informe a quantidade.';
                          }

                          if (quantidade < 0) {
                            return 'A quantidade não pode ser negativa.';
                          }

                          if (_tipoSelecionado != 'AJUSTE' && quantidade == 0) {
                            return 'A quantidade deve ser maior que zero.';
                          }

                          return null;
                        },
                      ),
                      if (_tipoSelecionado == 'SAIDA' && item != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Disponível: '
                            '${_numero(item.quantidade)} '
                            '${item.unidade}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_tipoSelecionado == 'AJUSTE') ...[
                        TextFormField(
                          controller: _motivoController,
                          enabled: !_salvando,
                          decoration: const InputDecoration(
                            labelText: 'Motivo do ajuste',
                            prefixIcon: Icon(Icons.rule_folder_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (valor) {
                            if (_tipoSelecionado != 'AJUSTE') {
                              return null;
                            }

                            if (valor == null || valor.trim().isEmpty) {
                              return 'Informe o motivo do ajuste.';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _observacaoController,
                        enabled: !_salvando,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Observação',
                          prefixIcon: Icon(Icons.notes_rounded),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_tipoSelecionado == 'ENTRADA') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _valorTotalPagoController,
                          enabled: !_salvando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor total pago',
                            prefixText: 'R\$ ',
                            prefixIcon: Icon(Icons.payments_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _unidadeCompra,
                          decoration: const InputDecoration(
                            labelText: 'Unidade da embalagem',
                            prefixIcon: Icon(Icons.straighten),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'ml', child: Text('ml')),
                            DropdownMenuItem(value: 'l', child: Text('L')),
                            DropdownMenuItem(value: 'g', child: Text('g')),
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(
                              value: 'metro',
                              child: Text('metro'),
                            ),
                            DropdownMenuItem(
                              value: 'unidade',
                              child: Text('unidade'),
                            ),
                          ],
                          onChanged: _salvando
                              ? null
                              : (valor) {
                                  if (valor == null) {
                                    return;
                                  }

                                  setState(() {
                                    _unidadeCompra = valor;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _fornecedorController,
                          enabled: !_salvando,
                          decoration: const InputDecoration(
                            labelText: 'Fornecedor (opcional)',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _salvando
                      ? null
                      : () {
                          Navigator.of(context).pop(false);
                        },
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
