import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../models/fornecedor.dart';
import '../models/movimento_financeiro.dart';
import '../models/plano_conta_financeiro.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../repositories/fornecedor_repository.dart';
import '../repositories/plano_contas_repository.dart';

// financeiro-lancamento-unificado-v1
class LancamentoFinanceiroPage extends StatefulWidget {
  const LancamentoFinanceiroPage({
    super.key,
    this.tipoInicial = 'Entrada',
    this.movimento,
  });

  final String tipoInicial;
  final MovimentoFinanceiro? movimento;

  @override
  State<LancamentoFinanceiroPage> createState() =>
      _LancamentoFinanceiroPageState();
}

class _LancamentoFinanceiroPageState extends State<LancamentoFinanceiroPage> {
  final _formKey = GlobalKey<FormState>();
  final FinanceiroRepository _repository = FinanceiroRepository();
  final PlanoContasRepository _planoRepository = PlanoContasRepository();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
  final FornecedorRepository _fornecedorRepository = FornecedorRepository();

  late final TextEditingController _descricao;
  late final TextEditingController _valor;
  late final TextEditingController _documento;
  late final TextEditingController _observacoes;

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  List<PlanoContaFinanceiro> _plano = const [];
  List<ContaFinanceira> _contas = const [];
  List<Fornecedor> _fornecedores = const [];
  List<Map<String, dynamic>> _clientes = const [];

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

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final movimento = widget.movimento;

    _descricao = TextEditingController(text: movimento?.descricao ?? '');
    _valor = TextEditingController(
      text: movimento == null
          ? ''
          : movimento.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    _documento = TextEditingController(text: movimento?.numeroDocumento ?? '');
    _observacoes = TextEditingController(text: movimento?.observacoes ?? '');

    _tipo = _normalizarTipo(movimento?.tipo ?? widget.tipoInicial);
    _status = movimento?.status == 'Previsto' ? 'Previsto' : 'Realizado';
    _formaPagamento = movimento?.formaPagamento.trim().isNotEmpty == true
        ? movimento!.formaPagamento
        : 'Pix';
    _planoContaId = movimento?.planoContaId;
    _contaId = movimento?.contaId;
    _clienteId = movimento?.clienteId;
    _fornecedorId = movimento?.fornecedorId;
    _competencia =
        DateTime.tryParse(
          movimento?.dataCompetencia ?? movimento?.data ?? '',
        ) ??
        DateTime.now();
    _vencimento = DateTime.tryParse(movimento?.dataVencimento ?? '');
    _pagamento = _status == 'Realizado'
        ? DateTime.tryParse(
                movimento?.dataPagamento ?? movimento?.data ?? '',
              ) ??
              DateTime.now()
        : null;

    _carregar();
  }

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    _documento.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait<dynamic>([
        _planoRepository.listar(incluirInativos: false),
        _contasRepository.listar(),
        _fornecedorRepository.listar(),
        _repository.listarClientesAtivos(),
      ]);

      if (!mounted) return;

      setState(() {
        _plano = List<PlanoContaFinanceiro>.from(
          resultados[0] as List<dynamic>,
        );
        _contas = List<ContaFinanceira>.from(resultados[1] as List<dynamic>);
        _fornecedores = List<Fornecedor>.from(resultados[2] as List<dynamic>);
        _clientes = List<Map<String, dynamic>>.from(
          resultados[3] as List<dynamic>,
        );

        if (_contaId == null) {
          final ativas = _contas
              .where((item) => item.ativo && item.id != null)
              .toList();
          if (ativas.length == 1) {
            _contaId = ativas.single.id;
          }
        }

        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar os cadastros.\n$erro', erro: true);
    }
  }

  String _normalizarTipo(String valor) {
    final tipo = valor.trim().toLowerCase();
    return tipo == 'saída' || tipo == 'saida' ? 'Saída' : 'Entrada';
  }

  List<PlanoContaFinanceiro> get _categorias {
    final pais = _plano.map((item) => item.parentId).whereType<int>().toSet();
    return _plano.where((item) {
      if (!item.ativo || item.id == null || pais.contains(item.id)) {
        return false;
      }
      return item.tipo == _tipo || item.tipo == 'Neutro';
    }).toList();
  }

  PlanoContaFinanceiro? _categoriaCodigo(String codigo) {
    for (final item in _plano) {
      if (item.codigo == codigo && item.ativo) return item;
    }
    return null;
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

  Future<DateTime?> _selecionarData(DateTime? atual) {
    final hoje = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: atual ?? hoje,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoje.year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
  }

  Future<void> _alterarData(
    DateTime? atual,
    void Function(DateTime data) aplicar,
  ) async {
    final escolhida = await _selecionarData(atual);
    if (escolhida == null || !mounted) return;
    setState(() => aplicar(escolhida));
  }

  void _selecionarGastoPessoal() {
    final categoria = _categoriaCodigo('2.01.02');
    if (categoria?.id == null) {
      _mensagem(
        'A categoria de gastos pessoais do proprietário não está disponível.',
        erro: true,
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

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) return;

    final valor = _lerValor();
    if (valor == null || valor <= 0) {
      _mensagem('Informe um valor maior que zero.', erro: true);
      return;
    }

    if (_planoContaId == null) {
      _mensagem('Selecione uma categoria financeira.', erro: true);
      return;
    }

    if (_status == 'Realizado' && _contaId == null) {
      _mensagem(
        'Selecione a conta onde o dinheiro entrou ou saiu.',
        erro: true,
      );
      return;
    }

    if (_status == 'Previsto' && _vencimento == null) {
      _mensagem('Informe o vencimento.', erro: true);
      return;
    }

    setState(() => _salvando = true);

    try {
      final anterior = widget.movimento;
      final pagamento = _status == 'Realizado'
          ? (_pagamento ?? DateTime.now())
          : null;
      final dataBase = pagamento ?? _vencimento ?? _competencia;

      final movimento = MovimentoFinanceiro(
        id: anterior?.id,
        tipo: _tipo,
        descricao: _descricao.text.trim(),
        valor: valor,
        formaPagamento: _status == 'Realizado' ? _formaPagamento : '',
        data: dataBase.toIso8601String(),
        clienteId: _tipo == 'Entrada' ? _clienteId : null,
        agendamentoId: anterior?.agendamentoId,
        ordemServicoId: anterior?.ordemServicoId,
        pagamentoId: anterior?.pagamentoId,
        planoContaId: _planoContaId,
        contaId: _status == 'Realizado' ? _contaId : anterior?.contaId,
        fornecedorId: _tipo == 'Saída' ? _fornecedorId : null,
        transferenciaId: anterior?.transferenciaId,
        natureza: anterior?.natureza ?? 'Não classificado',
        origem: anterior?.origem ?? 'Manual',
        status: _status,
        dataCompetencia: _competencia.toIso8601String(),
        dataVencimento: _status == 'Previsto'
            ? _vencimento?.toIso8601String()
            : anterior?.dataVencimento,
        dataPagamento: pagamento?.toIso8601String(),
        numeroDocumento: _documento.text.trim(),
        observacoes: _observacoes.text.trim(),
        impactaDre: anterior?.impactaDre ?? true,
      );

      if (anterior == null) {
        await _repository.inserirMovimento(movimento);
      } else {
        await _repository.atualizarMovimento(movimento);
      }

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

  String get _rotuloRealizado {
    return _tipo == 'Entrada' ? 'Recebido agora' : 'Pago agora';
  }

  String get _rotuloPrevisto {
    return _tipo == 'Entrada' ? 'Receber depois' : 'Pagar depois';
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _categorias;

    if (_planoContaId != null &&
        !categorias.any((item) => item.id == _planoContaId)) {
      _planoContaId = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.movimento == null ? 'Novo lançamento' : 'Editar lançamento',
        ),
        actions: [
          TextButton(
            onPressed: _salvando || _carregando ? null : _salvar,
            child: Text(_salvando ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // financeiro-lancamento-modo-v1
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Entrada',
                        icon: Icon(Icons.south_west_rounded),
                        label: Text('Receita'),
                      ),
                      ButtonSegment(
                        value: 'Saída',
                        icon: Icon(Icons.north_east_rounded),
                        label: Text('Despesa'),
                      ),
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
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'Realizado',
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(_rotuloRealizado),
                      ),
                      ButtonSegment(
                        value: 'Previsto',
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text(_rotuloPrevisto),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: _salvando
                        ? null
                        : (selecionados) {
                            setState(() {
                              _status = selecionados.first;
                              if (_status == 'Realizado') {
                                _pagamento ??= DateTime.now();
                              } else {
                                _vencimento ??= DateTime.now();
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _descricao,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Ex.: Aluguel, material, venda avulsa',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                    validator: (valor) {
                      if ((valor ?? '').trim().length < 3) {
                        return 'Informe uma descrição com pelo menos 3 caracteres.';
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
                  DropdownButtonFormField<int?>(
                    initialValue: _planoContaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: categorias
                        .map(
                          (item) => DropdownMenuItem<int?>(
                            value: item.id,
                            child: Text(
                              '${item.codigo} • ${item.nome}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _salvando
                        ? null
                        : (valor) => setState(() => _planoContaId = valor),
                    validator: (valor) =>
                        valor == null ? 'Selecione a categoria.' : null,
                  ),
                  if (_categoriaCodigo('2.01.02') != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _salvando ? null : _selecionarGastoPessoal,
                        icon: const Icon(Icons.person_outline_rounded),
                        label: const Text('Gasto pessoal do proprietário'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_status == 'Realizado') ...[
                    DropdownButtonFormField<int?>(
                      initialValue: _contaId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _tipo == 'Entrada'
                            ? 'Conta de recebimento'
                            : 'Conta de pagamento',
                        helperText: 'Onde o dinheiro realmente movimentou',
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      items: _contas
                          .where(
                            (item) =>
                                item.id != null &&
                                (item.ativo || item.id == _contaId),
                          )
                          .map(
                            (item) => DropdownMenuItem<int?>(
                              value: item.id,
                              child: Text(
                                item.ativo
                                    ? item.nome
                                    : '${item.nome} (inativa)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _salvando
                          ? null
                          : (valor) => setState(() => _contaId = valor),
                      validator: (valor) => valor == null
                          ? 'Selecione a conta financeira.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _formaPagamento,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                        prefixIcon: Icon(Icons.wallet_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                        DropdownMenuItem(
                          value: 'Dinheiro',
                          child: Text('Dinheiro'),
                        ),
                        DropdownMenuItem(
                          value: 'Cartão de débito',
                          child: Text('Cartão de débito'),
                        ),
                        DropdownMenuItem(
                          value: 'Cartão de crédito',
                          child: Text('Cartão de crédito'),
                        ),
                        DropdownMenuItem(
                          value: 'Transferência',
                          child: Text('Transferência'),
                        ),
                        DropdownMenuItem(
                          value: 'Boleto',
                          child: Text('Boleto'),
                        ),
                        DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                      ],
                      onChanged: _salvando
                          ? null
                          : (valor) {
                              if (valor != null) {
                                setState(() => _formaPagamento = valor);
                              }
                            },
                    ),
                    const SizedBox(height: 14),
                    _BotaoData(
                      titulo: _tipo == 'Entrada'
                          ? 'Data do recebimento'
                          : 'Data do pagamento',
                      data: _pagamento ?? DateTime.now(),
                      onPressed: _salvando
                          ? null
                          : () => _alterarData(
                              _pagamento,
                              (data) => _pagamento = data,
                            ),
                    ),
                  ] else ...[
                    _BotaoData(
                      titulo: 'Vencimento',
                      data: _vencimento ?? DateTime.now(),
                      onPressed: _salvando
                          ? null
                          : () => _alterarData(
                              _vencimento,
                              (data) => _vencimento = data,
                            ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // financeiro-lancamento-detalhes-v1
                  Card(
                    margin: EdgeInsets.zero,
                    child: ExpansionTile(
                      title: const Text('Mais detalhes'),
                      subtitle: const Text(
                        'Competência, cliente/fornecedor, documento e observações',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _BotaoData(
                          titulo: 'Competência',
                          data: _competencia,
                          onPressed: _salvando
                              ? null
                              : () => _alterarData(
                                  _competencia,
                                  (data) => _competencia = data,
                                ),
                        ),
                        const SizedBox(height: 14),
                        if (_tipo == 'Entrada')
                          DropdownButtonFormField<int?>(
                            initialValue: _clienteId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cliente (opcional)',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Sem cliente vinculado'),
                              ),
                              ..._clientes.map((cliente) {
                                final id = _int(cliente['id']);
                                final nome = (cliente['nome'] ?? '')
                                    .toString()
                                    .trim();
                                final telefone = (cliente['telefone'] ?? '')
                                    .toString()
                                    .trim();
                                return DropdownMenuItem<int?>(
                                  value: id,
                                  child: Text(
                                    telefone.isEmpty
                                        ? nome
                                        : '$nome • $telefone',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) => setState(() => _clienteId = valor),
                          )
                        else
                          DropdownButtonFormField<int?>(
                            initialValue: _fornecedorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Fornecedor (opcional)',
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Sem fornecedor vinculado'),
                              ),
                              ..._fornecedores.map(
                                (item) => DropdownMenuItem<int?>(
                                  value: item.id,
                                  child: Text(
                                    item.nome,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) =>
                                      setState(() => _fornecedorId = valor),
                          ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _documento,
                          decoration: const InputDecoration(
                            labelText: 'Número do documento (opcional)',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _observacoes,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                            alignLabelWithHint: true,
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _salvando ? 'Salvando...' : 'Salvar lançamento',
                    ),
                  ),
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
}

class _BotaoData extends StatelessWidget {
  const _BotaoData({
    required this.titulo,
    required this.data,
    required this.onPressed,
  });

  final String titulo;
  final DateTime data;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy');

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_today_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text('$titulo: ${formato.format(data)}'),
        ),
      ),
    );
  }
}
