import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/ponto_repository.dart';
import 'funcionarios_resumo_page.dart';
import 'mao_obra_custos_page.dart';
import 'pagamentos_funcionarios_page.dart';
import 'ponto_funcionarios_page.dart';
import 'usuarios_permissoes_page.dart';

class FuncionariosCentralPage extends StatefulWidget {
  const FuncionariosCentralPage({super.key});

  @override
  State<FuncionariosCentralPage> createState() =>
      _FuncionariosCentralPageState();
}

class _FuncionariosCentralPageState extends State<FuncionariosCentralPage> {
  final CustosRepository _custosRepository = CustosRepository();
  final PontoRepository _pontoRepository = PontoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool _carregando = true;
  List<ColaboradorCusto> _colaboradores = const [];
  Map<int, Map<String, dynamic>> _fechamentos = const {};
  List<Map<String, dynamic>> _pagamentosMes = const [];

  DateTime get _inicioMes => DateTime(_mes.year, _mes.month, 1);
  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  String _tituloMes() {
    final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return texto.substring(0, 1).toUpperCase() + texto.substring(1);
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final colaboradores = await _custosRepository.listarColaboradores(
        incluirInativos: true,
      );
      final pagamentos = await _custosRepository.listarPagamentosColaboradores(
        inicio: _inicioMes,
        fim: _fimMes,
      );
      final fechamentos = <int, Map<String, dynamic>>{};

      for (final colaborador in colaboradores) {
        final id = colaborador.id;
        if (id == null) {
          continue;
        }
        final ativoNoPeriodo = await _custosRepository
            .colaboradorAtivoNoPeriodo(
              colaboradorId: id,
              inicio: _inicioMes,
              fim: _fimMes,
            );
        if (!ativoNoPeriodo) {
          continue;
        }
        fechamentos[id] = await _pontoRepository.obterFechamentoMes(
          colaboradorId: id,
          inicio: _inicioMes,
          fim: _fimMes,
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _colaboradores = colaboradores;
        _fechamentos = fechamentos;
        _pagamentosMes = List<Map<String, dynamic>>.from(pagamentos);
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      _mensagem(
        'Não foi possível carregar os funcionários.\n$erro',
        erro: true,
      );
    }
  }

  void _mesAnterior() {
    setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
    _carregar();
  }

  void _mesSeguinte() {
    final atual = DateTime(DateTime.now().year, DateTime.now().month);
    final proximo = DateTime(_mes.year, _mes.month + 1);
    if (proximo.isAfter(atual)) {
      return;
    }
    setState(() => _mes = proximo);
    _carregar();
  }

  Map<String, double> get _totaisFolha {
    var estimado = 0.0;
    var falta = 0.0;
    for (final fechamento in _fechamentos.values) {
      estimado += _double(fechamento['valor_estimado_pagar']);
      falta += _double(fechamento['restante_estimado']);
    }
    final pago = _pagamentosMes.fold<double>(
      0,
      (total, item) => total + _double(item['valor']),
    );
    return {'estimado': estimado, 'pago': pago, 'falta': falta};
  }

  Future<void> _abrir(Widget pagina) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina));
    await _carregar();
  }

  Future<void> _abrirFuncionario(ColaboradorCusto colaborador) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _FuncionarioCentralDetalhePage(colaboradorId: colaborador.id!),
      ),
    );
    await _carregar();
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
    final ativos = _colaboradores.where((item) => item.ativo).length;
    final inativos = _colaboradores.length - ativos;
    final totais = _totaisFolha;
    final atual = DateTime(DateTime.now().year, DateTime.now().month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Funcionários'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
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
                                onPressed: _mes.isBefore(atual)
                                    ? _mesSeguinte
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          const Divider(),
                          _linhaValor(
                            'Estimado a pagar',
                            _moeda.format(totais['estimado'] ?? 0),
                          ),
                          _linhaValor(
                            'Já pago',
                            _moeda.format(totais['pago'] ?? 0),
                          ),
                          _linhaValor(
                            'Falta pagar',
                            _moeda.format(totais['falta'] ?? 0),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Este painel mostra somente valores ligados aos funcionários. '
                        'Aluguel, energia, estoque e outros custos da empresa não entram '
                        'no resumo da folha. O total já pago inclui pagamentos feitos no mês '
                        'mesmo quando o funcionário já foi inativado.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Acessos rápidos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _atalho(
                        Icons.badge_outlined,
                        'Cadastro e salários',
                        () => _abrir(const MaoObraCustosPage()),
                      ),
                      _atalho(
                        Icons.payments_outlined,
                        'Pagamentos',
                        () => _abrir(const PagamentosFuncionariosPage()),
                      ),
                      _atalho(
                        Icons.summarize_outlined,
                        'Resumo da folha',
                        () => _abrir(const FuncionariosResumoPage()),
                      ),
                      _atalho(
                        Icons.fingerprint_rounded,
                        'Ponto',
                        () => _abrir(const PontoFuncionariosPage()),
                      ),
                      _atalho(
                        Icons.manage_accounts_outlined,
                        'Acessos',
                        () => _abrir(const UsuariosPermissoesPage()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Equipe',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '$ativos ativo(s) • $inativos inativo(s)',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_colaboradores.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhum funcionário cadastrado.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._colaboradores.map((colaborador) {
                      final id = colaborador.id;
                      final fechamento = id == null ? null : _fechamentos[id];
                      final falta = fechamento == null
                          ? null
                          : _double(fechamento['restante_estimado']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              colaborador.ativo
                                  ? Icons.person_outline_rounded
                                  : Icons.person_off_outlined,
                            ),
                          ),
                          title: Text(
                            colaborador.nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              colaborador.ativo ? 'Ativo' : 'Inativo',
                              if (colaborador.funcao.isNotEmpty)
                                colaborador.funcao,
                              'Salário ${_moeda.format(colaborador.remuneracaoMensal)}',
                              if (falta != null)
                                'Falta ${_moeda.format(falta)}',
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: id == null
                              ? null
                              : () => _abrirFuncionario(colaborador),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }

  Widget _linhaValor(String titulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: destaque ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _atalho(IconData icone, String titulo, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icone, size: 18),
      label: Text(titulo),
      onPressed: onTap,
    );
  }
}

class _FuncionarioCentralDetalhePage extends StatefulWidget {
  const _FuncionarioCentralDetalhePage({required this.colaboradorId});

  final int colaboradorId;

  @override
  State<_FuncionarioCentralDetalhePage> createState() =>
      _FuncionarioCentralDetalhePageState();
}

class _FuncionarioCentralDetalhePageState
    extends State<_FuncionarioCentralDetalhePage> {
  final CustosRepository _repository = CustosRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  ColaboradorCusto? _colaborador;
  List<Map<String, dynamic>> _historico = const [];
  List<Map<String, dynamic>> _pagamentos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final colaboradores = await _repository.listarColaboradores(
        incluirInativos: true,
      );
      ColaboradorCusto? colaborador;
      for (final item in colaboradores) {
        if (item.id == widget.colaboradorId) {
          colaborador = item;
          break;
        }
      }
      if (colaborador == null) {
        throw StateError('Funcionário não encontrado.');
      }

      final agora = DateTime.now();
      final inicio = DateTime(agora.year - 1, agora.month, 1);
      final historico = await _repository.listarHistoricoColaborador(
        widget.colaboradorId,
      );
      final pagamentos = await _repository.listarPagamentosColaboradores(
        inicio: inicio,
        fim: agora,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _colaborador = colaborador;
        _historico = historico;
        _pagamentos = pagamentos
            .where((item) => item['colaborador_id'] == widget.colaboradorId)
            .toList();
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

  Future<void> _alterarSituacao() async {
    final colaborador = _colaborador;
    if (colaborador?.id == null) {
      return;
    }
    final novoAtivo = !colaborador!.ativo;

    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(novoAtivo ? 'Ativar funcionário' : 'Inativar funcionário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              novoAtivo
                  ? 'Ao ativar, o salário, encargos e outros custos deste funcionário voltam a compor imediatamente o custo/hora da empresa.'
                  : 'Ao inativar, este funcionário deixa imediatamente de compor o custo/hora da empresa. Pagamentos e histórico anteriores continuam preservados.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Opcional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(novoAtivo ? 'Ativar' : 'Inativar'),
          ),
        ],
      ),
    );

    final motivo = motivoController.text;
    motivoController.dispose();
    if (confirmar != true) {
      return;
    }

    await _repository.definirAtivoColaborador(
      colaborador.id!,
      novoAtivo,
      motivo: motivo,
    );
    await _carregar();
  }

  Future<void> _registrarReajuste() async {
    final colaborador = _colaborador;
    if (colaborador?.id == null) {
      return;
    }

    final valorController = TextEditingController(
      text: colaborador!.remuneracaoMensal
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    final motivoController = TextEditingController();
    var vigencia = DateTime.now();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar reajuste salarial'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valorController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Novo salário / remuneração',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ex.: reajuste anual, promoção...',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final data = await showDatePicker(
                    context: dialogContext,
                    initialDate: vigencia,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    locale: const Locale('pt', 'BR'),
                  );
                  if (data != null) {
                    setDialogState(() => vigencia = data);
                  }
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  'Vigência: ${DateFormat('dd/MM/yyyy').format(vigencia)}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salvar reajuste'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) {
      valorController.dispose();
      motivoController.dispose();
      return;
    }

    var texto = valorController.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }
    final valor = double.tryParse(texto);
    final motivo = motivoController.text;
    valorController.dispose();
    motivoController.dispose();

    if (valor == null || valor < 0) {
      _mensagem('Informe um valor de remuneração válido.', erro: true);
      return;
    }

    try {
      await _repository.registrarReajusteRemuneracao(
        colaboradorId: colaborador.id!,
        novaRemuneracao: valor,
        vigencia: vigencia,
        motivo: motivo,
      );
      await _carregar();
      _mensagem('Reajuste registrado no histórico.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
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

  String _data(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null ? '-' : DateFormat('dd/MM/yyyy').format(data.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final colaborador = _colaborador;
    return Scaffold(
      appBar: AppBar(title: Text(colaborador?.nome ?? 'Funcionário')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : colaborador == null
          ? const Center(child: Text('Funcionário não encontrado.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    colaborador.nome,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (colaborador.funcao.isNotEmpty)
                                    Text(
                                      colaborador.funcao,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(
                                colaborador.ativo ? 'Ativo' : 'Inativo',
                              ),
                              avatar: Icon(
                                colaborador.ativo
                                    ? Icons.check_circle_outline
                                    : Icons.pause_circle_outline,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _detalhe(
                          'Salário / remuneração atual',
                          _moeda.format(colaborador.remuneracaoMensal),
                        ),
                        _detalhe(
                          'Encargos e benefícios',
                          _moeda.format(colaborador.encargosMensais),
                        ),
                        _detalhe(
                          'Outros custos do funcionário',
                          _moeda.format(colaborador.outrosCustosMensais),
                        ),
                        _detalhe(
                          'Custo mensal para precificação',
                          colaborador.ativo
                              ? _moeda.format(colaborador.custoMensalTotal)
                              : 'R\$ 0,00 (inativo)',
                        ),
                        _detalhe(
                          'Custo individual/hora',
                          colaborador.ativo
                              ? _moeda.format(colaborador.custoHoraProdutiva)
                              : 'Fora do cálculo atual',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _registrarReajuste,
                        icon: const Icon(Icons.trending_up_rounded),
                        label: const Text('Reajuste salarial'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _alterarSituacao,
                        icon: Icon(
                          colaborador.ativo
                              ? Icons.person_off_outlined
                              : Icons.person_add_alt_outlined,
                        ),
                        label: Text(colaborador.ativo ? 'Inativar' : 'Ativar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const MaoObraCustosPage(),
                      ),
                    );
                    await _carregar();
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar cadastro e custos'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Histórico salarial e de situação',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_historico.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Nenhum histórico registrado ainda.'),
                    ),
                  )
                else
                  ..._historico.take(30).map((item) {
                    final tipo = (item['tipo'] ?? '').toString();
                    final anterior = _double(item['remuneracao_anterior']);
                    final novo = _double(item['remuneracao_nova']);
                    final motivo = (item['motivo'] ?? '').toString().trim();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          tipo == 'Reajuste salarial'
                              ? Icons.trending_up_rounded
                              : tipo == 'Inativação'
                              ? Icons.person_off_outlined
                              : tipo == 'Ativação'
                              ? Icons.person_add_alt_outlined
                              : Icons.history_rounded,
                        ),
                        title: Text(tipo),
                        subtitle: Text(
                          [
                            _data(item['vigencia_em']),
                            if (tipo == 'Reajuste salarial')
                              '${_moeda.format(anterior)} → ${_moeda.format(novo)}',
                            if (motivo.isNotEmpty) motivo,
                          ].join(' • '),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 18),
                const Text(
                  'Pagamentos dos últimos 12 meses',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_pagamentos.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Nenhum pagamento encontrado no período.'),
                    ),
                  )
                else
                  ..._pagamentos
                      .take(20)
                      .map(
                        (item) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.payments_outlined),
                            title: Text(
                              _moeda.format(_double(item['valor'])),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              [
                                _data(item['data_pagamento']),
                                (item['forma_pagamento'] ?? '').toString(),
                                (item['conta_nome'] ?? '').toString(),
                              ].where((e) => e.trim().isNotEmpty).join(' • '),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _detalhe(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
