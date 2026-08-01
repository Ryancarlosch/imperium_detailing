import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../models/produto_ordem_servico.dart';
import '../repositories/estoque_repository.dart';
import '../repositories/produto_ordem_servico_repository.dart';

class OrdemServicoProdutosPage extends StatefulWidget {
  final int ordemServicoId;
  final String numeroOrdem;
  final String cliente;
  final String veiculo;
  final bool somenteLeitura;

  const OrdemServicoProdutosPage({
    super.key,
    required this.ordemServicoId,
    required this.numeroOrdem,
    required this.cliente,
    required this.veiculo,
    this.somenteLeitura = false,
  });

  @override
  State<OrdemServicoProdutosPage> createState() =>
      _OrdemServicoProdutosPageState();
}

class _OrdemServicoProdutosPageState extends State<OrdemServicoProdutosPage> {
  final ProdutoOrdemServicoRepository _produtoRepository =
      ProdutoOrdemServicoRepository();

  final EstoqueRepository _estoqueRepository = EstoqueRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  List<ProdutoOrdemServico> _produtos = [];

  bool _carregando = true;
  bool _executandoAcao = false;
  bool _alterou = false;

  String _pesquisa = '';

  @override
  void initState() {
    super.initState();

    _pesquisaController.addListener(_aoAlterarPesquisa);

    _carregarProdutos();
  }

  @override
  void dispose() {
    _pesquisaController.removeListener(_aoAlterarPesquisa);

    _pesquisaController.dispose();

    super.dispose();
  }

  void _aoAlterarPesquisa() {
    if (!mounted) {
      return;
    }

    setState(() {
      _pesquisa = _pesquisaController.text.trim().toLowerCase();
    });
  }

  Future<void> _carregarProdutos() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final produtos = await _produtoRepository.listarProdutosPorOrdemServico(
        widget.ordemServicoId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _produtos = produtos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar os produtos.\n$erro',
        erro: true,
      );
    }
  }

  List<ProdutoOrdemServico> get _produtosFiltrados {
    if (_pesquisa.isEmpty) {
      return _produtos;
    }

    return _produtos.where((produto) {
      final texto = [
        produto.produtoNome,
        produto.unidade,
      ].join(' ').toLowerCase();

      return texto.contains(_pesquisa);
    }).toList();
  }

  double get _custoTotal {
    return _produtos.fold<double>(
      0,
      (total, produto) => total + produto.custoTotal,
    );
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : null,
      ),
    );
  }

  String _formatarQuantidade(double quantidade) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(3)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }

  double? _converterQuantidade(String texto) {
    final textoLimpo = texto.trim();

    if (textoLimpo.isEmpty) {
      return null;
    }

    final valor = textoLimpo.contains(',')
        ? textoLimpo.replaceAll('.', '').replaceAll(',', '.')
        : textoLimpo;

    return double.tryParse(valor);
  }

  Future<bool> _confirmarAcao({
    required String titulo,
    required String mensagem,
    String textoConfirmar = 'Confirmar',
    Color? corConfirmar,
  }) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(mensagem),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: corConfirmar),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(textoConfirmar),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  Future<void> _adicionarProduto() async {
    if (widget.somenteLeitura || _executandoAcao) {
      return;
    }

    try {
      final itens = await _estoqueRepository.listarItens();

      if (!mounted) {
        return;
      }

      if (itens.isEmpty) {
        _mostrarMensagem(
          'Nenhum produto foi cadastrado no estoque.',
          erro: true,
        );

        return;
      }

      final itemSelecionado = await _selecionarProdutoEstoque(itens);

      if (itemSelecionado == null || !mounted) {
        return;
      }

      final quantidade = await _informarQuantidade(item: itemSelecionado);

      if (quantidade == null || !mounted) {
        return;
      }

      if (quantidade <= 0) {
        _mostrarMensagem('Informe uma quantidade maior que zero.', erro: true);

        return;
      }

      setState(() {
        _executandoAcao = true;
      });

      final produto = ProdutoOrdemServico(
        ordemServicoId: widget.ordemServicoId,
        produtoId: itemSelecionado.id,
        produtoNome: itemSelecionado.nome,
        quantidade: quantidade,
        unidade: itemSelecionado.unidade,
        custoUnitario: itemSelecionado.custoUnitario,
      );

      await _produtoRepository.adicionarOuSomarProduto(produto);

      _alterou = true;

      await _carregarProdutos();

      _mostrarMensagem('Produto adicionado à Ordem de Serviço.');
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível adicionar o produto.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<ItemEstoque?> _selecionarProdutoEstoque(
    List<ItemEstoque> itens,
  ) async {
    final pesquisaController = TextEditingController();

    ItemEstoque? resultado;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (bottomContext) {
        String pesquisa = '';

        return StatefulBuilder(
          builder: (context, alterarEstado) {
            final itensFiltrados = itens.where((item) {
              final termo = pesquisa.trim().toLowerCase();

              if (termo.isEmpty) {
                return true;
              }

              final texto = [
                item.nome,
                item.categoria,
                item.fornecedor,
              ].join(' ').toLowerCase();

              return texto.contains(termo);
            }).toList();

            return FractionallySizedBox(
              heightFactor: 0.88,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selecionar produto',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text('Escolha um produto cadastrado no estoque.'),
                        const SizedBox(height: 14),
                        TextField(
                          controller: pesquisaController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Pesquisar produto ou categoria',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: pesquisaController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      pesquisaController.clear();

                                      alterarEstado(() {
                                        pesquisa = '';
                                      });
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onChanged: (valor) {
                            alterarEstado(() {
                              pesquisa = valor;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: itensFiltrados.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 60,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Nenhum produto encontrado',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
                            itemCount: itensFiltrados.length,
                            separatorBuilder: (_, __) {
                              return const SizedBox(height: 7);
                            },
                            itemBuilder: (context, index) {
                              final item = itensFiltrados[index];

                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Icon(
                                      item.estoqueBaixo
                                          ? Icons.warning_amber_rounded
                                          : Icons.inventory_2_outlined,
                                    ),
                                  ),
                                  title: Text(
                                    item.nome,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_formatarQuantidade(item.quantidade)} '
                                    '${item.unidade}'
                                    '${item.categoria.isEmpty ? '' : ' • ${item.categoria}'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    resultado = item;

                                    Navigator.of(bottomContext).pop();
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pesquisaController.dispose();

    return resultado;
  }

  Future<double?> _informarQuantidade({
    required ItemEstoque item,
    double? quantidadeAtual,
  }) async {
    final quantidadeController = TextEditingController(
      text: quantidadeAtual == null ? '' : _formatarQuantidade(quantidadeAtual),
    );

    String? erro;

    final resultado = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, alterarEstado) {
            void confirmar() {
              final quantidade = _converterQuantidade(
                quantidadeController.text,
              );

              if (quantidade == null || quantidade <= 0) {
                alterarEstado(() {
                  erro = 'Informe uma quantidade maior que zero.';
                });

                return;
              }

              if (quantidade > item.quantidade) {
                alterarEstado(() {
                  erro =
                      'Quantidade maior que o estoque disponível: '
                      '${_formatarQuantidade(item.quantidade)} ${item.unidade}.';
                });

                return;
              }

              Navigator.of(dialogContext).pop(quantidade);
            }

            return AlertDialog(
              title: Text(
                quantidadeAtual == null
                    ? 'Adicionar produto'
                    : 'Alterar quantidade',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nome,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Disponível no estoque: '
                      '${_formatarQuantidade(item.quantidade)} '
                      '${item.unidade}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadeController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Quantidade utilizada',
                        suffixText: item.unidade,
                        errorText: erro,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        confirmar();
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Custo unitário: '
                      '${_moeda.format(item.custoUnitario)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: confirmar,
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    quantidadeController.dispose();

    return resultado;
  }

  Future<void> _editarProduto(ProdutoOrdemServico produto) async {
    if (widget.somenteLeitura || produto.baixadoEstoque || _executandoAcao) {
      return;
    }

    final itemEstoqueId = produto.produtoId;

    if (itemEstoqueId == null) {
      _mostrarMensagem(
        'Este produto não está vinculado ao estoque.',
        erro: true,
      );

      return;
    }

    try {
      final item = await _estoqueRepository.buscarItemPorId(itemEstoqueId);

      if (!mounted) {
        return;
      }

      if (item == null) {
        _mostrarMensagem('O produto não existe mais no estoque.', erro: true);

        return;
      }

      final novaQuantidade = await _informarQuantidade(
        item: item,
        quantidadeAtual: produto.quantidade,
      );

      if (novaQuantidade == null || !mounted) {
        return;
      }

      setState(() {
        _executandoAcao = true;
      });

      await _produtoRepository.atualizarProduto(
        produto.copyWith(
          quantidade: novaQuantidade,
          produtoNome: item.nome,
          unidade: item.unidade,
          custoUnitario: item.custoUnitario,
        ),
      );

      _alterou = true;

      await _carregarProdutos();

      _mostrarMensagem('Quantidade atualizada.');
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível atualizar o produto.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _excluirProduto(ProdutoOrdemServico produto) async {
    if (widget.somenteLeitura || produto.baixadoEstoque || _executandoAcao) {
      return;
    }

    final id = produto.id;

    if (id == null) {
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Remover produto',
      mensagem:
          'Deseja remover ${produto.produtoNome} desta '
          'Ordem de Serviço?',
      textoConfirmar: 'Remover',
      corConfirmar: Colors.red.shade700,
    );

    if (!confirmar || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _produtoRepository.excluirProduto(id);

      _alterou = true;

      await _carregarProdutos();

      _mostrarMensagem('Produto removido da Ordem de Serviço.');
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível remover o produto.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<bool> _aoVoltar() async {
    Navigator.of(context).pop(_alterou);

    return false;
  }

  Widget _construirCabecalho() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.numeroOrdem,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_produtos.length} '
                  '${_produtos.length == 1 ? 'produto' : 'produtos'}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.cliente,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(widget.veiculo, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _construirResumo() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.payments_outlined)),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custo dos produtos',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Valor interno utilizado nesta OS',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Text(
              _moeda.format(_custoTotal),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirProduto(ProdutoOrdemServico produto) {
    final baixado = produto.baixadoEstoque;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.somenteLeitura || baixado
            ? null
            : () => _editarProduto(produto),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: baixado
                    ? Colors.green.withValues(alpha: 0.14)
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  baixado
                      ? Icons.check_circle_outline
                      : Icons.inventory_2_outlined,
                  color: baixado ? Colors.green.shade700 : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.produtoNome,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatarQuantidade(produto.quantidade)} '
                      '${produto.unidade}',
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_moeda.format(produto.custoUnitario)} '
                      'por ${produto.unidade}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    if (baixado) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Baixado do estoque',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _moeda.format(produto.custoTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (!widget.somenteLeitura && !baixado)
                    IconButton(
                      tooltip: 'Remover produto',
                      onPressed: _executandoAcao
                          ? null
                          : () => _excluirProduto(produto),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red.shade700,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    final produtos = _produtosFiltrados;

    return RefreshIndicator(
      onRefresh: _carregarProdutos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
        children: [
          _construirCabecalho(),
          const SizedBox(height: 12),
          _construirResumo(),
          const SizedBox(height: 14),
          TextField(
            controller: _pesquisaController,
            decoration: InputDecoration(
              hintText: 'Pesquisar produto utilizado',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pesquisaController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar pesquisa',
                      onPressed: () {
                        _pesquisaController.clear();
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (produtos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
              child: Column(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 70,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _produtos.isEmpty
                        ? 'Nenhum produto utilizado'
                        : 'Nenhum produto encontrado',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_produtos.isEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      widget.somenteLeitura
                          ? 'Esta Ordem de Serviço não possui '
                                'produtos registrados.'
                          : 'Toque em “Adicionar produto” para '
                                'registrar os materiais usados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            )
          else
            ...produtos.map(
              (produto) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _construirProduto(produto),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _aoVoltar();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Produtos utilizados'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _aoVoltar,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregarProdutos,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _construirConteudo(),
        floatingActionButton: widget.somenteLeitura
            ? null
            : FloatingActionButton.extended(
                onPressed: _executandoAcao ? null : _adicionarProduto,
                icon: _executandoAcao
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
      ),
    );
  }
}
