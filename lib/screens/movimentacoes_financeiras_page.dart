import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../models/movimento_financeiro.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_repository.dart';
import 'lancamento_financeiro_page.dart';
import 'transferencia_financeira_page.dart';

// financeiro-movimentacoes-compactas-v1
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
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
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
  List<Map<String, dynamic>> _movimentos = const [];

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
    if (mounted) setState(() => _carregando = true);

    try {
      final movimentos = await _repository.listarMovimentosComDetalhes(
        tipo: _tipo == 'Todos' ? null : _tipo,
        status: _status == 'Todos' ? null : _status,
      );

      if (!mounted) return;

      setState(() {
        _movimentos = movimentos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final termo = _pesquisa.trim().toLowerCase();
    if (termo.isEmpty) return _movimentos;

    return _movimentos.where((item) {
      return [
        item['descricao'],
        item['cliente_nome'],
        item['fornecedor_nome'],
        item['conta_nome'],
        item['plano_nome'],
        item['forma_pagamento'],
        item['numero_documento'],
        item['origem'],
      ].any((valor) => (valor ?? '').toString().toLowerCase().contains(termo));
    }).toList();
  }

  bool _automatico(Map<String, dynamic> item) {
    final origem = (item['origem'] ?? 'Manual').toString().trim();
    return item['pagamento_id'] != null ||
        item['ordem_servico_id'] != null ||
        item['transferencia_id'] != null ||
        origem != 'Manual';
  }

  Future<void> _novo({Map<String, dynamic>? item}) async {
    final movimento = item == null
        ? null
        : MovimentoFinanceiro.fromMap(Map<String, dynamic>.from(item));

    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LancamentoFinanceiroPage(
          tipoInicial: _tipo == 'Saída' ? 'Saída' : 'Entrada',
          movimento: movimento,
        ),
      ),
    );

    if (resultado == true) await _carregar();
  }

  Future<void> _transferir() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TransferenciaFinanceiraPage()),
    );

    if (resultado == true) await _carregar();
  }

  Future<void> _baixar(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) return;

    final contas = await _contasRepository.listar();
    if (!mounted) return;

    if (contas.isEmpty) {
      _mensagem('Cadastre uma conta financeira antes da baixa.', erro: true);
      return;
    }

    int? selecionada = _int(item['conta_id']);
    if (!contas.any((conta) => conta.id == selecionada && conta.ativo)) {
      final ativas = contas.where((conta) => conta.id != null && conta.ativo);
      selecionada = ativas.length == 1 ? ativas.first.id : null;
    }

    final contaId = await showDialog<int>(
      context: context,
      builder: (dialogContext) =>
          _EscolherContaDialog(contas: contas, inicial: selecionada),
    );

    if (contaId == null) return;

    try {
      await _repository.marcarComoRealizado(
        id: id,
        contaId: contaId,
        dataPagamento: DateTime.now(),
        formaPagamento:
            (item['forma_pagamento'] ?? '').toString().trim().isEmpty
            ? null
            : (item['forma_pagamento'] ?? '').toString(),
      );
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) return;

    final ok = await _confirmar(
      titulo: 'Cancelar lançamento?',
      texto:
          'O lançamento continuará no histórico, mas deixará de afetar as análises.',
      acao: 'Cancelar lançamento',
    );

    if (!ok) return;

    try {
      await _repository.cancelarMovimento(id);
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _excluir(Map<String, dynamic> item) async {
    final id = _int(item['id']);
    if (id == null) return;

    final ok = await _confirmar(
      titulo: 'Excluir lançamento manual?',
      texto:
          'Use exclusão somente para lançamento manual criado por engano. Movimentos automáticos são protegidos.',
      acao: 'Excluir',
    );

    if (!ok) return;

    try {
      await _repository.excluirMovimento(id);
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String acao,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(titulo),
            content: Text(texto),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(acao),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _detalhes(Map<String, dynamic> item) async {
    final automatico = _automatico(item);
    final status = (item['status'] ?? '').toString();
    final descricao = (item['descricao'] ?? '').toString();
    final tipo = _tipoNormalizado(item['tipo']);
    final valor = _double(item['valor']);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  descricao,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _DetalheLinha('Valor', _moeda.format(valor)),
                _DetalheLinha('Tipo', tipo),
                _DetalheLinha('Status', status),
                _DetalheLinha(
                  'Competência',
                  _formatarData(item['data_competencia']),
                ),
                if ((item['data_vencimento'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _DetalheLinha(
                    'Vencimento',
                    _formatarData(item['data_vencimento']),
                  ),
                if ((item['data_pagamento'] ?? '').toString().trim().isNotEmpty)
                  _DetalheLinha(
                    'Pagamento',
                    _formatarData(item['data_pagamento']),
                  ),
                _DetalheLinha(
                  'Categoria',
                  (item['plano_nome'] ?? 'Sem categoria').toString(),
                ),
                _DetalheLinha(
                  'Conta',
                  (item['conta_nome'] ?? 'Não informada').toString(),
                ),
                if ((item['cliente_nome'] ?? '').toString().trim().isNotEmpty)
                  _DetalheLinha('Cliente', item['cliente_nome'].toString()),
                if ((item['fornecedor_nome'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _DetalheLinha(
                    'Fornecedor',
                    item['fornecedor_nome'].toString(),
                  ),
                if ((item['forma_pagamento'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _DetalheLinha('Forma', item['forma_pagamento'].toString()),
                if ((item['numero_documento'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty)
                  _DetalheLinha(
                    'Documento',
                    item['numero_documento'].toString(),
                  ),
                _DetalheLinha(
                  'Origem',
                  (item['origem'] ?? 'Manual').toString(),
                ),
                if ((item['observacoes'] ?? '').toString().trim().isNotEmpty)
                  _DetalheLinha('Observações', item['observacoes'].toString()),
                const SizedBox(height: 16),
                if (automatico)
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Este lançamento é automático. Para alterar, use o módulo que o gerou.',
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(bottomContext).pop();
                          _novo(item: item);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                      if (status == 'Previsto')
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(bottomContext).pop();
                            _baixar(item);
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Marcar realizado'),
                        ),
                      if (status != 'Cancelado')
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(bottomContext).pop();
                            _cancelar(item);
                          },
                          icon: const Icon(Icons.block_outlined),
                          label: const Text('Cancelar'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(bottomContext).pop();
                          _excluir(item);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Excluir'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatarData(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null ? '-' : _data.format(data);
  }

  DateTime? _dataMovimento(Map<String, dynamic> item) {
    for (final chave in [
      'data_pagamento',
      'data_vencimento',
      'data_competencia',
      'data',
    ]) {
      final data = DateTime.tryParse(item[chave]?.toString() ?? '');
      if (data != null) return data;
    }
    return null;
  }

  String _tipoNormalizado(dynamic valor) {
    final texto = (valor ?? '').toString().trim().toLowerCase();
    return texto == 'saída' || texto == 'saida' ? 'Saída' : 'Entrada';
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
    final lista = _filtrados;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Transferir entre contas',
            onPressed: _transferir,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _novo(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Lançamento'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  TextField(
                    controller: _pesquisaController,
                    onChanged: (valor) => setState(() => _pesquisa = valor),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar descrição, conta, categoria...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _pesquisa.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _pesquisaController.clear();
                                setState(() => _pesquisa = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FiltroChip(
                          titulo: 'Todos',
                          selecionado: _status == 'Todos',
                          onTap: () {
                            setState(() => _status = 'Todos');
                            _carregar();
                          },
                        ),
                        _FiltroChip(
                          titulo: 'Previstos',
                          selecionado: _status == 'Previsto',
                          onTap: () {
                            setState(() => _status = 'Previsto');
                            _carregar();
                          },
                        ),
                        _FiltroChip(
                          titulo: 'Realizados',
                          selecionado: _status == 'Realizado',
                          onTap: () {
                            setState(() => _status = 'Realizado');
                            _carregar();
                          },
                        ),
                        _FiltroChip(
                          titulo: 'Atrasados',
                          selecionado: _status == 'Atrasado',
                          onTap: () {
                            setState(() => _status = 'Atrasado');
                            _carregar();
                          },
                        ),
                        _FiltroChip(
                          titulo: 'Cancelados',
                          selecionado: _status == 'Cancelado',
                          onTap: () {
                            setState(() => _status = 'Cancelado');
                            _carregar();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Todos', label: Text('Todos')),
                      ButtonSegment(value: 'Entrada', label: Text('Receitas')),
                      ButtonSegment(value: 'Saída', label: Text('Despesas')),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (selecionados) {
                      setState(() => _tipo = selecionados.first);
                      _carregar();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 70),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Colors.white30,
                          ),
                          SizedBox(height: 12),
                          Text('Nenhuma movimentação encontrada.'),
                        ],
                      ),
                    )
                  else
                    ...lista.map((item) {
                      final tipo = _tipoNormalizado(item['tipo']);
                      final valor = _double(item['valor']);
                      final data = _dataMovimento(item);
                      final status = (item['status'] ?? '').toString();
                      final categoria = (item['plano_nome'] ?? 'Sem categoria')
                          .toString();
                      final conta = (item['conta_nome'] ?? 'Sem conta')
                          .toString();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            tipo == 'Entrada'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                          ),
                          title: Text(
                            (item['descricao'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${data == null ? '-' : _data.format(data)} • '
                            '$categoria • $conta • $status',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _moeda.format(valor),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => _detalhes(item),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }

  static int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '');
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({
    required this.titulo,
    required this.selecionado,
    required this.onTap,
  });

  final String titulo;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: FilterChip(
        label: Text(titulo),
        selected: selecionado,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _DetalheLinha extends StatelessWidget {
  const _DetalheLinha(this.titulo, this.valor);

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              titulo,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}

class _EscolherContaDialog extends StatefulWidget {
  const _EscolherContaDialog({required this.contas, this.inicial});

  final List<ContaFinanceira> contas;
  final int? inicial;

  @override
  State<_EscolherContaDialog> createState() => _EscolherContaDialogState();
}

class _EscolherContaDialogState extends State<_EscolherContaDialog> {
  int? _selecionada;

  @override
  void initState() {
    super.initState();
    _selecionada = widget.inicial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Marcar como realizado'),
      content: DropdownButtonFormField<int?>(
        initialValue: _selecionada,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Conta que movimentou'),
        items: widget.contas
            .where((item) => item.id != null && item.ativo)
            .map(
              (item) => DropdownMenuItem<int?>(
                value: item.id,
                child: Text(item.nome),
              ),
            )
            .toList(),
        onChanged: (valor) => setState(() => _selecionada = valor),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _selecionada == null
              ? null
              : () => Navigator.of(context).pop(_selecionada),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
