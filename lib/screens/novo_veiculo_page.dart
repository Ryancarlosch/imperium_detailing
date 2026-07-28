import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/veiculo.dart';
import '../repositories/veiculo_repository.dart';

class NovoVeiculoPage extends StatefulWidget {
  const NovoVeiculoPage({
    super.key,
    this.veiculo,
  });

  final Veiculo? veiculo;

  bool get editando => veiculo != null;

  @override
  State<NovoVeiculoPage> createState() =>
      _NovoVeiculoPageState();
}

class _NovoVeiculoPageState
    extends State<NovoVeiculoPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = VeiculoRepository();

  late final TextEditingController _marcaController;
  late final TextEditingController _modeloController;
  late final TextEditingController _placaController;
  late final TextEditingController _corController;
  late final TextEditingController _anoController;
  late final TextEditingController
      _observacoesController;

  List<Map<String, dynamic>> _clientes = [];
  int? _clienteIdSelecionado;

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final veiculo = widget.veiculo;

    _marcaController = TextEditingController(
      text: veiculo?.marca ?? '',
    );
    _modeloController = TextEditingController(
      text: veiculo?.modelo ?? '',
    );
    _placaController = TextEditingController(
      text: veiculo?.placa ?? '',
    );
    _corController = TextEditingController(
      text: veiculo?.cor ?? '',
    );
    _anoController = TextEditingController(
      text: veiculo?.ano ?? '',
    );
    _observacoesController = TextEditingController(
      text: veiculo?.observacoes ?? '',
    );

    _clienteIdSelecionado = veiculo?.clienteId;

    _carregarClientes();
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _placaController.dispose();
    _corController.dispose();
    _anoController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _carregarClientes() async {
    try {
      final database =
          await AppDatabase.instance.database;

      final clientes = await database.query(
        'clientes',
        columns: [
          'id',
          'nome',
          'telefone',
        ],
        orderBy: 'nome ASC',
      );

      if (!mounted) return;

      setState(() {
        _clientes = clientes;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar os clientes: $erro',
        erro: true,
      );
    }
  }

  int? _converterParaInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_clienteIdSelecionado == null) {
      _mostrarMensagem(
        'Selecione o proprietário do veículo.',
        erro: true,
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final veiculo = Veiculo(
        id: widget.veiculo?.id,
        clienteId: _clienteIdSelecionado!,
        marca: _marcaController.text.trim(),
        modelo: _modeloController.text.trim(),
        placa: _placaController.text
            .trim()
            .toUpperCase(),
        cor: _corController.text.trim(),
        ano: _anoController.text.trim(),
        observacoes:
            _observacoesController.text.trim(),
      );

      if (widget.editando) {
        await _repository.atualizarVeiculo(veiculo);
      } else {
        await _repository.inserirVeiculo(veiculo);
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem(
        'Não foi possível salvar o veículo: $erro',
        erro: true,
      );
    }
  }

  void _mostrarMensagem(
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editando
              ? 'Editar veículo'
              : 'Novo veículo',
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
              ? _SemClientes(
                  aoVoltar: () {
                    Navigator.pop(context);
                  },
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<int>(
                        value: _clienteIdSelecionado,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(
                          labelText: 'Proprietário',
                          prefixIcon: Icon(
                            Icons.person_outline,
                          ),
                        ),
                        items: _clientes.map((cliente) {
                          final id = _converterParaInt(
                            cliente['id'],
                          )!;

                          final nome =
                              (cliente['nome'] ?? '')
                                  .toString();

                          final telefone =
                              (cliente['telefone'] ??
                                      '')
                                  .toString()
                                  .trim();

                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(
                              telefone.isEmpty
                                  ? nome
                                  : '$nome • $telefone',
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (valor) {
                          setState(() {
                            _clienteIdSelecionado =
                                valor;
                          });
                        },
                        validator: (valor) {
                          if (valor == null) {
                            return 'Selecione o proprietário.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _marcaController,
                        textCapitalization:
                            TextCapitalization.words,
                        decoration:
                            const InputDecoration(
                          labelText: 'Marca',
                          hintText: 'Ex.: Volkswagen',
                          prefixIcon: Icon(
                            Icons.factory_outlined,
                          ),
                        ),
                        validator: (valor) {
                          if (valor == null ||
                              valor.trim().isEmpty) {
                            return 'Informe a marca.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _modeloController,
                        textCapitalization:
                            TextCapitalization.words,
                        decoration:
                            const InputDecoration(
                          labelText: 'Modelo',
                          hintText: 'Ex.: Golf',
                          prefixIcon: Icon(
                            Icons.directions_car_outlined,
                          ),
                        ),
                        validator: (valor) {
                          if (valor == null ||
                              valor.trim().isEmpty) {
                            return 'Informe o modelo.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _placaController,
                        textCapitalization:
                            TextCapitalization.characters,
                        maxLength: 8,
                        decoration:
                            const InputDecoration(
                          labelText: 'Placa',
                          hintText: 'ABC1D23',
                          prefixIcon: Icon(
                            Icons.pin_outlined,
                          ),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller:
                                  _corController,
                              textCapitalization:
                                  TextCapitalization
                                      .words,
                              decoration:
                                  const InputDecoration(
                                labelText: 'Cor',
                                hintText: 'Ex.: Preto',
                                prefixIcon: Icon(
                                  Icons.palette_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller:
                                  _anoController,
                              keyboardType:
                                  TextInputType.number,
                              maxLength: 9,
                              decoration:
                                  const InputDecoration(
                                labelText: 'Ano',
                                hintText: '2020/2021',
                                prefixIcon: Icon(
                                  Icons
                                      .calendar_today_outlined,
                                ),
                                counterText: '',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller:
                            _observacoesController,
                        minLines: 4,
                        maxLines: 7,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration:
                            const InputDecoration(
                          labelText: 'Observações',
                          hintText:
                              'Detalhes ou informações importantes',
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
                              : 'Salvar veículo',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SemClientes extends StatelessWidget {
  const _SemClientes({
    required this.aoVoltar,
  });

  final VoidCallback aoVoltar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 72,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum cliente cadastrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cadastre um cliente antes de adicionar um veículo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: aoVoltar,
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
