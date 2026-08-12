import 'package:flutter/material.dart';

import '../models/conta_financeira.dart';
import '../models/regra_taxa_cartao.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/regra_taxa_repository.dart';

class RegrasTaxaPage extends StatefulWidget {
  const RegrasTaxaPage({super.key});

  @override
  State<RegrasTaxaPage> createState() => _RegrasTaxaPageState();
}

class _RegrasTaxaPageState extends State<RegrasTaxaPage> {
  final RegraTaxaRepository _repository = RegraTaxaRepository();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();

  bool _carregando = true;
  List<RegraTaxaCartao> _regras = const [];
  List<ContaFinanceira> _contas = const [];

  List<ContaFinanceira> get _maquininhas {
    return _contas.where((conta) => conta.tipo == 'Maquininha').toList();
  }

  List<ContaFinanceira> get _maquininhasAtivas {
    return _maquininhas.where((conta) => conta.ativo).toList();
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.listar(incluirInativas: true),
        _contasRepository.listar(incluirInativas: true),
      ]);

      if (!mounted) return;

      setState(() {
        _regras = List<RegraTaxaCartao>.from(
          resultados[0] as List<dynamic>,
        );
        _contas = List<ContaFinanceira>.from(
          resultados[1] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem(
        'Não foi possível carregar as regras.\n$erro',
        erro: true,
      );
    }
  }

  List<_GrupoRegra> get _grupos {
    final mapa = <String, List<RegraTaxaCartao>>{};

    for (final regra in _regras) {
      final chave = [
        regra.nome.trim().toLowerCase(),
        regra.formaPagamento,
        regra.contaId?.toString() ?? 'null',
      ].join('|');

      mapa.putIfAbsent(chave, () => <RegraTaxaCartao>[]).add(regra);
    }

    final grupos = mapa.values
        .map((itens) {
          itens.sort((a, b) => a.parcelas.compareTo(b.parcelas));
          return _GrupoRegra(itens);
        })
        .toList();

    grupos.sort((a, b) {
      if (a.ativo != b.ativo) {
        return a.ativo ? -1 : 1;
      }
      final porConta = a.contaNome(_contas).compareTo(
        b.contaNome(_contas),
      );
      if (porConta != 0) return porConta;
      final porNome = a.nome.toLowerCase().compareTo(
        b.nome.toLowerCase(),
      );
      if (porNome != 0) return porNome;
      return a.formaPagamento.compareTo(b.formaPagamento);
    });

    return grupos;
  }

  Future<void> _abrirEditor([_GrupoRegra? grupo]) async {
    if (_maquininhasAtivas.isEmpty && grupo == null) {
      _mensagem(
        'Cadastre primeiro uma conta ativa do tipo Maquininha em '
        'Financeiro > Contas e caixa.',
        erro: true,
      );
      return;
    }

    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorRegraSheet(
        repository: _repository,
        grupo: grupo,
        contas: _maquininhas,
      ),
    );

    if (salvo == true) {
      await _carregar();
      _mensagem(grupo == null ? 'Regra criada.' : 'Regra atualizada.');
    }
  }

  Future<void> _alternar(_GrupoRegra grupo) async {
    try {
      final novoAtivo = !grupo.ativo;
      final agora = DateTime.now().toIso8601String();

      for (final regra in grupo.itens) {
        await _repository.salvar(
          RegraTaxaCartao(
            id: regra.id,
            nome: regra.nome,
            formaPagamento: regra.formaPagamento,
            parcelas: regra.parcelas,
            contaId: regra.contaId,
            taxaPercentual: regra.taxaPercentual,
            taxaFixa: regra.taxaFixa,
            prazoRecebimentoDias: regra.prazoRecebimentoDias,
            prioridade: regra.prioridade,
            repassarCliente: regra.repassarCliente,
            observacoes: regra.observacoes,
            ativo: novoAtivo,
            criadoEm: regra.criadoEm,
            atualizadoEm: agora,
          ),
        );
      }

      await _carregar();
      _mensagem(novoAtivo ? 'Regra ativada.' : 'Regra desativada.');
    } catch (erro) {
      _mensagem('Não foi possível alterar a regra.\n$erro', erro: true);
    }
  }

  Future<void> _arquivar(_GrupoRegra grupo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arquivar regra'),
        content: Text(
          'Arquivar "${grupo.nome}"? Ela deixará de ser usada nos novos '
          'pagamentos, mas o histórico dos pagamentos antigos será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      for (final regra in grupo.itens) {
        if (regra.id != null) {
          await _repository.arquivar(regra.id!);
        }
      }
      await _carregar();
      _mensagem('Regra arquivada.');
    } catch (erro) {
      _mensagem('Não foi possível arquivar a regra.\n$erro', erro: true);
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
    final grupos = _grupos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regras de maquininha'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _carregando ? null : () => _abrirEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova regra'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : grupos.isEmpty
              ? _EstadoVazio(onCriar: () => _abrirEditor())
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      const _AvisoRegras(),
                      const SizedBox(height: 12),
                      ...grupos.map(
                        (grupo) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CardRegra(
                            grupo: grupo,
                            contas: _contas,
                            onEditar: () => _abrirEditor(grupo),
                            onAlternar: () => _alternar(grupo),
                            onArquivar: () => _arquivar(grupo),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _AvisoRegras extends StatelessWidget {
  const _AvisoRegras();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFD6A84B),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cada regra fica vinculada a uma conta do tipo Maquininha. '
                'No recebimento por cartão, o sistema identifica automaticamente '
                'a taxa pela forma e pela quantidade de parcelas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardRegra extends StatelessWidget {
  const _CardRegra({
    required this.grupo,
    required this.contas,
    required this.onEditar,
    required this.onAlternar,
    required this.onArquivar,
  });

  final _GrupoRegra grupo;
  final List<ContaFinanceira> contas;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onArquivar;

  @override
  Widget build(BuildContext context) {
    final limite = grupo.credito ? 12 : 1;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFFD6A84B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            grupo.nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (!grupo.ativo)
                          const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Inativa'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${grupo.formaPagamento} • ${grupo.contaNome(contas)}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (grupo.repassarCliente) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Taxa repassada ao cliente',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var parcela = 1; parcela <= limite; parcela++)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              '${parcela}x ${_percentual(grupo.taxa(parcela))}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (valor) {
                  if (valor == 'alternar') {
                    onAlternar();
                  } else if (valor == 'arquivar') {
                    onArquivar();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'alternar',
                    child: Text(grupo.ativo ? 'Desativar' : 'Ativar'),
                  ),
                  const PopupMenuItem(
                    value: 'arquivar',
                    child: Text('Arquivar'),
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

class _EditorRegraSheet extends StatefulWidget {
  const _EditorRegraSheet({
    required this.repository,
    required this.grupo,
    required this.contas,
  });

  final RegraTaxaRepository repository;
  final _GrupoRegra? grupo;
  final List<ContaFinanceira> contas;

  @override
  State<_EditorRegraSheet> createState() => _EditorRegraSheetState();
}

class _EditorRegraSheetState extends State<_EditorRegraSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  final Map<int, TextEditingController> _taxas = {};

  late String _forma;
  int? _contaId;
  bool _repassar = false;
  bool _ativo = true;
  bool _salvando = false;

  bool get _credito => _forma == 'Cartão de crédito';

  List<ContaFinanceira> get _contasDisponiveis {
    final atualId = widget.grupo?.contaId;
    return widget.contas
        .where(
          (conta) =>
              conta.id != null &&
              (conta.ativo || conta.id == atualId),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();

    final grupo = widget.grupo;
    _nome = TextEditingController(text: grupo?.nome ?? '');
    _forma = grupo?.formaPagamento ?? 'Cartão de crédito';
    _contaId = grupo?.contaId;
    _repassar = grupo?.repassarCliente ?? false;
    _ativo = grupo?.ativo ?? true;

    final ativas = widget.contas
        .where((conta) => conta.ativo && conta.id != null)
        .toList();

    if (_contaId == null && ativas.length == 1) {
      _contaId = ativas.single.id;
    }

    for (var parcela = 1; parcela <= 12; parcela++) {
      final valor = grupo?.taxaNula(parcela);
      _taxas[parcela] = TextEditingController(
        text: valor == null ? '' : _campoPercentual(valor),
      );
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    for (final controller in _taxas.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final contaId = _contaId;
    if (contaId == null) return;

    final conta = widget.contas.where((item) => item.id == contaId).firstOrNull;
    if (conta == null || conta.tipo != 'Maquininha') {
      _mensagem('Selecione uma conta do tipo Maquininha.');
      return;
    }

    if (_ativo && !conta.ativo) {
      _mensagem('A conta selecionada está inativa.');
      return;
    }

    final limite = _credito ? 12 : 1;
    final agora = DateTime.now().toIso8601String();
    final anteriores = <int, RegraTaxaCartao>{
      for (final item in widget.grupo?.itens ?? const <RegraTaxaCartao>[])
        item.parcelas: item,
    };

    setState(() => _salvando = true);

    try {
      for (var parcela = 1; parcela <= limite; parcela++) {
        final taxa = _lerPercentual(_taxas[parcela]!.text);
        if (taxa == null) {
          throw ArgumentError('Informe a taxa de ${parcela}x.');
        }

        final anterior = anteriores[parcela];

        await widget.repository.salvar(
          RegraTaxaCartao(
            id: anterior?.id,
            nome: _nome.text.trim(),
            formaPagamento: _forma,
            parcelas: parcela,
            contaId: contaId,
            taxaPercentual: taxa,
            taxaFixa: anterior?.taxaFixa ?? 0,
            prazoRecebimentoDias:
                anterior?.prazoRecebimentoDias ?? 0,
            prioridade: anterior?.prioridade ?? 0,
            repassarCliente: _repassar,
            observacoes: anterior?.observacoes ?? '',
            ativo: _ativo,
            criadoEm: anterior?.criadoEm.isNotEmpty == true
                ? anterior!.criadoEm
                : agora,
            atualizadoEm: agora,
          ),
        );
      }

      for (final anterior in anteriores.values) {
        if (anterior.parcelas > limite && anterior.id != null) {
          await widget.repository.arquivar(anterior.id!);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mensagem('Não foi possível salvar.\n$erro');
    }
  }

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final limite = _credito ? 12 : 1;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
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
                widget.grupo == null ? 'Nova regra' : 'Editar regra',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Crédito usa taxas de 1x a 12x. Débito usa apenas 1x.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nome,
                enabled: !_salvando,
                decoration: const InputDecoration(
                  labelText: 'Nome da regra',
                  hintText: 'Ex.: Stone Visa/Mastercard',
                ),
                validator: (valor) =>
                    (valor ?? '').trim().length < 2
                        ? 'Informe o nome da regra.'
                        : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _forma,
                decoration: const InputDecoration(labelText: 'Forma'),
                items: const [
                  DropdownMenuItem(
                    value: 'Cartão de crédito',
                    child: Text('Crédito'),
                  ),
                  DropdownMenuItem(
                    value: 'Cartão de débito',
                    child: Text('Débito'),
                  ),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor == null) return;
                        setState(() => _forma = valor);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _contaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta da maquininha',
                  helperText:
                      'Somente contas cadastradas como tipo Maquininha aparecem aqui.',
                ),
                items: _contasDisponiveis
                    .map(
                      (conta) => DropdownMenuItem<int>(
                        value: conta.id,
                        child: Text(
                          conta.ativo
                              ? conta.nome
                              : '${conta.nome} (inativa)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _contaId = valor),
                validator: (valor) =>
                    valor == null ? 'Selecione a maquininha.' : null,
              ),
              const SizedBox(height: 18),
              Text(
                _credito ? 'Taxas por parcela' : 'Taxa do débito',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final colunas = constraints.maxWidth >= 520 ? 3 : 2;
                  final largura =
                      (constraints.maxWidth - ((colunas - 1) * 10)) /
                          colunas;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var parcela = 1; parcela <= limite; parcela++)
                        SizedBox(
                          width: largura,
                          child: TextFormField(
                            controller: _taxas[parcela],
                            enabled: !_salvando,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: '${parcela}x',
                              suffixText: '%',
                            ),
                            validator: (valor) {
                              final taxa = _lerPercentual(valor ?? '');
                              if (taxa == null || taxa < 0 || taxa >= 100) {
                                return '0 a 99,99';
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _repassar,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _repassar = valor),
                title: const Text('Repassar taxa ao cliente'),
                subtitle: const Text(
                  'Desligado: a empresa absorve a taxa. '
                  'Ligado: o sistema acrescenta o valor necessário.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _ativo = valor),
                title: const Text('Regra ativa'),
              ),
              const SizedBox(height: 14),
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
                        _salvando ? 'Salvando...' : 'Salvar regra',
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

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onCriar});

  final VoidCallback onCriar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.credit_card_off_outlined,
              size: 72,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma regra cadastrada',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cadastre uma conta do tipo Maquininha e depois informe '
              'as taxas de débito ou crédito.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCriar,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar primeira regra'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrupoRegra {
  _GrupoRegra(this.itens);

  final List<RegraTaxaCartao> itens;

  RegraTaxaCartao get principal => itens.first;
  String get nome => principal.nome;
  String get formaPagamento => principal.formaPagamento;
  int? get contaId => principal.contaId;
  bool get credito => formaPagamento == 'Cartão de crédito';
  bool get ativo => itens.any((item) => item.ativo);
  bool get repassarCliente =>
      itens.any((item) => item.repassarCliente);

  double? taxaNula(int parcela) {
    for (final regra in itens) {
      if (regra.parcelas == parcela) {
        return regra.taxaPercentual;
      }
    }
    return null;
  }

  double taxa(int parcela) => taxaNula(parcela) ?? 0;

  String contaNome(List<ContaFinanceira> contas) {
    for (final conta in contas) {
      if (conta.id == contaId) {
        return conta.ativo ? conta.nome : '${conta.nome} (inativa)';
      }
    }
    return 'Conta não encontrada';
  }
}

double? _lerPercentual(String texto) {
  final limpo = texto
      .trim()
      .replaceAll('%', '')
      .replaceAll(' ', '');

  if (limpo.isEmpty) return null;

  if (limpo.contains(',') && limpo.contains('.')) {
    return double.tryParse(
      limpo.replaceAll('.', '').replaceAll(',', '.'),
    );
  }

  return double.tryParse(limpo.replaceAll(',', '.'));
}

String _campoPercentual(double valor) {
  return valor
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

String _percentual(double valor) => '${_campoPercentual(valor)}%';
