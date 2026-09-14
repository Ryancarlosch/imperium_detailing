import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_dre_service.dart';
import 'imperium_web_theme.dart';

class WebDrePage extends StatefulWidget {
  const WebDrePage({super.key});

  @override
  State<WebDrePage> createState() => _WebDrePageState();
}

class _WebDrePageState extends State<WebDrePage> {
  final _service = WebCloudDreService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataBr = DateFormat('dd/MM/yyyy', 'pt_BR');

  late DateTime _inicio;
  late DateTime _fim;
  WebDreRegime _regime = WebDreRegime.competencia;
  WebDreResultado? _resultado;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _inicio = DateTime(agora.year, agora.month, 1);
    _fim = DateTime(agora.year, agora.month + 1, 0);
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
      final resultado = await _service.calcular(
        inicio: _inicio,
        fim: _fim,
        regime: _regime,
      );
      if (!mounted) return;
      setState(() => _resultado = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _mudarRegime(WebDreRegime regime) async {
    if (_regime == regime) return;
    setState(() => _regime = regime);
    await _carregar();
  }

  Future<void> _mesAnterior() async {
    final mes = DateTime(_inicio.year, _inicio.month - 1, 1);
    setState(() {
      _inicio = mes;
      _fim = DateTime(mes.year, mes.month + 1, 0);
    });
    await _carregar();
  }

  Future<void> _mesSeguinte() async {
    final mes = DateTime(_inicio.year, _inicio.month + 1, 1);
    setState(() {
      _inicio = mes;
      _fim = DateTime(mes.year, mes.month + 1, 0);
    });
    await _carregar();
  }

  Future<void> _escolherInicio() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (data == null) return;
    setState(() => _inicio = data);
    await _carregar();
  }

  Future<void> _escolherFim() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _fim,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (data == null) return;
    setState(() => _fim = data);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DRE gerencial'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _filtros(),
          const Divider(),
          Expanded(child: _conteudo()),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 820;
          final periodo = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Mês anterior',
                onPressed: _carregando ? null : _mesAnterior,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              OutlinedButton.icon(
                onPressed: _carregando ? null : _escolherInicio,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_dataBr.format(_inicio)),
              ),
              const Text('até'),
              OutlinedButton.icon(
                onPressed: _carregando ? null : _escolherFim,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(_dataBr.format(_fim)),
              ),
              IconButton.filledTonal(
                tooltip: 'Mês seguinte',
                onPressed: _carregando ? null : _mesSeguinte,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          );

          final regime = SegmentedButton<WebDreRegime>(
            segments: const [
              ButtonSegment(
                value: WebDreRegime.competencia,
                icon: Icon(Icons.receipt_long_outlined),
                label: Text('Competência'),
              ),
              ButtonSegment(
                value: WebDreRegime.caixa,
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: Text('Caixa'),
              ),
            ],
            selected: {_regime},
            onSelectionChanged: _carregando
                ? null
                : (value) => _mudarRegime(value.first),
          );

          if (compacto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                regime,
                const SizedBox(height: 12),
                periodo,
              ],
            );
          }

          return Row(
            children: [
              regime,
              const Spacer(),
              periodo,
            ],
          );
        },
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 42),
                  const SizedBox(height: 12),
                  Text(_erro!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
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

    final resultado = _resultado;
    if (resultado == null) {
      return const Center(child: Text('Nenhum resultado disponível.'));
    }

    final grupos = <String, List<WebDreDetalhe>>{};
    for (final detalhe in resultado.detalhes) {
      grupos.putIfAbsent(detalhe.grupo, () => []).add(detalhe);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        _cabecalho(resultado),
        const SizedBox(height: 18),
        _cardsResumo(resultado),
        const SizedBox(height: 24),
        _resultadoPrincipal(resultado),
        const SizedBox(height: 24),
        Text(
          'Composição do resultado',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (grupos.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('Não há lançamentos de DRE neste período.'),
            ),
          )
        else
          ..._ordemGrupos
              .where(grupos.containsKey)
              .map((grupo) => _grupoCard(grupo, grupos[grupo]!)),
      ],
    );
  }

  Widget _cabecalho(WebDreResultado resultado) {
    final competencia = resultado.regime == WebDreRegime.competencia;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                competencia ? 'Resultado por competência' : 'Resultado por caixa',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                competencia
                    ? 'Reconhece a venda quando a OS é finalizada, independentemente de quando o cliente pagar.'
                    : 'Reconhece os valores conforme o dinheiro é efetivamente recebido ou pago.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFAAB3BD),
                ),
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 720)
          _StatusChip(
            icon: competencia
                ? Icons.receipt_long_outlined
                : Icons.account_balance_wallet_outlined,
            label: competencia ? 'Competência' : 'Caixa',
          ),
      ],
    );
  }

  Widget _cardsResumo(WebDreResultado r) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _IndicadorDre(
          titulo: 'Receita bruta',
          valor: _moeda.format(r.receitaBruta),
          icon: Icons.trending_up_rounded,
        ),
        _IndicadorDre(
          titulo: 'Deduções',
          valor: _moeda.format(r.deducoes),
          icon: Icons.remove_circle_outline_rounded,
        ),
        _IndicadorDre(
          titulo: 'Receita líquida',
          valor: _moeda.format(r.receitaLiquida),
          icon: Icons.payments_outlined,
        ),
        _IndicadorDre(
          titulo: 'Custos variáveis',
          valor: _moeda.format(r.custosVariaveis),
          icon: Icons.inventory_2_outlined,
        ),
        _IndicadorDre(
          titulo: 'Margem de contribuição',
          valor: _moeda.format(r.margemContribuicao),
          icon: Icons.stacked_line_chart_rounded,
        ),
        _IndicadorDre(
          titulo: 'Despesas operacionais',
          valor: _moeda.format(r.despesasOperacionais),
          icon: Icons.domain_outlined,
        ),
      ],
    );
  }

  Widget _resultadoPrincipal(WebDreResultado r) {
    final positivo = r.resultadoGerencial >= 0;
    final cor = positivo
        ? const Color(0xFF55D6A0)
        : Theme.of(context).colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 620;
            final numero = Column(
              crossAxisAlignment: compacto
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  'Resultado gerencial',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _moeda.format(r.resultadoGerencial),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: cor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            );

            final texto = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      positivo
                          ? Icons.arrow_circle_up_rounded
                          : Icons.arrow_circle_down_rounded,
                      color: cor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      positivo ? 'Operação positiva' : 'Operação negativa',
                      style: TextStyle(
                        color: cor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Receita líquida menos custos variáveis, despesas operacionais e resultado financeiro, com outras receitas e despesas.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFAAB3BD),
                  ),
                ),
              ],
            );

            if (compacto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  texto,
                  const SizedBox(height: 18),
                  numero,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: texto),
                const SizedBox(width: 24),
                numero,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _grupoCard(String grupo, List<WebDreDetalhe> detalhes) {
    final total = detalhes.fold<double>(0, (soma, item) => soma + item.valor);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: grupo == 'Receita Bruta' || grupo == 'Deduções',
        leading: Icon(_iconeGrupo(grupo)),
        title: Text(
          grupo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${detalhes.length} lançamento(s)'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _moeda.format(total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
        children: detalhes
            .map(
              (item) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(item.nome),
                subtitle: item.codigo.isEmpty ? null : Text(item.codigo),
                trailing: Text(
                  _moeda.format(item.valor),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  IconData _iconeGrupo(String grupo) {
    return switch (grupo) {
      'Receita Bruta' => Icons.trending_up_rounded,
      'Deduções' => Icons.remove_circle_outline_rounded,
      'Custos Variáveis' => Icons.inventory_2_outlined,
      'Despesas Operacionais' => Icons.domain_outlined,
      'Resultado Financeiro' => Icons.account_balance_outlined,
      'Outras Receitas' => Icons.add_circle_outline_rounded,
      'Outras Despesas' => Icons.money_off_csred_outlined,
      _ => Icons.receipt_long_outlined,
    };
  }

  static String _textoErro(Object e) {
    var texto = e.toString().trim();
    for (final prefixo in const [
      'PostgrestException: ',
      'StateError: ',
      'Bad state: ',
      'ArgumentError: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto.isEmpty ? 'Falha ao calcular o DRE.' : texto;
  }

  static const _ordemGrupos = <String>[
    'Receita Bruta',
    'Deduções',
    'Custos Variáveis',
    'Despesas Operacionais',
    'Resultado Financeiro',
    'Outras Receitas',
    'Outras Despesas',
  ];
}

class _IndicadorDre extends StatelessWidget {
  const _IndicadorDre({
    required this.titulo,
    required this.valor,
    required this.icon,
  });

  final String titulo;
  final String valor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 238,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ImperiumWebTheme.accentStrong),
              const SizedBox(height: 14),
              Text(
                titulo,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFAAB3BD),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.08),
        border: Border.all(
          color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.22),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ImperiumWebTheme.accentStrong),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
