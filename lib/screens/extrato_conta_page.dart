import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';
import 'comparativo_conta_page.dart';

enum _FiltroExtrato { todos, entradas, saidas }

class ExtratoContaPage extends StatefulWidget {
  const ExtratoContaPage({super.key, required this.conta});

  final ContaFinanceira conta;

  @override
  State<ExtratoContaPage> createState() => _ExtratoContaPageState();
}

class _ExtratoContaPageState extends State<ExtratoContaPage> {
  final ContaFinanceiraRepository _repository = ContaFinanceiraRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _mesAno = DateFormat('MMMM yyyy', 'pt_BR');
  final DateFormat _diaSemana = DateFormat("EEEE, dd/MM", 'pt_BR');
  final DateFormat _hora = DateFormat('HH:mm');

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _dados;
  List<Map<String, dynamic>> _conciliacoes = [];
  _FiltroExtrato _filtro = _FiltroExtrato.todos;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.conta.id;
    if (id == null) {
      setState(() {
        _carregando = false;
        _erro = 'Conta financeira sem ID.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.obterExtratoMensal(contaId: id, mes: _mes),
        _repository.listarConciliacoesMes(contaId: id, mes: _mes),
      ]);
      if (!mounted) return;
      setState(() {
        _dados = Map<String, dynamic>.from(
          resultados[0] as Map<String, dynamic>,
        );
        _conciliacoes = List<Map<String, dynamic>>.from(
          resultados[1] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = '$erro';
        _carregando = false;
      });
    }
  }

  void _mudarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  bool _ehEntrada(Map<String, dynamic> item) {
    return (item['tipo'] ?? '').toString().trim().toLowerCase() == 'entrada';
  }

  DateTime _dataMovimento(Map<String, dynamic> item) {
    final texto = (item['data_pagamento'] ?? item['data'] ?? '').toString();
    return DateTime.tryParse(texto) ?? _mes;
  }

  List<Map<String, dynamic>> get _movimentos {
    final dados = _dados;
    if (dados == null) return const [];
    return List<Map<String, dynamic>>.from(
      dados['movimentos'] as List<dynamic>? ?? const [],
    );
  }

  List<_DiaExtrato> _agruparDias() {
    final saldoInicial = _double(_dados?['saldo_inicial_mes']);
    final todos = _movimentos;

    var saldoCorrente = saldoInicial;
    final grupos = <String, _DiaExtrato>{};

    for (final item in todos) {
      final data = _dataMovimento(item);
      final chave =
          '${data.year.toString().padLeft(4, '0')}-'
          '${data.month.toString().padLeft(2, '0')}-'
          '${data.day.toString().padLeft(2, '0')}';

      final grupo = grupos.putIfAbsent(
        chave,
        () => _DiaExtrato(
          data: DateTime(data.year, data.month, data.day),
          saldoInicialDia: saldoCorrente,
        ),
      );

      final valor = _double(item['valor']);
      if (_ehEntrada(item)) {
        grupo.entradas += valor;
        saldoCorrente += valor;
      } else {
        grupo.saidas += valor;
        saldoCorrente -= valor;
      }

      grupo.movimentos.add(item);
      grupo.saldoFinalDia = saldoCorrente;
    }

    final dias = grupos.values.toList()
      ..sort((a, b) => b.data.compareTo(a.data));
    return dias;
  }

  List<Map<String, dynamic>> _filtrarMovimentos(
    List<Map<String, dynamic>> itens,
  ) {
    switch (_filtro) {
      case _FiltroExtrato.todos:
        return itens;
      case _FiltroExtrato.entradas:
        return itens.where(_ehEntrada).toList();
      case _FiltroExtrato.saidas:
        return itens.where((item) => !_ehEntrada(item)).toList();
    }
  }

  Future<void> _abrirConciliacao() async {
    final id = widget.conta.id;
    if (id == null) return;

    final agora = DateTime.now();
    final inicioMes = DateTime(_mes.year, _mes.month, 1);
    final inicioMesAtual = DateTime(agora.year, agora.month, 1);

    if (inicioMes.isAfter(inicioMesAtual)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Não é possível conciliar um mês futuro.'),
          ),
        );
      return;
    }

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConciliacaoContaSheet(
        repository: _repository,
        conta: widget.conta,
        mes: _mes,
      ),
    );

    if (resultado == true) {
      await _carregar();
    }
  }

  // conciliacao-remover-ui-v1
  Future<void> _removerConciliacao(Map<String, dynamic> item) async {
    final contaId = widget.conta.id;
    final conciliacaoId = int.tryParse((item['id'] ?? '').toString());
    if (contaId == null || conciliacaoId == null) return;

    final movimentoAjusteId = int.tryParse(
      (item['movimento_ajuste_id'] ?? '').toString(),
    );
    final temAjuste = movimentoAjusteId != null;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover conciliação?'),
        content: Text(
          temAjuste
              ? 'Esta conciliação criou um ajuste de saldo. Ao remover, '
                    'o Imperium também removerá esse ajuste financeiro e '
                    'recalculará o saldo da conta automaticamente.\n\n'
                    'Deseja realmente continuar?'
              : 'Esta conciliação será removida do histórico. '
                    'Nenhum lançamento bancário comum será apagado.\n\n'
                    'Deseja realmente continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    try {
      await _repository.removerConciliacaoConta(
        conciliacaoId: conciliacaoId,
        contaId: contaId,
      );

      if (!mounted) return;
      await _carregar();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              temAjuste
                  ? 'Conciliação e ajuste removidos. Saldo recalculado.'
                  : 'Conciliação removida com sucesso.',
            ),
          ),
        );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$erro'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Widget _historicoConciliacoes() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.verified_outlined),
        title: const Text(
          'Conciliações do mês',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${_conciliacoes.length} conferência(s) registrada(s)'),
        children: _conciliacoes.map((item) {
          final data =
              DateTime.tryParse((item['data_conciliacao'] ?? '').toString()) ??
              _mes;
          final status = (item['status'] ?? '').toString();
          final diferenca = _double(item['diferenca']);
          final saldoInformado = _double(item['saldo_informado']);
          final ajustado = status == 'Ajustado';
          final divergente = status == 'Divergente';

          return ListTile(
            dense: true,
            leading: Icon(
              divergente
                  ? Icons.warning_amber_rounded
                  : ajustado
                  ? Icons.build_circle_outlined
                  : Icons.check_circle_outline_rounded,
              color: divergente
                  ? Colors.orange
                  : ajustado
                  ? Colors.blueAccent
                  : Colors.green,
            ),
            title: Text(
              '${DateFormat('dd/MM/yyyy').format(data)} • $status',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              divergente || ajustado
                  ? 'Saldo real ${_moeda.format(saldoInformado)} • '
                        'Diferença ${_moeda.format(diferenca)}'
                  : 'Saldo conferido ${_moeda.format(saldoInformado)}',
            ),
            trailing: IconButton(
              tooltip: 'Remover conciliação',
              onPressed: () => _removerConciliacao(item),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conta.nome),
        actions: [
          IconButton(
            tooltip: 'Comparar meses',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ComparativoContaPage(conta: widget.conta, mes: _mes),
                ),
              );
            },
            icon: const Icon(Icons.query_stats_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? _ErroExtrato(mensagem: _erro!, onTentar: _carregar)
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _cabecalhoPeriodo(),
                  const SizedBox(height: 14),
                  _resumoMes(),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _abrirConciliacao,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Conferir saldo da conta'),
                  ),
                  if (_conciliacoes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _historicoConciliacoes(),
                  ],
                  const SizedBox(height: 14),
                  _filtros(),
                  const SizedBox(height: 14),
                  ..._conteudoDias(),
                ],
              ),
            ),
    );
  }

  Widget _cabecalhoPeriodo() {
    final titulo = _mesAno.format(_mes);
    final exibicao = titulo.isEmpty
        ? titulo
        : '${titulo[0].toUpperCase()}${titulo.substring(1)}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => _mudarMes(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    exibicao,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      widget.conta.tipo,
                      if (widget.conta.instituicao.isNotEmpty)
                        widget.conta.instituicao,
                    ].join(' • '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: () => _mudarMes(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumoMes() {
    final saldoInicial = _double(_dados?['saldo_inicial_mes']);
    final entradas = _double(_dados?['entradas']);
    final saidas = _double(_dados?['saidas']);
    final saldoFinal = _double(_dados?['saldo_final_mes']);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ResumoCard(
                titulo: 'Saldo inicial',
                valor: _moeda.format(saldoInicial),
                icone: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResumoCard(
                titulo: 'Saldo final',
                valor: _moeda.format(saldoFinal),
                icone: Icons.savings_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ResumoCard(
                titulo: 'Entradas',
                valor: _moeda.format(entradas),
                icone: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResumoCard(
                titulo: 'Saídas',
                valor: _moeda.format(saidas),
                icone: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.swap_vert_rounded),
            title: const Text('Movimento líquido do mês'),
            subtitle: const Text('Entradas menos saídas nesta conta.'),
            trailing: Text(
              _moeda.format(entradas - saidas),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filtros() {
    return SegmentedButton<_FiltroExtrato>(
      segments: const [
        ButtonSegment(value: _FiltroExtrato.todos, label: Text('Todos')),
        ButtonSegment(value: _FiltroExtrato.entradas, label: Text('Entradas')),
        ButtonSegment(value: _FiltroExtrato.saidas, label: Text('Saídas')),
      ],
      selected: {_filtro},
      onSelectionChanged: (selecionados) {
        setState(() => _filtro = selecionados.first);
      },
    );
  }

  List<Widget> _conteudoDias() {
    final dias = _agruparDias();

    if (dias.isEmpty) {
      return const [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 36),
                SizedBox(height: 10),
                Text(
                  'Nenhuma movimentação realizada nesta conta neste mês.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final dia in dias) {
      final filtrados = _filtrarMovimentos(dia.movimentos);
      if (filtrados.isEmpty) continue;

      widgets.add(
        _DiaCard(
          dia: dia,
          movimentos: filtrados.reversed.toList(),
          moeda: _moeda,
          diaSemana: _diaSemana,
          hora: _hora,
          ehEntrada: _ehEntrada,
          dataMovimento: _dataMovimento,
          doubleValue: _double,
        ),
      );
      widgets.add(const SizedBox(height: 10));
    }

    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }
    return widgets;
  }
}

class _ConciliacaoContaSheet extends StatefulWidget {
  const _ConciliacaoContaSheet({
    required this.repository,
    required this.conta,
    required this.mes,
  });

  final ContaFinanceiraRepository repository;
  final ContaFinanceira conta;
  final DateTime mes;

  @override
  State<_ConciliacaoContaSheet> createState() => _ConciliacaoContaSheetState();
}

class _ConciliacaoContaSheetState extends State<_ConciliacaoContaSheet> {
  final TextEditingController _saldo = TextEditingController();
  final TextEditingController _observacoes = TextEditingController();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  late DateTime _dataSelecionada;
  bool _calculando = false;
  bool _salvando = false;
  double? _saldoCalculado;
  double? _saldoInformado;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    final ultimoDia = DateTime(widget.mes.year, widget.mes.month + 1, 0);

    if (widget.mes.year == agora.year && widget.mes.month == agora.month) {
      _dataSelecionada = DateTime(agora.year, agora.month, agora.day);
    } else {
      _dataSelecionada = ultimoDia.isAfter(agora)
          ? DateTime(agora.year, agora.month, agora.day)
          : ultimoDia;
    }
  }

  @override
  void dispose() {
    _saldo.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  double? _lerSaldo() {
    var texto = _saldo.text.trim().replaceAll('R\$', '').replaceAll(' ', '');
    if (texto.isEmpty) return null;

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto);
  }

  Future<void> _selecionarData() async {
    final agora = DateTime.now();
    final primeiro = DateTime(widget.mes.year, widget.mes.month, 1);
    final ultimoMes = DateTime(widget.mes.year, widget.mes.month + 1, 0);
    final ultimo = ultimoMes.isAfter(agora)
        ? DateTime(agora.year, agora.month, agora.day)
        : ultimoMes;

    final selecionada = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _dataSelecionada,
      firstDate: primeiro,
      lastDate: ultimo,
    );

    if (selecionada == null || !mounted) return;

    setState(() {
      _dataSelecionada = selecionada;
      _saldoCalculado = null;
      _saldoInformado = null;
    });
  }

  Future<void> _calcular() async {
    final id = widget.conta.id;
    final informado = _lerSaldo();

    if (id == null) return;
    if (informado == null) {
      _mensagem('Informe o saldo real da conta.', erro: true);
      return;
    }

    setState(() => _calculando = true);

    try {
      final calculado = await widget.repository.obterSaldoCalculadoAte(
        contaId: id,
        data: _dataSelecionada,
      );

      if (!mounted) return;
      setState(() {
        _saldoCalculado = calculado;
        _saldoInformado = informado;
        _calculando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _calculando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _salvar({required bool criarAjuste}) async {
    final id = widget.conta.id;
    final informado = _saldoInformado;
    if (id == null || informado == null) return;

    // conciliacao-confirmacao-final-v1
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          criarAjuste
              ? 'Criar ajuste e concluir conciliação?'
              : 'Confirmar conciliação bancária?',
        ),
        content: Text(
          criarAjuste
              ? 'Você deseja realmente criar o ajuste e concluir esta '
                    'conciliação?\n\nAntes de continuar, verifique '
                    'completamente o extrato bancário, os lançamentos e '
                    'o saldo da conta. O ajuste alterará o saldo financeiro.'
              : 'Você deseja realmente registrar esta conciliação?\n\n'
                    'Antes de continuar, verifique completamente a '
                    'conciliação bancária, os lançamentos e o saldo da conta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar e revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              criarAjuste ? 'Sim, criar e conciliar' : 'Sim, confirmar',
            ),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    setState(() => _salvando = true);

    try {
      await widget.repository.registrarConciliacaoConta(
        contaId: id,
        data: _dataSelecionada,
        saldoInformado: informado,
        criarAjuste: criarAjuste,
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
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final calculado = _saldoCalculado;
    final informado = _saldoInformado;
    final diferenca = calculado == null || informado == null
        ? null
        : informado - calculado;
    final bateu = diferenca != null && diferenca.abs() < 0.005;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 18, 16, teclado + 24),
        shrinkWrap: true,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conferir ${widget.conta.nome}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Informe o saldo que aparece no banco/caixa. O Imperium compara '
            'com os lançamentos realizados até a data escolhida.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Data da conferência'),
            subtitle: Text(_data.format(_dataSelecionada)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _salvando ? null : _selecionarData,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _saldo,
            enabled: !_salvando,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Saldo real no banco / caixa',
              prefixText: 'R\$ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_saldoCalculado != null || _saldoInformado != null) {
                setState(() {
                  _saldoCalculado = null;
                  _saldoInformado = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _calculando || _salvando ? null : _calcular,
            icon: _calculando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calculate_outlined),
            label: Text(_calculando ? 'Calculando...' : 'Calcular diferença'),
          ),
          if (diferenca != null) ...[
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _LinhaConciliacao(
                      titulo: 'Saldo calculado pelo Imperium',
                      valor: _moeda.format(calculado),
                    ),
                    const SizedBox(height: 8),
                    _LinhaConciliacao(
                      titulo: 'Saldo real informado',
                      valor: _moeda.format(informado),
                    ),
                    const Divider(height: 22),
                    _LinhaConciliacao(
                      titulo: 'Diferença',
                      valor: _moeda.format(diferenca),
                      destaque: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          bateu
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: bateu ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bateu
                                ? 'Saldo conferido. Não há diferença.'
                                : 'Existe diferença. Confira os lançamentos '
                                      'antes de criar um ajuste.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacoes,
              enabled: !_salvando,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observação',
                hintText: 'Opcional. Ex.: conferido no app do banco.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            if (bateu)
              FilledButton.icon(
                onPressed: _salvando ? null : () => _salvar(criarAjuste: false),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Salvar conciliação'),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _salvando ? null : () => _salvar(criarAjuste: false),
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Registrar divergência sem ajustar'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _salvando ? null : () => _salvar(criarAjuste: true),
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text('Criar ajuste e conciliar'),
              ),
              const SizedBox(height: 8),
              Text(
                'O ajuste usa Correção de caixa e não afeta a DRE.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LinhaConciliacao extends StatelessWidget {
  const _LinhaConciliacao({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(titulo)),
        const SizedBox(width: 12),
        Text(
          valor,
          style: TextStyle(
            fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            fontSize: destaque ? 16 : null,
          ),
        ),
      ],
    );
  }
}

class _DiaExtrato {
  _DiaExtrato({required this.data, required this.saldoInicialDia})
    : saldoFinalDia = saldoInicialDia;

  final DateTime data;
  final double saldoInicialDia;
  double entradas = 0;
  double saidas = 0;
  double saldoFinalDia;
  final List<Map<String, dynamic>> movimentos = [];
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 20),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valor,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaCard extends StatelessWidget {
  const _DiaCard({
    required this.dia,
    required this.movimentos,
    required this.moeda,
    required this.diaSemana,
    required this.hora,
    required this.ehEntrada,
    required this.dataMovimento,
    required this.doubleValue,
  });

  final _DiaExtrato dia;
  final List<Map<String, dynamic>> movimentos;
  final NumberFormat moeda;
  final DateFormat diaSemana;
  final DateFormat hora;
  final bool Function(Map<String, dynamic>) ehEntrada;
  final DateTime Function(Map<String, dynamic>) dataMovimento;
  final double Function(dynamic) doubleValue;

  @override
  Widget build(BuildContext context) {
    final titulo = diaSemana.format(dia.data);
    final tituloExibicao = titulo.isEmpty
        ? titulo
        : '${titulo[0].toUpperCase()}${titulo.substring(1)}';

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: Text(
          tituloExibicao,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              Text('Entradas ${moeda.format(dia.entradas)}'),
              Text('Saídas ${moeda.format(dia.saidas)}'),
              Text(
                'Fechamento ${moeda.format(dia.saldoFinalDia)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        children: movimentos.map((item) {
          final entrada = ehEntrada(item);
          final valor = doubleValue(item['valor']);
          final data = dataMovimento(item);
          final categoria = (item['plano_nome'] ?? '').toString().trim();
          final origem = (item['origem'] ?? '').toString().trim();
          final forma = (item['forma_pagamento'] ?? '').toString().trim();

          final detalhes = <String>[
            hora.format(data),
            if (categoria.isNotEmpty) categoria,
            if (forma.isNotEmpty) forma,
            if (origem.isNotEmpty && origem != 'Manual') origem,
          ];

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entrada ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 19,
                  color: entrada ? Colors.green : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['descricao'] ?? 'Movimentação').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detalhes.join(' • '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if ((item['observacoes'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          (item['observacoes'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entrada ? '+' : '-'} ${moeda.format(valor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: entrada ? Colors.green : Colors.redAccent,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ErroExtrato extends StatelessWidget {
  const _ErroExtrato({required this.mensagem, required this.onTentar});

  final String mensagem;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onTentar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
