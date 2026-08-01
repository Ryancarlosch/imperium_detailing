import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/movimento_financeiro.dart';
import '../repositories/financeiro_repository.dart';

class NovoMovimentoPage extends StatefulWidget {
  const NovoMovimentoPage({super.key, this.movimento});

  final Map<String, dynamic>? movimento;

  @override
  State<NovoMovimentoPage> createState() => _NovoMovimentoPageState();
}

class _NovoMovimentoPageState extends State<NovoMovimentoPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final FinanceiroRepository _financeiroRepository = FinanceiroRepository();

  final TextEditingController _descricaoController = TextEditingController();

  final TextEditingController _valorController = TextEditingController();

  final TextEditingController _observacoesController = TextEditingController();

  final DateFormat _formatoData = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _salvando = false;

  String _tipo = 'Entrada';
  String _formaPagamento = 'Pix';

  DateTime _dataSelecionada = DateTime.now();

  int? _clienteIdSelecionado;
  int? _agendamentoId;

  List<Map<String, dynamic>> _clientes = [];

  bool get _editando => widget.movimento != null;

  @override
  void initState() {
    super.initState();
    _prepararTela();
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _prepararTela() async {
    try {
      await _carregarClientes();
      _preencherDadosDaEdicao();

      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem('Não foi possível preparar a tela: $erro', erro: true);
    }
  }

  Future<void> _carregarClientes() async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'clientes',
      columns: ['id', 'nome', 'telefone'],
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    _clientes = resultado;
  }

  void _preencherDadosDaEdicao() {
    final movimento = widget.movimento;

    if (movimento == null) {
      return;
    }

    final tipoSalvo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();

    if (tipoSalvo == 'saída' || tipoSalvo == 'saida') {
      _tipo = 'Saída';
    } else {
      _tipo = 'Entrada';
    }

    _descricaoController.text = (movimento['descricao'] ?? '').toString();

    _valorController.text = _formatarValorInicial(movimento['valor']);

    final formaPagamento = (movimento['forma_pagamento'] ?? '')
        .toString()
        .trim();

    if (formaPagamento.isNotEmpty) {
      _formaPagamento = formaPagamento;
    }

    _clienteIdSelecionado = _converterParaInt(movimento['cliente_id']);

    _agendamentoId = _converterParaInt(movimento['agendamento_id']);

    final data = _converterParaData(movimento['data']);

    if (data != null) {
      _dataSelecionada = data;
    }
  }

  int? _converterParaInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  DateTime? _converterParaData(dynamic valor) {
    if (valor == null) {
      return null;
    }

    final texto = valor.toString();

    try {
      return DateTime.parse(texto);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(texto);
      } catch (_) {
        return null;
      }
    }
  }

  String _formatarValorInicial(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;

    return numero.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _lerValor() {
    var texto = _valorController.text.trim();

    if (texto.isEmpty) {
      return null;
    }

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto);
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _dataSelecionada,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 20),
      helpText: 'Selecionar data',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD6A84B),
              onPrimary: Colors.black,
              surface: Color(0xFF211D17),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF151515),
            ),
          ),
          child: child!,
        );
      },
    );

    if (data == null || !mounted) {
      return;
    }

    setState(() {
      _dataSelecionada = DateTime(data.year, data.month, data.day);
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final valor = _lerValor();

    if (valor == null || valor <= 0) {
      _mostrarMensagem('Informe um valor maior que zero.', erro: true);
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final movimento = MovimentoFinanceiro(
        id: _converterParaInt(widget.movimento?['id']),
        tipo: _tipo,
        descricao: _montarDescricaoCompleta(),
        valor: valor,
        formaPagamento: _formaPagamento,
        data: DateTime(
          _dataSelecionada.year,
          _dataSelecionada.month,
          _dataSelecionada.day,
        ).toIso8601String(),
        clienteId: _clienteIdSelecionado,
        agendamentoId: _agendamentoId,
      );

      if (_editando) {
        await _financeiroRepository.atualizarMovimento(movimento);
      } else {
        await _financeiroRepository.inserirMovimento(movimento);
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
        'Não foi possível salvar a movimentação: $erro',
        erro: true,
      );
    }
  }

  String _montarDescricaoCompleta() {
    final descricao = _descricaoController.text.trim();
    final observacoes = _observacoesController.text.trim();

    if (observacoes.isEmpty) {
      return descricao;
    }

    return '$descricao — $observacoes';
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151515),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_editando ? 'Editar movimentação' : 'Nova movimentação'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  children: [
                    _construirCabecalho(),
                    const SizedBox(height: 16),
                    _construirTipo(),
                    const SizedBox(height: 16),
                    _construirDadosPrincipais(),
                    const SizedBox(height: 16),
                    _construirVinculos(),
                    const SizedBox(height: 16),
                    _construirObservacoes(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _carregando
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _salvando
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _salvando ? null : _salvar,
                        icon: _salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _construirCabecalho() {
    final entrada = _tipo == 'Entrada';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: entrada
              ? [Colors.green.shade800, Colors.green.shade600]
              : [Colors.red.shade800, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (entrada ? Colors.green : Colors.red).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              entrada ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entrada ? 'Registrar entrada' : 'Registrar saída',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entrada
                      ? 'Registre pagamentos e receitas da empresa.'
                      : 'Registre despesas, compras e outros custos.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirTipo() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'Entrada',
              label: Text('Entrada'),
              icon: Icon(Icons.south_west_rounded),
            ),
            ButtonSegment<String>(
              value: 'Saída',
              label: Text('Saída'),
              icon: Icon(Icons.north_east_rounded),
            ),
          ],
          selected: {_tipo},
          onSelectionChanged: (selecionados) {
            setState(() {
              _tipo = selecionados.first;
            });
          },
        ),
      ),
    );
  }

  Widget _construirDadosPrincipais() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dados da movimentação',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descricaoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex.: Polimento completo',
                prefixIcon: Icon(Icons.description_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                if (valor == null || valor.trim().isEmpty) {
                  return 'Informe uma descrição.';
                }

                if (valor.trim().length < 3) {
                  return 'Digite pelo menos 3 caracteres.';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _valorController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor',
                hintText: '0,00',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (_) {
                final valor = _lerValor();

                if (valor == null) {
                  return 'Informe o valor.';
                }

                if (valor <= 0) {
                  return 'O valor deve ser maior que zero.';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _formaPagamento,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1A1A1A),
                labelText: 'Forma de pagamento',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                DropdownMenuItem(
                  value: 'Cartão de crédito',
                  child: Text('Cartão de crédito'),
                ),
                DropdownMenuItem(
                  value: 'Cartão de débito',
                  child: Text('Cartão de débito'),
                ),
                DropdownMenuItem(
                  value: 'Transferência',
                  child: Text('Transferência'),
                ),
                DropdownMenuItem(value: 'Boleto', child: Text('Boleto')),
                DropdownMenuItem(value: 'Outro', child: Text('Outro')),
              ],
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _formaPagamento = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _selecionarData,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                  labelText: 'Data',
                  prefixIcon: Icon(Icons.calendar_month_rounded),
                  suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(_formatoData.format(_dataSelecionada)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirVinculos() {
    final clienteValido =
        _clienteIdSelecionado == null ||
        _clientes.any(
          (cliente) =>
              _converterParaInt(cliente['id']) == _clienteIdSelecionado,
        );

    if (!clienteValido) {
      _clienteIdSelecionado = null;
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'O vínculo com um cliente é opcional.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              value: _clienteIdSelecionado,
              isExpanded: true,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1A1A1A),
                labelText: 'Selecionar cliente',
                prefixIcon: Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sem cliente vinculado'),
                ),
                ..._clientes.map((cliente) {
                  final id = _converterParaInt(cliente['id']);

                  final nome = (cliente['nome'] ?? '').toString();

                  final telefone = (cliente['telefone'] ?? '')
                      .toString()
                      .trim();

                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text(
                      telefone.isEmpty ? nome : '$nome • $telefone',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (valor) {
                setState(() {
                  _clienteIdSelecionado = valor;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirObservacoes() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Observações',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _observacoesController,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1A1A1A),
                hintText: 'Informações adicionais sobre a movimentação',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
