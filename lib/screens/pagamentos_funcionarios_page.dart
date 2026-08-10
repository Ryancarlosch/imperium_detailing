import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/colaborador_custo.dart';
import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/custos_repository.dart';
import 'ponto_funcionarios_page.dart';

class PagamentosFuncionariosPage extends StatefulWidget {
  const PagamentosFuncionariosPage({super.key});

  @override
  State<PagamentosFuncionariosPage> createState() =>
      _PagamentosFuncionariosPageState();
}

class _PagamentosFuncionariosPageState
    extends State<PagamentosFuncionariosPage> {
  final CustosRepository _repository = CustosRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool _carregando = true;
  List<ColaboradorCusto> _colaboradores = const [];
  List<Map<String, dynamic>> _pagamentos = const [];

  DateTime get _inicioMes => DateTime(_mes.year, _mes.month, 1);
  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.listarColaboradores(),
        _repository.listarPagamentosColaboradores(
          inicio: _inicioMes,
          fim: _fimMes,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _colaboradores = resultados[0] as List<ColaboradorCusto>;
        _pagamentos =
            List<Map<String, dynamic>>.from(resultados[1] as List<dynamic>);
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar os pagamentos.\n$erro', erro: true);
    }
  }

  void _mesAnterior() {
    setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
    _carregar();
  }

  void _mesSeguinte() {
    final atual = DateTime(DateTime.now().year, DateTime.now().month);
    final proximo = DateTime(_mes.year, _mes.month + 1);
    if (proximo.isAfter(atual)) return;
    setState(() => _mes = proximo);
    _carregar();
  }

  String _tituloMes() {
    final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return texto.substring(0, 1).toUpperCase() + texto.substring(1);
  }

  double get _totalMes => _pagamentos.fold<double>(
        0,
        (total, item) => total + _double(item['valor']),
      );

  Map<int, List<Map<String, dynamic>>> get _porColaborador {
    final resultado = <int, List<Map<String, dynamic>>>{};
    for (final pagamento in _pagamentos) {
      final id = _int(pagamento['colaborador_id']);
      if (id == null) continue;
      resultado.putIfAbsent(id, () => <Map<String, dynamic>>[]).add(pagamento);
    }
    return resultado;
  }

  Future<void> _novoPagamento([ColaboradorCusto? colaborador]) async {
    if (_colaboradores.isEmpty) {
      _mensagem(
        'Cadastre pelo menos um funcionário antes de lançar pagamentos.',
        erro: true,
      );
      return;
    }

    final salvou = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PagamentoFuncionarioSheet(
        repository: _repository,
        colaboradores: _colaboradores,
        colaboradorInicial: colaborador,
      ),
    );

    if (salvou == true) {
      await _carregar();
    }
  }

  Future<void> _excluirPagamento(Map<String, dynamic> pagamento) async {
    final id = _int(pagamento['id']);
    if (id == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir pagamento?'),
        content: Text(
          'O lançamento de ${_moeda.format(_double(pagamento['valor']))} '
          'será removido do Caixa, do saldo da conta e da DRE.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await _repository.excluirPagamentoColaborador(id);
      await _carregar();
      _mensagem('Pagamento excluído.');
    } catch (erro) {
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

  String _dataTexto(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null ? '' : DateFormat('dd/MM/yyyy').format(data);
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _porColaborador;
    final mesAtual = DateTime(DateTime.now().year, DateTime.now().month);
    final podeAvancar = _mes.isBefore(mesAtual);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos de funcionários'),
        actions: [
          IconButton(
            tooltip: 'Controle de ponto',
            onPressed: _carregando
                ? null
                : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const PontoFuncionariosPage(),
                      ),
                    );
                    await _carregar();
                  },
            icon: const Icon(Icons.access_time_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _carregando ? null : () => _novoPagamento(),
        icon: const Icon(Icons.add),
        label: const Text('Pagamento'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Mês anterior',
                                onPressed: _mesAnterior,
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  _tituloMes(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Próximo mês',
                                onPressed: podeAvancar ? _mesSeguinte : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _moeda.format(_totalMes),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _pagamentos.length == 1
                                ? '1 pagamento realizado no mês'
                                : '${_pagamentos.length} pagamentos realizados no mês',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Cada pagamento é independente. Você escolhe o valor, '
                        'a conta e a data. Não existe valor mensal automático.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_colaboradores.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhum funcionário ativo cadastrado.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._colaboradores.map((colaborador) {
                      final id = colaborador.id;
                      final pagamentos = id == null
                          ? const <Map<String, dynamic>>[]
                          : grupos[id] ?? const <Map<String, dynamic>>[];
                      final total = pagamentos.fold<double>(
                        0,
                        (soma, item) => soma + _double(item['valor']),
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.engineering_outlined),
                          ),
                          title: Text(
                            colaborador.nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${pagamentos.length} lançamentos • '
                            '${_moeda.format(total)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Lançar pagamento',
                            onPressed: () => _novoPagamento(colaborador),
                            icon: const Icon(Icons.add_card_rounded),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            12,
                          ),
                          children: [
                            if (pagamentos.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Nenhum pagamento neste mês.'),
                              )
                            else
                              ...pagamentos.map(
                                (item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.payments_outlined),
                                  title: Text(
                                    _moeda.format(_double(item['valor'])),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      _dataTexto(
                                        item['data_pagamento'] ?? item['data'],
                                      ),
                                      (item['conta_nome'] ?? '').toString(),
                                      (item['forma_pagamento'] ?? '').toString(),
                                    ].where((e) => e.trim().isNotEmpty).join(
                                      ' • ',
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (valor) {
                                      if (valor == 'excluir') {
                                        _excluirPagamento(item);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'excluir',
                                        child: Text(
                                          'Excluir pagamento',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

class _PagamentoFuncionarioSheet extends StatefulWidget {
  const _PagamentoFuncionarioSheet({
    required this.repository,
    required this.colaboradores,
    this.colaboradorInicial,
  });

  final CustosRepository repository;
  final List<ColaboradorCusto> colaboradores;
  final ColaboradorCusto? colaboradorInicial;

  @override
  State<_PagamentoFuncionarioSheet> createState() =>
      _PagamentoFuncionarioSheetState();
}

class _PagamentoFuncionarioSheetState
    extends State<_PagamentoFuncionarioSheet> {
  final _formKey = GlobalKey<FormState>();
  final _valor = TextEditingController();
  final _observacoes = TextEditingController();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();

  ColaboradorCusto? _colaborador;
  List<ContaFinanceira> _contas = const [];
  int? _contaId;
  String _forma = 'Pix';
  DateTime _data = DateTime.now();
  bool _carregandoContas = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _colaborador = widget.colaboradorInicial ??
        (widget.colaboradores.length == 1 ? widget.colaboradores.first : null);
    _carregarContas();
  }

  @override
  void dispose() {
    _valor.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregarContas() async {
    try {
      final contas = await _contasRepository.listar();
      if (!mounted) return;
      setState(() {
        _contas = contas.where((item) => item.ativo).toList();
        if (_contas.length == 1) {
          _contaId = _contas.single.id;
        }
        _carregandoContas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoContas = false);
    }
  }

  double? _valorNumerico() {
    var texto = _valor.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

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
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (data != null && mounted) {
      setState(() => _data = data);
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) return;

    final colaborador = _colaborador;
    final contaId = _contaId;
    final valor = _valorNumerico();

    if (colaborador?.id == null || contaId == null || valor == null) return;

    setState(() => _salvando = true);

    try {
      await widget.repository.registrarPagamentoColaborador(
        colaboradorId: colaborador!.id!,
        valor: valor,
        contaId: contaId,
        dataPagamento: _data,
        formaPagamento: _forma,
        observacoes: _observacoes.text,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, teclado + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Novo pagamento',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              const Text(
                'O valor é livre. Faça quantos pagamentos forem necessários '
                'durante o mês.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ColaboradorCusto>(
                initialValue: _colaborador,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Funcionário *',
                  prefixIcon: Icon(Icons.engineering_outlined),
                  border: OutlineInputBorder(),
                ),
                items: widget.colaboradores
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(
                          item.nome,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _colaborador = valor),
                validator: (valor) =>
                    valor == null ? 'Selecione o funcionário' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _valor,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Valor pago *',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (_) {
                  final numero = _valorNumerico();
                  if (numero == null || numero <= 0) {
                    return 'Informe o valor pago';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _contaId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Conta de saída *',
                  prefixIcon: const Icon(
                    Icons.account_balance_wallet_outlined,
                  ),
                  border: const OutlineInputBorder(),
                  helperText: _carregandoContas
                      ? 'Carregando contas...'
                      : 'O saldo desta conta será reduzido.',
                ),
                items: _contas
                    .where((conta) => conta.id != null)
                    .map(
                      (conta) => DropdownMenuItem<int>(
                        value: conta.id!,
                        child: Text(
                          conta.nome,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _salvando || _carregandoContas
                    ? null
                    : (valor) => setState(() => _contaId = valor),
                validator: (valor) =>
                    valor == null ? 'Selecione a conta' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _forma,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                  prefixIcon: Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(
                    value: 'Transferência',
                    child: Text('Transferência'),
                  ),
                  DropdownMenuItem(value: 'Boleto', child: Text('Boleto')),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor != null) {
                          setState(() => _forma = valor);
                        }
                      },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _salvando ? null : _selecionarData,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  'Data: ${DateFormat('dd/MM/yyyy').format(_data)}',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacoes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  hintText: 'Opcional',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _salvando ? 'Salvando...' : 'Confirmar pagamento',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
