import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/configuracao_estoque.dart';
import '../models/item_estoque.dart';
import '../models/movimentacao_estoque.dart';
import '../repositories/estoque_repository.dart';
import 'item_estoque_detalhes_page.dart';
import 'novo_item_estoque_page.dart';

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage>
    with SingleTickerProviderStateMixin {
  final EstoqueRepository _repository = EstoqueRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  late final TabController _tabController;

  List<ItemEstoque> _itens = [];
  List<MovimentacaoEstoque> _movimentacoes = [];

  ConfiguracaoEstoque _configuracao = ConfiguracaoEstoque.padrao();

  bool _carregando = true;
  bool _salvandoConfiguracao = false;
  bool _somenteBaixo = false;

  String _pesquisa = '';

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _repository.listarItens(incluirInativos: true),
        _repository.listarMovimentacoes(),
        _repository.obterConfiguracao(),
      ]);

      if (!mounted) return;

      setState(() {
        _itens = resultados[0] as List<ItemEstoque>;
        _movimentacoes = resultados[1] as List<MovimentacaoEstoque>;
        _configuracao = resultados[2] as ConfiguracaoEstoque;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar o estoque: $erro')),
      );
    }
  }

  Future<void> _atualizarTudo() async {
    setState(() {
      _carregando = true;
    });

    await _carregar();
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
          ].join(' ').toLowerCase().contains(termo);

      final correspondeEstoque = !_somenteBaixo || item.estoqueBaixo;

      return correspondePesquisa && correspondeEstoque;
    }).toList();
  }

  Future<void> _adicionarItem() async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovoItemEstoquePage()),
    );

    if (!mounted || salvou != true) {
      return;
    }

    try {
      final itensAtualizados = await _repository.listarItens(
        incluirInativos: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _itens = itensAtualizados;
        _carregando = false;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto cadastrado com sucesso.')),
      );
    } catch (erro, stackTrace) {
      debugPrint('ERRO AO ATUALIZAR PRODUTOS');
      debugPrint(erro.toString());
      debugPrint(stackTrace.toString());

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'O produto foi salvo, mas a lista não pôde ser atualizada:\n$erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrirItem(ItemEstoque item) async {
    if (item.id == null) return;

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ItemEstoqueDetalhesPage(itemId: item.id!),
      ),
    );

    if (!mounted) return;

    if (alterou == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estoque atualizado com sucesso.')),
      );
    }

    await _atualizarTudo();
  }

  Future<void> _abrirNovaMovimentacao() async {
    if (_itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre um produto antes de registrar movimentações.',
          ),
        ),
      );

      return;
    }

    ItemEstoque itemSelecionado = _itens.first;
    String tipoSelecionado = 'ENTRADA';

    String quantidadeDigitada = '';
    String valorPagoDigitado = '';
    String unidadeCompra = 'unidade';
    String fornecedorDigitado = '';
    String motivoAjuste = '';
    String observacaoDigitada = '';

    final salvou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool salvando = false;

        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return AlertDialog(
              title: const Text('Nova movimentação de estoque'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<ItemEstoque>(
                      initialValue: itemSelecionado,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Produto',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: _itens.map((item) {
                        return DropdownMenuItem<ItemEstoque>(
                          value: item,
                          child: Text(
                            item.nome,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: salvando
                          ? null
                          : (item) {
                              if (item == null) {
                                return;
                              }

                              setStateDialog(() {
                                itemSelecionado = item;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: tipoSelecionado,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        prefixIcon: Icon(Icons.swap_vert_rounded),
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
                      onChanged: salvando
                          ? null
                          : (tipo) {
                              if (tipo == null) {
                                return;
                              }

                              setStateDialog(() {
                                tipoSelecionado = tipo;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      enabled: !salvando,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (valor) {
                        quantidadeDigitada = valor;
                      },
                      decoration: InputDecoration(
                        labelText: tipoSelecionado == 'AJUSTE'
                            ? 'Nova quantidade total'
                            : tipoSelecionado == 'ENTRADA'
                            ? 'Quantidade da embalagem'
                            : 'Quantidade',
                        prefixIcon: const Icon(Icons.numbers_rounded),
                        suffixText: tipoSelecionado == 'ENTRADA'
                            ? unidadeCompra
                            : itemSelecionado.unidade,
                      ),
                    ),
                    if (tipoSelecionado == 'ENTRADA') ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        enabled: !salvando,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (valor) {
                          valorPagoDigitado = valor;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Valor total pago',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: unidadeCompra,
                        decoration: const InputDecoration(
                          labelText: 'Unidade da embalagem',
                          prefixIcon: Icon(Icons.straighten),
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
                        onChanged: salvando
                            ? null
                            : (valor) {
                                if (valor == null) {
                                  return;
                                }
                                setStateDialog(() {
                                  unidadeCompra = valor;
                                });
                              },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        enabled: !salvando,
                        onChanged: (valor) {
                          fornecedorDigitado = valor;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Fornecedor (opcional)',
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (tipoSelecionado == 'AJUSTE') ...[
                      TextFormField(
                        enabled: !salvando,
                        onChanged: (valor) {
                          motivoAjuste = valor;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Motivo do ajuste',
                          prefixIcon: Icon(Icons.rule_folder_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      enabled: !salvando,
                      maxLines: 3,
                      onChanged: (valor) {
                        observacaoDigitada = valor;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        prefixIcon: Icon(Icons.notes_rounded),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (tipoSelecionado == 'SAIDA') ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Disponível: '
                          '${_numero(itemSelecionado.quantidade)} '
                          '${itemSelecionado.unidade}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: salvando
                      ? null
                      : () async {
                          final texto = quantidadeDigitada.trim().replaceAll(
                            ',',
                            '.',
                          );

                          final quantidade = double.tryParse(texto);

                          if (quantidade == null ||
                              quantidade < 0 ||
                              (quantidade == 0 &&
                                  tipoSelecionado != 'AJUSTE')) {
                            ScaffoldMessenger.of(dialogContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Informe uma quantidade válida.',
                                  ),
                                ),
                              );

                            return;
                          }

                          if (tipoSelecionado == 'ENTRADA') {
                            final valorPago = double.tryParse(
                              valorPagoDigitado.trim().replaceAll(',', '.'),
                            );

                            if (valorPago == null || valorPago <= 0) {
                              ScaffoldMessenger.of(dialogContext)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Informe o valor total pago da compra.',
                                    ),
                                  ),
                                );
                              return;
                            }
                          }

                          if (tipoSelecionado == 'SAIDA' &&
                              quantidade > itemSelecionado.quantidade) {
                            ScaffoldMessenger.of(dialogContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'A quantidade de saída é maior que o estoque disponível.',
                                  ),
                                ),
                              );

                            return;
                          }

                          if (tipoSelecionado == 'AJUSTE' &&
                              motivoAjuste.trim().isEmpty) {
                            ScaffoldMessenger.of(dialogContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Informe o motivo do ajuste manual.',
                                  ),
                                ),
                              );

                            return;
                          }

                          final itemId = itemSelecionado.id;

                          if (itemId == null) {
                            ScaffoldMessenger.of(dialogContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Não foi possível identificar o produto.',
                                  ),
                                ),
                              );

                            return;
                          }

                          setStateDialog(() {
                            salvando = true;
                          });

                          try {
                            if (tipoSelecionado == 'ENTRADA') {
                              final valorPago =
                                  double.tryParse(
                                    valorPagoDigitado.trim().replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  0;

                              await _repository.adicionarEntradaEstoque(
                                itemId: itemId,
                                valorTotalPago: valorPago,
                                quantidadeTotal: quantidade,
                                unidadeInformada: unidadeCompra,
                                fornecedor: fornecedorDigitado.trim(),
                                observacao: observacaoDigitada.trim(),
                              );
                            } else {
                              await _repository.registrarMovimentacao(
                                MovimentacaoEstoque(
                                  itemId: itemId,
                                  tipo: tipoSelecionado,
                                  quantidade: quantidade,
                                  motivo: tipoSelecionado == 'AJUSTE'
                                      ? motivoAjuste.trim()
                                      : '',
                                  observacao: observacaoDigitada.trim(),
                                  data: DateTime.now().toIso8601String(),
                                ),
                              );
                            }

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop(true);
                          } catch (erro) {
                            if (!dialogContext.mounted) {
                              return;
                            }

                            setStateDialog(() {
                              salvando = false;
                            });

                            ScaffoldMessenger.of(dialogContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro ao registrar movimentação: $erro',
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                          }
                        },
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvou != true || !mounted) {
      return;
    }

    // Aguarda o diálogo terminar de sair completamente da tela.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return;
    }

    try {
      final resultados = await Future.wait([
        _repository.listarItens(incluirInativos: true),
        _repository.listarMovimentacoes(),
        _repository.obterConfiguracao(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _itens = resultados[0] as List<ItemEstoque>;
        _movimentacoes = resultados[1] as List<MovimentacaoEstoque>;
        _configuracao = resultados[2] as ConfiguracaoEstoque;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Movimentação registrada com sucesso.')),
        );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'A movimentação foi salva, mas a tela não pôde ser atualizada: $erro',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Future<void> _salvarConfiguracao(ConfiguracaoEstoque novaConfiguracao) async {
    setState(() {
      _configuracao = novaConfiguracao;
      _salvandoConfiguracao = true;
    });

    try {
      await _repository.salvarConfiguracao(
        novaConfiguracao.copyWith(
          atualizadoEm: DateTime.now().toIso8601String(),
        ),
      );

      final configuracaoAtualizada = await _repository.obterConfiguracao();

      if (!mounted) return;

      setState(() {
        _configuracao = configuracaoAtualizada;
        _salvandoConfiguracao = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _salvandoConfiguracao = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar a configuração: $erro'),
        ),
      );
    }
  }

  String _nomeItemMovimentacao(MovimentacaoEstoque movimentacao) {
    for (final item in _itens) {
      if (item.id == movimentacao.itemId) {
        return item.nome;
      }
    }

    return 'Produto removido';
  }

  String _unidadeItemMovimentacao(MovimentacaoEstoque movimentacao) {
    for (final item in _itens) {
      if (item.id == movimentacao.itemId) {
        return item.unidade;
      }
    }

    return '';
  }

  String _numero(double valor) {
    if (valor == valor.truncateToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _dataFormatada(String valor) {
    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _formatoData.format(data);
  }

  String _nomeTipoMovimentacao(String tipo) {
    switch (tipo) {
      case 'ENTRADA':
        return 'Entrada';
      case 'SAIDA':
        return 'Saída';
      case 'AJUSTE':
        return 'Ajuste';
      default:
        return tipo;
    }
  }

  IconData _iconeTipoMovimentacao(String tipo) {
    switch (tipo) {
      case 'ENTRADA':
        return Icons.add_circle_outline_rounded;
      case 'SAIDA':
        return Icons.remove_circle_outline_rounded;
      case 'AJUSTE':
        return Icons.tune_rounded;
      default:
        return Icons.swap_vert_rounded;
    }
  }

  Color _corTipoMovimentacao(String tipo) {
    switch (tipo) {
      case 'ENTRADA':
        return Colors.green;
      case 'SAIDA':
        return Colors.red;
      case 'AJUSTE':
        return Colors.orange;
      default:
        return const Color(0xFFD6A84B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de estoque'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _atualizarTudo,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Produtos'),
            Tab(icon: Icon(Icons.swap_vert_rounded), text: 'Movimentações'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Configurações'),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _abaProdutos(),
                _abaMovimentacoes(),
                _abaConfiguracoes(),
              ],
            ),
      floatingActionButton: _carregando
          ? null
          : AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                if (_tabController.index == 0) {
                  return FloatingActionButton.extended(
                    onPressed: _adicionarItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo produto'),
                  );
                }

                if (_tabController.index == 1) {
                  return FloatingActionButton.extended(
                    onPressed: _abrirNovaMovimentacao,
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: const Text('Movimentar'),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
    );
  }

  Widget _abaProdutos() {
    final filtrados = _itensFiltrados;

    final valorTotal = _itens.fold<double>(
      0,
      (total, item) => total + item.valorTotal,
    );

    final baixos = _itens.where((item) => item.estoqueBaixo).length;

    return RefreshIndicator(
      onRefresh: _atualizarTudo,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: _Resumo(
                  titulo: 'Produtos',
                  valor: _itens.length.toString(),
                  icone: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Resumo(
                  titulo: 'Estoque baixo',
                  valor: baixos.toString(),
                  icone: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Color(0xFFD6A84B),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Valor total em estoque')),
                  Text(
                    _moeda.format(valorTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
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
            decoration: InputDecoration(
              hintText: 'Pesquisar produto, categoria ou fornecedor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pesquisa.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _pesquisaController.clear();

                        setState(() {
                          _pesquisa = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _somenteBaixo,
              label: const Text('Somente estoque baixo'),
              avatar: const Icon(Icons.warning_amber_rounded),
              onSelected: (selecionado) {
                setState(() {
                  _somenteBaixo = selecionado;
                });
              },
            ),
          ),
          const SizedBox(height: 14),
          if (filtrados.isEmpty)
            _EstadoVazio(
              icone: Icons.inventory_2_outlined,
              titulo: _itens.isEmpty
                  ? 'Nenhum produto cadastrado'
                  : 'Nenhum produto encontrado',
              descricao: _itens.isEmpty
                  ? 'Cadastre os produtos utilizados na empresa.'
                  : 'Altere a pesquisa ou remova os filtros.',
            )
          else
            ...filtrados.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    onTap: () => _abrirItem(item),
                    leading: CircleAvatar(
                      backgroundColor:
                          (item.estoqueBaixo
                                  ? Colors.orange
                                  : const Color(0xFFD6A84B))
                              .withValues(alpha: 0.15),
                      child: Icon(
                        item.estoqueBaixo
                            ? Icons.warning_amber_rounded
                            : Icons.inventory_2_outlined,
                        color: item.estoqueBaixo
                            ? Colors.orange
                            : const Color(0xFFD6A84B),
                      ),
                    ),
                    title: Text(
                      item.nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${_numero(item.quantidade)} '
                      '${item.unidade}'
                      '${item.categoria.isEmpty ? '' : ' • ${item.categoria}'}'
                      '${item.estoqueZerado ? ' • ZERADO' : ''}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _moeda.format(item.valorTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.chevron_right, size: 19),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _abaMovimentacoes() {
    return RefreshIndicator(
      onRefresh: _atualizarTudo,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.history_rounded)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Histórico do estoque',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          '${_movimentacoes.length} movimentações registradas',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_movimentacoes.isEmpty)
            const _EstadoVazio(
              icone: Icons.swap_vert_rounded,
              titulo: 'Nenhuma movimentação',
              descricao: 'Registre entradas, saídas ou ajustes de estoque.',
            )
          else
            ..._movimentacoes.map((movimentacao) {
              final cor = _corTipoMovimentacao(movimentacao.tipo);

              final unidade = _unidadeItemMovimentacao(movimentacao);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cor.withValues(alpha: 0.15),
                      child: Icon(
                        _iconeTipoMovimentacao(movimentacao.tipo),
                        color: cor,
                      ),
                    ),
                    title: Text(
                      _nomeItemMovimentacao(movimentacao),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_nomeTipoMovimentacao(movimentacao.tipo)}'
                          ' • ${_dataFormatada(movimentacao.data)}',
                        ),
                        if (movimentacao.quantidadeAnterior != null &&
                            movimentacao.quantidadePosterior != null)
                          Text(
                            'Anterior: ${_numero(movimentacao.quantidadeAnterior!)} '
                            '$unidade • Posterior: ${_numero(movimentacao.quantidadePosterior!)} $unidade',
                          ),
                        if (movimentacao.observacao.isNotEmpty)
                          Text(
                            movimentacao.observacao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Text(
                      '${movimentacao.tipo == 'ENTRADA'
                          ? '+'
                          : movimentacao.tipo == 'SAIDA'
                          ? '-'
                          : ''}'
                      '${_numero(movimentacao.quantidade)}'
                      '${unidade.isEmpty ? '' : ' $unidade'}',
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _abaConfiguracoes() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_salvandoConfiguracao) const LinearProgressIndicator(),
        if (_salvandoConfiguracao) const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Controlar estoque'),
                subtitle: const Text('Ativa o módulo de controle de produtos.'),
                secondary: const Icon(Icons.inventory_2_outlined),
                value: _configuracao.controlarEstoque,
                onChanged: _salvandoConfiguracao
                    ? null
                    : (valor) {
                        _salvarConfiguracao(
                          _configuracao.copyWith(
                            controlarEstoque: valor,
                            controlarProdutosOrdemServico: valor
                                ? _configuracao.controlarProdutosOrdemServico
                                : false,
                            baixaAutomatica: valor
                                ? _configuracao.baixaAutomatica
                                : false,
                            exigirQuantidade: valor
                                ? _configuracao.exigirQuantidade
                                : false,
                          ),
                        );
                      },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Produtos nas Ordens de Serviço'),
                subtitle: const Text(
                  'Mostra os produtos utilizados dentro das Ordens de Serviço.',
                ),
                secondary: const Icon(Icons.assignment_turned_in_outlined),
                value: _configuracao.controlarProdutosOrdemServico,
                onChanged:
                    !_configuracao.controlarEstoque || _salvandoConfiguracao
                    ? null
                    : (valor) {
                        _salvarConfiguracao(
                          _configuracao.copyWith(
                            controlarProdutosOrdemServico: valor,
                            baixaAutomatica: valor
                                ? _configuracao.baixaAutomatica
                                : false,
                            exigirQuantidade: valor
                                ? _configuracao.exigirQuantidade
                                : false,
                          ),
                        );
                      },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Baixa automática'),
                subtitle: const Text(
                  'Desconta os produtos quando a Ordem de Serviço for finalizada.',
                ),
                secondary: const Icon(Icons.auto_fix_high_outlined),
                value: _configuracao.baixaAutomatica,
                onChanged:
                    !_configuracao.controlarEstoque ||
                        !_configuracao.controlarProdutosOrdemServico ||
                        _salvandoConfiguracao
                    ? null
                    : (valor) {
                        _salvarConfiguracao(
                          _configuracao.copyWith(baixaAutomatica: valor),
                        );
                      },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Exigir quantidade utilizada'),
                subtitle: const Text(
                  'Não permite adicionar produto na Ordem de Serviço sem informar a quantidade.',
                ),
                secondary: const Icon(Icons.numbers_rounded),
                value: _configuracao.exigirQuantidade,
                onChanged:
                    !_configuracao.controlarEstoque ||
                        !_configuracao.controlarProdutosOrdemServico ||
                        _salvandoConfiguracao
                    ? null
                    : (valor) {
                        _salvarConfiguracao(
                          _configuracao.copyWith(exigirQuantidade: valor),
                        );
                      },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Alertar estoque baixo'),
                subtitle: const Text(
                  'Destaca produtos que atingiram a quantidade mínima.',
                ),
                secondary: const Icon(Icons.warning_amber_rounded),
                value: _configuracao.alertarEstoqueBaixo,
                onChanged:
                    !_configuracao.controlarEstoque || _salvandoConfiguracao
                    ? null
                    : (valor) {
                        _salvarConfiguracao(
                          _configuracao.copyWith(alertarEstoqueBaixo: valor),
                        );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFD6A84B),
            ),
            title: const Text(
              'Controle opcional',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Você pode usar apenas o cadastro e as movimentações do estoque sem controlar produtos nas Ordens de Serviço.',
            ),
          ),
        ),
      ],
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
            Icon(icone, color: const Color(0xFFD6A84B)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({
    required this.icone,
    required this.titulo,
    required this.descricao,
  });

  final IconData icone;
  final String titulo;
  final String descricao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        children: [
          Icon(icone, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
