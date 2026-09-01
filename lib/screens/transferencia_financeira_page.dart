import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_repository.dart';

// financeiro-transferencia-rapida-v1
class TransferenciaFinanceiraPage extends StatefulWidget {
  const TransferenciaFinanceiraPage({super.key});

  @override
  State<TransferenciaFinanceiraPage> createState() =>
      _TransferenciaFinanceiraPageState();
}

class _TransferenciaFinanceiraPageState
    extends State<TransferenciaFinanceiraPage> {
  final _formKey = GlobalKey<FormState>();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
  final FinanceiroRepository _repository = FinanceiroRepository();
  final TextEditingController _valor = TextEditingController();
  final TextEditingController _descricao = TextEditingController(
    text: 'Transferência entre contas',
  );
  final TextEditingController _observacoes = TextEditingController();

  List<ContaFinanceira> _contas = const [];
  int? _origem;
  int? _destino;
  DateTime _data = DateTime.now();
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final contas = await _contasRepository.listar();
      if (!mounted) return;

      final ativas = contas
          .where((item) => item.id != null && item.ativo)
          .toList();

      setState(() {
        _contas = ativas;
        if (_contas.isNotEmpty) _origem = _contas.first.id;
        if (_contas.length > 1) _destino = _contas[1].id;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  double? _lerValor() {
    var texto = _valor.text.trim().replaceAll('R\$', '').replaceAll(' ', '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }
    return double.tryParse(texto);
  }

  Future<void> _selecionarData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );

    if (escolhida != null && mounted) {
      setState(() => _data = escolhida);
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) return;

    final valor = _lerValor();
    if (_origem == null || _destino == null || valor == null) return;

    setState(() => _salvando = true);

    try {
      await _repository.registrarTransferencia(
        contaOrigemId: _origem!,
        contaDestinoId: _destino!,
        valor: valor,
        data: _data,
        descricao: _descricao.text,
        observacoes: _observacoes.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mensagem('$erro', erro: true);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferir entre contas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _contas.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cadastre pelo menos duas contas financeiras ativas para fazer uma transferência.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Transferências mudam o saldo das contas, mas não são receita nem despesa e não entram na DRE.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    initialValue: _origem,
                    decoration: const InputDecoration(
                      labelText: 'Conta de origem',
                      prefixIcon: Icon(Icons.logout_rounded),
                    ),
                    items: _contas
                        .map(
                          (item) => DropdownMenuItem<int?>(
                            value: item.id,
                            child: Text(item.nome),
                          ),
                        )
                        .toList(),
                    onChanged: _salvando
                        ? null
                        : (valor) => setState(() => _origem = valor),
                    validator: (valor) =>
                        valor == null ? 'Selecione a origem.' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int?>(
                    initialValue: _destino,
                    decoration: const InputDecoration(
                      labelText: 'Conta de destino',
                      prefixIcon: Icon(Icons.login_rounded),
                    ),
                    items: _contas
                        .map(
                          (item) => DropdownMenuItem<int?>(
                            value: item.id,
                            child: Text(item.nome),
                          ),
                        )
                        .toList(),
                    onChanged: _salvando
                        ? null
                        : (valor) => setState(() => _destino = valor),
                    validator: (valor) {
                      if (valor == null) return 'Selecione o destino.';
                      if (valor == _origem) {
                        return 'Origem e destino precisam ser diferentes.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _valor,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    validator: (_) {
                      final valor = _lerValor();
                      return valor == null || valor <= 0
                          ? 'Informe um valor maior que zero.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _salvando ? null : _selecionarData,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        'Data: ${DateFormat('dd/MM/yyyy').format(_data)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descricao,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    validator: (valor) => (valor ?? '').trim().length < 3
                        ? 'Informe uma descrição.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _observacoes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.comment_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(_salvando ? 'Transferindo...' : 'Transferir'),
                  ),
                ],
              ),
            ),
    );
  }
}
