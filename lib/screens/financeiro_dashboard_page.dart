import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/financeiro_dashboard_repository.dart';

class FinanceiroDashboardPage extends StatefulWidget {
  const FinanceiroDashboardPage({super.key});

  @override
  State<FinanceiroDashboardPage> createState() =>
      _FinanceiroDashboardPageState();
}

class _FinanceiroDashboardPageState extends State<FinanceiroDashboardPage> {
  final FinanceiroDashboardRepository _repository =
      FinanceiroDashboardRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _carregando = true;
  bool _saldosVisiveis = true;
  FinanceiroDashboardData? _dados;
  Map<String, double> _saldosContas = const {};

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
        _repository.carregar(mes: _mes),
        _repository.saldosContas(),
      ]);

      if (!mounted) return;

      setState(() {
        _dados = resultados[0] as FinanceiroDashboardData;
        _saldosContas = Map<String, double>.from(
          resultados[1] as Map<String, double>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível carregar o dashboard financeiro.\n$erro',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  void _alterarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  double _necessarioPorDia({required double meta, required double faturado}) {
    final falta = (meta - faturado).clamp(0, double.infinity).toDouble();

    if (falta <= 0) return 0;

    final hoje = DateTime.now();
    final mesAtual = DateTime(hoje.year, hoje.month, 1);
    final selecionado = DateTime(_mes.year, _mes.month, 1);

    if (selecionado.isBefore(mesAtual)) return 0;

    final dias = selecionado == mesAtual
        ? DateTime(
                _mes.year,
                _mes.month + 1,
                0,
              ).difference(DateTime(hoje.year, hoje.month, hoje.day)).inDays +
              1
        : DateTime(_mes.year, _mes.month + 1, 0).day;

    return dias <= 0 ? 0 : falta / dias;
  }

  String _valorOcultavel(double valor) {
    return _saldosVisiveis ? _moeda.format(valor) : 'R\$ ••••••';
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final titulo = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final tituloMes = titulo.isEmpty
        ? ''
        : titulo[0].toUpperCase() + titulo.substring(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard financeiro'),
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
          : dados == null
          ? const Center(child: Text('Sem dados para exibir.'))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _SeletorMes(
                    titulo: tituloMes,
                    onAnterior: () => _alterarMes(-1),
                    onProximo: () => _alterarMes(1),
                  ),
                  const SizedBox(height: 12),
                  _SaldosCard(
                    saldos: _saldosContas,
                    valor: _valorOcultavel,
                    visiveis: _saldosVisiveis,
                    onAlternar: () {
                      setState(() => _saldosVisiveis = !_saldosVisiveis);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ExplicacaoFaturamento(
                    recebido: dados.recebido,
                    vendas: dados.vendasFinalizadas,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 12),
                  _ResultadoPrincipal(
                    resultado: dados.dreCompetencia.resultadoGerencial,
                    margem: dados.dreCompetencia.margemPercentual,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 12),
                  _GradeKpis(
                    itens: [
                      _KpiDados(
                        'Faturamento recebido',
                        _moeda.format(dados.recebido),
                        Icons.payments_outlined,
                      ),
                      _KpiDados(
                        'Vendas finalizadas',
                        _moeda.format(dados.vendasFinalizadas),
                        Icons.receipt_long_outlined,
                      ),
                      _KpiDados(
                        'Recebido líquido',
                        _moeda.format(dados.recebidoLiquido),
                        Icons.savings_outlined,
                      ),
                      _KpiDados(
                        'A receber total',
                        _moeda.format(dados.aReceber),
                        Icons.schedule_rounded,
                      ),
                      _KpiDados(
                        'Vencido agora',
                        _moeda.format(dados.vencido),
                        Icons.warning_amber_rounded,
                        alerta: dados.vencido > 0,
                      ),
                      _KpiDados(
                        'Taxas de cartão',
                        _moeda.format(dados.taxas),
                        Icons.credit_card_off_outlined,
                      ),
                      _KpiDados(
                        'Resultado de caixa',
                        _moeda.format(dados.resultadoCaixa),
                        Icons.account_balance_wallet_outlined,
                      ),
                      _KpiDados(
                        'Receitas realizadas',
                        _moeda.format(dados.receitaRealizada),
                        Icons.south_west_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    'Metas do mês',
                    'Faturamento usa o dinheiro efetivamente recebido.',
                  ),
                  const SizedBox(height: 10),
                  _MetaCard(
                    titulo: 'Meta de faturamento',
                    atual: dados.recebido,
                    meta: dados.metaReceita,
                    moeda: _moeda,
                    extras: [
                      _LinhaMeta('Vendas finalizadas', dados.vendasFinalizadas),
                      _LinhaMeta(
                        'Falta receber para meta',
                        (dados.metaReceita - dados.recebido)
                            .clamp(0, double.infinity)
                            .toDouble(),
                      ),
                      if (dados.metaReceita > dados.recebido)
                        _LinhaMeta(
                          'Necessário por dia',
                          _necessarioPorDia(
                            meta: dados.metaReceita,
                            faturado: dados.recebido,
                          ),
                        ),
                    ],
                  ),
                  _MetaCard(
                    titulo: 'Limite de despesas',
                    atual: dados.despesaPrevista > dados.despesaRealizada
                        ? dados.despesaPrevista
                        : dados.despesaRealizada,
                    meta: dados.metaDespesa,
                    moeda: _moeda,
                    extras: [
                      _LinhaMeta('Previsto', dados.despesaPrevista),
                      _LinhaMeta('Pago', dados.despesaRealizada),
                    ],
                  ),
                  _MetaCard(
                    titulo: 'Meta de resultado',
                    atual: dados.dreCompetencia.resultadoGerencial,
                    meta: dados.metaResultado,
                    moeda: _moeda,
                    extras: [
                      _LinhaMeta('Resultado de caixa', dados.resultadoCaixa),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    'Estrutura de custos',
                    'Valores de referência usados na gestão e precificação.',
                  ),
                  const SizedBox(height: 10),
                  _GradeKpis(
                    itens: [
                      _KpiDados(
                        'Custos fixos',
                        _moeda.format(dados.custoFixoMensal),
                        Icons.home_work_outlined,
                      ),
                      _KpiDados(
                        'Mão de obra',
                        _moeda.format(dados.custoMaoObraMensal),
                        Icons.engineering_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    'Últimos 6 meses',
                    'Recebimentos e vendas são mostrados separadamente.',
                  ),
                  const SizedBox(height: 10),
                  ...dados.evolucao.map(
                    (item) => _EvolucaoCard(item: item, moeda: _moeda),
                  ),
                  if (dados.topResultadosOs.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _TituloSecao(
                      'OS com maior resultado',
                      'Ranking comercial das OS finalizadas no mês.',
                    ),
                    const SizedBox(height: 10),
                    ...dados.topResultadosOs.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(
                            Icons.car_repair_outlined,
                            color: Color(0xFFD6A84B),
                          ),
                          title: Text((item['numero'] ?? 'OS').toString()),
                          subtitle: Text(
                            (item['cliente_nome'] ?? '').toString(),
                          ),
                          trailing: Text(
                            _moeda.format(_double(item['resultado_os'])),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SeletorMes extends StatelessWidget {
  const _SeletorMes({
    required this.titulo,
    required this.onAnterior,
    required this.onProximo,
  });

  final String titulo;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Mês anterior',
          onPressed: onAnterior,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Próximo mês',
          onPressed: onProximo,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _SaldosCard extends StatelessWidget {
  const _SaldosCard({
    required this.saldos,
    required this.valor,
    required this.visiveis,
    required this.onAlternar,
  });

  final Map<String, double> saldos;
  final String Function(double valor) valor;
  final bool visiveis;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final total = saldos.values.fold<double>(0, (soma, item) => soma + item);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFFD6A84B),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Saldo disponível agora',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: visiveis ? 'Ocultar valores' : 'Mostrar valores',
                  onPressed: onAlternar,
                  icon: Icon(
                    visiveis
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ],
            ),
            Text(
              valor(total),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (saldos.isEmpty)
              const Text(
                'Nenhuma conta financeira ativa.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ...saldos.entries.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        size: 17,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        valor(item.value),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 7),
            const Text(
              'Saldo inicial + entradas realizadas − saídas realizadas.',
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplicacaoFaturamento extends StatelessWidget {
  const _ExplicacaoFaturamento({
    required this.recebido,
    required this.vendas,
    required this.moeda,
  });

  final double recebido;
  final double vendas;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFD6A84B)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Faturamento recebido: ${moeda.format(recebido)}. '
                'Vendas finalizadas: ${moeda.format(vendas)}. '
                'Em vendas parceladas, cada parcela entra no faturamento '
                'do mês em que for efetivamente paga.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoPrincipal extends StatelessWidget {
  const _ResultadoPrincipal({
    required this.resultado,
    required this.margem,
    required this.moeda,
  });

  final double resultado;
  final double margem;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              resultado >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: resultado >= 0 ? Colors.greenAccent : Colors.orangeAccent,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resultado gerencial',
                    style: TextStyle(color: Colors.white60),
                  ),
                  Text(
                    moeda.format(resultado),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Margem ${margem.toStringAsFixed(1).replaceAll('.', ',')}% '
                    '• competência das vendas',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
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

class _KpiDados {
  const _KpiDados(this.titulo, this.valor, this.icone, {this.alerta = false});

  final String titulo;
  final String valor;
  final IconData icone;
  final bool alerta;
}

class _GradeKpis extends StatelessWidget {
  const _GradeKpis({required this.itens});

  final List<_KpiDados> itens;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth < 520 ? 2 : 3;
        final espaco = 10.0;
        final largura =
            (constraints.maxWidth - espaco * (colunas - 1)) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: _KpiCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.item});

  final _KpiDados item;

  @override
  Widget build(BuildContext context) {
    final cor = item.alerta ? Colors.orangeAccent : const Color(0xFFD6A84B);

    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icone, color: cor, size: 21),
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
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSecao extends StatelessWidget {
  const _TituloSecao(this.titulo, this.subtitulo);

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
        Text(subtitulo, style: const TextStyle(color: Colors.white60)),
      ],
    );
  }
}

class _LinhaMeta {
  const _LinhaMeta(this.titulo, this.valor);

  final String titulo;
  final double valor;
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.titulo,
    required this.atual,
    required this.meta,
    required this.moeda,
    required this.extras,
  });

  final String titulo;
  final double atual;
  final double meta;
  final NumberFormat moeda;
  final List<_LinhaMeta> extras;

  @override
  Widget build(BuildContext context) {
    final progresso = meta <= 0
        ? 0.0
        : (atual / meta).clamp(0.0, 1.0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    meta > 0
                        ? '${moeda.format(atual)} de ${moeda.format(meta)}'
                        : moeda.format(atual),
                  ),
                ),
                if (meta > 0)
                  Text(
                    '${(progresso * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            if (meta > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progresso,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...extras.map(
                (linha) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          linha.titulo,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      Text(
                        moeda.format(linha.valor),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (meta <= 0) ...[
              const SizedBox(height: 8),
              const Text(
                'Nenhuma meta cadastrada para este mês.',
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvolucaoCard extends StatelessWidget {
  const _EvolucaoCard({required this.item, required this.moeda});

  final Map<String, dynamic> item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final ano = _int(item['ano']) ?? DateTime.now().year;
    final mes = _int(item['mes']) ?? DateTime.now().month;
    final data = DateTime(ano, mes, 1);
    final label = DateFormat('MMM/yy', 'pt_BR').format(data).toUpperCase();

    final recebido = _double(item['recebido'] ?? item['receita']);
    final vendas = _double(item['vendas']);
    final taxas = _double(item['taxas']);
    final caixa = _double(item['resultado_caixa']);
    final gerencial = _double(item['resultado']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('Recebido ${moeda.format(recebido)}'),
                Text('Vendas ${moeda.format(vendas)}'),
                Text('Taxas ${moeda.format(taxas)}'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Resultado de caixa ${moeda.format(caixa)} • '
              'Gerencial ${moeda.format(gerencial)}',
              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

int? _int(dynamic valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor?.toString().trim() ?? '');
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().trim().replaceAll(',', '.') ?? '') ??
      0;
}
