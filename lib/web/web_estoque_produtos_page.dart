import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_estoque_produtos_service.dart';

class WebEstoqueProdutosPage extends StatefulWidget {
  const WebEstoqueProdutosPage({super.key});

  @override
  State<WebEstoqueProdutosPage> createState() =>
      _WebEstoqueProdutosPageState();
}

class _WebEstoqueProdutosPageState extends State<WebEstoqueProdutosPage> {
  final _service = WebEstoqueProdutosService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  late Future<List<Map<String, dynamic>>> _future;
  bool _mostrarInativos = false;

  @override
  void initState() {
    super.initState();
    _future = _carregar();
  }

  Future<List<Map<String, dynamic>>> _carregar() {
    return _service.listarItens(incluirInativos: _mostrarInativos);
  }

  void _recarregar() {
    setState(() => _future = _carregar());
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
                                  DropdownMenuItem(value: 'ml', child: Text('ml')),
                                  DropdownMenuItem(value: 'g', child: Text('g')),
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
                                          unidadeCompra =
                                              _unidadesCompra(valor).first;
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
                                  if ((texto ?? '').trim().isEmpty || valor < 0) {
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

        final itens = snapshot.data!;
        final ativos = itens.where((item) => item['ativo'] != false).length;
        final inativos = itens.length - ativos;

        return RefreshIndicator(
          onRefresh: () async {
            _recarregar();
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cadastro de produtos',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Metadados sincronizados com o aplicativo. Saldo só muda por movimentação.',
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Mostrar inativos'),
                        selected: _mostrarInativos,
                        onSelected: (valor) {
                          setState(() {
                            _mostrarInativos = valor;
                            _future = _carregar();
                          });
                        },
                      ),
                      FilledButton.icon(
                        onPressed: () => _abrirProduto(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Novo produto'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ProdutoResumoCard(titulo: 'Ativos', valor: '$ativos'),
                  _ProdutoResumoCard(titulo: 'Inativos', valor: '$inativos'),
                  _ProdutoResumoCard(titulo: 'Total listado', valor: '${itens.length}'),
                ],
              ),
              const SizedBox(height: 20),
              if (itens.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhum produto encontrado.'),
                  ),
                )
              else
                ...itens.map((item) {
                  final saldo = _double(item['quantidade']);
                  final custo = _double(item['custo_unitario_calculado']) > 0
                      ? _double(item['custo_unitario_calculado'])
                      : _double(item['custo_unitario']);
                  final ativo = item['ativo'] != false;
                  final unidade = (item['unidade'] ?? '').toString();

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        ativo
                            ? Icons.inventory_2_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text((item['nome'] ?? 'Produto').toString()),
                          ),
                          if (!ativo) const Chip(label: Text('Inativo')),
                        ],
                      ),
                      subtitle: Text(
                        [
                          (item['categoria'] ?? '').toString(),
                          'Saldo ${_numero(saldo)} $unidade',
                          'Mínimo ${_numero(_double(item['quantidade_minima']))}',
                          if (custo > 0) 'Custo ${_moeda.format(custo)} / $unidade',
                          if ((item['ean'] ?? '').toString().trim().isNotEmpty)
                            'EAN ${item['ean']}',
                        ].where((texto) => texto.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Editar produto',
                        onPressed: () => _abrirProduto(item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _ProdutoResumoCard extends StatelessWidget {
  const _ProdutoResumoCard({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo),
              const SizedBox(height: 5),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
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
  return valor.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(
    RegExp(r'\.$'),
    '',
  );
}

String _textoErro(Object erro) {
  final texto = erro.toString();
  const prefixos = ['PostgrestException(message: ', 'Exception: ', 'Bad state: '];
  var resultado = texto;
  for (final prefixo in prefixos) {
    if (resultado.startsWith(prefixo)) {
      resultado = resultado.substring(prefixo.length);
    }
  }
  final detalhes = resultado.indexOf(', code:');
  if (detalhes > 0) resultado = resultado.substring(0, detalhes);
  if (resultado.endsWith(')')) resultado = resultado.substring(0, resultado.length - 1);
  return resultado.trim();
}
