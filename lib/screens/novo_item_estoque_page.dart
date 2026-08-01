import 'package:flutter/material.dart';

import '../models/item_estoque.dart';
import '../repositories/estoque_repository.dart';

class NovoItemEstoquePage extends StatefulWidget {
  const NovoItemEstoquePage({super.key, this.item});

  final ItemEstoque? item;

  @override
  State<NovoItemEstoquePage> createState() => _NovoItemEstoquePageState();
}

class _NovoItemEstoquePageState extends State<NovoItemEstoquePage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = EstoqueRepository();

  late final TextEditingController _nomeController;
  late final TextEditingController _categoriaController;
  late final TextEditingController _quantidadeController;
  late final TextEditingController _quantidadeMinimaController;
  late final TextEditingController _custoController;
  late final TextEditingController _fornecedorController;
  late final TextEditingController _observacoesController;

  String _unidade = 'un';
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    _nomeController = TextEditingController(text: item?.nome ?? '');

    _categoriaController = TextEditingController(text: item?.categoria ?? '');

    _quantidadeController = TextEditingController(
      text: item == null ? '' : _formatarNumero(item.quantidade),
    );

    _quantidadeMinimaController = TextEditingController(
      text: item == null ? '' : _formatarNumero(item.quantidadeMinima),
    );

    _custoController = TextEditingController(
      text: item == null
          ? ''
          : item.custoUnitario.toStringAsFixed(2).replaceAll('.', ','),
    );

    _fornecedorController = TextEditingController(text: item?.fornecedor ?? '');

    _observacoesController = TextEditingController(
      text: item?.observacoes ?? '',
    );

    _unidade = item?.unidade ?? 'un';
  }

  String _formatarNumero(double valor) {
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _lerNumero(String texto) {
    return double.tryParse(texto.trim().replaceAll(',', '.'));
  }

  bool get _unidadeAceitaDecimal {
    return _unidade != 'un';
  }

  bool _numeroEhInteiro(double valor) {
    return valor == valor.truncateToDouble();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _categoriaController.dispose();
    _quantidadeController.dispose();
    _quantidadeMinimaController.dispose();
    _custoController.dispose();
    _fornecedorController.dispose();
    _observacoesController.dispose();

    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) {
      return;
    }

    final formularioValido = _formKey.currentState?.validate() ?? false;

    if (!formularioValido) {
      return;
    }

    final nome = _nomeController.text.trim();

    final itemExistente = await _repository.buscarItemPorNome(nome);

    if (itemExistente != null && itemExistente.id != widget.item?.id) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Já existe um produto com este nome.')),
      );

      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final item = ItemEstoque(
        id: widget.item?.id,
        nome: nome,
        categoria: _categoriaController.text.trim(),
        quantidade: _lerNumero(_quantidadeController.text) ?? 0,
        quantidadeMinima: _lerNumero(_quantidadeMinimaController.text) ?? 0,
        unidade: _unidade,
        custoUnitario: _lerNumero(_custoController.text) ?? 0,
        fornecedor: _fornecedorController.text.trim(),
        observacoes: _observacoesController.text.trim(),
        atualizadoEm: DateTime.now().toIso8601String(),
      );

      if (widget.item == null) {
        await _repository.inserirItem(item);
      } else {
        await _repository.atualizarItem(item);
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (erro, stackTrace) {
      debugPrint('==============================');
      debugPrint('ERRO AO SALVAR ESTOQUE');
      debugPrint(erro.toString());
      debugPrint(stackTrace.toString());
      debugPrint('==============================');

      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar o item:\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String? _validarNumero(String? valor, {required String campo}) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Informe $campo.';
    }

    final numero = _lerNumero(valor);

    if (numero == null || numero < 0) {
      return 'Informe um valor válido.';
    }

    if (!_unidadeAceitaDecimal && !_numeroEhInteiro(numero)) {
      return 'Para unidade, informe valor inteiro.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editando ? 'Editar item' : 'Novo item'),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('SALVAR'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome do produto',
                hintText: 'Ex.: Shampoo automotivo',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Informe o nome.';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _categoriaController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                hintText: 'Ex.: Limpeza, Polimento',
                prefixIcon: Icon(Icons.category_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                    validator: (valor) =>
                        _validarNumero(valor, campo: 'a quantidade'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unidade,
                    decoration: const InputDecoration(
                      labelText: 'Unidade',
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'un', child: Text('Unidade')),
                      DropdownMenuItem(value: 'L', child: Text('Litro')),
                      DropdownMenuItem(value: 'ml', child: Text('Mililitro')),
                      DropdownMenuItem(value: 'kg', child: Text('Quilograma')),
                      DropdownMenuItem(value: 'g', child: Text('Grama')),
                      DropdownMenuItem(value: 'm', child: Text('Metro')),
                    ],
                    onChanged: (valor) {
                      if (valor == null) {
                        return;
                      }

                      setState(() {
                        _unidade = valor;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantidadeMinimaController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Estoque mínimo',
                hintText: 'Avisar quando chegar neste valor',
                prefixIcon: Icon(Icons.warning_amber_rounded),
              ),
              validator: (valor) =>
                  _validarNumero(valor, campo: 'o estoque mínimo'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _custoController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Custo unitário',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.attach_money),
              ),
              validator: (valor) =>
                  _validarNumero(valor, campo: 'o custo unitário'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _fornecedorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Fornecedor',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _observacoesController,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_salvando ? 'Salvando...' : 'Salvar item'),
            ),
          ],
        ),
      ),
    );
  }
}
