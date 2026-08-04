import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../models/movimentacao_estoque.dart';
import '../repositories/estoque_repository.dart';
import 'novo_item_estoque_page.dart';

class ItemEstoqueDetalhesPage extends StatefulWidget {
  const ItemEstoqueDetalhesPage({super.key, required this.itemId});

  final int itemId;

  @override
  State<ItemEstoqueDetalhesPage> createState() =>
      _ItemEstoqueDetalhesPageState();
}

class _ItemEstoqueDetalhesPageState extends State<ItemEstoqueDetalhesPage> {
  final _repository = EstoqueRepository();

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  ItemEstoque? _item;
  List<EstoqueLote> _lotes = [];
  List<MovimentacaoEstoque> _movimentacoes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final resultados = await Future.wait([
      _repository.buscarItemPorId(widget.itemId),
      _repository.listarLotesDoItem(widget.itemId),
      _repository.listarMovimentacoesDoItem(widget.itemId),
    ]);

    final item = resultados[0] as ItemEstoque?;
    final lotes = resultados[1] as List<EstoqueLote>;
    final movimentacoes = resultados[2] as List<MovimentacaoEstoque>;

    if (!mounted) return;

    setState(() {
      _item = item;
      _lotes = lotes;
      _movimentacoes = movimentacoes;
      _carregando = false;
    });
  }

  Future<void> _novaEntradaEstoque() async {
    final item = _item;

    if (item == null) return;

    String textoQuantidade = '';
    String textoValor = '';
    String fornecedor = item.fornecedor;
    String observacao = '';
    String unidadeCompra = item.unidade;
    final fornecedorController = TextEditingController(text: fornecedor);

    final salvou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nova entrada de estoque'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (valor) {
                    textoQuantidade = valor;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Quantidade comprada',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unidadeCompra,
                  items: const [
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
                    DropdownMenuItem(value: 'l', child: Text('L')),
                    DropdownMenuItem(value: 'g', child: Text('g')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'metro', child: Text('metro')),
                    DropdownMenuItem(value: 'unidade', child: Text('unidade')),
                  ],
                  onChanged: (valor) {
                    if (valor != null) {
                      unidadeCompra = valor;
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Unidade original',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (valor) {
                    textoValor = valor;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Valor total pago',
                    prefixText: 'R\$ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fornecedorController,
                  onChanged: (valor) {
                    fornecedor = valor;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Fornecedor (opcional)',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (valor) {
                    observacao = valor;
                  },
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final quantidade = double.tryParse(
                  textoQuantidade.trim().replaceAll(',', '.'),
                );
                final valor = double.tryParse(
                  textoValor.trim().replaceAll(',', '.'),
                );

                if (quantidade == null || quantidade <= 0) {
                  return;
                }

                if (valor == null || valor <= 0) {
                  return;
                }

                try {
                  await _repository.adicionarEntradaEstoque(
                    itemId: item.id!,
                    valorTotalPago: valor,
                    quantidadeTotal: quantidade,
                    unidadeInformada: unidadeCompra,
                    fornecedor: fornecedor.trim(),
                    observacao: observacao.trim(),
                    origem: 'Nova entrada de estoque',
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.pop(dialogContext, true);
                } catch (_) {
                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.pop(dialogContext, false);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (salvou == true) {
      await _carregar();
    }

    fornecedorController.dispose();
  }

  Future<void> _ajusteManual() async {
    final item = _item;

    if (item == null) return;

    String textoQuantidade = _numero(item.quantidade);
    String motivo = '';
    String observacao = '';
    final quantidadeController = TextEditingController(text: textoQuantidade);

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajuste manual de estoque'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  controller: quantidadeController,
                  onChanged: (valor) {
                    textoQuantidade = valor;
                  },
                  decoration: InputDecoration(
                    labelText: 'Nova quantidade (${item.unidade})',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: null,
                  items: const [
                    DropdownMenuItem(
                      value: 'Inventário físico',
                      child: Text('Inventário físico'),
                    ),
                    DropdownMenuItem(
                      value: 'Perda/avaria',
                      child: Text('Perda/avaria'),
                    ),
                    DropdownMenuItem(
                      value: 'Correção cadastral',
                      child: Text('Correção cadastral'),
                    ),
                    DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                  ],
                  onChanged: (valor) {
                    motivo = valor?.trim() ?? '';
                  },
                  decoration: const InputDecoration(
                    labelText: 'Motivo do ajuste',
                    prefixIcon: Icon(Icons.rule_folder_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (valor) {
                    observacao = valor;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final valor = double.tryParse(
                  textoQuantidade.trim().replaceAll(',', '.'),
                );

                if (valor == null || valor < 0 || motivo.trim().isEmpty) {
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              child: const Text('Confirmar ajuste'),
            ),
          ],
        );
      },
    );

    if (confirmou != true) {
      quantidadeController.dispose();
      return;
    }

    final novaQuantidade = double.tryParse(
      textoQuantidade.trim().replaceAll(',', '.'),
    );

    if (novaQuantidade == null || novaQuantidade < 0) {
      quantidadeController.dispose();
      return;
    }

    await _repository.registrarMovimentacao(
      MovimentacaoEstoque(
        itemId: item.id!,
        tipo: 'AJUSTE',
        quantidade: novaQuantidade,
        motivo: motivo,
        observacao: observacao.trim(),
        origem: 'Ajuste manual',
        data: DateTime.now().toIso8601String(),
      ),
    );

    quantidadeController.dispose();

    await _carregar();
  }

  Future<void> _editar() async {
    final item = _item;

    if (item == null) return;

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NovoItemEstoquePage(item: item)),
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
          title: const Text('Inativar item?'),
          content: const Text(
            'O produto não aparecerá em novas Ordens de Serviço, mas o histórico será preservado.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Inativar'),
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

    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatarData(String valor) {
    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _formatoData.format(data);
  }

  String _rotuloTipoMovimentacao(String tipo) {
    switch (tipo) {
      case 'ENTRADA':
        return 'Entrada';
      case 'SAIDA':
        return 'Saída';
      case 'AJUSTE':
        return 'Ajuste manual';
      default:
        return tipo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final valorAtualEstoque = _lotes.fold<double>(
      0,
      (total, lote) => total + (lote.quantidadeDisponivel * lote.custoUnitario),
    );
    final estoqueLotes = _lotes.fold<double>(
      0,
      (total, lote) => total + lote.quantidadeDisponivel,
    );
    final custoMedio = estoqueLotes > 0 ? valorAtualEstoque / estoqueLotes : 0;
    final ultimoLote = _lotes.isEmpty ? null : _lotes.last;

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
              PopupMenuItem(value: 'excluir', child: Text('Inativar item')),
            ],
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : item == null
          ? const Center(child: Text('Item não encontrado.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          item.estoqueBaixo
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_2_outlined,
                          size: 64,
                          color: item.estoqueBaixo
                              ? Colors.orange
                              : const Color(0xFFD6A84B),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          item.nome,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.categoria.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            item.categoria,
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: item.ativo
                                ? Colors.green.withValues(alpha: 0.16)
                                : Colors.red.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            item.ativo ? 'Ativo' : 'Inativo',
                            style: TextStyle(
                              color: item.ativo
                                  ? Colors.green
                                  : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${_numero(item.quantidade)} ${item.unidade}',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: item.estoqueBaixo
                                ? Colors.orange
                                : Colors.greenAccent,
                          ),
                        ),
                        if (item.estoqueBaixo)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Estoque baixo',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
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
                          _novaEntradaEstoque();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Nova entrada'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _ajusteManual();
                        },
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Ajuste manual'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CADASTRO',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD6A84B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Linha(titulo: 'Nome', valor: item.nome),
                        _Linha(
                          titulo: 'Unidade-base',
                          valor: item.unidadeNormalizada,
                        ),
                        _Linha(
                          titulo: 'Estoque mínimo',
                          valor:
                              '${_numero(item.quantidadeMinima)} ${item.unidade}',
                        ),
                        _Linha(
                          titulo: 'Status',
                          valor: item.ativo ? 'Ativo' : 'Inativo',
                        ),
                        _Linha(
                          titulo: 'Fornecedor',
                          valor: item.fornecedor.isEmpty
                              ? 'Não informado'
                              : item.fornecedor,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ESTOQUE ATUAL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD6A84B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Linha(
                          titulo: 'Quantidade disponível',
                          valor: '${_numero(item.quantidade)} ${item.unidade}',
                        ),
                        _Linha(
                          titulo: 'Valor estimado armazenado',
                          valor: _moeda.format(valorAtualEstoque),
                        ),
                        _Linha(
                          titulo: 'Custo médio (informativo)',
                          valor:
                              '${_moeda.format(custoMedio)} por ${item.unidade}',
                        ),
                        _Linha(
                          titulo: 'Último custo de compra',
                          valor: ultimoLote == null
                              ? 'Não informado'
                              : '${_moeda.format(ultimoLote.custoUnitario)} por ${ultimoLote.unidadeBase}',
                        ),
                        _Linha(
                          titulo: 'Indicador',
                          valor: item.estoqueBaixo
                              ? 'Estoque baixo'
                              : 'Estoque normal',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'COMPRAS',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_lotes.isEmpty)
                          const Text(
                            'Nenhum lote registrado para este produto.',
                          )
                        else
                          ..._lotes.map(
                            (lote) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Compra: ${_formatarData(lote.dataCompra)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Quantidade inicial: ${_numero(lote.quantidadeOriginal)} ${lote.unidadeOriginal}',
                                    ),
                                    Text(
                                      'Quantidade normalizada: ${_numero(lote.quantidadeNormalizada)} ${lote.unidadeBase}',
                                    ),
                                    Text(
                                      'Quantidade restante: ${_numero(lote.quantidadeDisponivel)} ${lote.unidadeBase}',
                                    ),
                                    Text(
                                      'Valor pago: ${_moeda.format(lote.valorTotalPago)}',
                                    ),
                                    Text(
                                      'Custo unitário: ${_moeda.format(lote.custoUnitario)} por ${lote.unidadeBase}',
                                    ),
                                    Text(
                                      'Fornecedor: ${lote.fornecedor.trim().isEmpty ? 'Não informado' : lote.fornecedor}',
                                    ),
                                    Text(
                                      'Observação: ${lote.observacao.trim().isEmpty ? 'Não informada' : lote.observacao}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MOVIMENTAÇÕES',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_movimentacoes.isEmpty)
                          const Text('Nenhuma movimentação registrada.')
                        else
                          ..._movimentacoes.map((mov) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_rotuloTipoMovimentacao(mov.tipo)} • ${_formatarData(mov.data)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Quantidade: ${_numero(mov.quantidade)} ${item.unidade}',
                                    ),
                                    if (mov.quantidadeAnterior != null &&
                                        mov.quantidadePosterior != null)
                                      Text(
                                        'Anterior: ${_numero(mov.quantidadeAnterior!)} • Posterior: ${_numero(mov.quantidadePosterior!)}',
                                      ),
                                    if (mov.motivo.trim().isNotEmpty)
                                      Text('Motivo: ${mov.motivo}'),
                                    if (mov.observacao.trim().isNotEmpty)
                                      Text('Obs.: ${mov.observacao}'),
                                    Text('Origem: ${mov.origem}'),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                if (item.observacoes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Observações',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.observacoes,
                            style: const TextStyle(
                              color: Colors.white70,
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
  const _Linha({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
