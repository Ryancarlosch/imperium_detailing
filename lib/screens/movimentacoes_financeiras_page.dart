import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../models/fornecedor.dart';
import '../models/movimento_financeiro.dart';
import '../models/plano_conta_financeiro.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../repositories/fornecedor_repository.dart';
import '../repositories/plano_contas_repository.dart';

class MovimentacoesFinanceirasPage extends StatefulWidget {
  const MovimentacoesFinanceirasPage({
    super.key,
    this.tipoInicial = 'Todos',
    this.statusInicial = 'Todos',
    this.titulo = 'Movimentações',
  });

  final String tipoInicial;
  final String statusInicial;
  final String titulo;

  @override
  State<MovimentacoesFinanceirasPage> createState() =>
      _MovimentacoesFinanceirasPageState();
}

class _MovimentacoesFinanceirasPageState
    extends State<MovimentacoesFinanceirasPage> {
  final FinanceiroRepository _repository = FinanceiroRepository();
  final PlanoContasRepository _planoRepository = PlanoContasRepository();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
  final FornecedorRepository _fornecedorRepository = FornecedorRepository();
  final TextEditingController _pesquisaController = TextEditingController();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  late String _tipo;
  late String _status;
  String _pesquisa = '';
  bool _carregando = true;
  List<Map<String, dynamic>> _movimentos = [];

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial;
    _status = widget.statusInicial;
    _carregar();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final movimentos = await _repository.listarMovimentosComDetalhes(
        tipo: _tipo == 'Todos' ? null : _tipo,
        status: _status == 'Todos' ? null : _status,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _movimentos = movimentos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final termo = _pesquisa.trim().toLowerCase();
    if (termo.isEmpty) {
      return _movimentos;
    }

    return _movimentos.where((item) {
      final campos = [
        item['descricao'],
        item['cliente_nome'],
        item['fornecedor_nome'],
        item['conta_nome'],
        item['plano_nome'],
        item['forma_pagamento'],
        item['numero_documento'],
      ].map((e) => e?.toString().toLowerCase() ?? '');
      return campos.any((texto) => texto.contains(termo));
    }).toList();
  }

  Future<_DadosFormularioFinanceiro?> _dadosFormulario() async {
    try {
      final resultados = await Future.wait<dynamic>([
        _planoRepository.listar(incluirInativos: false),
        _contasRepository.listar(),
        _fornecedorRepository.listar(),
        _repository.listarClientesAtivos(),
      ]);

      return _DadosFormularioFinanceiro(
        plano: List<PlanoContaFinanceiro>.from(resultados[0] as List<dynamic>),
        contas: List<ContaFinanceira>.from(resultados[1] as List<dynamic>),
        fornecedores: List<Fornecedor>.from(resultados[2] as List<dynamic>),
        clientes: List<Map<String, dynamic>>.from(
          resultados[3] as List<dynamic>,
        ),
      );
    } catch (erro) {
      _mensagem('Não foi possível carregar os cadastros.\n$erro', erro: true);
      return null;
    }
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? mapa}) async {
    final dados = await _dadosFormulario();
    if (dados == null || !mounted) {
      return;
    }

    final movimento = mapa == null
        ? null
        : MovimentoFinanceiro.fromMap(Map<String, dynamic>.from(mapa));

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MovimentoFormSheet(
        repository: _repository,
        dados: dados,
        movimento: movimento,
      ),
    );

    if (resultado == true) {
      await _carregar();
    }
  }

  Future<void> _abrirTransferencia() async {
    final contas = await _contasRepository.listar();
    if (!mounted) {
      return;
    }

    if (contas.length < 2) {
      _mensagem(
        'Cadastre pelo menos duas contas financeiras para fazer uma transferência.',
        erro: true,
      );
      return;
    }

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _TransferenciaSheet(repository: _repository, contas: contas),
    );

    if (resultado == true) {
      await _carregar();
    }
  }

  Future<void> _baixar(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) {
      return;
    }

    final contas = await _contasRepository.listar();
    if (!mounted) {
      return;
    }

    if (contas.isEmpty) {
      _mensagem(
        'Cadastre uma conta financeira antes de realizar o lançamento.',
        erro: true,
      );
      return;
    }

    var contaSelecionada = _int(item['conta_id']);
    if (contaSelecionada != null &&
        !contas.any((conta) => conta.id == contaSelecionada)) {
      contaSelecionada = null;
    }
    if (contaSelecionada == null && contas.length == 1) {
      contaSelecionada = contas.single.id;
    }

    final contaId = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var selecionada = contaSelecionada;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Marcar como realizado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirmar hoje o lançamento "${item['descricao']}" no valor de '
                  '${_moeda.format(_double(item['valor']))}?',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selecionada,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Conta / caixa',
                    helperText: 'O saldo desta conta será atualizado.',
                  ),
                  items: contas
                      .where((conta) => conta.id != null)
                      .map(
                        (conta) => DropdownMenuItem<int>(
                          value: conta.id,
                          child: Text(conta.nome),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) {
                    setDialogState(() {
                      selecionada = valor;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selecionada == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(selecionada),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
      },
    );

    if (contaId == null) {
      return;
    }

    try {
      await _repository.marcarComoRealizado(id: id, contaId: contaId);
      await _carregar();
      _mensagem('Lançamento marcado como realizado.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) {
      return;
    }
    try {
      await _repository.cancelarMovimento(id);
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _excluir(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text(
          'Use exclusão somente para lançamento criado por engano. '
          'Para preservar histórico, prefira cancelar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }
    try {
      await _repository.excluirMovimento(id);
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  bool _automatico(Map<String, dynamic> item) {
    final origem = (item['origem'] ?? 'Manual').toString();
    return item['pagamento_id'] != null ||
        item['ordem_servico_id'] != null ||
        item['transferencia_id'] != null ||
        origem != 'Manual';
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }
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
    final movimentos = _filtrados;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Transferir entre contas',
            onPressed: _abrirTransferencia,
            icon: const Icon(Icons.compare_arrows_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo lançamento'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  TextField(
                    controller: _pesquisaController,
                    onChanged: (valor) => setState(() => _pesquisa = valor),
                    decoration: const InputDecoration(
                      hintText:
                          'Pesquisar lançamento, pessoa, conta ou categoria',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _tipo,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(
                              value: 'Todos',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'Entrada',
                              child: Text('Entradas'),
                            ),
                            DropdownMenuItem(
                              value: 'Saída',
                              child: Text('Saídas'),
                            ),
                          ],
                          onChanged: (valor) {
                            if (valor == null) {
                              return;
                            }
                            setState(() => _tipo = valor);
                            _carregar();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Todos',
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: 'Previsto',
                              child: Text('Previstos'),
                            ),
                            DropdownMenuItem(
                              value: 'Atrasado',
                              child: Text('Atrasados'),
                            ),
                            DropdownMenuItem(
                              value: 'Realizado',
                              child: Text('Realizados'),
                            ),
                            DropdownMenuItem(
                              value: 'Cancelado',
                              child: Text('Cancelados'),
                            ),
                          ],
                          onChanged: (valor) {
                            if (valor == null) {
                              return;
                            }
                            setState(() => _status = valor);
                            _carregar();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (movimentos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Text(
                        'Nenhum lançamento encontrado.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...movimentos.map((item) {
                      final entrada =
                          (item['tipo'] ?? '').toString().toLowerCase() ==
                          'entrada';
                      final automatico = _automatico(item);
                      final status =
                          (item['status_exibicao'] ?? item['status'] ?? '')
                              .toString();
                      final data = _dataMovimento(item);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                entrada
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                                color: entrada
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (item['descricao'] ?? 'Lançamento')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _moeda.format(_double(item['valor'])),
                                      style: TextStyle(
                                        color: entrada
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 5,
                                      children: [
                                        _Tag(
                                          texto: status,
                                          cor: _corStatus(status),
                                        ),
                                        if ((item['plano_nome'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          _Tag(
                                            texto: item['plano_nome']
                                                .toString(),
                                          ),
                                        if ((item['conta_nome'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          _Tag(
                                            texto: item['conta_nome']
                                                .toString(),
                                          ),
                                        if (data != null)
                                          _Tag(texto: _data.format(data)),
                                        if (automatico)
                                          const _Tag(
                                            texto: 'Automático',
                                            icone: Icons.lock_outline_rounded,
                                          ),
                                      ],
                                    ),
                                    _finalParte(item),
                                  ],
                                ),
                              ),
                              if (!automatico)
                                PopupMenuButton<String>(
                                  onSelected: (valor) {
                                    if (valor == 'editar') {
                                      _abrirFormulario(mapa: item);
                                    } else if (valor == 'baixar') {
                                      _baixar(item);
                                    } else if (valor == 'cancelar') {
                                      _cancelar(item);
                                    } else if (valor == 'excluir') {
                                      _excluir(item);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'editar',
                                      child: Text('Editar'),
                                    ),
                                    if ((item['status'] ?? '') == 'Previsto')
                                      const PopupMenuItem(
                                        value: 'baixar',
                                        child: Text('Marcar como realizado'),
                                      ),
                                    if ((item['status'] ?? '') != 'Cancelado')
                                      const PopupMenuItem(
                                        value: 'cancelar',
                                        child: Text('Cancelar lançamento'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'excluir',
                                      child: Text(
                                        'Excluir',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _finalParte(Map<String, dynamic> item) {
    final pessoa = (item['cliente_nome'] ?? item['fornecedor_nome'] ?? '')
        .toString();
    final obs = (item['observacoes'] ?? '').toString();
    if (pessoa.isEmpty && obs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        [if (pessoa.isNotEmpty) pessoa, if (obs.isNotEmpty) obs].join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      ),
    );
  }

  DateTime? _dataMovimento(Map<String, dynamic> item) {
    for (final chave in [
      'data_pagamento',
      'data_vencimento',
      'data_competencia',
      'data',
    ]) {
      final data = DateTime.tryParse(item[chave]?.toString() ?? '');
      if (data != null) {
        return data;
      }
    }
    return null;
  }
}

class _DadosFormularioFinanceiro {
  const _DadosFormularioFinanceiro({
    required this.plano,
    required this.contas,
    required this.fornecedores,
    required this.clientes,
  });

  final List<PlanoContaFinanceiro> plano;
  final List<ContaFinanceira> contas;
  final List<Fornecedor> fornecedores;
  final List<Map<String, dynamic>> clientes;

  List<PlanoContaFinanceiro> folhas(String tipo) {
    final parentIds = plano.map((e) => e.parentId).whereType<int>().toSet();
    return plano.where((item) {
      if (!item.ativo || item.id == null || parentIds.contains(item.id)) {
        return false;
      }
      return item.tipo == tipo || item.tipo == 'Neutro';
    }).toList();
  }
}

class _MovimentoFormSheet extends StatefulWidget {
  const _MovimentoFormSheet({
    required this.repository,
    required this.dados,
    this.movimento,
  });

  final FinanceiroRepository repository;
  final _DadosFormularioFinanceiro dados;
  final MovimentoFinanceiro? movimento;

  @override
  State<_MovimentoFormSheet> createState() => _MovimentoFormSheetState();
}

class _MovimentoFormSheetState extends State<_MovimentoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descricao;
  late final TextEditingController _valor;
  late final TextEditingController _documento;
  late final TextEditingController _observacoes;

  String _tipo = 'Entrada';
  String _status = 'Realizado';
  String _formaPagamento = 'Pix';
  int? _planoContaId;
  int? _contaId;
  int? _clienteId;
  int? _fornecedorId;
  DateTime _competencia = DateTime.now();
  DateTime? _vencimento;
  DateTime? _pagamento = DateTime.now();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final m = widget.movimento;
    _descricao = TextEditingController(text: m?.descricao ?? '');
    _valor = TextEditingController(
      text: m == null ? '' : m.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    _documento = TextEditingController(text: m?.numeroDocumento ?? '');
    _observacoes = TextEditingController(text: m?.observacoes ?? '');
    _tipo = _tipoNormalizado(m?.tipo ?? 'Entrada');
    _status = m?.status ?? 'Realizado';
    _formaPagamento = m?.formaPagamento.isNotEmpty == true
        ? m!.formaPagamento
        : 'Pix';
    _planoContaId = m?.planoContaId;
    _contaId = m?.contaId;
    _clienteId = m?.clienteId;
    _fornecedorId = m?.fornecedorId;
    _competencia =
        DateTime.tryParse(m?.dataCompetencia ?? m?.data ?? '') ??
        DateTime.now();
    _vencimento = DateTime.tryParse(m?.dataVencimento ?? '');
    _pagamento = m?.status == 'Previsto'
        ? DateTime.tryParse(m?.dataPagamento ?? '')
        : DateTime.tryParse(m?.dataPagamento ?? m?.data ?? '') ??
              DateTime.now();
  }

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    _documento.dispose();
    _observacoes.dispose();
    super.dispose();
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

  Future<DateTime?> _escolherData(DateTime? atual) async {
    final hoje = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: atual ?? hoje,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoje.year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final valor = _lerValor();
    if (valor == null || valor <= 0) {
      return;
    }

    if (_status == 'Realizado' && _pagamento == null) {
      _pagamento = DateTime.now();
    }

    setState(() => _salvando = true);
    try {
      final anterior = widget.movimento;
      final base = _status == 'Realizado'
          ? _pagamento ?? _competencia
          : _vencimento ?? _competencia;

      final movimento = MovimentoFinanceiro(
        id: anterior?.id,
        tipo: _tipo,
        descricao: _descricao.text.trim(),
        valor: valor,
        formaPagamento: _formaPagamento,
        data: base.toIso8601String(),
        clienteId: _tipo == 'Entrada' ? _clienteId : null,
        agendamentoId: anterior?.agendamentoId,
        ordemServicoId: anterior?.ordemServicoId,
        pagamentoId: anterior?.pagamentoId,
        planoContaId: _planoContaId,
        contaId: _contaId,
        fornecedorId: _tipo == 'Saída' ? _fornecedorId : null,
        transferenciaId: anterior?.transferenciaId,
        natureza: anterior?.natureza ?? 'Não classificado',
        origem: anterior?.origem ?? 'Manual',
        status: _status,
        dataCompetencia: _competencia.toIso8601String(),
        dataVencimento: _vencimento?.toIso8601String(),
        dataPagamento: _status == 'Realizado'
            ? _pagamento?.toIso8601String()
            : null,
        numeroDocumento: _documento.text.trim(),
        observacoes: _observacoes.text.trim(),
        impactaDre: anterior?.impactaDre ?? true,
      );

      if (anterior == null) {
        await widget.repository.inserirMovimento(movimento);
      } else {
        await widget.repository.atualizarMovimento(movimento);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  PlanoContaFinanceiro? _categoriaPorCodigo(String codigo) {
    for (final item in widget.dados.plano) {
      if (item.codigo == codigo && item.ativo) {
        return item;
      }
    }
    return null;
  }

  void _selecionarGastoPessoalProprietario() {
    final categoria = _categoriaPorCodigo('2.01.02');
    if (categoria?.id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'A categoria de gastos pessoais do proprietário não está disponível.',
            ),
          ),
        );
      return;
    }

    setState(() {
      _tipo = 'Saída';
      _planoContaId = categoria!.id;
      _clienteId = null;
      _fornecedorId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final categorias = widget.dados.folhas(_tipo);
    if (_planoContaId != null &&
        !categorias.any((item) => item.id == _planoContaId)) {
      _planoContaId = null;
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.95,
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.movimento == null
                    ? 'Novo lançamento'
                    : 'Editar lançamento',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Entrada', label: Text('Entrada')),
                  ButtonSegment(value: 'Saída', label: Text('Saída')),
                ],
                selected: {_tipo},
                onSelectionChanged: _salvando
                    ? null
                    : (selecionados) {
                        setState(() {
                          _tipo = selecionados.first;
                          _planoContaId = null;
                          _clienteId = null;
                          _fornecedorId = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (_categoriaPorCodigo('2.01.02') != null) ...[
                OutlinedButton.icon(
                  onPressed: _salvando
                      ? null
                      : _selecionarGastoPessoalProprietario,
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('Selecionar gasto pessoal do proprietário'),
                ),
                if (_planoContaId == _categoriaPorCodigo('2.01.02')?.id) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Este valor será tratado como despesa efetivamente paga '
                    'ao proprietário e entrará na DRE. O valor cadastrado em '
                    'Mão de Obra continua apenas na precificação.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<int?>(
                key: ValueKey('plano-$_tipo-$_planoContaId'),
                initialValue: _planoContaId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: categorias
                    .map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text('${item.codigo} ${item.nome}'),
                      ),
                    )
                    .toList(),
                validator: (valor) =>
                    valor == null ? 'Selecione a categoria.' : null,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _planoContaId = valor),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descricao,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descrição'),
                validator: (valor) => (valor?.trim().length ?? 0) < 3
                    ? 'Informe uma descrição.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$ ',
                ),
                validator: (_) {
                  final valor = _lerValor();
                  return valor == null || valor <= 0
                      ? 'Informe um valor válido.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Situação'),
                items: const [
                  DropdownMenuItem(value: 'Previsto', child: Text('Previsto')),
                  DropdownMenuItem(
                    value: 'Realizado',
                    child: Text('Realizado'),
                  ),
                  DropdownMenuItem(
                    value: 'Cancelado',
                    child: Text('Cancelado'),
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
                          if (valor == 'Realizado') {
                            _pagamento ??= DateTime.now();
                          } else {
                            _pagamento = null;
                          }
                        });
                      },
              ),
              const SizedBox(height: 8),
              _DataTile(
                titulo: 'Competência',
                data: _competencia,
                obrigatoria: true,
                onTap: _salvando
                    ? null
                    : () async {
                        final valor = await _escolherData(_competencia);
                        if (valor != null && mounted) {
                          setState(() => _competencia = valor);
                        }
                      },
              ),
              _DataTile(
                titulo: 'Vencimento',
                data: _vencimento,
                onTap: _salvando
                    ? null
                    : () async {
                        final valor = await _escolherData(_vencimento);
                        if (valor != null && mounted) {
                          setState(() => _vencimento = valor);
                        }
                      },
                onClear: _vencimento == null || _salvando
                    ? null
                    : () => setState(() => _vencimento = null),
              ),
              if (_status == 'Realizado')
                _DataTile(
                  titulo: 'Data do pagamento',
                  data: _pagamento,
                  obrigatoria: true,
                  onTap: _salvando
                      ? null
                      : () async {
                          final valor = await _escolherData(_pagamento);
                          if (valor != null && mounted) {
                            setState(() => _pagamento = valor);
                          }
                        },
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _contaId,
                decoration: InputDecoration(
                  labelText: _status == 'Realizado'
                      ? 'Conta / caixa *'
                      : 'Conta / caixa (opcional)',
                  helperText: _status == 'Realizado'
                      ? 'Obrigatória para atualizar o saldo real.'
                      : 'Pode ser definida quando o lançamento for realizado.',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Não informado'),
                  ),
                  ...widget.dados.contas.map(
                    (item) => DropdownMenuItem<int?>(
                      value: item.id,
                      child: Text(item.nome),
                    ),
                  ),
                ],
                validator: (valor) {
                  if (_status == 'Realizado' && valor == null) {
                    return 'Selecione a conta/caixa.';
                  }
                  return null;
                },
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _contaId = valor),
              ),
              const SizedBox(height: 12),
              if (_tipo == 'Entrada')
                DropdownButtonFormField<int?>(
                  initialValue: _clienteId,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (opcional)',
                  ),
                  menuMaxHeight: 360,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Não informado'),
                    ),
                    ...widget.dados.clientes.map(
                      (item) => DropdownMenuItem<int?>(
                        value: _int(item['id']),
                        child: Text((item['nome'] ?? 'Cliente').toString()),
                      ),
                    ),
                  ],
                  onChanged: _salvando
                      ? null
                      : (valor) => setState(() => _clienteId = valor),
                )
              else
                DropdownButtonFormField<int?>(
                  initialValue: _fornecedorId,
                  decoration: const InputDecoration(
                    labelText: 'Fornecedor (opcional)',
                  ),
                  menuMaxHeight: 360,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Não informado'),
                    ),
                    ...widget.dados.fornecedores.map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text(item.nome),
                      ),
                    ),
                  ],
                  onChanged: _salvando
                      ? null
                      : (valor) => setState(() => _fornecedorId = valor),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _formasPagamento.contains(_formaPagamento)
                    ? _formaPagamento
                    : 'Outro',
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                ),
                items: _formasPagamento
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) => setState(
                        () => _formaPagamento = valor ?? _formaPagamento,
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _documento,
                decoration: const InputDecoration(
                  labelText: 'Documento / referência (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observacoes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferenciaSheet extends StatefulWidget {
  const _TransferenciaSheet({required this.repository, required this.contas});

  final FinanceiroRepository repository;
  final List<ContaFinanceira> contas;

  @override
  State<_TransferenciaSheet> createState() => _TransferenciaSheetState();
}

class _TransferenciaSheetState extends State<_TransferenciaSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _valor = TextEditingController();
  final TextEditingController _descricao = TextEditingController(
    text: 'Transferência entre contas',
  );
  final TextEditingController _observacoes = TextEditingController();
  int? _origem;
  int? _destino;
  DateTime _data = DateTime.now();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    if (widget.contas.isNotEmpty) {
      _origem = widget.contas.first.id;
    }
    if (widget.contas.length > 1) {
      _destino = widget.contas[1].id;
    }
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    _observacoes.dispose();
    super.dispose();
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

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_origem == null || _destino == null) {
      return;
    }
    setState(() => _salvando = true);
    try {
      await widget.repository.registrarTransferencia(
        contaOrigemId: _origem!,
        contaDestinoId: _destino!,
        valor: _lerValor()!,
        data: _data,
        descricao: _descricao.text,
        observacoes: _observacoes.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transferência entre contas',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'A transferência movimenta o caixa, mas não entra na DRE.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _origem,
                decoration: const InputDecoration(labelText: 'Conta de origem'),
                items: widget.contas
                    .map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text(item.nome),
                      ),
                    )
                    .toList(),
                validator: (valor) =>
                    valor == null ? 'Selecione a origem.' : null,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _origem = valor),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _destino,
                decoration: const InputDecoration(
                  labelText: 'Conta de destino',
                ),
                items: widget.contas
                    .map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text(item.nome),
                      ),
                    )
                    .toList(),
                validator: (valor) {
                  if (valor == null) {
                    return 'Selecione o destino.';
                  }
                  if (valor == _origem) {
                    return 'A conta de destino deve ser diferente.';
                  }
                  return null;
                },
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _destino = valor),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$ ',
                ),
                validator: (_) {
                  final valor = _lerValor();
                  return valor == null || valor <= 0
                      ? 'Informe um valor válido.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descricao,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              _DataTile(
                titulo: 'Data',
                data: _data,
                obrigatoria: true,
                onTap: _salvando
                    ? null
                    : () async {
                        final hoje = DateTime.now();
                        final valor = await showDatePicker(
                          context: context,
                          initialDate: _data,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(hoje.year + 10, 12, 31),
                          locale: const Locale('pt', 'BR'),
                        );
                        if (valor != null && mounted) {
                          setState(() => _data = valor);
                        }
                      },
              ),
              TextField(
                controller: _observacoes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Transferir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  const _DataTile({
    required this.titulo,
    required this.data,
    this.onTap,
    this.onClear,
    this.obrigatoria = false,
  });

  final String titulo;
  final DateTime? data;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool obrigatoria;

  @override
  Widget build(BuildContext context) {
    final texto = data == null
        ? (obrigatoria ? 'Selecione a data' : 'Não informado')
        : DateFormat('dd/MM/yyyy').format(data!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_month_outlined),
      title: Text(titulo),
      subtitle: Text(texto),
      trailing: onClear == null
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton(
              tooltip: 'Remover data',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
      onTap: onTap,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.texto, this.cor, this.icone});

  final String texto;
  final Color? cor;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final corBase = cor ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: corBase.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 12, color: corBase),
            const SizedBox(width: 3),
          ],
          Text(texto, style: TextStyle(color: corBase, fontSize: 11)),
        ],
      ),
    );
  }
}

const _formasPagamento = <String>[
  'Pix',
  'Dinheiro',
  'Cartão de crédito',
  'Cartão de débito',
  'Transferência',
  'Boleto',
  'Outro',
];

String _tipoNormalizado(String valor) {
  final tipo = valor.trim().toLowerCase();
  return tipo == 'saída' || tipo == 'saida' ? 'Saída' : 'Entrada';
}

Color _corStatus(String status) {
  switch (status) {
    case 'Realizado':
      return Colors.green;
    case 'Atrasado':
      return Colors.redAccent;
    case 'Previsto':
      return Colors.amber;
    case 'Cancelado':
      return Colors.grey;
    default:
      return Colors.blueGrey;
  }
}

int? _int(dynamic valor) {
  if (valor is int) {
    return valor;
  }
  if (valor is num) {
    return valor.toInt();
  }
  return int.tryParse(valor?.toString().trim() ?? '');
}

double _double(dynamic valor) {
  if (valor is num) {
    return valor.toDouble();
  }
  return double.tryParse(valor?.toString().trim().replaceAll(',', '.') ?? '') ??
      0;
}
