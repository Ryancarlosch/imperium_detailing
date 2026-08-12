import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import 'extrato_conta_page.dart';
import '../repositories/conta_financeira_repository.dart';

class ContasFinanceirasPage extends StatefulWidget {
  const ContasFinanceirasPage({super.key});

  @override
  State<ContasFinanceirasPage> createState() => _ContasFinanceirasPageState();
}

class _ContasFinanceirasPageState extends State<ContasFinanceirasPage> {
  final ContaFinanceiraRepository _repository = ContaFinanceiraRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  bool _mostrarInativas = false;
  List<ContaFinanceira> _contas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final contas = await _repository.listar(
        incluirInativas: _mostrarInativas,
      );
      if (!mounted) return;
      setState(() {
        _contas = contas;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _abrirExtrato(ContaFinanceira conta) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ExtratoContaPage(conta: conta)));
    if (mounted) {
      await _carregar();
    }
  }

  Future<void> _abrirFormulario({ContaFinanceira? conta}) async {
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ContaFinanceiraForm(repository: _repository, conta: conta),
    );

    if (resultado == true) await _carregar();
  }

  Future<void> _alternar(ContaFinanceira conta) async {
    if (conta.id == null) return;
    try {
      await _repository.alterarAtivo(conta.id!, !conta.ativo);
      await _carregar();
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

  @override
  Widget build(BuildContext context) {
    final total = _contas
        .where((item) => item.ativo)
        .fold<double>(
          0,
          (soma, item) => soma + (item.saldoAtual ?? item.saldoInicial),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas e caixa'),
        actions: [
          IconButton(
            tooltip: _mostrarInativas ? 'Ocultar inativas' : 'Mostrar inativas',
            onPressed: () {
              setState(() => _mostrarInativas = !_mostrarInativas);
              _carregar();
            },
            icon: Icon(
              _mostrarInativas
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova conta'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Color(0xFFD6A84B),
                      ),
                      title: const Text('Saldo total das contas ativas'),
                      subtitle: const Text(
                        'Saldo inicial + movimentações realizadas vinculadas.',
                      ),
                      trailing: Text(
                        _moeda.format(total),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_contas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 50),
                      child: Text(
                        'Nenhuma conta cadastrada.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._contas.map(
                      (conta) => Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          enabled: true,
                          leading: Icon(
                            _iconeTipo(conta.tipo),
                            color: conta.ativo
                                ? const Color(0xFFD6A84B)
                                : Colors.white30,
                          ),
                          title: Text(
                            conta.nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              conta.tipo,
                              if (conta.instituicao.isNotEmpty)
                                conta.instituicao,
                              if (!conta.ativo) 'Inativa',
                            ].join(' • '),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _moeda.format(
                                  conta.saldoAtual ?? conta.saldoInicial,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                onSelected: (valor) {
                                  if (valor == 'editar') {
                                    _abrirFormulario(conta: conta);
                                  } else {
                                    _alternar(conta);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'ativo',
                                    child: Text(
                                      conta.ativo ? 'Desativar' : 'Reativar',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _abrirExtrato(conta),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ContaFinanceiraForm extends StatefulWidget {
  const _ContaFinanceiraForm({required this.repository, this.conta});

  final ContaFinanceiraRepository repository;
  final ContaFinanceira? conta;

  @override
  State<_ContaFinanceiraForm> createState() => _ContaFinanceiraFormState();
}

class _ContaFinanceiraFormState extends State<_ContaFinanceiraForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _instituicao;
  late final TextEditingController _saldo;
  late final TextEditingController _observacoes;

  String _tipo = 'Conta bancária';
  DateTime? _dataSaldo;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final conta = widget.conta;
    _nome = TextEditingController(text: conta?.nome ?? '');
    _instituicao = TextEditingController(text: conta?.instituicao ?? '');
    _saldo = TextEditingController(
      text: conta == null
          ? '0,00'
          : conta.saldoInicial.toStringAsFixed(2).replaceAll('.', ','),
    );
    _observacoes = TextEditingController(text: conta?.observacoes ?? '');
    _tipo = conta?.tipo ?? 'Conta bancária';
    _dataSaldo = DateTime.tryParse(conta?.dataSaldoInicial ?? '');
  }

  @override
  void dispose() {
    _nome.dispose();
    _instituicao.dispose();
    _saldo.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  double? _valorSaldo() {
    var texto = _saldo.text.trim().replaceAll('R\$', '').replaceAll(' ', '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }
    return double.tryParse(texto);
  }

  Future<void> _selecionarData() async {
    final hoje = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _dataSaldo ?? hoje,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoje.year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (data != null && mounted) setState(() => _dataSaldo = data);
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) return;
    final saldo = _valorSaldo();
    if (saldo == null) return;

    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      final anterior = widget.conta;
      final conta = ContaFinanceira(
        id: anterior?.id,
        nome: _nome.text.trim(),
        tipo: _tipo,
        instituicao: _instituicao.text.trim(),
        saldoInicial: saldo,
        dataSaldoInicial: _dataSaldo?.toIso8601String(),
        observacoes: _observacoes.text.trim(),
        ativo: anterior?.ativo ?? true,
        criadoEm: anterior?.criadoEm ?? agora,
        atualizadoEm: agora,
      );

      if (anterior == null) {
        await widget.repository.inserir(conta);
      } else {
        await widget.repository.atualizar(conta);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final dataTexto = _dataSaldo == null
        ? 'Não definida'
        : DateFormat('dd/MM/yyyy').format(_dataSaldo!);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
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
                widget.conta == null ? 'Nova conta' : 'Editar conta',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome da conta'),
                validator: (valor) => (valor?.trim().length ?? 0) < 2
                    ? 'Informe o nome da conta.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(
                    value: 'Conta bancária',
                    child: Text('Conta bancária'),
                  ),
                  DropdownMenuItem(
                    value: 'Carteira digital',
                    child: Text('Carteira digital'),
                  ),
                  DropdownMenuItem(
                    value: 'Maquininha',
                    child: Text('Maquininha'),
                  ),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _tipo = valor ?? _tipo),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _instituicao,
                decoration: const InputDecoration(
                  labelText: 'Instituição / banco (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _saldo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Saldo inicial',
                  prefixText: 'R\$ ',
                ),
                validator: (_) =>
                    _valorSaldo() == null ? 'Informe um valor válido.' : null,
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Data do saldo inicial'),
                subtitle: Text(dataTexto),
                onTap: _salvando ? null : _selecionarData,
              ),
              TextFormField(
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

IconData _iconeTipo(String tipo) {
  switch (tipo) {
    case 'Dinheiro':
      return Icons.payments_outlined;
    case 'Carteira digital':
      return Icons.account_balance_wallet_outlined;
    case 'Maquininha':
      return Icons.point_of_sale_outlined;
    case 'Conta bancária':
      return Icons.account_balance_outlined;
    default:
      return Icons.wallet_outlined;
  }
}
