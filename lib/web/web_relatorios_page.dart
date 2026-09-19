import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_dre_service.dart';
import '../services/web_cloud_relatorios_service.dart';
import 'imperium_web_theme.dart';

class WebRelatoriosPage extends StatefulWidget {
  const WebRelatoriosPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WebRelatoriosPage> createState() => _WebRelatoriosPageState();
}

class _WebRelatoriosPageState extends State<WebRelatoriosPage> {
  final _service = WebCloudRelatoriosService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  late DateTimeRange _periodo;
  WebRelatoriosResumo? _resumo;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _periodo = DateTimeRange(
      start: DateTime(agora.year, agora.month, 1),
      end: DateTime(agora.year, agora.month + 1, 0),
    );
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resumo = await _service.carregar(
        inicio: _periodo.start,
        fim: _periodo.end,
      );
      if (!mounted) return;
      setState(() => _resumo = resumo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _selecionarPeriodo() async {
    final novo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
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

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _CabecalhoRelatorio(
          periodo: _periodo,
          data: _data,
          carregando: _carregando,
          onSelecionarPeriodo: _selecionarPeriodo,
        ),
        const Divider(),
        Expanded(child: _conteudo()),
      ],
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios gerenciais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  Widget _conteudo() {
    if (_carregando && _resumo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null && _resumo == null) {
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
                  Text(_erro!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _carregar,
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

    final resumo = _resumo!;
    final detalhes = resumo.competencia.detalhes.toList()
      ..sort((a, b) => b.valor.abs().compareTo(a.valor.abs()));

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard(
                  titulo: 'Vendas líquidas',
                  valor: _moeda.format(resumo.vendas),
                  icon: Icons.receipt_long_outlined,
                ),
                _MetricCard(
                  titulo: 'Recebido',
                  valor: _moeda.format(resumo.recebido),
                  icon: Icons.payments_outlined,
                ),
                _MetricCard(
                  titulo: 'A receber',
                  valor: _moeda.format(resumo.aReceber),
                  icon: Icons.schedule_rounded,
                  alerta: resumo.aReceber > 0,
                ),
                _MetricCard(
                  titulo: 'Resultado competência',
                  valor: _moeda.format(resumo.competencia.resultadoGerencial),
                  icon: Icons.query_stats_rounded,
                  alerta: resumo.competencia.resultadoGerencial < 0,
                ),
                _MetricCard(
                  titulo: 'Resultado caixa',
                  valor: _moeda.format(resumo.caixa.resultadoGerencial),
                  icon: Icons.account_balance_wallet_outlined,
                  alerta: resumo.caixa.resultadoGerencial < 0,
                ),
                _MetricCard(
                  titulo: 'Ticket médio',
                  valor: _moeda.format(resumo.ticketMedio),
                  icon: Icons.shopping_bag_outlined,
                ),
                _MetricCard(
                  titulo: 'OS finalizadas',
                  valor: '${resumo.quantidadeOrdens}',
                  icon: Icons.car_repair_outlined,
                ),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionTitle(
              titulo: 'Competência × caixa',
              subtitulo:
                  'Competência mede o resultado econômico; caixa mede o que realmente entrou e saiu.',
            ),
            const SizedBox(height: 10),
            _DreCompareCard(
              competencia: resumo.competencia,
              caixa: resumo.caixa,
              moeda: _moeda,
            ),
            const SizedBox(height: 26),
            const _SectionTitle(
              titulo: 'Desempenho por executor',
              subtitulo:
                  'Vendas das OS executadas, sem expor salário ou valor-hora interno.',
            ),
            const SizedBox(height: 10),
            if (resumo.executores.isEmpty)
              const _EmptyState('Sem executores no período selecionado.')
            else
              ...resumo.executores
                  .take(10)
                  .map((item) => _ExecutorCard(item: item, moeda: _moeda)),
            const SizedBox(height: 26),
            const _SectionTitle(
              titulo: 'Maiores vendas do período',
              subtitulo:
                  'Os valores já consideram descontos, negociação, acréscimos e juros da OS.',
            ),
            const SizedBox(height: 10),
            if (resumo.ordens.isEmpty)
              const _EmptyState('Nenhuma OS finalizada no período.')
            else
              ...resumo.ordens
                  .take(10)
                  .map(
                    (ordem) => _OrderCard(
                      ordem: ordem,
                      venda: WebCloudRelatoriosService.vendaOrdem(ordem),
                      moeda: _moeda,
                      data: _data,
                    ),
                  ),
            const SizedBox(height: 26),
            const _SectionTitle(
              titulo: 'Maiores categorias da DRE',
              subtitulo:
                  'Categorias com maior impacto absoluto no resultado do período.',
            ),
            const SizedBox(height: 10),
            if (detalhes.isEmpty)
              const _EmptyState('Sem categorias financeiras no período.')
            else
              ...detalhes
                  .take(12)
                  .map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(item.nome),
                        subtitle: Text(
                          '${item.grupo}'
                          '${item.codigo.isEmpty ? '' : ' · ${item.codigo}'}',
                        ),
                        trailing: Text(
                          _moeda.format(item.valor),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
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
  }

  static String _textoErro(Object erro) {
    final texto = erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
    return texto.trim().isEmpty
        ? 'Não foi possível carregar os relatórios.'
        : texto;
  }
}

class _CabecalhoRelatorio extends StatelessWidget {
  const _CabecalhoRelatorio({
    required this.periodo,
    required this.data,
    required this.carregando,
    required this.onSelecionarPeriodo,
  });

  final DateTimeRange periodo;
  final DateFormat data;
  final bool carregando;
  final VoidCallback onSelecionarPeriodo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final periodoButton = OutlinedButton.icon(
            onPressed: carregando ? null : onSelecionarPeriodo,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              '${data.format(periodo.start)} — ${data.format(periodo.end)}',
            ),
          );

          final titulo = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visão consolidada da empresa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'Vendas líquidas, recebimentos e DRE usam a mesma fonte cloud do Android.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFFAAB3BD)),
              ),
            ],
          );

          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [titulo, const SizedBox(height: 12), periodoButton],
            );
          }

          return Row(
            children: [
              Expanded(child: titulo),
              const SizedBox(width: 16),
              periodoButton,
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFAAB3BD),
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

class _DreCompareCard extends StatelessWidget {
  const _DreCompareCard({
    required this.competencia,
    required this.caixa,
    required this.moeda,
  });

  final WebDreResultado competencia;
  final WebDreResultado caixa;
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
            DataColumn(label: Text('Competência'), numeric: true),
            DataColumn(label: Text('Caixa'), numeric: true),
          ],
          rows: [
            _row('Receita bruta', competencia.receitaBruta, caixa.receitaBruta),
            _row('Deduções', competencia.deducoes, caixa.deducoes),
            _row(
              'Receita líquida',
              competencia.receitaLiquida,
              caixa.receitaLiquida,
            ),
            _row(
              'Custos variáveis',
              competencia.custosVariaveis,
              caixa.custosVariaveis,
            ),
            _row(
              'Margem de contribuição',
              competencia.margemContribuicao,
              caixa.margemContribuicao,
            ),
            _row(
              'Despesas operacionais',
              competencia.despesasOperacionais,
              caixa.despesasOperacionais,
            ),
            _row(
              'Resultado gerencial',
              competencia.resultadoGerencial,
              caixa.resultadoGerencial,
            ),
          ],
        ),
      ),
    );
  }

  DataRow _row(String titulo, double competenciaValor, double caixaValor) {
    return DataRow(
      cells: [
        DataCell(Text(titulo)),
        DataCell(Text(moeda.format(competenciaValor))),
        DataCell(Text(moeda.format(caixaValor))),
      ],
    );
  }
}

class _ExecutorCard extends StatelessWidget {
  const _ExecutorCard({required this.item, required this.moeda});

  final WebRelatoriosExecutor item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(
          item.nome,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${item.quantidade} OS · Recebido ${moeda.format(item.recebido)}',
        ),
        trailing: Text(
          moeda.format(item.vendas),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.ordem,
    required this.venda,
    required this.moeda,
    required this.data,
  });

  final Map<String, dynamic> ordem;
  final double venda;
  final NumberFormat moeda;
  final DateFormat data;

  @override
  Widget build(BuildContext context) {
    final finalizacao = DateTime.tryParse(
      (ordem['data_finalizacao'] ?? '').toString(),
    );
    final responsavel = (ordem['funcionario_responsavel'] ?? '')
        .toString()
        .trim();
    final statusPagamento = (ordem['status_pagamento'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.car_repair_outlined),
        title: Text(
          'OS ${ordem['numero'] ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (finalizacao != null) data.format(finalizacao),
            if (responsavel.isNotEmpty) responsavel,
            if (statusPagamento.isNotEmpty) statusPagamento,
          ].join(' · '),
        ),
        trailing: Text(
          moeda.format(venda),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          subtitulo,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFFAAB3BD)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: Color(0xFF89939E)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    );
  }
}
