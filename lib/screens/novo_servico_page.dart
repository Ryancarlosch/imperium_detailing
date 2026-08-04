import 'package:flutter/material.dart';

import '../models/servico_catalogo.dart';
import '../models/servico_produto.dart';
import '../repositories/servico_repository.dart';

class NovoServicoPage extends StatefulWidget {
  const NovoServicoPage({super.key, this.servico});

  final ServicoCatalogo? servico;

  @override
  State<NovoServicoPage> createState() => _NovoServicoPageState();
}

class _NovoServicoPageState extends State<NovoServicoPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ServicoRepository();

  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _observacoes = TextEditingController();
  final _precoPadrao = TextEditingController();
  final _horas = TextEditingController();
  final _minutos = TextEditingController();

  bool _ativo = true;
  bool _carregando = true;
  bool _salvando = false;

  List<Map<String, dynamic>> _produtosDisponiveis = [];
  List<ServicoCategoria> _categorias = [];
  int? _categoriaSelecionadaId;
  final List<_ProdutoForm> _produtos = [];

  bool get _editando => widget.servico != null;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  @override
  void dispose() {
    for (final controller in [
      _nome,
      _descricao,
      _observacoes,
      _precoPadrao,
      _horas,
      _minutos,
    ]) {
      controller.dispose();
    }

    for (final produto in _produtos) {
      produto.dispose();
    }

    super.dispose();
  }

  Future<void> _preparar() async {
    _produtosDisponiveis = await _repository.listarProdutosDisponiveis();
    _categorias = await _repository.listarCategorias();

    final servico = widget.servico;

    if (servico != null) {
      _nome.text = servico.nome;
      _descricao.text = servico.descricao;
      _observacoes.text = servico.observacoesPadrao;
      _precoPadrao.text = _numero(servico.precoPadrao);
      _horas.text = '${servico.duracaoMinutos ~/ 60}';
      _minutos.text = '${servico.duracaoMinutos % 60}';
      _ativo = servico.ativo;

      _categoriaSelecionadaId = servico.categoriaId;

      if (_categoriaSelecionadaId == null &&
          servico.categoria.trim().isNotEmpty) {
        for (final categoria in _categorias) {
          if (categoria.nome.trim().toLowerCase() ==
              servico.categoria.trim().toLowerCase()) {
            _categoriaSelecionadaId = categoria.id;
            break;
          }
        }
      }

      if (servico.id != null) {
        final produtos = await _repository.listarProdutosDoServico(servico.id!);

        _produtos.addAll(produtos.map(_ProdutoForm.fromModel));
      }
    }

    if (!mounted) return;

    setState(() => _carregando = false);
  }

  Future<void> _criarCategoria() async {
    final controller = TextEditingController();
    bool salvando = false;

    final criada = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nova categoria'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da categoria',
                  hintText: 'Ex.: Polimento',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: salvando
                      ? null
                      : () async {
                          final nome = controller.text.trim();
                          if (nome.isEmpty) {
                            return;
                          }

                          setDialogState(() => salvando = true);

                          try {
                            final id = await _repository.criarCategoria(nome);
                            _categorias = await _repository.listarCategorias();
                            _categoriaSelecionadaId = id;
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              setDialogState(() => salvando = false);
                            }
                          }
                        },
                  child: Text(salvando ? 'Salvando...' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (criada == true && mounted) {
      setState(() {});
    }
  }

  String _numero(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _valor(TextEditingController controller) {
    var texto = controller.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  Future<void> _adicionarProduto() async {
    final usados = _produtos.map((e) => e.itemId).toSet();

    final disponiveis = _produtosDisponiveis
        .where((item) => !usados.contains((item['id'] as num).toInt()))
        .toList();

    if (disponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há outros produtos disponíveis no estoque.'),
        ),
      );
      return;
    }

    final selecionado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Selecionar produto',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ...disponiveis.map(
            (item) => ListTile(
              title: Text(item['nome']?.toString() ?? ''),
              subtitle: Text(
                '${item['quantidade']} ${item['unidade']} em estoque',
              ),
              onTap: () => Navigator.pop(context, item),
            ),
          ),
        ],
      ),
    );

    if (selecionado == null || !mounted) {
      return;
    }

    setState(() {
      _produtos.add(
        _ProdutoForm(
          itemId: (selecionado['id'] as num).toInt(),
          nome: selecionado['nome']?.toString() ?? '',
          unidade: selecionado['unidade']?.toString() ?? '',
          custoUnitario:
              ((selecionado['custo_unitario_calculado'] as num?)?.toDouble() ??
                      0) >
                  0
              ? (selecionado['custo_unitario_calculado'] as num).toDouble()
              : (selecionado['custo_unitario'] as num?)?.toDouble() ?? 0,
        ),
      );
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final padrao = _valor(_precoPadrao);

    for (final produto in _produtos) {
      if (produto.quantidade <= 0) {
        _erro('Informe a quantidade de ${produto.nome}.');
        return;
      }
    }

    setState(() => _salvando = true);

    try {
      final agora = DateTime.now().toIso8601String();

      final categoria = _categorias.firstWhere(
        (item) => item.id == _categoriaSelecionadaId,
        orElse: () => const ServicoCategoria(nome: '', ativo: true),
      );

      final servico = ServicoCatalogo(
        id: widget.servico?.id,
        nome: _nome.text.trim(),
        categoriaId: categoria.id,
        categoria: categoria.nome,
        descricao: _descricao.text.trim(),
        observacoesPadrao: _observacoes.text.trim(),
        precoPadrao: padrao,
        duracaoMinutos:
            (int.tryParse(_horas.text) ?? 0) * 60 +
            (int.tryParse(_minutos.text) ?? 0),
        ativo: _ativo,
        criadoEm: widget.servico?.criadoEm ?? agora,
        atualizadoEm: agora,
      );

      final produtos = _produtos
          .asMap()
          .entries
          .map(
            (entry) => entry.value.toModel(
              servicoId: widget.servico?.id ?? 0,
              ordem: entry.key,
            ),
          )
          .toList();

      if (_editando) {
        await _repository.atualizarServico(servico, produtos: produtos);
      } else {
        await _repository.inserirServico(servico, produtos: produtos);
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) return;

      setState(() => _salvando = false);
      _erro('Erro ao salvar serviço: $erro');
    }
  }

  void _erro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar serviço' : 'Novo serviço'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(
                labelText: 'Nome do serviço',
                prefixIcon: Icon(Icons.cleaning_services_outlined),
              ),
              validator: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Informe o nome.';
                }

                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _categoriaSelecionadaId,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sem categoria'),
                      ),
                      ..._categorias.map(
                        (categoria) => DropdownMenuItem<int?>(
                          value: categoria.id,
                          child: Text(categoria.nome),
                        ),
                      ),
                    ],
                    onChanged: (valor) {
                      setState(() => _categoriaSelecionadaId = valor);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _criarCategoria,
                  tooltip: 'Criar categoria',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descricao,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacoes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observações padrão',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Preços',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _campoValor(
                    _precoPadrao,
                    'Preço padrão',
                    obrigatorio: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Tempo estimado',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _horas,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Horas'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _minutos,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutos'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Produtos utilizados',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _adicionarProduto,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            if (_produtos.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Nenhum produto vinculado.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._produtos.asMap().entries.map(
                (entry) => _produtoCard(entry.key, entry.value),
              ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _ativo,
              onChanged: (valor) {
                setState(() => _ativo = valor);
              },
              title: const Text('Serviço ativo'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_salvando ? 'Salvando...' : 'Salvar serviço'),
          ),
        ),
      ),
    );
  }

  Widget _campoValor(
    TextEditingController controller,
    String label, {
    bool obrigatorio = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, prefixText: 'R\$ '),
      validator: obrigatorio
          ? (_) => _valor(controller) <= 0 ? 'Obrigatório' : null
          : null,
    );
  }

  Widget _produtoCard(int indice, _ProdutoForm produto) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    produto.nome,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      final removido = _produtos.removeAt(indice);
                      removido.dispose();
                    });
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: produto.quantidadeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantidade padrão',
                suffixText: produto.unidade,
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: produto.obrigatorio,
              onChanged: (valor) {
                setState(() {
                  produto.obrigatorio = valor;

                  if (valor) {
                    produto.marcadoPorPadrao = true;
                  }
                });
              },
              title: const Text('Obrigatório'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: produto.marcadoPorPadrao,
              onChanged: produto.obrigatorio
                  ? null
                  : (valor) {
                      setState(() {
                        produto.marcadoPorPadrao = valor;
                      });
                    },
              title: const Text('Marcado por padrão'),
              subtitle: const Text('Pode ser alterado na Ordem de Serviço.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProdutoForm {
  _ProdutoForm({
    required this.itemId,
    required this.nome,
    required this.unidade,
    required this.custoUnitario,
    double quantidade = 0,
    this.obrigatorio = false,
    this.marcadoPorPadrao = false,
  }) : quantidadeController = TextEditingController(
         text: quantidade <= 0
             ? ''
             : quantidade.toString().replaceAll('.', ','),
       );

  factory _ProdutoForm.fromModel(ServicoProduto produto) {
    return _ProdutoForm(
      itemId: produto.itemEstoqueId,
      nome: produto.produtoNome,
      unidade: produto.unidade,
      custoUnitario: produto.custoUnitario,
      quantidade: produto.quantidadePadrao,
      obrigatorio: produto.obrigatorio,
      marcadoPorPadrao: produto.marcadoPorPadrao,
    );
  }

  final int itemId;
  final String nome;
  final String unidade;
  final double custoUnitario;
  final TextEditingController quantidadeController;

  bool obrigatorio;
  bool marcadoPorPadrao;

  double get quantidade {
    return double.tryParse(
          quantidadeController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
  }

  ServicoProduto toModel({required int servicoId, required int ordem}) {
    return ServicoProduto(
      servicoId: servicoId,
      itemEstoqueId: itemId,
      quantidadePadrao: quantidade,
      unidade: unidade,
      obrigatorio: obrigatorio,
      marcadoPorPadrao: obrigatorio || marcadoPorPadrao,
      ordem: ordem,
      produtoNome: nome,
      custoUnitario: custoUnitario,
    );
  }

  void dispose() {
    quantidadeController.dispose();
  }
}
