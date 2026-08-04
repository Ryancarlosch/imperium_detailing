import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  late final TextEditingController _nomeController;
  late final TextEditingController _categoriaController;
  late final TextEditingController _valorTotalController;
  late final TextEditingController _quantidadeTotalController;
  late final TextEditingController _custoCalculadoController;
  late final TextEditingController _quantidadeController;
  late final TextEditingController _quantidadeMinimaController;
  late final TextEditingController _fornecedorController;
  late final TextEditingController _observacoesController;

  String _unidade = 'unidade';
  bool _ativo = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    _nomeController = TextEditingController(text: item?.nome ?? '');

    _categoriaController = TextEditingController(text: item?.categoria ?? '');

    _valorTotalController = TextEditingController(
      text: item != null && item.valorTotalPago > 0
          ? _formatarNumero(item.valorTotalPago)
          : '',
    );

    _quantidadeTotalController = TextEditingController(
      text: item != null && item.quantidadeTotal > 0
          ? _formatarNumero(item.quantidadeTotal)
          : '',
    );

    _custoCalculadoController = TextEditingController(
      text: item != null && item.custoUnitarioEfetivo > 0
          ? _moeda.format(item.custoUnitarioEfetivo)
          : '',
    );

    _quantidadeController = TextEditingController(
      text: item == null ? '' : _formatarNumero(item.quantidade),
    );

    _quantidadeMinimaController = TextEditingController(
      text: item == null ? '' : _formatarNumero(item.quantidadeMinima),
    );

    _fornecedorController = TextEditingController(text: item?.fornecedor ?? '');

    _observacoesController = TextEditingController(
      text: item?.observacoes ?? '',
    );

    _unidade = ItemEstoque.normalizarUnidadeEntrada(item?.unidade ?? 'unidade');
    _ativo = item?.ativo ?? true;

    _atualizarCustoCalculado();
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
    return _unidade != 'unidade';
  }

  bool get _temCompraLegadaSemDetalhes {
    final item = widget.item;

    return item != null && !item.possuiDadosCompra;
  }

  bool get _temEntradaCompraParcial {
    return _valorTotalController.text.trim().isNotEmpty ||
        _quantidadeTotalController.text.trim().isNotEmpty;
  }

  String get _unidadeBaseCompra =>
      ItemEstoque.unidadeNormalizadaParaBase(_unidade);

  bool get _unidadeCompraAceitaDecimal {
    return _unidade != 'unidade';
  }

  _ResumoCompra? _calcularResumoCompra() {
    final valorTotal = _lerNumero(_valorTotalController.text);
    final quantidadeTotal = _lerNumero(_quantidadeTotalController.text);

    if (valorTotal == null || quantidadeTotal == null) {
      return null;
    }

    if (valorTotal <= 0 || quantidadeTotal <= 0) {
      return null;
    }

    final quantidadeNormalizada = ItemEstoque.quantidadeNormalizada(
      quantidadeTotal,
      _unidade,
    );

    if (!quantidadeNormalizada.isFinite || quantidadeNormalizada <= 0) {
      return null;
    }

    final custo = valorTotal / quantidadeNormalizada;

    if (!custo.isFinite || custo.isNaN || custo <= 0) {
      return null;
    }

    return _ResumoCompra(
      valorTotal: valorTotal,
      quantidadeInformada: quantidadeTotal,
      quantidadeNormalizada: quantidadeNormalizada,
      unidadeBase: _unidadeBaseCompra,
      custoUnitario: custo,
    );
  }

  void _atualizarCustoCalculado() {
    final item = widget.item;
    final resumo = _calcularResumoCompra();

    if (widget.item == null) {
      _quantidadeController.text = resumo == null
          ? ''
          : _formatarNumero(resumo.quantidadeNormalizada);
    }

    final texto = resumo != null
        ? _moeda.format(resumo.custoUnitario)
        : item != null &&
              !_temEntradaCompraParcial &&
              item.custoUnitarioEfetivo > 0
        ? _moeda.format(item.custoUnitarioEfetivo)
        : '';

    _custoCalculadoController.text = texto;
  }

  bool _numeroEhInteiro(double valor) {
    return valor == valor.truncateToDouble();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _categoriaController.dispose();
    _valorTotalController.dispose();
    _quantidadeTotalController.dispose();
    _custoCalculadoController.dispose();
    _quantidadeController.dispose();
    _quantidadeMinimaController.dispose();
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
      final resumoCompra = _calcularResumoCompra();
      final itemExistenteLegado = widget.item?.possuiDadosCompra == false;
      final deveSalvarCompra = resumoCompra != null;

      if (!deveSalvarCompra && !itemExistenteLegado && widget.item == null) {
        throw Exception('Informe o valor total pago e a quantidade total.');
      }

      final valorTotalPago =
          resumoCompra?.valorTotal ?? widget.item?.valorTotalPago ?? 0;
      final quantidadeTotal =
          resumoCompra?.quantidadeNormalizada ??
          widget.item?.quantidadeTotal ??
          0;
      final unidadeNormalizada =
          resumoCompra?.unidadeBase ??
          widget.item?.unidade ??
          _unidadeBaseCompra;
      final custoCalculado =
          resumoCompra?.custoUnitario ?? widget.item?.custoUnitarioEfetivo ?? 0;

      final quantidadeEmEstoque = widget.item == null
          ? (resumoCompra?.quantidadeNormalizada ?? 0)
          : (_lerNumero(_quantidadeController.text) ?? widget.item!.quantidade);

      final item = ItemEstoque(
        id: widget.item?.id,
        nome: nome,
        categoria: _categoriaController.text.trim(),
        quantidade: quantidadeEmEstoque,
        quantidadeMinima: _lerNumero(_quantidadeMinimaController.text) ?? 0,
        unidade: unidadeNormalizada,
        valorTotalPago: valorTotalPago,
        quantidadeTotal: quantidadeTotal,
        custoUnitario: custoCalculado,
        custoUnitarioCalculado: custoCalculado,
        fornecedor: _fornecedorController.text.trim(),
        observacoes: _observacoesController.text.trim(),
        ativo: _ativo,
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

  String? _validarValorTotal(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      if (_temCompraLegadaSemDetalhes && !_temEntradaCompraParcial) {
        return null;
      }

      return 'Informe o valor total pago.';
    }

    final numero = _lerNumero(texto);

    if (numero == null || !numero.isFinite || numero <= 0) {
      return 'Informe um valor válido.';
    }

    return null;
  }

  String? _validarQuantidadeTotal(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      if (_temCompraLegadaSemDetalhes && !_temEntradaCompraParcial) {
        return null;
      }

      return 'Informe a quantidade total.';
    }

    final numero = _lerNumero(texto);

    if (numero == null || !numero.isFinite || numero <= 0) {
      return 'Informe um valor válido.';
    }

    if (!_unidadeCompraAceitaDecimal && numero != numero.truncateToDouble()) {
      return 'Para unidade, informe valor inteiro.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.item != null;
    final resumoCompra = _calcularResumoCompra();
    final item = widget.item;

    final textoCustoCalculado = resumoCompra != null
        ? _moeda.format(resumoCompra.custoUnitario)
        : item != null &&
              !_temEntradaCompraParcial &&
              item.custoUnitarioEfetivo > 0
        ? _moeda.format(item.custoUnitarioEfetivo)
        : '—';

    final textoQuantidadePreview = resumoCompra != null
        ? '${_formatarNumero(resumoCompra.quantidadeNormalizada)} ${resumoCompra.unidadeBase}'
        : item != null && item.possuiDadosCompra
        ? '${_formatarNumero(item.quantidadeTotalNormalizada)} ${item.unidadeNormalizada}'
        : '—';

    final textoValorPreview = resumoCompra != null
        ? _moeda.format(resumoCompra.valorTotal)
        : item != null && item.valorTotalPago > 0
        ? _moeda.format(item.valorTotalPago)
        : '—';

    return Scaffold(
      appBar: AppBar(
        title: Text(editando ? 'Editar produto' : 'Cadastro de produto'),
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
            _SeccaoFormEstoque(
              titulo: 'Compra do produto',
              subtitulo: 'Informe o valor pago e a quantidade da embalagem.',
              children: [
                TextFormField(
                  controller: _valorTotalController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor total pago',
                    prefixText: 'R\$ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: _validarValorTotal,
                  onChanged: (_) {
                    setState(_atualizarCustoCalculado);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantidadeTotalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantidade total',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        validator: _validarQuantidadeTotal,
                        onChanged: (_) {
                          setState(_atualizarCustoCalculado);
                        },
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
                          DropdownMenuItem(
                            value: 'unidade',
                            child: Text('Unidade'),
                          ),
                          DropdownMenuItem(value: 'l', child: Text('Litro')),
                          DropdownMenuItem(
                            value: 'ml',
                            child: Text('Mililitro'),
                          ),
                          DropdownMenuItem(
                            value: 'kg',
                            child: Text('Quilograma'),
                          ),
                          DropdownMenuItem(value: 'g', child: Text('Grama')),
                          DropdownMenuItem(
                            value: 'metro',
                            child: Text('Metro'),
                          ),
                        ],
                        onChanged: (valor) {
                          if (valor == null) {
                            return;
                          }

                          setState(() {
                            _unidade = valor;
                            _atualizarCustoCalculado();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'O sistema converte L para ml e kg para g antes de calcular o custo unitário.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SeccaoFormEstoque(
              titulo: 'Custo calculado',
              subtitulo: 'Campo somente leitura atualizado automaticamente.',
              children: [
                TextFormField(
                  controller: _custoCalculadoController,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(
                    labelText: 'Custo unitário calculado',
                    prefixText: 'R\$ ',
                    suffixText: 'por $_unidadeBaseCompra',
                    prefixIcon: const Icon(Icons.calculate_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD6A84B).withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LinhaCompraPreview(
                        titulo: 'Valor total',
                        valor: textoValorPreview,
                      ),
                      const SizedBox(height: 6),
                      _LinhaCompraPreview(
                        titulo: 'Quantidade',
                        valor: textoQuantidadePreview,
                      ),
                      const SizedBox(height: 6),
                      _LinhaCompraPreview(
                        titulo: 'Custo calculado',
                        valor: textoCustoCalculado == '—'
                            ? '—'
                            : '$textoCustoCalculado por $_unidadeBaseCompra',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Exemplo: R\$ 60,00 ÷ 1000 ml = R\$ 0,06 por ml.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SeccaoFormEstoque(
              titulo: 'Estoque atual',
              subtitulo: 'Quantidade em estoque, fornecedor e observações.',
              children: [
                TextFormField(
                  controller: _quantidadeController,
                  readOnly: widget.item == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.item == null
                        ? 'Quantidade em estoque (automática)'
                        : 'Quantidade em estoque',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (valor) =>
                      _validarNumero(valor, campo: 'a quantidade em estoque'),
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
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _ativo,
                  onChanged: (valor) {
                    setState(() => _ativo = valor);
                  },
                  title: const Text('Produto ativo'),
                  subtitle: const Text(
                    'Produto inativo não aparece em novas Ordens de Serviço.',
                  ),
                ),
              ],
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

class _SeccaoFormEstoque extends StatelessWidget {
  const _SeccaoFormEstoque({
    required this.titulo,
    required this.subtitulo,
    required this.children,
  });

  final String titulo;
  final String subtitulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.64)),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _LinhaCompraPreview extends StatelessWidget {
  const _LinhaCompraPreview({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(width: 12),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ResumoCompra {
  const _ResumoCompra({
    required this.valorTotal,
    required this.quantidadeInformada,
    required this.quantidadeNormalizada,
    required this.unidadeBase,
    required this.custoUnitario,
  });

  final double valorTotal;
  final double quantidadeInformada;
  final double quantidadeNormalizada;
  final String unidadeBase;
  final double custoUnitario;
}
