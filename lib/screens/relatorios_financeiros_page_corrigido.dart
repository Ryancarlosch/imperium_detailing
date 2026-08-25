import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/custos_repository.dart';
import '../repositories/dre_repository.dart';

class RelatoriosFinanceirosPage extends StatefulWidget {
  const RelatoriosFinanceirosPage({super.key});

  @override
  State<RelatoriosFinanceirosPage> createState() =>
      _RelatoriosFinanceirosPageState();
}

class _RelatoriosFinanceirosPageState extends State<RelatoriosFinanceirosPage> {
  final DreRepository _dreRepository = DreRepository();
  final CustosRepository _custosRepository = CustosRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  DateTimeRange _periodo = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
  );

  bool _carregando = true;
  DreResultado? _dreCompetencia;
  DreResultado? _dreCaixa;
  List<Map<String, dynamic>> _ordens = const [];

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
        _dreRepository.calcular(
          inicio: _periodo.start,
          fim: _periodo.end,
          regime: DreRegime.competencia,
        ),
        _dreRepository.calcular(
          inicio: _periodo.start,
          fim: _periodo.end,
          regime: DreRegime.caixa,
        ),
        _custosRepository.listarResultadoOrdens(),
      ]);

      final inicio = DateTime(
        _periodo.start.year,
        _periodo.start.month,
        _periodo.start.day,
      );
      final fim = DateTime(
        _periodo.end.year,
        _periodo.end.month,
        _periodo.end.day,
        23,
        59,
        59,
      );

      final ordens =
          List<Map<String, dynamic>>.from(resultados[2] as List<dynamic>).where(
            (item) {
              final data = DateTime.tryParse(
                (item['data_finalizacao'] ?? '').toString(),
              );

              if (data == null) return false;

              return !data.isBefore(inicio) && !data.isAfter(fim);
            },
          ).toList();

      ordens.sort((a, b) => _resultadoOrdem(b).compareTo(_resultadoOrdem(a)));

      if (!mounted) return;

      setState(() {
        _dreCompetencia = resultados[0] as DreResultado;
        _dreCaixa = resultados[1] as DreResultado;
        _ordens = ordens;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Não foi possível carregar os relatórios.\n$erro'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Future<void> _selecionarPeriodo() async {
    final novo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: _periodo,
      locale: const Locale('pt', 'BR'),
      helpText: 'Selecionar período do relatório',
      saveText: 'Aplicar',
      cancelText: 'Cancelar',
    );

    if (novo == null || !mounted) return;

    setState(() => _periodo = novo);
    await _carregar();
  }

  double get _vendasOs {
    return _ordens.fold<double>(0, (total, item) => total + _vendaOrdem(item));
  }

  double get _resultadoOs {
    return _ordens.fold<double>(
      0,
      (total, item) => total + _resultadoOrdem(item),
    );
  }

  double get _ticketMedio {
    return _ordens.isEmpty ? 0 : _vendasOs / _ordens.length;
  }

  double get _margemGerencial {
    final vendas = _vendasOs;
    if (vendas <= 0) return 0;
    return (_resultadoOs / vendas) * 100;
  }

  int get _ordensPositivas {
    return _ordens.where((item) => _resultadoOrdem(item) >= 0).length;
  }

  int get _ordensNegativas {
    return _ordens.where((item) => _resultadoOrdem(item) < 0).length;
  }

  double get _resultadoMedioPorOs {
    return _ordens.isEmpty ? 0 : _resultadoOs / _ordens.length;
  }

  List<Map<String, dynamic>> get _pioresOrdens {
    final lista = List<Map<String, dynamic>>.from(_ordens)
      ..sort((a, b) => _resultadoOrdem(a).compareTo(_resultadoOrdem(b)));
    return lista.take(5).toList();
  }

  List<_ResumoExecutor> get _executores {
    final agrupado = <String, _ResumoExecutor>{};

    for (final item in _ordens) {
      final nomeBruto = (item['funcionario_responsavel'] ?? '').toString();
      final nome = nomeBruto.trim().isEmpty
          ? 'Sem executor informado'
          : nomeBruto.trim();

      final atual = agrupado.putIfAbsent(
        nome,
        () => _ResumoExecutor(nome: nome),
      );

      atual.quantidade += 1;
      atual.vendas += _vendaOrdem(item);
      atual.resultado += _resultadoOrdem(item);
    }

    final lista = agrupado.values.toList();

    lista.sort((a, b) {
      final porResultado = b.resultado.compareTo(a.resultado);
      if (porResultado != 0) return porResultado;
      return b.vendas.compareTo(a.vendas);
    });

    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final competencia = _dreCompetencia;
    final caixa = _dreCaixa;

    final detalhes = competencia?.detalhes.toList() ?? <DreDetalhe>[];
    detalhes.sort((a, b) => b.valor.abs().compareTo(a.valor.abs()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios gerenciais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  OutlinedButton.icon(
                    onPressed: _selecionarPeriodo,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      '${_data.format(_periodo.start)} até '
                      '${_data.format(_periodo.end)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _AvisoRelatorio(),
                  const SizedBox(height: 14),
                  const _TituloSecao(
                    titulo: 'Visão rápida',
                    subtitulo:
                        'Indicadores comerciais e gerenciais das OS finalizadas.',
                  ),
                  const SizedBox(height: 9),
                  _GradeIndicadores(
                    itens: [
                      _IndicadorDados(
                        titulo: 'Vendas finalizadas',
                        valor: _moeda.format(_vendasOs),
                        icone: Icons.receipt_long_outlined,
                      ),
                      _IndicadorDados(
                        titulo: 'Resultado gerencial',
                        valor: _moeda.format(_resultadoOs),
                        icone: Icons.trending_up_rounded,
                        alerta: _resultadoOs < 0,
                      ),
                      _IndicadorDados(
                        titulo: 'Ticket médio',
                        valor: _moeda.format(_ticketMedio),
                        icone: Icons.shopping_bag_outlined,
                      ),
                      _IndicadorDados(
                        titulo: 'Margem gerencial',
                        valor: _percentual(_margemGerencial),
                        icone: Icons.percent_rounded,
                        alerta: _margemGerencial < 0,
                      ),
                      _IndicadorDados(
                        titulo: 'OS finalizadas',
                        valor: '${_ordens.length}',
                        icone: Icons.car_repair_outlined,
                      ),
                      _IndicadorDados(
                        titulo: 'Resultado médio / OS',
                        valor: _moeda.format(_resultadoMedioPorOs),
                        icone: Icons.analytics_outlined,
                        alerta: _resultadoMedioPorOs < 0,
                      ),
                      _IndicadorDados(
                        titulo: 'OS com resultado positivo',
                        valor: '$_ordensPositivas',
                        icone: Icons.check_circle_outline_rounded,
                      ),
                      _IndicadorDados(
                        titulo: 'OS com prejuízo',
                        valor: '$_ordensNegativas',
                        icone: Icons.warning_amber_rounded,
                        alerta: _ordensNegativas > 0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Competência × caixa',
                    subtitulo:
                        'Competência mede as vendas; caixa mede o que realmente entrou e saiu.',
                  ),
                  const SizedBox(height: 9),
                  if (competencia != null && caixa != null)
                    _ComparativoCard(
                      competencia: competencia,
                      caixa: caixa,
                      moeda: _moeda,
                      percentual: _percentual,
                    ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Melhores OS',
                    subtitulo:
                        'Ranking pelo resultado gerencial estimado do período.',
                  ),
                  const SizedBox(height: 9),
                  if (_ordens.isEmpty)
                    const _EstadoVazio(
                      texto: 'Nenhuma OS finalizada no período.',
                    )
                  else
                    ..._ordens
                        .take(5)
                        .map(
                          (item) => _OrdemRankingCard(
                            item: item,
                            moeda: _moeda,
                            resultado: _resultadoOrdem(item),
                            margem: _margemOrdem(item),
                            venda: _vendaOrdem(item),
                            data: _dataTexto(item['data_finalizacao']),
                          ),
                        ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'OS que precisam de atenção',
                    subtitulo: 'As menores rentabilidades aparecem primeiro.',
                  ),
                  const SizedBox(height: 9),
                  if (_ordens.isEmpty)
                    const _EstadoVazio(
                      texto: 'Nenhuma OS finalizada no período.',
                    )
                  else
                    ..._pioresOrdens.map(
                      (item) => _OrdemRankingCard(
                        item: item,
                        moeda: _moeda,
                        resultado: _resultadoOrdem(item),
                        margem: _margemOrdem(item),
                        venda: _vendaOrdem(item),
                        data: _dataTexto(item['data_finalizacao']),
                        destaqueAtencao: _resultadoOrdem(item) < 0,
                      ),
                    ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Desempenho por executor',
                    subtitulo:
                        'Mostra resultado das OS executadas, sem expor salário ou valor-hora.',
                  ),
                  const SizedBox(height: 9),
                  if (_executores.isEmpty)
                    const _EstadoVazio(
                      texto: 'Sem executores no período selecionado.',
                    )
                  else
                    ..._executores.map(
                      (executor) => _ExecutorCard(
                        executor: executor,
                        moeda: _moeda,
                        percentual: _percentual,
                      ),
                    ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Maiores categorias da DRE',
                    subtitulo:
                        'Categorias com maior impacto em valor no período.',
                  ),
                  const SizedBox(height: 9),
                  if (detalhes.isEmpty)
                    const _EstadoVazio(texto: 'Sem categorias no período.')
                  else
                    ...detalhes
                        .take(12)
                        .map(
                          (item) => Card(
                            margin: const EdgeInsets.only(bottom: 7),
                            child: ListTile(
                              leading: const Icon(Icons.account_tree_outlined),
                              title: Text(item.nome),
                              subtitle: Text(
                                '${item.grupo}'
                                '${item.codigo.isEmpty ? '' : ' • ${item.codigo}'}',
                              ),
                              trailing: Text(
                                _moeda.format(item.valor),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  String _dataTexto(dynamic valor) {
    final data = DateTime.tryParse((valor ?? '').toString());
    return data == null ? '' : _data.format(data);
  }

  String _percentual(double valor) {
    return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static double _vendaOrdem(Map<String, dynamic> item) {
    final negociado = _double(item['valor_negociado']);
    if (negociado.abs() > 0.000001) return negociado;

    return _double(
      item['valor_total_liquido'] ?? item['valor_total'] ?? item['receita_os'],
    );
  }

  static double _resultadoOrdem(Map<String, dynamic> item) {
    if (item.containsKey('resultado_gerencial_estimado')) {
      return _double(item['resultado_gerencial_estimado']);
    }

    if (item.containsKey('resultado_os')) {
      return _double(item['resultado_os']);
    }

    return _double(item['resultado_comercial']);
  }

  static double _margemOrdem(Map<String, dynamic> item) {
    if (item.containsKey('margem_gerencial_estimada')) {
      return _double(item['margem_gerencial_estimada']);
    }

    if (item.containsKey('margem_os')) {
      return _double(item['margem_os']);
    }

    final venda = _vendaOrdem(item);
    if (venda <= 0) return 0;

    return (_resultadoOrdem(item) / venda) * 100;
  }
}

class _AvisoRelatorio extends StatelessWidget {
  const _AvisoRelatorio();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFD6A84B)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Use este relatório para identificar quais OS estão gerando '
                'resultado, onde a margem está baixa e se o caixa acompanha '
                'as vendas do período.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSecao extends StatelessWidget {
  const _TituloSecao({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Text(
          subtitulo,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _IndicadorDados {
  const _IndicadorDados({
    required this.titulo,
    required this.valor,
    required this.icone,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final bool alerta;
}

class _GradeIndicadores extends StatelessWidget {
  const _GradeIndicadores({required this.itens});

  final List<_IndicadorDados> itens;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;

        const espaco = 9.0;
        final largura =
            (constraints.maxWidth - (espaco * (colunas - 1))) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.icone,
                          size: 21,
                          color: item.alerta
                              ? Colors.orangeAccent
                              : const Color(0xFFD6A84B),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.valor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ComparativoCard extends StatelessWidget {
  const _ComparativoCard({
    required this.competencia,
    required this.caixa,
    required this.moeda,
    required this.percentual,
  });

  final DreResultado competencia;
  final DreResultado caixa;
  final NumberFormat moeda;
  final String Function(double) percentual;

  @override
  Widget build(BuildContext context) {
    final diferencaResultado =
        caixa.resultadoGerencial - competencia.resultadoGerencial;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _LinhaComparativo(
              titulo: 'Receita líquida',
              competencia: moeda.format(competencia.receitaLiquida),
              caixa: moeda.format(caixa.receitaLiquida),
            ),
            _LinhaComparativo(
              titulo: 'Custos variáveis',
              competencia: moeda.format(competencia.custosVariaveis),
              caixa: moeda.format(caixa.custosVariaveis),
            ),
            _LinhaComparativo(
              titulo: 'Despesas operacionais',
              competencia: moeda.format(competencia.despesasOperacionais),
              caixa: moeda.format(caixa.despesasOperacionais),
            ),
            const Divider(),
            _LinhaComparativo(
              titulo: 'Resultado',
              competencia: moeda.format(competencia.resultadoGerencial),
              caixa: moeda.format(caixa.resultadoGerencial),
              destaque: true,
            ),
            _LinhaComparativo(
              titulo: 'Margem',
              competencia: percentual(competencia.margemPercentual),
              caixa: percentual(caixa.margemPercentual),
            ),
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                diferencaResultado.abs() <= 0.01
                    ? 'Resultado de competência e caixa estão alinhados neste período.'
                    : diferencaResultado > 0
                    ? 'O resultado de caixa está '
                          '${moeda.format(diferencaResultado.abs())} acima '
                          'da competência no período.'
                    : 'O resultado de caixa está '
                          '${moeda.format(diferencaResultado.abs())} abaixo '
                          'da competência no período.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaComparativo extends StatelessWidget {
  const _LinhaComparativo({
    required this.titulo,
    required this.competencia,
    required this.caixa,
    this.destaque = false,
  });

  final String titulo;
  final String competencia;
  final String caixa;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
      fontSize: destaque ? 14 : 12.5,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(titulo, style: estilo)),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(competencia, style: estilo),
                const Text('competência', style: TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(caixa, style: estilo),
                const Text('caixa', style: TextStyle(fontSize: 9.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdemRankingCard extends StatelessWidget {
  const _OrdemRankingCard({
    required this.item,
    required this.moeda,
    required this.resultado,
    required this.margem,
    required this.venda,
    required this.data,
    this.destaqueAtencao = false,
  });

  final Map<String, dynamic> item;
  final NumberFormat moeda;
  final double resultado;
  final double margem;
  final double venda;
  final String data;
  final bool destaqueAtencao;

  @override
  Widget build(BuildContext context) {
    final numero = (item['numero'] ?? 'OS').toString();
    final cliente = (item['cliente_nome'] ?? '').toString().trim();
    final executor = (item['funcionario_responsavel'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: Icon(
          destaqueAtencao
              ? Icons.warning_amber_rounded
              : Icons.receipt_long_outlined,
          color: destaqueAtencao ? Colors.orangeAccent : null,
        ),
        title: Text(
          numero,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            if (cliente.isNotEmpty) cliente,
            if (executor.isNotEmpty) executor,
            if (data.isNotEmpty) data,
            'Venda ${moeda.format(venda)}',
          ].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moeda.format(resultado),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: resultado < 0 ? Colors.orangeAccent : null,
              ),
            ),
            Text(
              '${margem.toStringAsFixed(1).replaceAll('.', ',')}%',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoExecutor {
  _ResumoExecutor({required this.nome});

  final String nome;
  int quantidade = 0;
  double vendas = 0;
  double resultado = 0;

  double get ticketMedio => quantidade <= 0 ? 0 : vendas / quantidade;

  double get margem {
    if (vendas <= 0) return 0;
    return (resultado / vendas) * 100;
  }
}

class _ExecutorCard extends StatelessWidget {
  const _ExecutorCard({
    required this.executor,
    required this.moeda,
    required this.percentual,
  });

  final _ResumoExecutor executor;
  final NumberFormat moeda;
  final String Function(double) percentual;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.engineering_outlined)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    executor.nome,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${executor.quantidade} '
                  '${executor.quantidade == 1 ? 'OS' : 'OSs'}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('Vendas ${moeda.format(executor.vendas)}'),
                Text('Resultado ${moeda.format(executor.resultado)}'),
                Text('Margem ${percentual(executor.margem)}'),
                Text('Ticket ${moeda.format(executor.ticketMedio)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
