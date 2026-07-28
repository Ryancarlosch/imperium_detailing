import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/orcamento.dart';
import '../repositories/orcamento_repository.dart';

class NovoOrcamentoPage extends StatefulWidget {
  const NovoOrcamentoPage({
    super.key,
    this.orcamento,
  });

  final Orcamento? orcamento;

  @override
  State<NovoOrcamentoPage> createState() =>
      _NovoOrcamentoPageState();
}

class _NovoOrcamentoPageState
    extends State<NovoOrcamentoPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = OrcamentoRepository();
  final _dataFormatada = DateFormat('dd/MM/yyyy');

  late final TextEditingController
      _servicoController;
  late final TextEditingController
      _descricaoController;
  late final TextEditingController
      _valorController;
  late final TextEditingController
      _observacoesController;

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _veiculos = [];

  int? _clienteId;
  int? _veiculoId;
  DateTime _dataEmissao = DateTime.now();
  DateTime _validade =
      DateTime.now().add(const Duration(days: 15));
  String _status = 'Pendente';

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final orcamento = widget.orcamento;

    _servicoController = TextEditingController(
      text: orcamento?.servico ?? '',
    );
    _descricaoController = TextEditingController(
      text: orcamento?.descricao ?? '',
    );
    _valorController = TextEditingController(
      text: orcamento == null
          ? ''
          : orcamento.valor
              .toStringAsFixed(2)
              .replaceAll('.', ','),
    );
    _observacoesController = TextEditingController(
      text: orcamento?.observacoes ?? '',
    );

    if (orcamento != null) {
      _clienteId = orcamento.clienteId;
      _veiculoId = orcamento.veiculoId;
      _status = orcamento.status;
      _dataEmissao =
          DateTime.tryParse(orcamento.dataEmissao) ??
              DateTime.now();
      _validade =
          DateTime.tryParse(orcamento.validade) ??
              DateTime.now().add(
                const Duration(days: 15),
              );
    }

    _carregarDados();
  }

  @override
  void dispose() {
    _servicoController.dispose();
    _descricaoController.dispose();
    _valorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final database =
          await AppDatabase.instance.database;

      final clientes = await database.query(
        'clientes',
        orderBy: 'nome ASC',
      );

      List<Map<String, dynamic>> veiculos = [];

      if (_clienteId != null) {
        veiculos = await database.query(
          'veiculos',
          where: 'cliente_id = ?',
          whereArgs: [_clienteId],
          orderBy: 'marca ASC, modelo ASC',
        );
      }

      if (!mounted) return;

      setState(() {
        _clientes = clientes;
        _veiculos = veiculos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem(
        'Não foi possível carregar os dados: $erro',
        erro: true,
      );
    }
  }

  Future<void> _carregarVeiculos(
    int clienteId,
  ) async {
    final database =
        await AppDatabase.instance.database;

    final veiculos = await database.query(
      'veiculos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'marca ASC, modelo ASC',
    );

    if (!mounted) return;

    setState(() {
      _veiculos = veiculos;
      _veiculoId = null;
    });
  }

  int? _int(dynamic valor) {
    if (valor is int) return valor;
    return int.tryParse(valor?.toString() ?? '');
  }

  double? _valor() {
    return double.tryParse(
      _valorController.text
          .trim()
          .replaceAll('.', '')
          .replaceAll(',', '.'),
    );
  }

  Future<void> _selecionarData({
    required bool validade,
  }) async {
    final atual =
        validade ? _validade : _dataEmissao;

    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (escolhida == null || !mounted) return;

    setState(() {
      if (validade) {
        _validade = escolhida;
      } else {
        _dataEmissao = escolhida;
      }
    });
  }

  Future<void> _salvar() async {
    if (_salvando ||
        !_formKey.currentState!.validate()) {
      return;
    }

    if (_clienteId == null) {
      _mensagem(
        'Selecione um cliente.',
        erro: true,
      );
      return;
    }

    if (_validade.isBefore(_dataEmissao)) {
      _mensagem(
        'A validade não pode ser anterior à emissão.',
        erro: true,
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final orcamento = Orcamento(
        id: widget.orcamento?.id,
        clienteId: _clienteId!,
        veiculoId: _veiculoId,
        servico: _servicoController.text.trim(),
        descricao:
            _descricaoController.text.trim(),
        valor: _valor() ?? 0,
        dataEmissao:
            _dataEmissao.toIso8601String(),
        validade: _validade.toIso8601String(),
        status: _status,
        observacoes:
            _observacoesController.text.trim(),
      );

      if (widget.orcamento == null) {
        await _repository.inserirOrcamento(
          orcamento,
        );
      } else {
        await _repository.atualizarOrcamento(
          orcamento,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _salvando = false;
      });

      _mensagem(
        'Não foi possível salvar: $erro',
        erro: true,
      );
    }
  }

  void _mensagem(
    String mensagem, {
    bool erro = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor:
              erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.orcamento != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editando
              ? 'Editar orçamento'
              : 'Novo orçamento',
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('SALVAR'),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _clientes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Cadastre um cliente antes de criar um orçamento.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding:
                        const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<int>(
                        value: _clienteId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(
                          labelText: 'Cliente',
                          prefixIcon: Icon(
                            Icons.person_outline,
                          ),
                        ),
                        items: _clientes.map((cliente) {
                          return DropdownMenuItem<int>(
                            value: _int(cliente['id']),
                            child: Text(
                              (cliente['nome'] ?? '')
                                  .toString(),
                            ),
                          );
                        }).toList(),
                        onChanged: (valor) async {
                          if (valor == null) return;

                          setState(() {
                            _clienteId = valor;
                          });

                          await _carregarVeiculos(
                            valor,
                          );
                        },
                        validator: (valor) {
                          return valor == null
                              ? 'Selecione um cliente.'
                              : null;
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int?>(
                        value: _veiculoId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Veículo (opcional)',
                          prefixIcon: Icon(
                            Icons
                                .directions_car_outlined,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Sem veículo vinculado',
                            ),
                          ),
                          ..._veiculos.map((veiculo) {
                            final marca =
                                (veiculo['marca'] ?? '')
                                    .toString();
                            final modelo =
                                (veiculo['modelo'] ?? '')
                                    .toString();
                            final placa =
                                (veiculo['placa'] ?? '')
                                    .toString();

                            return DropdownMenuItem<int?>(
                              value:
                                  _int(veiculo['id']),
                              child: Text(
                                placa.isEmpty
                                    ? '$marca $modelo'
                                    : '$marca $modelo • $placa',
                              ),
                            );
                          }),
                        ],
                        onChanged: (valor) {
                          setState(() {
                            _veiculoId = valor;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                            _servicoController,
                        textCapitalization:
                            TextCapitalization
                                .sentences,
                        decoration:
                            const InputDecoration(
                          labelText: 'Serviço',
                          hintText:
                              'Ex.: Polimento técnico',
                          prefixIcon: Icon(
                            Icons
                                .design_services_outlined,
                          ),
                        ),
                        validator: (valor) {
                          if (valor == null ||
                              valor.trim().isEmpty) {
                            return 'Informe o serviço.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                            _descricaoController,
                        minLines: 3,
                        maxLines: 6,
                        textCapitalization:
                            TextCapitalization
                                .sentences,
                        decoration:
                            const InputDecoration(
                          labelText: 'Descrição',
                          hintText:
                              'Detalhes do que será realizado',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(
                            Icons
                                .description_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _valorController,
                        keyboardType:
                            const TextInputType
                                .numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(
                          labelText: 'Valor',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(
                            Icons.attach_money,
                          ),
                        ),
                        validator: (_) {
                          final valor = _valor();

                          if (valor == null ||
                              valor <= 0) {
                            return 'Informe um valor válido.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _CampoData(
                              titulo: 'Emissão',
                              data: _dataFormatada
                                  .format(
                                _dataEmissao,
                              ),
                              aoTocar: () {
                                _selecionarData(
                                  validade: false,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CampoData(
                              titulo: 'Validade',
                              data: _dataFormatada
                                  .format(
                                _validade,
                              ),
                              aoTocar: () {
                                _selecionarData(
                                  validade: true,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration:
                            const InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(
                            Icons
                                .assignment_turned_in_outlined,
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
                        onChanged: (valor) {
                          if (valor == null) return;

                          setState(() {
                            _status = valor;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                            _observacoesController,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization:
                            TextCapitalization
                                .sentences,
                        decoration:
                            const InputDecoration(
                          labelText: 'Observações',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(
                            Icons.notes_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed:
                            _salvando ? null : _salvar,
                        icon: _salvando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.save_outlined,
                              ),
                        label: Text(
                          _salvando
                              ? 'Salvando...'
                              : 'Salvar orçamento',
                        ),
                      ),
                    ],
                  ),
                ),
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
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: titulo,
          prefixIcon: const Icon(
            Icons.calendar_today_outlined,
          ),
        ),
        child: Text(data),
      ),
    );
  }
}
