import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_contas_service.dart';
import 'imperium_web_theme.dart';

class WebContasFinanceirasPage extends StatefulWidget {
  const WebContasFinanceirasPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WebContasFinanceirasPage> createState() =>
      _WebContasFinanceirasPageState();
}

class _WebContasFinanceirasPageState extends State<WebContasFinanceirasPage> {
  final _service = WebCloudContasService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<WebContaFinanceiraResumo> _contas = const [];
  bool _carregando = true;
  bool _mostrarInativas = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final contas = await _service.listarContas();
      if (!mounted) return;
      setState(() => _contas = contas);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirConta(WebContaFinanceiraResumo conta) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebExtratoContaPage(conta: conta),
      ),
    );
    if (mounted) await _carregar();
  }

  Future<void> _abrirFormulario({WebContaFinanceiraResumo? conta}) async {
    final atual = conta?.conta;
    final nome = TextEditingController(text: (atual?['nome'] ?? '').toString());
    final instituicao = TextEditingController(
      text: (atual?['instituicao'] ?? '').toString(),
    );
    final saldo = TextEditingController(
      text: _double(atual?['saldo_inicial'])
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    final observacoes = TextEditingController(
      text: (atual?['observacoes'] ?? '').toString(),
    );
    var tipo = (atual?['tipo'] ?? 'Conta bancária').toString();
    var dataSaldo = DateTime.tryParse(
      (atual?['data_saldo_inicial'] ?? '').toString(),
    );
    var ativa = atual == null || atual['ativo'] != false;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(conta == null ? 'Nova conta' : 'Editar conta'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    autofocus: conta == null,
                    decoration: const InputDecoration(labelText: 'Nome da conta *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: const <String>{
                      'Dinheiro',
                      'Conta bancária',
                      'Carteira digital',
                      'Maquininha',
                      'Outro',
                    }.contains(tipo)
                        ? tipo
                        : 'Outro',
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
                    onChanged: (value) {
                      if (value != null) setLocal(() => tipo = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instituicao,
                    decoration: const InputDecoration(
                      labelText: 'Instituição / banco',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: saldo,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Saldo inicial',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Data do saldo inicial'),
                    subtitle: Text(
                      dataSaldo == null
                          ? 'Não definida'
                          : DateFormat('dd/MM/yyyy').format(dataSaldo!),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (dataSaldo != null)
                          IconButton(
                            tooltip: 'Limpar data',
                            onPressed: () => setLocal(() => dataSaldo = null),
                            icon: const Icon(Icons.clear_rounded),
                          ),
                        IconButton(
                          tooltip: 'Escolher data',
                          onPressed: () async {
                            final hoje = DateTime.now();
                            final escolhida = await showDatePicker(
                              context: context,
                              initialDate: dataSaldo ?? hoje,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(hoje.year + 10, 12, 31),
                            );
                            if (escolhida != null) {
                              setLocal(() => dataSaldo = escolhida);
                            }
                          },
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: observacoes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Observações'),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Conta ativa'),
                    subtitle: const Text(
                      'Contas inativas preservam o histórico, mas não recebem novos ajustes.',
                    ),
                    value: ativa,
                    onChanged: (value) => setLocal(() => ativa = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    try {
      await _service.salvarConta(
        id: atual?['id']?.toString(),
        atualizadoEmEsperado: atual?['atualizado_em']?.toString(),
        nome: nome.text,
        tipo: tipo,
        instituicao: instituicao.text,
        saldoInicial: _numero(saldo.text),
        dataSaldoInicial: dataSaldo,
        observacoes: observacoes.text,
        ativo: ativa,
      );
      await _carregar();
      _mensagem(conta == null ? 'Conta criada e sincronizada.' : 'Conta atualizada.');
    } catch (e) {
      _mensagem(_textoErro(e), erro: true);
    } finally {
      nome.dispose();
      instituicao.dispose();
      saldo.dispose();
      observacoes.dispose();
    }
  }

  Future<void> _alternarConta(WebContaFinanceiraResumo conta) async {
    try {
      await _service.definirAtivo(conta: conta.conta, ativo: !conta.ativa);
      await _carregar();
      _mensagem(conta.ativa ? 'Conta desativada.' : 'Conta reativada.');
    } catch (e) {
      _mensagem(_textoErro(e), erro: true);
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

  double _numero(String valor) {
    var texto = valor.trim().replaceAll(r'R
  Widget build(BuildContext context) {
    final visiveis = _contas
        .where((conta) => _mostrarInativas || conta.ativa)
        .toList();
    final ativas = _contas.where((conta) => conta.ativa).toList();
    final saldoTotal = ativas.fold<double>(
      0,
      (total, conta) => total + conta.saldoAtual,
    );

    final body = _carregando && _contas.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _erro != null && _contas.isEmpty
        ? _ErroFinanceiro(mensagem: _erro!, onTentarNovamente: _carregar)
        : Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                children: [
                  _HeroFinanceiro(
                    saldoTotal: saldoTotal,
                    contasAtivas: ativas.length,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Suas contas',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Saldo calculado com o mesmo snapshot financeiro usado no Android.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _carregando ? null : () => _abrirFormulario(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Nova conta'),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _mostrarInativas,
                        onSelected: (valor) {
                          setState(() => _mostrarInativas = valor);
                        },
                        avatar: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Mostrar inativas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visiveis.isEmpty)
                    const _EstadoVazio(
                      titulo: 'Nenhuma conta financeira',
                      detalhe:
                          'As contas sincronizadas com a empresa aparecerão aqui.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final largura = constraints.maxWidth >= 1180
                            ? (constraints.maxWidth - 24) / 3
                            : constraints.maxWidth >= 720
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final conta in visiveis)
                              SizedBox(
                                width: largura,
                                child: _ContaCard(
                                  conta: conta,
                                  moeda: _moeda,
                                  onTap: () => _abrirConta(conta),
                                  onEditar: () => _abrirFormulario(conta: conta),
                                  onAlternar: () => _alternarConta(conta),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: ImperiumWebTheme.accentStrong.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: ImperiumWebTheme.accentStrong,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Financeiro compartilhado com o aplicativo',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Contas, snapshots, extratos e conciliações usam o mesmo Cloud do aplicativo. Alterações feitas aqui ficam disponíveis no Android no próximo ciclo de sincronização.',
                                  style: TextStyle(color: Color(0xFFAAB3BD)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_carregando)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas e caixa'),
        actions: [
          IconButton(
            tooltip: 'Atualizar saldos',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  static String _textoErro(Object erro) {
    final texto = erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
    return texto.trim().isEmpty
        ? 'Não foi possível carregar as contas.'
        : texto;
  }
}

class WebExtratoContaPage extends StatefulWidget {
  const WebExtratoContaPage({super.key, required this.conta});

  final WebContaFinanceiraResumo conta;

  @override
  State<WebExtratoContaPage> createState() => _WebExtratoContaPageState();
}

enum _FiltroMovimento { todos, entradas, saidas }

class _WebExtratoContaPageState extends State<WebExtratoContaPage> {
  final _service = WebCloudContasService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _mesAno = DateFormat('MMMM yyyy', 'pt_BR');
  final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
  WebComparativoContaResumo? _comparativo;
  _FiltroMovimento _filtro = _FiltroMovimento.todos;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final comparativo = await _service.obterComparativo(
        contaId: widget.conta.id,
        mes: _mes,
      );
      if (!mounted) return;
      setState(() => _comparativo = comparativo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _mudarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conta.nome),
        actions: [
          IconButton(
            tooltip: 'Atualizar extrato',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _carregando && _comparativo == null
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _comparativo == null
          ? _ErroFinanceiro(mensagem: _erro!, onTentarNovamente: _carregar)
          : _conteudo(),
    );
  }

  Widget _conteudo() {
    final comparativo = _comparativo!;
    final atual = comparativo.atual;
    final anterior = comparativo.anterior;
    final movimentos = atual.movimentos
        .where((item) {
          final tipo = (item['tipo'] ?? '').toString().trim().toLowerCase();
          switch (_filtro) {
            case _FiltroMovimento.todos:
              return true;
            case _FiltroMovimento.entradas:
              return tipo == 'entrada';
            case _FiltroMovimento.saidas:
              return tipo == 'saída' || tipo == 'saida';
          }
        })
        .toList()
        .reversed
        .toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            _CabecalhoMes(
              tituloMes: _nomeMes(_mes),
              onAnterior: () => _mudarMes(-1),
              onProximo: () => _mudarMes(1),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniMetrica(
                  titulo: 'Saldo inicial',
                  valor: _moeda.format(atual.saldoInicialMes),
                  icon: Icons.account_balance_outlined,
                ),
                _MiniMetrica(
                  titulo: 'Entradas',
                  valor: _moeda.format(atual.entradas),
                  icon: Icons.south_west_rounded,
                ),
                _MiniMetrica(
                  titulo: 'Saídas',
                  valor: _moeda.format(atual.saidas),
                  icon: Icons.north_east_rounded,
                  alerta: atual.saidas > atual.entradas,
                ),
                _MiniMetrica(
                  titulo: 'Saldo final',
                  valor: _moeda.format(atual.saldoFinalMes),
                  icon: Icons.account_balance_wallet_outlined,
                  alerta: atual.saldoFinalMes < 0,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Mês anterior × mês atual',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              '${_nomeMes(anterior.mes)} comparado com ${_nomeMes(atual.mes)}',
              style: const TextStyle(color: Color(0xFFAAB3BD)),
            ),
            const SizedBox(height: 10),
            _ComparativoCard(atual: atual, anterior: anterior, moeda: _moeda),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Extrato do mês',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                SegmentedButton<_FiltroMovimento>(
                  segments: const [
                    ButtonSegment(
                      value: _FiltroMovimento.todos,
                      label: Text('Todos'),
                    ),
                    ButtonSegment(
                      value: _FiltroMovimento.entradas,
                      label: Text('Entradas'),
                    ),
                    ButtonSegment(
                      value: _FiltroMovimento.saidas,
                      label: Text('Saídas'),
                    ),
                  ],
                  selected: {_filtro},
                  onSelectionChanged: (selecionado) {
                    setState(() => _filtro = selecionado.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (movimentos.isEmpty)
              const _EstadoVazio(
                titulo: 'Sem movimentos neste filtro',
                detalhe: 'Nenhum lançamento realizado foi encontrado no mês.',
              )
            else
              ...movimentos.map(
                (movimento) => _MovimentoCard(
                  movimento: movimento,
                  moeda: _moeda,
                  dataHora: _dataHora,
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Conciliações registradas',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (atual.conciliacoes.isEmpty)
              const _EstadoVazio(
                titulo: 'Sem conciliação no mês',
                detalhe:
                    'Quando houver conferências sincronizadas pelo financeiro, elas aparecerão aqui.',
              )
            else
              ...atual.conciliacoes.map(
                (item) => _ConciliacaoCard(item: item, moeda: _moeda),
              ),
          ],
        ),
        if (_carregando)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  String _nomeMes(DateTime data) {
    final texto = _mesAno.format(data);
    if (texto.isEmpty) return texto;
    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }
}

class _HeroFinanceiro extends StatelessWidget {
  const _HeroFinanceiro({
    required this.saldoTotal,
    required this.contasAtivas,
    required this.moeda,
  });

  final double saldoTotal;
  final int contasAtivas;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ImperiumWebTheme.surfaceRaised,
            ImperiumWebTheme.accentStrong.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ImperiumWebTheme.border),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF302713),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: ImperiumWebTheme.accentStrong,
              ),
            ),
          ),
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo consolidado',
                  style: TextStyle(color: Color(0xFFAAB3BD)),
                ),
                const SizedBox(height: 4),
                Text(
                  moeda.format(saldoTotal),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$contasAtivas conta(s) ativa(s) compartilhadas com o Android',
                  style: const TextStyle(color: Color(0xFFAAB3BD)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContaCard extends StatelessWidget {
  const _ContaCard({
    required this.conta,
    required this.moeda,
    required this.onTap,
    required this.onEditar,
    required this.onAlternar,
  });

  final WebContaFinanceiraResumo conta;
  final NumberFormat moeda;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: ImperiumWebTheme.accentStrong.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_outlined,
                      color: ImperiumWebTheme.accentStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conta.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          [
                            if (conta.instituicao.trim().isNotEmpty)
                              conta.instituicao.trim(),
                            if (conta.tipo.trim().isNotEmpty) conta.tipo.trim(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAB3BD),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!conta.ativa) const Chip(label: Text('Inativa')),
                  PopupMenuButton<String>(
                    tooltip: 'Ações da conta',
                    onSelected: (value) {
                      if (value == 'editar') {
                        onEditar();
                      } else if (value == 'ativo') {
                        onAlternar();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ativo',
                        child: ListTile(
                          leading: Icon(
                            conta.ativa
                                ? Icons.archive_outlined
                                : Icons.restore_rounded,
                          ),
                          title: Text(conta.ativa ? 'Desativar' : 'Reativar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Saldo atual',
                style: TextStyle(color: Color(0xFFAAB3BD), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                moeda.format(conta.saldoAtual),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: conta.saldoAtual < 0 ? Colors.orangeAccent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CabecalhoMes extends StatelessWidget {
  const _CabecalhoMes({
    required this.tituloMes,
    required this.onAnterior,
    required this.onProximo,
  });

  final String tituloMes;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: onAnterior,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                tituloMes,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: onProximo,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetrica extends StatelessWidget {
  const _MiniMetrica({
    required this.titulo,
    required this.valor,
    required this.icon,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : ImperiumWebTheme.accentStrong;
    return SizedBox(
      width: 245,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: cor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFFAAB3BD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparativoCard extends StatelessWidget {
  const _ComparativoCard({
    required this.atual,
    required this.anterior,
    required this.moeda,
  });

  final WebExtratoContaResumo atual;
  final WebExtratoContaResumo anterior;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Indicador')),
            DataColumn(label: Text('Anterior'), numeric: true),
            DataColumn(label: Text('Atual'), numeric: true),
            DataColumn(label: Text('Variação'), numeric: true),
          ],
          rows: [
            _linha('Entradas', anterior.entradas, atual.entradas),
            _linha('Saídas', anterior.saidas, atual.saidas),
            _linha(
              'Movimento líquido',
              anterior.movimentoLiquido,
              atual.movimentoLiquido,
            ),
            _linha('Saldo final', anterior.saldoFinalMes, atual.saldoFinalMes),
          ],
        ),
      ),
    );
  }

  DataRow _linha(String titulo, double valorAnterior, double valorAtual) {
    return DataRow(
      cells: [
        DataCell(Text(titulo)),
        DataCell(Text(moeda.format(valorAnterior))),
        DataCell(Text(moeda.format(valorAtual))),
        DataCell(Text(_variacao(valorAtual, valorAnterior))),
      ],
    );
  }

  String _variacao(double atual, double anterior) {
    if (anterior.abs() < 0.005) {
      if (atual.abs() < 0.005) return '0,0%';
      return atual > 0 ? 'Novo' : '—';
    }
    final percentual = ((atual - anterior) / anterior.abs()) * 100;
    final sinal = percentual > 0 ? '+' : '';
    return '$sinal${percentual.toStringAsFixed(1).replaceAll('.', ',')}%';
  }
}

class _MovimentoCard extends StatelessWidget {
  const _MovimentoCard({
    required this.movimento,
    required this.moeda,
    required this.dataHora,
  });

  final Map<String, dynamic> movimento;
  final NumberFormat moeda;
  final DateFormat dataHora;

  @override
  Widget build(BuildContext context) {
    final tipo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();
    final entrada = tipo == 'entrada';
    final valor = _double(movimento['valor']);
    final data = DateTime.tryParse(
      (movimento['data_pagamento'] ?? movimento['data'] ?? '').toString(),
    );
    final descricao = (movimento['descricao'] ?? '').toString().trim();
    final natureza = (movimento['natureza'] ?? '').toString().trim();
    final forma = (movimento['forma_pagamento'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            entrada ? Icons.south_west_rounded : Icons.north_east_rounded,
          ),
        ),
        title: Text(
          descricao.isEmpty ? 'Movimento financeiro' : descricao,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (data != null) dataHora.format(data),
            if (natureza.isNotEmpty) natureza,
            if (forma.isNotEmpty) forma,
          ].join(' · '),
        ),
        trailing: Text(
          '${entrada ? '+' : '-'} ${moeda.format(valor)}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: entrada ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ),
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ConciliacaoCard extends StatelessWidget {
  const _ConciliacaoCard({required this.item, required this.moeda});

  final Map<String, dynamic> item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] ?? '').toString();
    final diferenca = _double(item['diferenca']);
    final informado = _double(item['saldo_informado']);
    final data = (item['data_conciliacao'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: Text(
          status.isEmpty ? 'Conciliação' : status,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (data.isNotEmpty) data,
            'Saldo informado ${moeda.format(informado)}',
          ].join(' · '),
        ),
        trailing: Text(
          'Dif. ${moeda.format(diferenca)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: diferenca.abs() < 0.005 ? null : Colors.orangeAccent,
          ),
        ),
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ErroFinanceiro extends StatelessWidget {
  const _ErroFinanceiro({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 38,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(mensagem, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onTentarNovamente,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.titulo, required this.detalhe});

  final String titulo;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: Color(0xFF89939E)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detalhe,
                    style: const TextStyle(color: Color(0xFFAAB3BD)),
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
, '').replaceAll(' ', '');
    if (texto.contains(',')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    }
    final numero = double.tryParse(texto);
    if (numero == null) throw ArgumentError('Informe um saldo válido.');
    return numero;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _contas
        .where((conta) => _mostrarInativas || conta.ativa)
        .toList();
    final ativas = _contas.where((conta) => conta.ativa).toList();
    final saldoTotal = ativas.fold<double>(
      0,
      (total, conta) => total + conta.saldoAtual,
    );

    final body = _carregando && _contas.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _erro != null && _contas.isEmpty
        ? _ErroFinanceiro(mensagem: _erro!, onTentarNovamente: _carregar)
        : Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                children: [
                  _HeroFinanceiro(
                    saldoTotal: saldoTotal,
                    contasAtivas: ativas.length,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Suas contas',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Saldo calculado com o mesmo snapshot financeiro usado no Android.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilterChip(
                        selected: _mostrarInativas,
                        onSelected: (valor) {
                          setState(() => _mostrarInativas = valor);
                        },
                        avatar: const Icon(Icons.archive_outlined, size: 18),
                        label: const Text('Mostrar inativas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visiveis.isEmpty)
                    const _EstadoVazio(
                      titulo: 'Nenhuma conta financeira',
                      detalhe:
                          'As contas sincronizadas com a empresa aparecerão aqui.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final largura = constraints.maxWidth >= 1180
                            ? (constraints.maxWidth - 24) / 3
                            : constraints.maxWidth >= 720
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final conta in visiveis)
                              SizedBox(
                                width: largura,
                                child: _ContaCard(
                                  conta: conta,
                                  moeda: _moeda,
                                  onTap: () => _abrirConta(conta),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: ImperiumWebTheme.accentStrong.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: ImperiumWebTheme.accentStrong,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Financeiro compartilhado com o aplicativo',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Esta tela lê as mesmas contas e movimentos protegidos por empresa no Supabase. Edição e conciliação Web serão liberadas somente pelo fluxo sincronizado, sem criar lançamentos paralelos.',
                                  style: TextStyle(color: Color(0xFFAAB3BD)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_carregando)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas e caixa'),
        actions: [
          IconButton(
            tooltip: 'Atualizar saldos',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  static String _textoErro(Object erro) {
    final texto = erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
    return texto.trim().isEmpty
        ? 'Não foi possível carregar as contas.'
        : texto;
  }
}

class WebExtratoContaPage extends StatefulWidget {
  const WebExtratoContaPage({super.key, required this.conta});

  final WebContaFinanceiraResumo conta;

  @override
  State<WebExtratoContaPage> createState() => _WebExtratoContaPageState();
}

enum _FiltroMovimento { todos, entradas, saidas }

class _WebExtratoContaPageState extends State<WebExtratoContaPage> {
  final _service = WebCloudContasService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _mesAno = DateFormat('MMMM yyyy', 'pt_BR');
  final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
  WebComparativoContaResumo? _comparativo;
  _FiltroMovimento _filtro = _FiltroMovimento.todos;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final comparativo = await _service.obterComparativo(
        contaId: widget.conta.id,
        mes: _mes,
      );
      if (!mounted) return;
      setState(() => _comparativo = comparativo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _mudarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conta.nome),
        actions: [
          IconButton(
            tooltip: 'Atualizar extrato',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _carregando && _comparativo == null
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _comparativo == null
          ? _ErroFinanceiro(mensagem: _erro!, onTentarNovamente: _carregar)
          : _conteudo(),
    );
  }

  Widget _conteudo() {
    final comparativo = _comparativo!;
    final atual = comparativo.atual;
    final anterior = comparativo.anterior;
    final movimentos = atual.movimentos
        .where((item) {
          final tipo = (item['tipo'] ?? '').toString().trim().toLowerCase();
          switch (_filtro) {
            case _FiltroMovimento.todos:
              return true;
            case _FiltroMovimento.entradas:
              return tipo == 'entrada';
            case _FiltroMovimento.saidas:
              return tipo == 'saída' || tipo == 'saida';
          }
        })
        .toList()
        .reversed
        .toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            _CabecalhoMes(
              tituloMes: _nomeMes(_mes),
              onAnterior: () => _mudarMes(-1),
              onProximo: () => _mudarMes(1),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniMetrica(
                  titulo: 'Saldo inicial',
                  valor: _moeda.format(atual.saldoInicialMes),
                  icon: Icons.account_balance_outlined,
                ),
                _MiniMetrica(
                  titulo: 'Entradas',
                  valor: _moeda.format(atual.entradas),
                  icon: Icons.south_west_rounded,
                ),
                _MiniMetrica(
                  titulo: 'Saídas',
                  valor: _moeda.format(atual.saidas),
                  icon: Icons.north_east_rounded,
                  alerta: atual.saidas > atual.entradas,
                ),
                _MiniMetrica(
                  titulo: 'Saldo final',
                  valor: _moeda.format(atual.saldoFinalMes),
                  icon: Icons.account_balance_wallet_outlined,
                  alerta: atual.saldoFinalMes < 0,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Mês anterior × mês atual',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              '${_nomeMes(anterior.mes)} comparado com ${_nomeMes(atual.mes)}',
              style: const TextStyle(color: Color(0xFFAAB3BD)),
            ),
            const SizedBox(height: 10),
            _ComparativoCard(atual: atual, anterior: anterior, moeda: _moeda),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Extrato do mês',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                SegmentedButton<_FiltroMovimento>(
                  segments: const [
                    ButtonSegment(
                      value: _FiltroMovimento.todos,
                      label: Text('Todos'),
                    ),
                    ButtonSegment(
                      value: _FiltroMovimento.entradas,
                      label: Text('Entradas'),
                    ),
                    ButtonSegment(
                      value: _FiltroMovimento.saidas,
                      label: Text('Saídas'),
                    ),
                  ],
                  selected: {_filtro},
                  onSelectionChanged: (selecionado) {
                    setState(() => _filtro = selecionado.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (movimentos.isEmpty)
              const _EstadoVazio(
                titulo: 'Sem movimentos neste filtro',
                detalhe: 'Nenhum lançamento realizado foi encontrado no mês.',
              )
            else
              ...movimentos.map(
                (movimento) => _MovimentoCard(
                  movimento: movimento,
                  moeda: _moeda,
                  dataHora: _dataHora,
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Conciliações registradas',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (atual.conciliacoes.isEmpty)
              const _EstadoVazio(
                titulo: 'Sem conciliação no mês',
                detalhe:
                    'Quando houver conferências sincronizadas pelo financeiro, elas aparecerão aqui.',
              )
            else
              ...atual.conciliacoes.map(
                (item) => _ConciliacaoCard(item: item, moeda: _moeda),
              ),
          ],
        ),
        if (_carregando)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  String _nomeMes(DateTime data) {
    final texto = _mesAno.format(data);
    if (texto.isEmpty) return texto;
    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }
}

class _HeroFinanceiro extends StatelessWidget {
  const _HeroFinanceiro({
    required this.saldoTotal,
    required this.contasAtivas,
    required this.moeda,
  });

  final double saldoTotal;
  final int contasAtivas;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ImperiumWebTheme.surfaceRaised,
            ImperiumWebTheme.accentStrong.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ImperiumWebTheme.border),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF302713),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: ImperiumWebTheme.accentStrong,
              ),
            ),
          ),
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo consolidado',
                  style: TextStyle(color: Color(0xFFAAB3BD)),
                ),
                const SizedBox(height: 4),
                Text(
                  moeda.format(saldoTotal),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$contasAtivas conta(s) ativa(s) compartilhadas com o Android',
                  style: const TextStyle(color: Color(0xFFAAB3BD)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContaCard extends StatelessWidget {
  const _ContaCard({
    required this.conta,
    required this.moeda,
    required this.onTap,
  });

  final WebContaFinanceiraResumo conta;
  final NumberFormat moeda;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: ImperiumWebTheme.accentStrong.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_outlined,
                      color: ImperiumWebTheme.accentStrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conta.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          [
                            if (conta.instituicao.trim().isNotEmpty)
                              conta.instituicao.trim(),
                            if (conta.tipo.trim().isNotEmpty) conta.tipo.trim(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAB3BD),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!conta.ativa)
                    const Chip(label: Text('Inativa'))
                  else
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Saldo atual',
                style: TextStyle(color: Color(0xFFAAB3BD), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                moeda.format(conta.saldoAtual),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: conta.saldoAtual < 0 ? Colors.orangeAccent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CabecalhoMes extends StatelessWidget {
  const _CabecalhoMes({
    required this.tituloMes,
    required this.onAnterior,
    required this.onProximo,
  });

  final String tituloMes;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: onAnterior,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                tituloMes,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: onProximo,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetrica extends StatelessWidget {
  const _MiniMetrica({
    required this.titulo,
    required this.valor,
    required this.icon,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : ImperiumWebTheme.accentStrong;
    return SizedBox(
      width: 245,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: cor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFFAAB3BD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparativoCard extends StatelessWidget {
  const _ComparativoCard({
    required this.atual,
    required this.anterior,
    required this.moeda,
  });

  final WebExtratoContaResumo atual;
  final WebExtratoContaResumo anterior;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Indicador')),
            DataColumn(label: Text('Anterior'), numeric: true),
            DataColumn(label: Text('Atual'), numeric: true),
            DataColumn(label: Text('Variação'), numeric: true),
          ],
          rows: [
            _linha('Entradas', anterior.entradas, atual.entradas),
            _linha('Saídas', anterior.saidas, atual.saidas),
            _linha(
              'Movimento líquido',
              anterior.movimentoLiquido,
              atual.movimentoLiquido,
            ),
            _linha('Saldo final', anterior.saldoFinalMes, atual.saldoFinalMes),
          ],
        ),
      ),
    );
  }

  DataRow _linha(String titulo, double valorAnterior, double valorAtual) {
    return DataRow(
      cells: [
        DataCell(Text(titulo)),
        DataCell(Text(moeda.format(valorAnterior))),
        DataCell(Text(moeda.format(valorAtual))),
        DataCell(Text(_variacao(valorAtual, valorAnterior))),
      ],
    );
  }

  String _variacao(double atual, double anterior) {
    if (anterior.abs() < 0.005) {
      if (atual.abs() < 0.005) return '0,0%';
      return atual > 0 ? 'Novo' : '—';
    }
    final percentual = ((atual - anterior) / anterior.abs()) * 100;
    final sinal = percentual > 0 ? '+' : '';
    return '$sinal${percentual.toStringAsFixed(1).replaceAll('.', ',')}%';
  }
}

class _MovimentoCard extends StatelessWidget {
  const _MovimentoCard({
    required this.movimento,
    required this.moeda,
    required this.dataHora,
  });

  final Map<String, dynamic> movimento;
  final NumberFormat moeda;
  final DateFormat dataHora;

  @override
  Widget build(BuildContext context) {
    final tipo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();
    final entrada = tipo == 'entrada';
    final valor = _double(movimento['valor']);
    final data = DateTime.tryParse(
      (movimento['data_pagamento'] ?? movimento['data'] ?? '').toString(),
    );
    final descricao = (movimento['descricao'] ?? '').toString().trim();
    final natureza = (movimento['natureza'] ?? '').toString().trim();
    final forma = (movimento['forma_pagamento'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            entrada ? Icons.south_west_rounded : Icons.north_east_rounded,
          ),
        ),
        title: Text(
          descricao.isEmpty ? 'Movimento financeiro' : descricao,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (data != null) dataHora.format(data),
            if (natureza.isNotEmpty) natureza,
            if (forma.isNotEmpty) forma,
          ].join(' · '),
        ),
        trailing: Text(
          '${entrada ? '+' : '-'} ${moeda.format(valor)}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: entrada ? Colors.greenAccent : Colors.orangeAccent,
          ),
        ),
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ConciliacaoCard extends StatelessWidget {
  const _ConciliacaoCard({required this.item, required this.moeda});

  final Map<String, dynamic> item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] ?? '').toString();
    final diferenca = _double(item['diferenca']);
    final informado = _double(item['saldo_informado']);
    final data = (item['data_conciliacao'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: Text(
          status.isEmpty ? 'Conciliação' : status,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (data.isNotEmpty) data,
            'Saldo informado ${moeda.format(informado)}',
          ].join(' · '),
        ),
        trailing: Text(
          'Dif. ${moeda.format(diferenca)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: diferenca.abs() < 0.005 ? null : Colors.orangeAccent,
          ),
        ),
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ErroFinanceiro extends StatelessWidget {
  const _ErroFinanceiro({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 38,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(mensagem, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onTentarNovamente,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.titulo, required this.detalhe});

  final String titulo;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: Color(0xFF89939E)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detalhe,
                    style: const TextStyle(color: Color(0xFFAAB3BD)),
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
