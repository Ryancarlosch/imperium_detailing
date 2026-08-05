import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/item_orcamento.dart';
import '../models/orcamento.dart';
import '../repositories/orcamento_repository.dart';

class NovoOrcamentoPage extends StatefulWidget {
  const NovoOrcamentoPage({super.key, this.orcamento});

  final Orcamento? orcamento;

  @override
  State<NovoOrcamentoPage> createState() => _NovoOrcamentoPageState();
}

class _NovoOrcamentoPageState extends State<NovoOrcamentoPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = OrcamentoRepository();

  final _observacoesController = TextEditingController();

  final _descontoController = TextEditingController();

  final _formatoData = DateFormat('dd/MM/yyyy');

  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _veiculos = [];
  List<ItemOrcamento> _itens = [];

  int? _clienteId;
  int? _veiculoId;

  DateTime _dataEmissao = DateTime.now();

  DateTime _validade = DateTime.now().add(const Duration(days: 15));

  String _status = 'Pendente';

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final orcamento = widget.orcamento;

    if (orcamento != null) {
      _clienteId = orcamento.clienteId;
      _veiculoId = orcamento.veiculoId;
      _status = orcamento.status;

      _dataEmissao = DateTime.tryParse(orcamento.dataEmissao) ?? DateTime.now();

      _validade =
          DateTime.tryParse(orcamento.validade) ??
          DateTime.now().add(const Duration(days: 15));

      _observacoesController.text = orcamento.observacoes;

      if (orcamento.desconto > 0) {
        _descontoController.text = orcamento.desconto
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }

      if (orcamento.itens.isNotEmpty) {
        _itens = List<ItemOrcamento>.from(orcamento.itens);
      } else if (orcamento.servico.trim().isNotEmpty || orcamento.valor > 0) {
        _itens = [
          ItemOrcamento(
            servico: orcamento.servico.trim().isEmpty
                ? 'Serviço'
                : orcamento.servico,
            descricao: orcamento.descricao,
            quantidade: 1,
            valorUnitario: orcamento.valor,
            ordem: 0,
          ),
        ];
      }
    }

    _carregarDados();
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    _descontoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final database = await AppDatabase.instance.database;

      final clientes = await database.query('clientes', orderBy: 'nome ASC');

      List<Map<String, dynamic>> veiculos = [];

      if (_clienteId != null) {
        veiculos = await database.query(
          'veiculos',
          where: 'cliente_id = ?',
          whereArgs: [_clienteId],
          orderBy: 'marca ASC, modelo ASC',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _clientes = clientes;
        _veiculos = veiculos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem('Não foi possível carregar os dados: $erro', erro: true);
    }
  }

  Future<void> _carregarVeiculos(int clienteId) async {
    try {
      final database = await AppDatabase.instance.database;

      final veiculos = await database.query(
        'veiculos',
        where: 'cliente_id = ?',
        whereArgs: [clienteId],
        orderBy: 'marca ASC, modelo ASC',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _veiculos = veiculos;
        _veiculoId = null;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível carregar os veículos: $erro',
        erro: true,
      );
    }
  }

  int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }

  double _converterValor(String texto) {
    final valorLimpo = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');

    if (valorLimpo.isEmpty) {
      return 0;
    }

    if (valorLimpo.contains(',')) {
      return double.tryParse(
            valorLimpo.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0;
    }

    return double.tryParse(valorLimpo) ?? 0;
  }

  double get _subtotal {
    return _itens.fold<double>(0, (total, item) => total + item.subtotal);
  }

  double get _desconto {
    return _converterValor(_descontoController.text);
  }

  double get _total {
    final total = _subtotal - _desconto;

    if (total < 0) {
      return 0;
    }

    return total;
  }

  Future<void> _selecionarData({required bool validade}) async {
    final dataAtual = validade ? _validade : _dataEmissao;

    final dataEscolhida = await showDatePicker(
      context: context,
      initialDate: dataAtual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (dataEscolhida == null || !mounted) {
      return;
    }

    setState(() {
      if (validade) {
        _validade = dataEscolhida;
      } else {
        _dataEmissao = dataEscolhida;
      }
    });
  }

  Future<void> _abrirFormularioItem({ItemOrcamento? item, int? indice}) async {
    final resultado = await showModalBottomSheet<ItemOrcamento>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return _FormularioItemOrcamento(
          item: item,
          ordem: indice ?? _itens.length,
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    setState(() {
      if (indice == null) {
        _itens.add(resultado.copyWith(ordem: _itens.length));
      } else {
        _itens[indice] = resultado.copyWith(ordem: indice);
      }
    });
  }

  Future<void> _removerItem(int indice) async {
    final item = _itens[indice];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover serviço'),
          content: Text(
            'Deseja remover "${item.servico}" '
            'deste orçamento?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _itens.removeAt(indice);

      _itens = List<ItemOrcamento>.generate(_itens.length, (index) {
        return _itens[index].copyWith(ordem: index);
      });
    });
  }

  Future<void> _salvar() async {
    if (_salvando) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_clienteId == null) {
      _mostrarMensagem('Selecione um cliente.', erro: true);

      return;
    }

    if (_itens.isEmpty) {
      _mostrarMensagem('Adicione pelo menos um serviço.', erro: true);

      return;
    }

    if (_validade.isBefore(_dataEmissao)) {
      _mostrarMensagem(
        'A validade não pode ser anterior à emissão.',
        erro: true,
      );

      return;
    }

    if (_desconto < 0) {
      _mostrarMensagem('O desconto não pode ser negativo.', erro: true);

      return;
    }

    if (_desconto > _subtotal) {
      _mostrarMensagem(
        'O desconto não pode ser maior que o subtotal.',
        erro: true,
      );

      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final primeiroItem = _itens.first;

      final orcamento = Orcamento(
        id: widget.orcamento?.id,
        clienteId: _clienteId!,
        veiculoId: _veiculoId,
        servico: primeiroItem.servico,
        descricao: primeiroItem.descricao,
        valor: _total,
        dataEmissao: _dataEmissao.toIso8601String(),
        validade: _validade.toIso8601String(),
        status: _status,
        observacoes: _observacoesController.text.trim(),
        desconto: _desconto,
        itens: List<ItemOrcamento>.generate(_itens.length, (index) {
          return _itens[index].copyWith(ordem: index);
        }),
      );

      if (widget.orcamento == null) {
        await _repository.inserirOrcamento(orcamento);
      } else {
        await _repository.atualizarOrcamento(orcamento);
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem(
        'Não foi possível salvar o orçamento: $erro',
        erro: true,
      );
    }
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.orcamento != null;

    return PopScope(
      canPop: !_salvando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(editando ? 'Editar orçamento' : 'Novo orçamento'),
          actions: [
            TextButton(
              onPressed: _salvando ? null : _salvar,
              child: const Text('SALVAR'),
            ),
          ],
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _clientes.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Cadastre um cliente antes '
                    'de criar um orçamento.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Secao(
                      titulo: 'Cliente e veículo',
                      icone: Icons.person_outline,
                      child: Column(
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: _clienteId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: _clientes.map((cliente) {
                              return DropdownMenuItem<int>(
                                value: _converterInt(cliente['id']),
                                child: Text(
                                  (cliente['nome'] ?? '',).toString(),
                                ),
                              );
                            }).toList(),
                            onChanged: _salvando
                                ? null
                                : (valor) async {
                                    if (valor == null) {
                                      return;
                                    }

                                    setState(() {
                                      _clienteId = valor;
                                    });

                                    await _carregarVeiculos(valor);
                                  },
                            validator: (valor) {
                              if (valor == null) {
                                return 'Selecione um cliente.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int?>(
                            initialValue: _veiculoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Veículo (opcional)',
                              prefixIcon: Icon(Icons.directions_car_outlined),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Sem veículo vinculado'),
                              ),
                              ..._veiculos.map((veiculo) {
                                final marca = (
                                  veiculo['marca'] ?? '',
                                ).toString();

                                final modelo = (
                                  veiculo['modelo'] ?? '',
                                ).toString();

                                final placa = (
                                  veiculo['placa'] ?? '',
                                ).toString();

                                final texto = placa.isEmpty
                                    ? '$marca $modelo'
                                    : '$marca $modelo • $placa';

                                return DropdownMenuItem<int?>(
                                  value: _converterInt(veiculo['id']),
                                  child: Text(texto.trim()),
                                );
                              }),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) {
                                    setState(() {
                                      _veiculoId = valor;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Serviços',
                      icone: Icons.design_services_outlined,
                      acao: TextButton.icon(
                        onPressed: _salvando
                            ? null
                            : () {
                                _abrirFormularioItem();
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar'),
                      ),
                      child: _itens.isEmpty
                          ? _EstadoSemItens(
                              aoAdicionar: () {
                                _abrirFormularioItem();
                              },
                            )
                          : Column(
                              children: List.generate(_itens.length, (indice) {
                                final item = _itens[indice];

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: indice == _itens.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: _CardItemOrcamento(
                                    item: item,
                                    formatoMoeda: _formatoMoeda,
                                    aoEditar: () {
                                      _abrirFormularioItem(
                                        item: item,
                                        indice: indice,
                                      );
                                    },
                                    aoRemover: () {
                                      _removerItem(indice);
                                    },
                                  ),
                                );
                              }),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Valores do orçamento',
                      icone: Icons.payments_outlined,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _descontoController,
                            enabled: !_salvando,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Desconto',
                              prefixText: 'R\$ ',
                              prefixIcon: Icon(Icons.discount_outlined),
                            ),
                            onChanged: (_) {
                              setState(() {});
                            },
                            validator: (texto) {
                              final desconto = _converterValor(texto ?? '');

                              if (desconto < 0) {
                                return 'Informe um desconto válido.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          _LinhaTotal(
                            titulo: 'Subtotal',
                            valor: _formatoMoeda.format(_subtotal),
                          ),
                          const SizedBox(height: 8),
                          _LinhaTotal(
                            titulo: 'Desconto',
                            valor: _formatoMoeda.format(_desconto),
                          ),
                          const Divider(height: 24),
                          _LinhaTotal(
                            titulo: 'Total',
                            valor: _formatoMoeda.format(_total),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Datas e situação',
                      icone: Icons.calendar_month_outlined,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _CampoData(
                                  titulo: 'Emissão',
                                  data: _formatoData.format(_dataEmissao),
                                  aoTocar: _salvando
                                      ? null
                                      : () {
                                          _selecionarData(validade: false);
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CampoData(
                                  titulo: 'Validade',
                                  data: _formatoData.format(_validade),
                                  aoTocar: _salvando
                                      ? null
                                      : () {
                                          _selecionarData(validade: true);
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              prefixIcon: Icon(
                                Icons.assignment_turned_in_outlined,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Pendente',
                                child: Text('Pendente'),
                              ),
                              DropdownMenuItem(
                                value: 'Aprovado',
                                child: Text('Aprovado'),
                              ),
                              DropdownMenuItem(
                                value: 'Recusado',
                                child: Text('Recusado'),
                              ),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) {
                                    if (valor == null) {
                                      return;
                                    }

                                    setState(() {
                                      _status = valor;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Observações',
                      icone: Icons.notes_outlined,
                      child: TextFormField(
                        controller: _observacoesController,
                        enabled: !_salvando,
                        minLines: 3,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Observações gerais',
                          hintText:
                              'Condições, prazo, garantia ou outras informações',
                          alignLabelWithHint: true,
                        ),
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
                      label: Text(
                        _salvando
                            ? 'Salvando...'
                            : editando
                            ? 'Salvar alterações'
                            : 'Criar orçamento',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

class _FormularioItemOrcamento extends StatefulWidget {
  const _FormularioItemOrcamento({required this.ordem, this.item});

  final ItemOrcamento? item;
  final int ordem;

  @override
  State<_FormularioItemOrcamento> createState() =>
      _FormularioItemOrcamentoState();
}

class _FormularioItemOrcamentoState extends State<_FormularioItemOrcamento> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _servicoController;

  late final TextEditingController _descricaoController;

  late final TextEditingController _quantidadeController;

  late final TextEditingController _valorController;

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    _servicoController = TextEditingController(text: item?.servico ?? '');

    _descricaoController = TextEditingController(text: item?.descricao ?? '');

    _quantidadeController = TextEditingController(
      text: item == null ? '1' : _formatarNumero(item.quantidade),
    );

    _valorController = TextEditingController(
      text: item == null
          ? ''
          : item.valorUnitario.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _servicoController.dispose();
    _descricaoController.dispose();
    _quantidadeController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  static String _formatarNumero(double numero) {
    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    return numero
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }

  double _converterValor(String texto) {
    final textoLimpo = texto.trim();

    if (textoLimpo.isEmpty) {
      return 0;
    }

    if (textoLimpo.contains(',')) {
      return double.tryParse(
            textoLimpo.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0;
    }

    return double.tryParse(textoLimpo) ?? 0;
  }

  double get _quantidade {
    return _converterValor(_quantidadeController.text);
  }

  double get _valorUnitario {
    return _converterValor(_valorController.text);
  }

  double get _subtotal {
    return _quantidade * _valorUnitario;
  }

  void _salvarItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final item = ItemOrcamento(
      id: widget.item?.id,
      orcamentoId: widget.item?.orcamentoId,
      servico: _servicoController.text.trim(),
      descricao: _descricaoController.text.trim(),
      quantidade: _quantidade,
      valorUnitario: _valorUnitario,
      ordem: widget.ordem,
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final editando = widget.item != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editando ? 'Editar serviço' : 'Adicionar serviço',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _servicoController,
                autofocus: !editando,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Serviço',
                  hintText: 'Ex.: Polimento técnico',
                  prefixIcon: Icon(Icons.design_services_outlined),
                ),
                validator: (texto) {
                  if (texto == null || texto.trim().isEmpty) {
                    return 'Informe o serviço.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descricaoController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                  hintText: 'Detalhes do serviço',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.description_outlined),
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
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      validator: (texto) {
                        final quantidade = _converterValor(texto ?? '');

                        if (quantidade <= 0) {
                          return 'Valor inválido.';
                        }

                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _valorController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Valor unitário',
                        prefixText: 'R\$ ',
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      validator: (texto) {
                        final valor = _converterValor(texto ?? '');

                        if (valor <= 0) {
                          return 'Valor inválido.';
                        }

                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subtotal do serviço',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(_subtotal),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _salvarItem,
                icon: const Icon(Icons.check),
                label: Text(editando ? 'Salvar serviço' : 'Adicionar serviço'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.icone,
    required this.child,
    this.acao,
  });

  final String titulo;
  final IconData icone;
  final Widget child;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icone, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?acao,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _EstadoSemItens extends StatelessWidget {
  const _EstadoSemItens({required this.aoAdicionar});

  final VoidCallback aoAdicionar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          const Icon(Icons.playlist_add_outlined, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Nenhum serviço adicionado',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Adicione os serviços que farão parte deste orçamento.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: aoAdicionar,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar serviço'),
          ),
        ],
      ),
    );
  }
}

class _CardItemOrcamento extends StatelessWidget {
  const _CardItemOrcamento({
    required this.item,
    required this.formatoMoeda,
    required this.aoEditar,
    required this.aoRemover,
  });

  final ItemOrcamento item;
  final NumberFormat formatoMoeda;
  final VoidCallback aoEditar;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.servico,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (opcao) {
                  if (opcao == 'editar') {
                    aoEditar();
                  } else if (opcao == 'remover') {
                    aoRemover();
                  }
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remover',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Remover'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          if (item.descricao.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.descricao),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InfoItem(
                titulo: 'Quantidade',
                valor: _formatarQuantidade(item.quantidade),
              ),
              _InfoItem(
                titulo: 'Valor unitário',
                valor: formatoMoeda.format(item.valorUnitario),
              ),
              _InfoItem(
                titulo: 'Subtotal',
                valor: formatoMoeda.format(item.subtotal),
                destaque: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatarQuantidade(double quantidade) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaTotal extends StatelessWidget {
  const _LinhaTotal({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final estilo = destaque
        ? Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;

    return Row(
      children: [
        Expanded(child: Text(titulo, style: estilo)),
        Text(valor, style: estilo),
      ],
    );
  }
}

class _CampoData extends StatelessWidget {
  const _CampoData({
    required this.titulo,
    required this.data,
    required this.aoTocar,
  });

  final String titulo;
  final String data;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: titulo,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(data),
      ),
    );
  }
}
