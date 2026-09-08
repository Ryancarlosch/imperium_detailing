import 'package:flutter/material.dart';

import '../models/movimento_financeiro.dart';
import '../models/nota_fiscal_entrada.dart';
import '../services/nota_fiscal_financeiro_service.dart';

class NotaFiscalFinanceiroPage extends StatefulWidget {
  const NotaFiscalFinanceiroPage({super.key, required this.nota});

  final NotaFiscalEntrada nota;

  @override
  State<NotaFiscalFinanceiroPage> createState() =>
      _NotaFiscalFinanceiroPageState();
}

class _NotaFiscalFinanceiroPageState extends State<NotaFiscalFinanceiroPage> {
  final NotaFiscalFinanceiroService _service = NotaFiscalFinanceiroService();

  NotaFiscalFinanceiroResumo? _resumo;
  List<Map<String, dynamic>> _contas = const [];
  List<Map<String, dynamic>> _categorias = const [];
  int? _contaId;
  int? _planoContaId;
  bool _jaPago = true;
  String _formaPagamento = 'Pix';
  int _parcelas = 1;
  DateTime _dataPagamento = DateTime.now();
  DateTime _primeiroVencimento = DateTime.now().add(const Duration(days: 30));
  bool _carregando = true;
  bool _salvando = false;

  static const _formas = <String>[
    'Pix',
    'Dinheiro',
    'Cartão de crédito',
    'Cartão de débito',
    'Transferência',
    'Boleto',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final resultados = await Future.wait([
        _service.obterResumo(widget.nota.id!),
        _service.listarContasAtivas(),
        _service.listarCategoriasCompra(),
        _service.categoriaPadraoId(widget.nota.id!),
      ]);

      if (!mounted) return;
      final contas = resultados[1] as List<Map<String, dynamic>>;
      final categorias = resultados[2] as List<Map<String, dynamic>>;
      final categoriaPadrao = resultados[3] as int?;

      setState(() {
        _resumo = resultados[0] as NotaFiscalFinanceiroResumo;
        _contas = contas;
        _categorias = categorias;
        _planoContaId ??= categoriaPadrao;
        _contaId ??= contas.length == 1 ? _int(contas.single['id']) : null;
        _carregando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$error', erro: true);
    }
  }

  Future<void> _criarLancamento() async {
    if (_planoContaId == null) {
      _mensagem('Selecione a categoria financeira.', erro: true);
      return;
    }
    if (_jaPago && _contaId == null) {
      _mensagem('Selecione a conta usada no pagamento.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      await _service.criarLancamento(
        notaFiscalId: widget.nota.id!,
        jaPago: _jaPago,
        planoContaId: _planoContaId!,
        contaId: _contaId,
        formaPagamento: _formaPagamento,
        dataPagamento: _jaPago ? _dataPagamento : null,
        totalParcelas: _jaPago ? 1 : _parcelas,
        primeiroVencimento: _jaPago ? null : _primeiroVencimento,
      );
      if (!mounted) return;
      _mensagem(
        _jaPago
            ? 'Pagamento da nota lançado como realizado.'
            : 'Conta a pagar criada sem alterar o saldo atual.',
      );
      await _carregar();
    } catch (error) {
      if (mounted) _mensagem('$error', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _baixarParcela(MovimentoFinanceiro movimento) async {
    int? contaId = _contaId ?? movimento.contaId;
    String forma =
        movimento.formaPagamento.trim().isEmpty ||
            movimento.formaPagamento == 'A definir'
        ? 'Pix'
        : movimento.formaPagamento;
    DateTime data = DateTime.now();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            movimento.totalParcelas > 1
                ? 'Pagar parcela ${movimento.parcelaNumero}/${movimento.totalParcelas}'
                : 'Pagar nota fiscal',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey(contaId),
                  initialValue:
                      _contas.any((item) => _int(item['id']) == contaId)
                      ? contaId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Conta/caixa',
                    border: OutlineInputBorder(),
                  ),
                  items: _contas
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: _int(item['id']),
                          child: Text((item['nome'] ?? '').toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => setLocal(() => contaId = valor),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _formas.contains(forma) ? forma : 'Outro',
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                    border: OutlineInputBorder(),
                  ),
                  items: _formas
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (valor) {
                    if (valor != null) setLocal(() => forma = valor);
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: context,
                      initialDate: data,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (escolhida != null) setLocal(() => data = escolhida);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data do pagamento',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(_data(data)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: contaId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar pagamento'),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true || contaId == null) return;

    try {
      await _service.marcarParcelaComoPaga(
        movimentoId: movimento.id!,
        contaId: contaId!,
        dataPagamento: data,
        formaPagamento: forma,
      );
      if (!mounted) return;
      _contaId = contaId;
      _mensagem('Pagamento registrado. O saldo da conta foi atualizado.');
      await _carregar();
    } catch (error) {
      if (mounted) _mensagem('$error', erro: true);
    }
  }

  Future<void> _cancelarPlanejamento() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar contas previstas?'),
        content: const Text(
          'Use esta opção somente se o lançamento foi criado incorretamente. '
          'Pagamentos já realizados nunca serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar planejamento'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _service.cancelarPlanejamento(widget.nota.id!);
      if (!mounted) return;
      _mensagem('Planejamento cancelado. É possível criar um novo.');
      await _carregar();
    } catch (error) {
      if (mounted) _mensagem('$error', erro: true);
    }
  }

  Future<void> _selecionarDataPagamento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataPagamento,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (data != null && mounted) setState(() => _dataPagamento = data);
  }

  Future<void> _selecionarPrimeiroVencimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _primeiroVencimento,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime(2100),
    );
    if (data != null && mounted) setState(() => _primeiroVencimento = data);
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
    final resumo = _resumo;
    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro da nota')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _cabecalhoNota(),
                  const SizedBox(height: 12),
                  if (resumo != null) _resumoFinanceiro(resumo),
                  const SizedBox(height: 16),
                  if (resumo == null || !resumo.possuiLancamentosAtivos)
                    _formularioNovoLancamento()
                  else
                    _movimentos(resumo),
                ],
              ),
            ),
    );
  }

  Widget _cabecalhoNota() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nota.emitenteNome ?? 'Emitente não informado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('NF ${widget.nota.numero ?? '-'}'),
            Text('Emissão: ${widget.nota.dataEmissao ?? '-'}'),
            Text(
              'Total: ${_moeda(widget.nota.valorTotal ?? 0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumoFinanceiro(NotaFiscalFinanceiroResumo resumo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _linha('Status', resumo.status),
            _linha('Valor da nota', _moeda(resumo.valorTotal)),
            _linha('Pago', _moeda(resumo.valorPago)),
            _linha('A pagar', _moeda(resumo.valorPrevisto)),
          ],
        ),
      ),
    );
  }

  Widget _formularioNovoLancamento() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lançar compra',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Importar a nota não altera o saldo. O saldo só muda quando '
              'um pagamento estiver Realizado.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Já paga'),
                  icon: Icon(Icons.check_circle_outline),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('A prazo'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_jaPago},
              onSelectionChanged: (valor) {
                setState(() {
                  _jaPago = valor.first;
                  if (_jaPago) _parcelas = 1;
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              key: ValueKey(_planoContaId),
              initialValue:
                  _categorias.any((item) => _int(item['id']) == _planoContaId)
                  ? _planoContaId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoria financeira',
                border: OutlineInputBorder(),
              ),
              items: _categorias
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: _int(item['id']),
                      child: Text(
                        '${item['codigo']} · ${item['nome']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (valor) => setState(() => _planoContaId = valor),
            ),
            if (_categoriaSelecionadaCodigo == '9.06') ...[
              const SizedBox(height: 8),
              const Text(
                'Compra para estoque não entra diretamente no DRE. '
                'O custo será reconhecido quando o produto for consumido '
                'nas ordens de serviço pelo FIFO.',
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              key: ValueKey('${_contaId}_${_jaPago ? 'pago' : 'previsto'}'),
              initialValue: _contas.any((item) => _int(item['id']) == _contaId)
                  ? _contaId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _jaPago
                    ? 'Conta/caixa do pagamento'
                    : 'Conta prevista (opcional)',
                border: const OutlineInputBorder(),
              ),
              items: [
                if (!_jaPago)
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Definir quando pagar'),
                  ),
                ..._contas.map(
                  (item) => DropdownMenuItem<int?>(
                    value: _int(item['id']),
                    child: Text((item['nome'] ?? '').toString()),
                  ),
                ),
              ],
              onChanged: (valor) => setState(() => _contaId = valor),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _formaPagamento,
              decoration: InputDecoration(
                labelText: _jaPago ? 'Forma de pagamento' : 'Forma prevista',
                border: const OutlineInputBorder(),
              ),
              items: _formas
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (valor) {
                if (valor != null) {
                  setState(() => _formaPagamento = valor);
                }
              },
            ),
            if (!_jaPago) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _parcelas,
                decoration: const InputDecoration(
                  labelText: 'Parcelas',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  12,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1}x'),
                  ),
                ),
                onChanged: (valor) {
                  if (valor != null) setState(() => _parcelas = valor);
                },
              ),
            ],
            const SizedBox(height: 14),
            InkWell(
              onTap: _jaPago
                  ? _selecionarDataPagamento
                  : _selecionarPrimeiroVencimento,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _jaPago
                      ? 'Data do pagamento'
                      : 'Primeiro vencimento',
                  border: const OutlineInputBorder(),
                ),
                child: Text(
                  _data(_jaPago ? _dataPagamento : _primeiroVencimento),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvando ? null : _criarLancamento,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(
                _salvando
                    ? 'Salvando...'
                    : _jaPago
                    ? 'Registrar pagamento'
                    : 'Criar conta a pagar',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _movimentos(NotaFiscalFinanceiroResumo resumo) {
    final ativos = resumo.movimentos
        .where((item) => item.status != 'Cancelado')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Lançamentos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...ativos.map(
          (movimento) => Card(
            child: ListTile(
              title: Text(
                movimento.totalParcelas > 1
                    ? 'Parcela ${movimento.parcelaNumero}/${movimento.totalParcelas}'
                    : 'Pagamento',
              ),
              subtitle: Text(
                '${movimento.status} · ${movimento.formaPagamento}'
                '${movimento.dataVencimento == null ? '' : '\nVencimento: ${_dataTexto(movimento.dataVencimento)}'}'
                '${movimento.dataPagamento == null ? '' : '\nPago em: ${_dataTexto(movimento.dataPagamento)}'}',
              ),
              trailing: movimento.status == 'Previsto'
                  ? FilledButton.tonal(
                      onPressed: () => _baixarParcela(movimento),
                      child: const Text('Pagar'),
                    )
                  : Text(
                      _moeda(movimento.valor),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
        if (ativos.isNotEmpty &&
            ativos.every((item) => item.status == 'Previsto')) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _cancelarPlanejamento,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar planejamento incorreto'),
          ),
        ],
      ],
    );
  }

  String? get _categoriaSelecionadaCodigo {
    for (final item in _categorias) {
      if (_int(item['id']) == _planoContaId) {
        return (item['codigo'] ?? '').toString();
      }
    }
    return null;
  }

  Widget _linha(String nome, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(nome)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _moeda(double valor) =>
      'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

  static String _data(DateTime valor) =>
      '${valor.day.toString().padLeft(2, '0')}/'
      '${valor.month.toString().padLeft(2, '0')}/${valor.year}';

  static String _dataTexto(String? valor) {
    final data = DateTime.tryParse(valor ?? '');
    return data == null ? '-' : _data(data);
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
