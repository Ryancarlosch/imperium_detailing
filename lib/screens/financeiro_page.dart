import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/movimento_financeiro.dart';
import '../repositories/financeiro_repository.dart';

class FinanceiroPage extends StatefulWidget {
  const FinanceiroPage({super.key});

  @override
  State<FinanceiroPage> createState() => _FinanceiroPageState();
}

class _FinanceiroPageState extends State<FinanceiroPage> {
  final FinanceiroRepository _repository = FinanceiroRepository();
  final TextEditingController _pesquisaController = TextEditingController();

  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _formatoData = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  String _pesquisa = '';
  String _filtroTipo = 'Todos';
  DateTimeRange? _periodoSelecionado;

  List<Map<String, dynamic>> _movimentos = [];

  double _entradas = 0;
  double _saidas = 0;
  double _saldo = 0;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final movimentos = await _repository.listarMovimentosComCliente();

      double entradas = 0;
      double saidas = 0;

      for (final movimento in movimentos) {
        final tipo = (movimento['tipo'] ?? '').toString().toLowerCase();
        final valor = _converterParaDouble(movimento['valor']);

        if (tipo == 'entrada') {
          entradas += valor;
        } else if (tipo == 'saída' || tipo == 'saida') {
          saidas += valor;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _movimentos = movimentos;
        _entradas = entradas;
        _saidas = saidas;
        _saldo = entradas - saidas;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar o financeiro: $erro',
        erro: true,
      );
    }
  }

  double _converterParaDouble(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
      valor.toString().replaceAll(',', '.'),
    ) ??
        0;
  }

  DateTime? _converterData(dynamic valor) {
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

  List<Map<String, dynamic>> get _movimentosFiltrados {
    final termo = _pesquisa.trim().toLowerCase();

    final lista = _movimentos.where((movimento) {
      final tipo = (movimento['tipo'] ?? '').toString();
      final descricao = (movimento['descricao'] ?? '').toString();
      final formaPagamento =
      (movimento['forma_pagamento'] ?? '').toString();
      final nomeCliente = (movimento['cliente_nome'] ??
          movimento['nome_cliente'] ??
          movimento['nome'] ??
          '')
          .toString();

      final correspondePesquisa = termo.isEmpty ||
          descricao.toLowerCase().contains(termo) ||
          formaPagamento.toLowerCase().contains(termo) ||
          nomeCliente.toLowerCase().contains(termo);

      final correspondeTipo = _filtroTipo == 'Todos' ||
          tipo.toLowerCase() == _filtroTipo.toLowerCase() ||
          (_filtroTipo == 'Saída' && tipo.toLowerCase() == 'saida');

      final dataMovimento = _converterData(movimento['data']);

      final correspondePeriodo = _periodoSelecionado == null ||
          (dataMovimento != null &&
              !dataMovimento.isBefore(
                DateTime(
                  _periodoSelecionado!.start.year,
                  _periodoSelecionado!.start.month,
                  _periodoSelecionado!.start.day,
                ),
              ) &&
              !dataMovimento.isAfter(
                DateTime(
                  _periodoSelecionado!.end.year,
                  _periodoSelecionado!.end.month,
                  _periodoSelecionado!.end.day,
                  23,
                  59,
                  59,
                ),
              ));

      return correspondePesquisa &&
          correspondeTipo &&
          correspondePeriodo;
    }).toList();

    lista.sort((a, b) {
      final dataA = _converterData(a['data']) ?? DateTime(1900);
      final dataB = _converterData(b['data']) ?? DateTime(1900);
      return dataB.compareTo(dataA);
    });

    return lista;
  }

  double get _entradasFiltradas {
    return _movimentosFiltrados
        .where(
          (item) =>
      (item['tipo'] ?? '').toString().toLowerCase() == 'entrada',
    )
        .fold<double>(
      0,
          (total, item) => total + _converterParaDouble(item['valor']),
    );
  }

  double get _saidasFiltradas {
    return _movimentosFiltrados
        .where((item) {
      final tipo = (item['tipo'] ?? '').toString().toLowerCase();
      return tipo == 'saída' || tipo == 'saida';
    })
        .fold<double>(
      0,
          (total, item) => total + _converterParaDouble(item['valor']),
    );
  }

  Future<void> _selecionarPeriodo() async {
    final hoje = DateTime.now();

    final periodo = await showDateRangePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      firstDate: DateTime(2020),
      lastDate: DateTime(hoje.year + 5),
      initialDateRange: _periodoSelecionado,
      helpText: 'Selecionar período',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
      fieldStartHintText: 'Data inicial',
      fieldEndHintText: 'Data final',
    );

    if (periodo == null || !mounted) {
      return;
    }

    setState(() {
      _periodoSelecionado = periodo;
    });
  }

  Future<void> _abrirFormulario({
    Map<String, dynamic>? movimento,
  }) async {
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FormularioMovimento(
          movimento: movimento,
          repository: _repository,
        );
      },
    );

    if (resultado == true) {
      await _carregarDados();
    }
  }

  Future<void> _confirmarExclusao(
      Map<String, dynamic> movimento,
      ) async {
    final descricao = (movimento['descricao'] ?? 'Movimentação').toString();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir movimentação'),
          content: Text(
            'Deseja realmente excluir "$descricao"?\n\n'
                'Esta ação não poderá ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    try {
      final id = movimento['id'] as int?;
      if (id == null) {
        throw Exception('Identificador da movimentação não encontrado.');
      }

      await _repository.excluirMovimento(id);

      if (!mounted) {
        return;
      }

      _mostrarMensagem('Movimentação excluída com sucesso.');
      await _carregarDados();
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível excluir: $erro',
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
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final movimentosFiltrados = _movimentosFiltrados;
    final usandoFiltros = _pesquisa.isNotEmpty ||
        _filtroTipo != 'Todos' ||
        _periodoSelecionado != null;

    final entradasExibidas =
    usandoFiltros ? _entradasFiltradas : _entradas;
    final saidasExibidas = usandoFiltros ? _saidasFiltradas : _saidas;
    final saldoExibido =
    usandoFiltros ? entradasExibidas - saidasExibidas : _saldo;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        title: const Text('Controle financeiro'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarDados,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova movimentação'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregarDados,
        child: _carregando
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _ResumoFinanceiro(
                  entradas: entradasExibidas,
                  saidas: saidasExibidas,
                  saldo: saldoExibido,
                  formatoMoeda: _formatoMoeda,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _construirFiltros(),
              ),
            ),
            if (movimentosFiltrados.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EstadoVazio(
                  possuiFiltros: usandoFiltros,
                  aoAdicionar: () => _abrirFormulario(),
                  aoLimparFiltros: _limparFiltros,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        'Movimentações',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${movimentosFiltrados.length} registro(s)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverList.separated(
                  itemCount: movimentosFiltrados.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final movimento = movimentosFiltrados[index];

                    return _CardMovimento(
                      movimento: movimento,
                      formatoMoeda: _formatoMoeda,
                      formatoData: _formatoData,
                      converterData: _converterData,
                      converterValor: _converterParaDouble,
                      aoEditar: () => _abrirFormulario(
                        movimento: movimento,
                      ),
                      aoExcluir: () => _confirmarExclusao(
                        movimento,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirFiltros() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _pesquisaController,
              onChanged: (valor) {
                setState(() {
                  _pesquisa = valor;
                });
              },
              decoration: InputDecoration(
                hintText: 'Pesquisar descrição, cliente ou pagamento',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _pesquisa.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Limpar pesquisa',
                  onPressed: () {
                    _pesquisaController.clear();
                    setState(() {
                      _pesquisa = '';
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroTipo,
                    decoration: InputDecoration(
                      labelText: 'Tipo',
                      prefixIcon: const Icon(Icons.tune_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
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

                      setState(() {
                        _filtroTipo = valor;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selecionarPeriodo,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      _periodoSelecionado == null
                          ? 'Período'
                          : '${_formatoData.format(_periodoSelecionado!.start)}'
                          ' até '
                          '${_formatoData.format(_periodoSelecionado!.end)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_pesquisa.isNotEmpty ||
                _filtroTipo != 'Todos' ||
                _periodoSelecionado != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _limparFiltros,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Limpar filtros'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _limparFiltros() {
    _pesquisaController.clear();

    setState(() {
      _pesquisa = '';
      _filtroTipo = 'Todos';
      _periodoSelecionado = null;
    });
  }
}

class _ResumoFinanceiro extends StatelessWidget {
  const _ResumoFinanceiro({
    required this.entradas,
    required this.saidas,
    required this.saldo,
    required this.formatoMoeda,
  });

  final double entradas;
  final double saidas;
  final double saldo;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final saldoPositivo = saldo >= 0;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blueGrey.shade900,
                Colors.blueGrey.shade700,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo atual',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatoMoeda.format(saldo),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: saldoPositivo
                      ? Colors.lightGreenAccent
                      : Colors.redAccent.shade100,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                saldoPositivo
                    ? 'As entradas estão acima das saídas.'
                    : 'As saídas estão acima das entradas.',
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CardResumoMenor(
                titulo: 'Entradas',
                valor: formatoMoeda.format(entradas),
                icone: Icons.south_west_rounded,
                cor: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CardResumoMenor(
                titulo: 'Saídas',
                valor: formatoMoeda.format(saidas),
                icone: Icons.north_east_rounded,
                cor: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CardResumoMenor extends StatelessWidget {
  const _CardResumoMenor({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icone,
                color: cor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardMovimento extends StatelessWidget {
  const _CardMovimento({
    required this.movimento,
    required this.formatoMoeda,
    required this.formatoData,
    required this.converterData,
    required this.converterValor,
    required this.aoEditar,
    required this.aoExcluir,
  });

  final Map<String, dynamic> movimento;
  final NumberFormat formatoMoeda;
  final DateFormat formatoData;
  final DateTime? Function(dynamic) converterData;
  final double Function(dynamic) converterValor;
  final VoidCallback aoEditar;
  final VoidCallback aoExcluir;

  @override
  Widget build(BuildContext context) {
    final tipo = (movimento['tipo'] ?? '').toString();
    final entrada = tipo.toLowerCase() == 'entrada';
    final valor = converterValor(movimento['valor']);
    final data = converterData(movimento['data']);

    final nomeCliente = (movimento['cliente_nome'] ??
        movimento['nome_cliente'] ??
        movimento['nome'] ??
        '')
        .toString();

    final formaPagamento =
    (movimento['forma_pagamento'] ?? '').toString();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoEditar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (entrada ? Colors.green : Colors.red)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  entrada
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: entrada ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (movimento['descricao'] ?? 'Sem descrição').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _InformacaoLinha(
                          icone: Icons.calendar_today_rounded,
                          texto: data == null
                              ? 'Data não informada'
                              : formatoData.format(data),
                        ),
                        if (formaPagamento.isNotEmpty)
                          _InformacaoLinha(
                            icone: Icons.payments_outlined,
                            texto: formaPagamento,
                          ),
                        if (nomeCliente.isNotEmpty)
                          _InformacaoLinha(
                            icone: Icons.person_outline_rounded,
                            texto: nomeCliente,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entrada ? '+' : '-'} ${formatoMoeda.format(valor)}',
                    style: TextStyle(
                      color: entrada ? Colors.green.shade700 : Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opções',
                    onSelected: (opcao) {
                      if (opcao == 'editar') {
                        aoEditar();
                      } else if (opcao == 'excluir') {
                        aoExcluir();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'editar',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'excluir',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                          ),
                          title: Text(
                            'Excluir',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
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

class _InformacaoLinha extends StatelessWidget {
  const _InformacaoLinha({
    required this.icone,
    required this.texto,
  });

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icone,
          size: 14,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({
    required this.possuiFiltros,
    required this.aoAdicionar,
    required this.aoLimparFiltros,
  });

  final bool possuiFiltros;
  final VoidCallback aoAdicionar;
  final VoidCallback aoLimparFiltros;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              possuiFiltros
                  ? Icons.search_off_rounded
                  : Icons.account_balance_wallet_outlined,
              size: 72,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              possuiFiltros
                  ? 'Nenhuma movimentação encontrada'
                  : 'Nenhuma movimentação cadastrada',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              possuiFiltros
                  ? 'Altere ou limpe os filtros para visualizar outros registros.'
                  : 'Cadastre entradas e saídas para acompanhar o resultado da empresa.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: possuiFiltros ? aoLimparFiltros : aoAdicionar,
              icon: Icon(
                possuiFiltros
                    ? Icons.filter_alt_off_rounded
                    : Icons.add_rounded,
              ),
              label: Text(
                possuiFiltros
                    ? 'Limpar filtros'
                    : 'Adicionar movimentação',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormularioMovimento extends StatefulWidget {
  const _FormularioMovimento({
    required this.repository,
    this.movimento,
  });

  final FinanceiroRepository repository;
  final Map<String, dynamic>? movimento;

  @override
  State<_FormularioMovimento> createState() =>
      _FormularioMovimentoState();
}

class _FormularioMovimentoState extends State<_FormularioMovimento> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _descricaoController;
  late final TextEditingController _valorController;

  final DateFormat _formatoData = DateFormat('dd/MM/yyyy');

  String _tipo = 'Entrada';
  String _formaPagamento = 'Pix';
  DateTime _data = DateTime.now();
  bool _salvando = false;

  bool get _editando => widget.movimento != null;

  @override
  void initState() {
    super.initState();

    final movimento = widget.movimento;

    _descricaoController = TextEditingController(
      text: (movimento?['descricao'] ?? '').toString(),
    );

    final valor = movimento?['valor'];
    _valorController = TextEditingController(
      text: valor == null ? '' : _formatarValorInicial(valor),
    );

    final tipoSalvo = (movimento?['tipo'] ?? '').toString().toLowerCase();
    if (tipoSalvo == 'saída' || tipoSalvo == 'saida') {
      _tipo = 'Saída';
    }

    final formaSalva =
    (movimento?['forma_pagamento'] ?? '').toString().trim();
    if (formaSalva.isNotEmpty) {
      _formaPagamento = formaSalva;
    }

    final dataSalva = movimento?['data'];
    if (dataSalva != null) {
      try {
        _data = DateTime.parse(dataSalva.toString());
      } catch (_) {
        try {
          _data = DateFormat('dd/MM/yyyy').parseStrict(
            dataSalva.toString(),
          );
        } catch (_) {}
      }
    }
  }

  String _formatarValorInicial(dynamic valor) {
    final numero = valor is num
        ? valor.toDouble()
        : double.tryParse(valor.toString()) ?? 0;

    return numero.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
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
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'Selecionar data',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );

    if (data == null || !mounted) {
      return;
    }

    setState(() {
      _data = data;
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final valor = _lerValor();
    if (valor == null || valor <= 0) {
      _mostrarErro('Informe um valor maior que zero.');
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final movimento = MovimentoFinanceiro(
        id: widget.movimento?['id'] as int?,
        tipo: _tipo,
        descricao: _descricaoController.text.trim(),
        valor: valor,
        formaPagamento: _formaPagamento,
        data: _data.toIso8601String(),
        clienteId: _converterInt(widget.movimento?['cliente_id']),
        agendamentoId:
        _converterInt(widget.movimento?['agendamento_id']),
      );

      if (_editando) {
        await widget.repository.atualizarMovimento(movimento);
      } else {
        await widget.repository.inserirMovimento(movimento);
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

      _mostrarErro('Não foi possível salvar: $erro');
    }
  }

  int? _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  void _mostrarErro(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 45,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              Text(
                _editando
                    ? 'Editar movimentação'
                    : 'Nova movimentação',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'Entrada',
                    label: Text('Entrada'),
                    icon: Icon(Icons.south_west_rounded),
                  ),
                  ButtonSegment(
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
                  labelText: 'Forma de pagamento',
                  prefixIcon: Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Pix',
                    child: Text('Pix'),
                  ),
                  DropdownMenuItem(
                    value: 'Dinheiro',
                    child: Text('Dinheiro'),
                  ),
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
                  DropdownMenuItem(
                    value: 'Boleto',
                    child: Text('Boleto'),
                  ),
                  DropdownMenuItem(
                    value: 'Outro',
                    child: Text('Outro'),
                  ),
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
                borderRadius: BorderRadius.circular(4),
                onTap: _selecionarData,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    prefixIcon: Icon(Icons.calendar_month_rounded),
                    suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _formatoData.format(_data),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
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
                      label: Text(
                        _salvando ? 'Salvando...' : 'Salvar',
                      ),
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
