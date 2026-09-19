import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_estoque_produtos_service.dart';
import 'imperium_web_theme.dart';

class WebEstoqueProdutosPage extends StatefulWidget {
  const WebEstoqueProdutosPage({super.key});

  @override
  State<WebEstoqueProdutosPage> createState() => _WebEstoqueProdutosPageState();
}

class _WebEstoqueProdutosPageState extends State<WebEstoqueProdutosPage> {
  final _service = WebEstoqueProdutosService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  late Future<List<Map<String, dynamic>>> _future;
  final _busca = TextEditingController();
  bool _mostrarInativos = false;

  @override
  void initState() {
    super.initState();
    _future = _carregar();
  }

  Future<List<Map<String, dynamic>>> _carregar() {
    return _service.listarItens(incluirInativos: true);
  }

  void _recarregar() {
    setState(() => _future = _carregar());
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _abrirProduto([Map<String, dynamic>? item]) async {
    final editando = item != null;
    final nome = TextEditingController(text: item?['nome']?.toString() ?? '');
    final categoria = TextEditingController(
      text: item?['categoria']?.toString() ?? '',
    );
    final minimo = TextEditingController(
      text: editando ? _numero(_double(item['quantidade_minima'])) : '0',
    );
    final ean = TextEditingController(text: item?['ean']?.toString() ?? '');
    final fornecedor = TextEditingController(
      text: item?['fornecedor']?.toString() ?? '',
    );
    final observacoes = TextEditingController(
      text: item?['observacoes']?.toString() ?? '',
    );
    final quantidadeInicial = TextEditingController();
    final valorTotalPago = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var unidadeBase = _unidadeBase(item?['unidade']?.toString() ?? 'unidade');
    var unidadeCompra = _unidadesCompra(unidadeBase).first;
    var ativo = item?['ativo'] != false;
    var salvando = false;
    String? erro;

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final saldo = _double(item?['quantidade']);
            final bloquearUnidade = editando && saldo.abs() > 0.000001;
            final unidadesCompra = _unidadesCompra(unidadeBase);
            if (!unidadesCompra.contains(unidadeCompra)) {
              unidadeCompra = unidadesCompra.first;
            }

            Future<void> salvar() async {
              if (salvando || !(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final quantidadeInicialNumero = _double(quantidadeInicial.text);
              final valorPagoNumero = _double(valorTotalPago.text);

              setModalState(() {
                salvando = true;
                erro = null;
              });

              try {
                if (editando) {
                  await _service.atualizarProduto(
                    item: item,
                    nome: nome.text,
                    categoria: categoria.text,
                    quantidadeMinima: _double(minimo.text),
                    unidadeBase: unidadeBase,
                    ativo: ativo,
                    ean: ean.text,
                    fornecedor: fornecedor.text,
                    observacoes: observacoes.text,
                  );
                } else {
                  await _service.criarProduto(
                    nome: nome.text,
                    categoria: categoria.text,
                    quantidadeMinima: _double(minimo.text),
                    unidadeBase: unidadeBase,
                    ean: ean.text,
                    fornecedor: fornecedor.text,
                    observacoes: observacoes.text,
                    quantidadeInicial: quantidadeInicialNumero,
                    unidadeCompra: unidadeCompra,
                    valorTotalPago: quantidadeInicialNumero > 0
                        ? valorPagoNumero
                        : null,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  salvando = false;
                  erro = _textoErro(e);
                });
              }
            }

            return AlertDialog(
              title: Text(editando ? 'Editar produto' : 'Novo produto'),
              content: SizedBox(
                width: 680,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (editando)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Saldo atual: ${_numero(saldo)} ${item['unidade'] ?? ''}. '
                              'Para alterar quantidade use a aba Movimentações.',
                            ),
                          ),
                        TextFormField(
                          controller: nome,
                          enabled: !salvando,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nome do produto *',
                          ),
                          validator: (texto) {
                            if ((texto ?? '').trim().length < 2) {
                              return 'Informe o nome do produto.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: categoria,
                          enabled: !salvando,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: unidadeBase,
                                decoration: const InputDecoration(
                                  labelText: 'Unidade base *',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'ml',
                                    child: Text('ml'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'g',
                                    child: Text('g'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'metro',
                                    child: Text('metro'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'unidade',
                                    child: Text('unidade'),
                                  ),
                                ],
                                onChanged: salvando || bloquearUnidade
                                    ? null
                                    : (valor) {
                                        if (valor == null) return;
                                        setModalState(() {
                                          unidadeBase = valor;
                                          unidadeCompra = _unidadesCompra(
                                            valor,
                                          ).first;
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: minimo,
                                enabled: !salvando,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Estoque mínimo *',
                                ),
                                validator: (texto) {
                                  final valor = _double(texto);
                                  if ((texto ?? '').trim().isEmpty ||
                                      valor < 0) {
                                    return 'Informe um mínimo válido.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        if (bloquearUnidade) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'A unidade base só pode mudar quando o saldo estiver zerado.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: ean,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'EAN / código de barras',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: fornecedor,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Fornecedor padrão',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: observacoes,
                          enabled: !salvando,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                          ),
                        ),
                        if (!editando) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 10),
                          const Text(
                            'Entrada inicial opcional',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Se informar quantidade, o lote e a movimentação são criados no mesmo commit Cloud.',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: quantidadeInicial,
                                  enabled: !salvando,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Quantidade inicial',
                                  ),
                                  validator: (texto) {
                                    if ((texto ?? '').trim().isNotEmpty &&
                                        _double(texto) < 0) {
                                      return 'Quantidade inválida.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: unidadeCompra,
                                  decoration: const InputDecoration(
                                    labelText: 'Unidade da compra',
                                  ),
                                  items: unidadesCompra
                                      .map(
                                        (unidade) => DropdownMenuItem<String>(
                                          value: unidade,
                                          child: Text(_rotuloUnidade(unidade)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: salvando
                                      ? null
                                      : (valor) {
                                          if (valor != null) {
                                            setModalState(
                                              () => unidadeCompra = valor,
                                            );
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: valorTotalPago,
                            enabled: !salvando,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Valor total pago na entrada inicial',
                              prefixText: 'R\$ ',
                            ),
                            validator: (texto) {
                              if (_double(quantidadeInicial.text) > 0 &&
                                  _double(texto) <= 0) {
                                return 'Informe o valor total pago.';
                              }
                              return null;
                            },
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Produto ativo'),
                            subtitle: const Text(
                              'Ao inativar, o produto deixa de aparecer nas operações novas.',
                            ),
                            value: ativo,
                            onChanged: salvando
                                ? null
                                : (valor) => setModalState(() => ativo = valor),
                          ),
                        ],
                        if (erro != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            erro!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: salvando ? null : salvar,
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar produto'),
                ),
              ],
            );
          },
        );
      },
    );

    nome.dispose();
    categoria.dispose();
    minimo.dispose();
    ean.dispose();
    fornecedor.dispose();
    observacoes.dispose();
    quantidadeInicial.dispose();
    valorTotalPago.dispose();

    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editando
                ? 'Produto atualizado na nuvem.'
                : 'Produto cadastrado e pronto para sincronizar com o aplicativo.',
          ),
        ),
      );
      _recarregar();
    }
  }

  Widget _resumoCard({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _textoErro(snapshot.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final todos = snapshot.data!;
        final ativos = todos.where((item) => item['ativo'] != false).length;
        final inativos = todos.length - ativos;
        final termo = _busca.text.trim().toLowerCase();

        final itens =
            todos.where((item) {
              final ativo = item['ativo'] != false;
              if (!_mostrarInativos && !ativo) return false;
              if (termo.isEmpty) return true;

              return [
                item['nome'],
                item['categoria'],
                item['ean'],
                item['fornecedor'],
                item['unidade'],
              ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
            }).toList()..sort(
              (a, b) => (a['nome'] ?? '').toString().toLowerCase().compareTo(
                (b['nome'] ?? '').toString().toLowerCase(),
              ),
            );

        final valorEstoque = todos.fold<double>(0, (total, item) {
          final custo = _double(item['custo_unitario_calculado']) > 0
              ? _double(item['custo_unitario_calculado'])
              : _double(item['custo_unitario']);
          return total + (_double(item['quantidade']) * custo);
        });

        final abaixoMinimo = todos.where((item) {
          if (item['ativo'] == false) return false;
          final minimo = _double(item['quantidade_minima']);
          return minimo > 0 && _double(item['quantidade']) <= minimo;
        }).length;

        return RefreshIndicator(
          onRefresh: () async {
            _recarregar();
            await _future;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 760;
              final tabela = constraints.maxWidth >= 980;
              final larguraDisponivel =
                  constraints.maxWidth - (compacto ? 32 : 48);
              final colunas = constraints.maxWidth >= 1100
                  ? 4
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              final larguraCard =
                  (larguraDisponivel - (12 * (colunas - 1))) / colunas;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  compacto ? 16 : 24,
                  compacto ? 18 : 24,
                  compacto ? 16 : 24,
                  40,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cadastro de produtos',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Produtos, custos, estoque mínimo e fornecedores sincronizados com a operação.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      FilledButton.icon(
                        onPressed: () => _abrirProduto(),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(compacto ? 'Novo' : 'Novo produto'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Ativos',
                        valor: '$ativos',
                        detalhe: 'Produtos disponíveis na operação',
                        icone: Icons.inventory_2_outlined,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Inativos',
                        valor: '$inativos',
                        detalhe: 'Cadastros fora das operações novas',
                        icone: Icons.inventory_2_outlined,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Abaixo do mínimo',
                        valor: '$abaixoMinimo',
                        detalhe: 'Produtos que precisam de atenção',
                        icone: Icons.warning_amber_rounded,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Valor em estoque',
                        valor: _moeda.format(valorEstoque),
                        detalhe: 'Custo estimado do saldo atual',
                        icone: Icons.payments_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compacto ? larguraDisponivel - 28 : 430,
                            child: TextField(
                              controller: _busca,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText:
                                    'Buscar produto, categoria, EAN ou fornecedor',
                                suffixIcon: _busca.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar busca',
                                        onPressed: () {
                                          _busca.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                          ),
                          FilterChip(
                            selected: _mostrarInativos,
                            onSelected: (valor) {
                              setState(() => _mostrarInativos = valor);
                            },
                            avatar: const Icon(
                              Icons.inventory_2_outlined,
                              size: 17,
                            ),
                            label: const Text('Mostrar inativos'),
                          ),
                          Text(
                            '${itens.length} resultado(s)',
                            style: const TextStyle(
                              color: Color(0xFF89939E),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (itens.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 40,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 42,
                              color: Color(0xFF89939E),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Nenhum produto encontrado',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (tabela)
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 60,
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('PRODUTO')),
                            DataColumn(label: Text('CATEGORIA')),
                            DataColumn(label: Text('SALDO')),
                            DataColumn(label: Text('MÍNIMO')),
                            DataColumn(label: Text('CUSTO UNITÁRIO')),
                            DataColumn(label: Text('FORNECEDOR')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('AÇÃO')),
                          ],
                          rows: itens.map((item) {
                            final saldo = _double(item['quantidade']);
                            final minimo = _double(item['quantidade_minima']);
                            final custo =
                                _double(item['custo_unitario_calculado']) > 0
                                ? _double(item['custo_unitario_calculado'])
                                : _double(item['custo_unitario']);
                            final unidade = (item['unidade'] ?? '').toString();
                            final ativo = item['ativo'] != false;
                            final baixo = minimo > 0 && saldo <= minimo;

                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 240,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 17,
                                          child: Icon(
                                            baixo
                                                ? Icons.warning_amber_rounded
                                                : Icons.inventory_2_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            (item['nome'] ?? 'Produto')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      (item['categoria'] ?? '—').toString(),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${_numero(saldo)} $unidade',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: baixo ? Colors.orangeAccent : null,
                                    ),
                                  ),
                                ),
                                DataCell(Text('${_numero(minimo)} $unidade')),
                                DataCell(
                                  Text(
                                    custo > 0
                                        ? '${_moeda.format(custo)} / $unidade'
                                        : '—',
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 180,
                                    child: Text(
                                      (item['fornecedor'] ?? '—').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Chip(
                                    label: Text(ativo ? 'Ativo' : 'Inativo'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    tooltip: 'Editar produto',
                                    onPressed: () => _abrirProduto(item),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  else
                    ...itens.map((item) {
                      final saldo = _double(item['quantidade']);
                      final minimo = _double(item['quantidade_minima']);
                      final custo =
                          _double(item['custo_unitario_calculado']) > 0
                          ? _double(item['custo_unitario_calculado'])
                          : _double(item['custo_unitario']);
                      final unidade = (item['unidade'] ?? '').toString();
                      final ativo = item['ativo'] != false;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.inventory_2_outlined),
                            ),
                            title: Text(
                              (item['nome'] ?? 'Produto').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              [
                                    (item['categoria'] ?? '').toString(),
                                    'Saldo ${_numero(saldo)} $unidade',
                                    'Mínimo ${_numero(minimo)}',
                                    if (custo > 0) _moeda.format(custo),
                                    if (!ativo) 'Inativo',
                                  ]
                                  .where((texto) => texto.trim().isNotEmpty)
                                  .join(' · '),
                            ),
                            trailing: IconButton(
                              tooltip: 'Editar produto',
                              onPressed: () => _abrirProduto(item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

List<String> _unidadesCompra(String base) {
  switch (_unidadeBase(base)) {
    case 'ml':
      return const ['ml', 'l'];
    case 'g':
      return const ['g', 'kg'];
    case 'metro':
      return const ['metro'];
    default:
      return const ['unidade'];
  }
}

String _unidadeBase(String valor) {
  switch (valor.trim().toLowerCase()) {
    case 'ml':
    case 'l':
    case 'litro':
    case 'litros':
      return 'ml';
    case 'g':
    case 'kg':
    case 'quilo':
    case 'quilos':
      return 'g';
    case 'm':
    case 'metro':
    case 'metros':
      return 'metro';
    default:
      return 'unidade';
  }
}

String _rotuloUnidade(String unidade) {
  return switch (unidade) {
    'l' => 'L',
    'kg' => 'kg',
    'ml' => 'ml',
    'g' => 'g',
    'metro' => 'metro',
    _ => 'unidade',
  };
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

String _numero(double valor) {
  if (valor == valor.truncateToDouble()) return valor.toInt().toString();
  return valor
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

String _textoErro(Object erro) {
  final texto = erro.toString();
  const prefixos = [
    'PostgrestException(message: ',
    'Exception: ',
    'Bad state: ',
  ];
  var resultado = texto;
  for (final prefixo in prefixos) {
    if (resultado.startsWith(prefixo)) {
      resultado = resultado.substring(prefixo.length);
    }
  }
  final detalhes = resultado.indexOf(', code:');
  if (detalhes > 0) resultado = resultado.substring(0, detalhes);
  if (resultado.endsWith(')')) {
    resultado = resultado.substring(0, resultado.length - 1);
  }
  return resultado.trim();
}
