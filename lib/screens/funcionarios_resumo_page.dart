import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/ponto_repository.dart';

class FuncionariosResumoPage extends StatefulWidget {
  const FuncionariosResumoPage({super.key});

  @override
  State<FuncionariosResumoPage> createState() => _FuncionariosResumoPageState();
}

class _FuncionariosResumoPageState extends State<FuncionariosResumoPage> {
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
  List<Map<String, dynamic>> _pagamentos = const [];

  DateTime get _inicioMes => DateTime(_mes.year, _mes.month, 1);

  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

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
      final todosColaboradores = await _custosRepository.listarColaboradores(
        incluirInativos: true,
      );

      final pagamentos = await _custosRepository.listarPagamentosColaboradores(
        inicio: _inicioMes,
        fim: _fimMes,
      );

      final colaboradores = <ColaboradorCusto>[];
      final fechamentos = <int, Map<String, dynamic>>{};

      for (final colaborador in todosColaboradores) {
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

        colaboradores.add(colaborador);
        fechamentos[id] = await _pontoRepository.obterFechamentoMes(
          colaboradorId: id,
          inicio: _inicioMes,
          fim: _fimMes,
        );
      }

      if (!mounted) return;

      setState(() {
        _colaboradores = colaboradores;
        _pagamentos = List<Map<String, dynamic>>.from(pagamentos);
        _fechamentos = fechamentos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar o resumo.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _mesAnterior() {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month - 1);
    });
    _carregar();
  }

  void _mesSeguinte() {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + 1);
    });
    _carregar();
  }

  String _tituloMes() {
    final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return texto.substring(0, 1).toUpperCase() + texto.substring(1);
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  String _horas(dynamic minutos) {
    final total = _int(minutos);
    final horas = total ~/ 60;
    final resto = total % 60;
    return '${horas}h ${resto.toString().padLeft(2, '0')}min';
  }

  List<Map<String, dynamic>> _pagamentosDoColaborador(int id) {
    return _pagamentos.where((item) {
      return _int(item['colaborador_id']) == id;
    }).toList();
  }

  Map<String, double> get _totaisGerais {
    var estimado = 0.0;
    var restante = 0.0;

    for (final item in _fechamentos.values) {
      estimado += _double(item['valor_estimado_pagar']);
      restante += _double(item['restante_estimado']);
    }

    final pago = _pagamentos.fold<double>(
      0,
      (total, item) => total + _double(item['valor']),
    );

    return {'estimado': estimado, 'pago': pago, 'restante': restante};
  }

  List<Map<String, dynamic>> _semanas(Map<String, dynamic> fechamento) {
    final diasBrutos = fechamento['dias'];
    if (diasBrutos is! List) {
      return const [];
    }

    final dias = List<Map<String, dynamic>>.from(diasBrutos);

    final agrupado = <String, Map<String, dynamic>>{};

    for (final dia in dias) {
      final data = DateTime.tryParse(dia['data']?.toString() ?? '');
      if (data == null) continue;

      final inicioSemana = data.subtract(
        Duration(days: data.weekday - DateTime.monday),
      );
      final fimSemana = inicioSemana.add(const Duration(days: 6));

      final chave =
          '${inicioSemana.year}-${inicioSemana.month}-${inicioSemana.day}';

      final item = agrupado.putIfAbsent(
        chave,
        () => {
          'inicio': inicioSemana,
          'fim': fimSemana,
          'trabalhados': 0,
          'extras': 0,
          'faltantes': 0,
          'faltas': 0,
          'pendencias': 0,
          'incompletos': 0,
        },
      );

      item['trabalhados'] =
          _int(item['trabalhados']) + _int(dia['minutos_trabalhados']);

      item['extras'] = _int(item['extras']) + _int(dia['minutos_extras']);

      item['faltantes'] =
          _int(item['faltantes']) + _int(dia['minutos_faltantes']);

      final status = (dia['status_exibido'] ?? '').toString();

      if (status == 'Falta') {
        item['faltas'] = _int(item['faltas']) + 1;
      }

      if (status == 'Pendente') {
        item['pendencias'] = _int(item['pendencias']) + 1;
      }

      if (status == 'Incompleto') {
        item['incompletos'] = _int(item['incompletos']) + 1;
      }
    }

    final lista = agrupado.values.toList();

    lista.sort((a, b) {
      final aData = a['inicio'] as DateTime;
      final bData = b['inicio'] as DateTime;
      return aData.compareTo(bData);
    });

    return lista;
  }

  Future<void> _abrirFuncionario(ColaboradorCusto colaborador) async {
    final id = colaborador.id;
    if (id == null) return;

    final fechamento = _fechamentos[id];
    if (fechamento == null) return;

    final pagamentos = _pagamentosDoColaborador(id);

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _FuncionarioResumoDetalhesPage(
          colaborador: colaborador,
          fechamento: fechamento,
          pagamentos: pagamentos,
          semanas: _semanas(fechamento),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totais = _totaisGerais;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumo dos funcionários'),
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
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Próximo mês',
                            onPressed: _mesSeguinte,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _ResumoFinanceiroLinha(
                            titulo: 'Estimado a pagar',
                            valor: _moeda.format(totais['estimado'] ?? 0),
                          ),
                          _ResumoFinanceiroLinha(
                            titulo: 'Já pago',
                            valor: _moeda.format(totais['pago'] ?? 0),
                          ),
                          const Divider(),
                          _ResumoFinanceiroLinha(
                            titulo: 'Falta pagar',
                            valor: _moeda.format(totais['restante'] ?? 0),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Este resumo considera somente valores relacionados aos funcionários: salário base, horas extras, descontos por horas faltantes e pagamentos realizados. Custos fixos e demais despesas da empresa não entram aqui.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_colaboradores.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhum funcionário ativo cadastrado.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._colaboradores.map((colaborador) {
                      final id = colaborador.id;
                      final fechamento = id == null ? null : _fechamentos[id];

                      if (id == null || fechamento == null) {
                        return const SizedBox.shrink();
                      }

                      final pendencias = _int(fechamento['pendencias']);
                      final incompletos = _int(fechamento['incompletos']);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _abrirFuncionario(colaborador),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const CircleAvatar(
                                      child: Icon(Icons.person_outline_rounded),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            colaborador.nome,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            fechamento['fechamento_status'] ==
                                                    'Fechado'
                                                ? 'Ponto fechado'
                                                : pendencias > 0 ||
                                                      incompletos > 0
                                                ? '$pendencias pendente(s) • '
                                                      '$incompletos incompleto(s)'
                                                : 'Ponto conferido',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _ResumoMini(
                                      titulo: 'Trabalhadas',
                                      valor: _horas(
                                        fechamento['minutos_trabalhados'],
                                      ),
                                    ),
                                    _ResumoMini(
                                      titulo: 'Extras',
                                      valor: _horas(
                                        fechamento['minutos_extras'],
                                      ),
                                    ),
                                    _ResumoMini(
                                      titulo: 'Faltas',
                                      valor: '${fechamento['faltas'] ?? 0}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ResumoValor(
                                        titulo: 'Estimado',
                                        valor: _moeda.format(
                                          fechamento['valor_estimado_pagar'] ??
                                              0,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _ResumoValor(
                                        titulo: 'Pago',
                                        valor: _moeda.format(
                                          fechamento['ja_pago_mes'] ?? 0,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _ResumoValor(
                                        titulo: 'Restante',
                                        valor: _moeda.format(
                                          fechamento['restante_estimado'] ?? 0,
                                        ),
                                        destaque: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

class _FuncionarioResumoDetalhesPage extends StatelessWidget {
  const _FuncionarioResumoDetalhesPage({
    required this.colaborador,
    required this.fechamento,
    required this.pagamentos,
    required this.semanas,
  });

  final ColaboradorCusto colaborador;
  final Map<String, dynamic> fechamento;
  final List<Map<String, dynamic>> pagamentos;
  final List<Map<String, dynamic>> semanas;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  String _horas(dynamic minutos) {
    final total = _int(minutos);
    final h = total ~/ 60;
    final m = total % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}min';
  }

  String _dataPagamento(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    if (data == null) return '';
    return DateFormat('dd/MM/yyyy').format(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(colaborador.nome)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _ResumoFinanceiroLinha(
                    titulo: 'Salário base',
                    valor: _moeda.format(_double(fechamento['salario_base'])),
                  ),
                  _ResumoFinanceiroLinha(
                    titulo: 'Valor da hora',
                    valor: _moeda.format(_double(fechamento['valor_hora'])),
                  ),
                  _ResumoFinanceiroLinha(
                    titulo: 'Horas extras',
                    valor:
                        '+ ${_moeda.format(_double(fechamento['valor_horas_extras']))}',
                  ),
                  _ResumoFinanceiroLinha(
                    titulo: 'Desconto por horas',
                    valor:
                        '- ${_moeda.format(_double(fechamento['desconto_horas_faltantes']))}',
                  ),
                  const Divider(),
                  _ResumoFinanceiroLinha(
                    titulo: 'Estimado a pagar',
                    valor: _moeda.format(
                      _double(fechamento['valor_estimado_pagar']),
                    ),
                    destaque: true,
                  ),
                  _ResumoFinanceiroLinha(
                    titulo: 'Já pago',
                    valor: _moeda.format(_double(fechamento['ja_pago_mes'])),
                  ),
                  _ResumoFinanceiroLinha(
                    titulo: 'Restante',
                    valor: _moeda.format(
                      _double(fechamento['restante_estimado']),
                    ),
                    destaque: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Resumo semanal',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (semanas.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Sem dados de ponto neste mês.'),
              ),
            )
          else
            ...semanas.map((semana) {
              final inicio = semana['inicio'] as DateTime;
              final fim = semana['fim'] as DateTime;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${DateFormat('dd/MM').format(inicio)} a '
                        '${DateFormat('dd/MM').format(fim)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 7,
                        children: [
                          Text(
                            'Trabalhadas: '
                            '${_horas(semana['trabalhados'])}',
                          ),
                          Text(
                            'Extras: '
                            '${_horas(semana['extras'])}',
                          ),
                          Text(
                            'Faltantes: '
                            '${_horas(semana['faltantes'])}',
                          ),
                          Text(
                            'Faltas: '
                            '${semana['faltas'] ?? 0}',
                          ),
                          if (_int(semana['pendencias']) > 0)
                            Text(
                              'Pendentes: '
                              '${semana['pendencias']}',
                            ),
                          if (_int(semana['incompletos']) > 0)
                            Text(
                              'Incompletos: '
                              '${semana['incompletos']}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 14),
          Text(
            'Pagamentos do mês',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pagamentos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Nenhum pagamento lançado neste mês.'),
              ),
            )
          else
            ...pagamentos.map((pagamento) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(
                    _moeda.format(_double(pagamento['valor'])),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      _dataPagamento(pagamento['data_pagamento']),
                      (pagamento['conta_nome'] ?? '').toString(),
                      (pagamento['forma_pagamento'] ?? '').toString(),
                    ].where((item) => item.trim().isNotEmpty).join(' • '),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ResumoFinanceiroLinha extends StatelessWidget {
  const _ResumoFinanceiroLinha({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
              fontSize: destaque ? 16 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoMini extends StatelessWidget {
  const _ResumoMini({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$titulo: $valor'),
    );
  }
}

class _ResumoValor extends StatelessWidget {
  const _ResumoValor({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 10.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
