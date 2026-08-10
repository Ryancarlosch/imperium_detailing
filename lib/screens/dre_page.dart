import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dre_repository.dart';
import '../repositories/precificacao_repository.dart';

class DrePage extends StatefulWidget {
  const DrePage({super.key});

  @override
  State<DrePage> createState() => _DrePageState();
}

class _DrePageState extends State<DrePage> {
  final DreRepository _repository = DreRepository();
  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  DreRegime _regime = DreRegime.competencia;
  DateTimeRange _periodo = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
  );
  bool _carregando = true;
  DreResultado? _resultado;
  List<DreServicoResultado> _servicos = const [];
  Map<String, PrecificacaoServico> _precificacaoPorServico = const {};
  double _margemAlvoPrecificacao = 0;

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
      PrecificacaoPainel? precificacao;

      if (_regime == DreRegime.competencia) {
        try {
          precificacao = await _precificacaoRepository.carregar();
        } catch (_) {
          // A DRE continua funcionando mesmo se a precificação ainda não
          // puder ser carregada. Nesse caso apenas escondemos a comparação.
        }
      }

      final resultadoFuture = _repository.calcular(
        inicio: _periodo.start,
        fim: _periodo.end,
        regime: _regime,
      );
      final Future<List<DreServicoResultado>> servicosFuture =
          _regime == DreRegime.competencia
          ? _repository.listarResultadoServicos(
              inicio: _periodo.start,
              fim: _periodo.end,
            )
          : Future.value(const <DreServicoResultado>[]);

      final resultado = await resultadoFuture;
      final servicos = await servicosFuture;

      if (!mounted) return;

      final mapaPrecificacao = <String, PrecificacaoServico>{};
      if (precificacao != null) {
        for (final item in precificacao.servicos) {
          mapaPrecificacao[item.nome.trim().toLowerCase()] = item;
        }
      }

      setState(() {
        _resultado = resultado;
        _servicos = servicos;
        _precificacaoPorServico = mapaPrecificacao;
        _margemAlvoPrecificacao =
            precificacao?.config.margemCliente ?? 0;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Não foi possível calcular a DRE.\n$erro'),
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
      helpText: _regime == DreRegime.competencia
          ? 'Período da DRE'
          : 'Período da visão de caixa',
      saveText: 'Aplicar',
      cancelText: 'Cancelar',
    );

    if (novo == null || !mounted) return;

    setState(() => _periodo = novo);
    await _carregar();
  }

  void _mostrarDetalhes({
    required String titulo,
    required List<String> grupos,
    required DreResultado resultado,
    String? explicacao,
  }) {
    final itens = resultado.detalhes
        .where((item) => grupos.contains(item.grupo))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) {
        final alturaMaxima = MediaQuery.sizeOf(bottomContext).height * 0.78;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: alturaMaxima),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (explicacao != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    explicacao,
                    style: TextStyle(
                      color: Theme.of(
                        bottomContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (itens.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      'Nenhum lançamento compõe este valor no período.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: itens.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = itens[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.nome),
                          subtitle: Text(
                            '${_nomeAmigavelGrupo(item.grupo)} • Toque para rastrear',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _moeda.format(item.valor),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.chevron_right_rounded, size: 19),
                            ],
                          ),
                          onTap: () async {
                            Navigator.of(bottomContext).pop();
                            await _mostrarOrigens(item);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _mostrarOrigens(DreDetalhe detalhe) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<DreOrigemDetalhe> origens;
    try {
      origens = await _repository.listarOrigens(
        detalhe: detalhe,
        inicio: _periodo.start,
        fim: _periodo.end,
        regime: _regime,
      );
    } catch (erro) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Não foi possível abrir as origens.\n$erro'),
              backgroundColor: Colors.red.shade700,
            ),
          );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) {
        final alturaMaxima = MediaQuery.sizeOf(bottomContext).height * 0.86;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: alturaMaxima),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  detalhe.nome,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Origem dos ${_moeda.format(detalhe.valor)}',
                  style: TextStyle(
                    color: Theme.of(
                      bottomContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (origens.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Text(
                      'Não foi possível localizar lançamentos individuais '
                      'para este total.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  _ResumoOrigens(
                    quantidade: origens.length,
                    total: origens.fold<double>(
                      0,
                      (soma, item) => soma + item.valor,
                    ),
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: origens.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final origem = origens[index];
                        return _OrigemTile(
                          origem: origem,
                          moeda: _moeda,
                          formatarData: _formatarDataOrigem,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }


  Future<void> _mostrarOrdensServico(DreServicoResultado servico) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<DreServicoOrdem> ordens;
    try {
      ordens = await _repository.listarOrdensServico(
        servico: servico.servico,
        inicio: _periodo.start,
        fim: _periodo.end,
      );
    } catch (erro) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Não foi possível abrir as OS deste serviço.\n$erro',
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) {
        final alturaMaxima = MediaQuery.sizeOf(bottomContext).height * 0.88;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: alturaMaxima),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  servico.servico,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${servico.quantidadeOrdens} OS • '
                  'Resultado gerencial '
                  '${_moeda.format(servico.resultadoGerencialEstimado)}',
                  style: TextStyle(
                    color: Theme.of(
                      bottomContext,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (ordens.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Text(
                      'Nenhuma Ordem de Serviço encontrada para este serviço '
                      'no período.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: ordens.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final ordem = ordens[index];
                        final data = _formatarDataOrigem(ordem.data);

                        return ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.fromLTRB(
                            8,
                            0,
                            8,
                            10,
                          ),
                          title: Text(
                            ordem.numero,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (ordem.cliente.isNotEmpty) ordem.cliente,
                              if (data.isNotEmpty) data,
                              'Qtd. ${_quantidadeServico(ordem.quantidade)}',
                            ].join(' • '),
                          ),
                          trailing: Text(
                            _moeda.format(ordem.resultadoGerencialEstimado),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: ordem.resultadoGerencialEstimado >= 0
                                  ? Colors.green.shade500
                                  : Colors.red.shade400,
                            ),
                          ),
                          children: [
                            _LinhaValorServico(
                              titulo: 'Faturamento bruto',
                              valor: ordem.faturamentoBruto,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Descontos rateados',
                              valor: -ordem.descontos,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Receita líquida',
                              valor: ordem.receitaLiquida,
                              moeda: _moeda,
                              destaque: true,
                            ),
                            _LinhaValorServico(
                              titulo: 'Produtos rateados',
                              valor: -ordem.custoProdutos,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Taxas rateadas',
                              valor: -ordem.taxasCartao,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Resultado comercial',
                              valor: ordem.resultadoComercial,
                              moeda: _moeda,
                              destaque: true,
                              complemento:
                                  'Margem ${_percentual(ordem.margemComercial)}',
                            ),
                            const Divider(height: 18),
                            _LinhaValorServico(
                              titulo: 'Horas gerenciais',
                              valor: ordem.horasGerenciais,
                              moeda: _moeda,
                              texto:
                                  '${_quantidadeServico(ordem.horasGerenciais)}h',
                            ),
                            _LinhaValorServico(
                              titulo: 'Mão de obra estimada',
                              valor: -ordem.custoMaoObraGerencial,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Estrutura rateada',
                              valor: -ordem.custoEstruturaRateada,
                              moeda: _moeda,
                            ),
                            _LinhaValorServico(
                              titulo: 'Resultado gerencial estimado',
                              valor: ordem.resultadoGerencialEstimado,
                              moeda: _moeda,
                              destaque: true,
                              complemento:
                                  'Margem ${_percentual(ordem.margemGerencial)}',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _quantidadeServico(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }

    return valor
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _formatarDataOrigem(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return '';

    final data = DateTime.tryParse(texto);
    if (data == null) return texto;

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  String _nomeAmigavelGrupo(String grupo) {
    switch (grupo) {
      case 'Receita Bruta':
        return 'Faturamento';
      case 'Deduções':
        return 'Descontos e deduções';
      case 'Custos Variáveis':
        return 'Custos das vendas';
      case 'Despesas Operacionais':
        return 'Despesas da empresa';
      case 'Resultado Financeiro':
        return 'Tarifas, juros e resultado financeiro';
      case 'Outras Receitas':
        return 'Outras receitas';
      case 'Outras Despesas':
        return 'Outras despesas';
      default:
        return grupo;
    }
  }

  double _despesasEmpresa(DreResultado resultado) {
    return resultado.despesasOperacionais +
        resultado.resultadoFinanceiro +
        resultado.outrasDespesas;
  }

  double _margemContribuicaoPercentual(DreResultado resultado) {
    if (resultado.receitaLiquida.abs() <= 0.000001) {
      return 0;
    }

    return (resultado.margemContribuicao / resultado.receitaLiquida) * 100;
  }

  String _percentual(double valor) {
    return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  @override
  Widget build(BuildContext context) {
    final resultado = _resultado;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _regime == DreRegime.competencia ? 'DRE gerencial' : 'Visão de caixa',
        ),
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
          : resultado == null
          ? const Center(child: Text('Não foi possível calcular a DRE.'))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
                children: [
                  SegmentedButton<DreRegime>(
                    segments: const [
                      ButtonSegment(
                        value: DreRegime.competencia,
                        icon: Icon(Icons.assessment_outlined),
                        label: Text('DRE'),
                      ),
                      ButtonSegment(
                        value: DreRegime.caixa,
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        label: Text('Caixa'),
                      ),
                    ],
                    selected: {_regime},
                    onSelectionChanged: (selecionado) {
                      setState(() => _regime = selecionado.first);
                      _carregar();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ExplicacaoRegime(regime: _regime),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _selecionarPeriodo,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      '${_data.format(_periodo.start)} até '
                      '${_data.format(_periodo.end)}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ResultadoPrincipal(
                    resultado: resultado,
                    moeda: _moeda,
                    regime: _regime,
                    percentual: _percentual,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _regime == DreRegime.competencia
                        ? 'Como chegamos ao resultado'
                        : 'Como o caixa se comportou',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque em uma linha para ver o que compõe o valor.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BlocoDre(
                    titulo: _regime == DreRegime.competencia
                        ? 'Faturamento bruto'
                        : 'Entradas reconhecidas',
                    valor: resultado.receitaBruta,
                    moeda: _moeda,
                    icone: Icons.trending_up_rounded,
                    onTap: () => _mostrarDetalhes(
                      titulo: _regime == DreRegime.competencia
                          ? 'Faturamento bruto'
                          : 'Entradas reconhecidas',
                      grupos: const ['Receita Bruta'],
                      resultado: resultado,
                      explicacao: _regime == DreRegime.competencia
                          ? 'Vendas e serviços reconhecidos no período.'
                          : 'Receitas consideradas pelo regime de caixa.',
                    ),
                  ),
                  if (resultado.deducoes.abs() > 0.000001)
                    _BlocoDre(
                      titulo: 'Descontos e deduções',
                      valor: -resultado.deducoes,
                      moeda: _moeda,
                      icone: Icons.remove_circle_outline,
                      compacto: true,
                      onTap: () => _mostrarDetalhes(
                        titulo: 'Descontos e deduções',
                        grupos: const ['Deduções'],
                        resultado: resultado,
                      ),
                    ),
                  _BlocoDre(
                    titulo: _regime == DreRegime.competencia
                        ? 'Receita líquida'
                        : 'Entradas líquidas',
                    valor: resultado.receitaLiquida,
                    moeda: _moeda,
                    icone: Icons.payments_outlined,
                    destaque: true,
                  ),
                  if (_regime == DreRegime.competencia) ...[
                    const SizedBox(height: 8),
                    _ResultadoServicosSection(
                      servicos: _servicos,
                      precificacaoPorServico: _precificacaoPorServico,
                      margemAlvoPrecificacao: _margemAlvoPrecificacao,
                      moeda: _moeda,
                      percentual: _percentual,
                      quantidade: _quantidadeServico,
                      onAbrirOrdens: _mostrarOrdensServico,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _BlocoDre(
                    titulo: 'Custos das vendas',
                    valor: -resultado.custosVariaveis,
                    moeda: _moeda,
                    icone: Icons.inventory_2_outlined,
                    onTap: () => _mostrarDetalhes(
                      titulo: 'Custos das vendas',
                      grupos: const ['Custos Variáveis'],
                      resultado: resultado,
                      explicacao:
                          'Produtos consumidos, taxas de cartão, comissões e '
                          'outros custos diretamente ligados às vendas.',
                    ),
                  ),
                  _BlocoDre(
                    titulo: _regime == DreRegime.competencia
                        ? 'Margem de contribuição'
                        : 'Caixa após custos das vendas',
                    valor: resultado.margemContribuicao,
                    moeda: _moeda,
                    icone: Icons.pie_chart_outline_rounded,
                    destaque: true,
                    complemento: _regime == DreRegime.competencia
                        ? _percentual(
                            _margemContribuicaoPercentual(resultado),
                          )
                        : 'Sobre entradas '
                              '${_percentual(_margemContribuicaoPercentual(resultado))}',
                  ),
                  const SizedBox(height: 8),
                  _BlocoDre(
                    titulo: 'Despesas da empresa',
                    valor: -_despesasEmpresa(resultado),
                    moeda: _moeda,
                    icone: Icons.business_outlined,
                    onTap: () => _mostrarDetalhes(
                      titulo: 'Despesas da empresa',
                      grupos: const [
                        'Despesas Operacionais',
                        'Resultado Financeiro',
                        'Outras Despesas',
                      ],
                      resultado: resultado,
                      explicacao:
                          'Estrutura da empresa, tarifas, juros e demais '
                          'despesas reconhecidas no período.',
                    ),
                  ),
                  if (resultado.outrasReceitas.abs() > 0.000001)
                    _BlocoDre(
                      titulo: 'Outras receitas',
                      valor: resultado.outrasReceitas,
                      moeda: _moeda,
                      icone: Icons.add_circle_outline,
                      compacto: true,
                      onTap: () => _mostrarDetalhes(
                        titulo: 'Outras receitas',
                        grupos: const ['Outras Receitas'],
                        resultado: resultado,
                      ),
                    ),
                  const SizedBox(height: 8),
                  _BlocoDre(
                    titulo: _regime == DreRegime.competencia
                        ? 'Resultado do período'
                        : 'Resultado de caixa',
                    valor: resultado.resultadoGerencial,
                    moeda: _moeda,
                    icone: resultado.resultadoGerencial >= 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    destaqueFinal: true,
                    complemento: _regime == DreRegime.competencia
                        ? 'Margem ${_percentual(resultado.margemPercentual)}'
                        : 'Sobre entradas '
                              '${_percentual(resultado.margemPercentual)}',
                  ),
                  const SizedBox(height: 20),
                  _DetalhamentoCompleto(
                    resultado: resultado,
                    moeda: _moeda,
                    nomeGrupo: _nomeAmigavelGrupo,
                    onDetalheTap: _mostrarOrigens,
                  ),
                  const SizedBox(height: 12),
                  _NotaDre(regime: _regime),
                ],
              ),
            ),
    );
  }
}


class _ResultadoServicosSection extends StatelessWidget {
  const _ResultadoServicosSection({
    required this.servicos,
    required this.precificacaoPorServico,
    required this.margemAlvoPrecificacao,
    required this.moeda,
    required this.percentual,
    required this.quantidade,
    required this.onAbrirOrdens,
  });

  final List<DreServicoResultado> servicos;
  final Map<String, PrecificacaoServico> precificacaoPorServico;
  final double margemAlvoPrecificacao;
  final NumberFormat moeda;
  final String Function(double) percentual;
  final String Function(double) quantidade;
  final Future<void> Function(DreServicoResultado) onAbrirOrdens;

  @override
  Widget build(BuildContext context) {
    final faturamentoServicos = servicos.fold<double>(
      0,
      (soma, item) => soma + item.faturamentoBruto,
    );
    final resultadoComercial = servicos.fold<double>(
      0,
      (soma, item) => soma + item.resultadoComercial,
    );
    final resultadoGerencial = servicos.fold<double>(
      0,
      (soma, item) => soma + item.resultadoGerencialEstimado,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.design_services_outlined),
        title: const Text(
          'Rentabilidade por serviço',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: servicos.isEmpty
            ? const Text('Nenhum serviço finalizado no período')
            : Text(
                '${servicos.length} serviços • '
                '${moeda.format(faturamentoServicos)} faturados',
              ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              servicos.isEmpty
                  ? 'O detalhamento aparecerá quando houver serviços em '
                        'Ordens de Serviço finalizadas no período.'
                  : 'O resultado comercial desconta produtos e taxas. '
                        'O gerencial também considera mão de obra estimada e '
                        'estrutura rateada. É uma análise interna e não lança '
                        'esses custos novamente na DRE. '
                        'Comercial: ${moeda.format(resultadoComercial)} • '
                        'Gerencial: ${moeda.format(resultadoGerencial)}.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          if (servicos.isNotEmpty)
            for (var index = 0; index < servicos.length; index++) ...[
              _ServicoResultadoTile(
                posicao: index + 1,
                servico: servicos[index],
                precificacao: precificacaoPorServico[
                    servicos[index].servico.trim().toLowerCase()
                ],
                margemAlvoPrecificacao: margemAlvoPrecificacao,
                faturamentoTotalServicos: faturamentoServicos,
                moeda: moeda,
                percentual: percentual,
                quantidade: quantidade,
                onAbrirOrdens: () => onAbrirOrdens(servicos[index]),
              ),
              if (index < servicos.length - 1) const SizedBox(height: 7),
            ],
        ],
      ),
    );
  }
}

class _ServicoResultadoTile extends StatelessWidget {
  const _ServicoResultadoTile({
    required this.posicao,
    required this.servico,
    required this.precificacao,
    required this.margemAlvoPrecificacao,
    required this.faturamentoTotalServicos,
    required this.moeda,
    required this.percentual,
    required this.quantidade,
    required this.onAbrirOrdens,
  });

  final int posicao;
  final DreServicoResultado servico;
  final PrecificacaoServico? precificacao;
  final double margemAlvoPrecificacao;
  final double faturamentoTotalServicos;
  final NumberFormat moeda;
  final String Function(double) percentual;
  final String Function(double) quantidade;
  final VoidCallback onAbrirOrdens;

  @override
  Widget build(BuildContext context) {
    final participacao = faturamentoTotalServicos.abs() <= 0.000001
        ? 0.0
        : servico.faturamentoBruto / faturamentoTotalServicos * 100;
    final positivo = servico.resultadoGerencialEstimado >= 0;
    final preco = precificacao;
    final precisaRevisar = preco != null &&
        (
          preco.precoAtual < preco.precoMinimoSeguro ||
          preco.precoSugerido > preco.precoAtual * 1.05
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: CircleAvatar(
          radius: 17,
          child: Text(
            '$posicao',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          servico.servico,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${quantidade(servico.quantidade)} realizados • '
          '${servico.quantidadeOrdens} OS • '
          '${percentual(participacao)} do faturamento',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moeda.format(servico.resultadoGerencialEstimado),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: positivo
                    ? Colors.green.shade500
                    : Colors.red.shade400,
              ),
            ),
            Text(
              'gerencial ${percentual(servico.margemGerencial)}',
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        children: [
          _LinhaValorServico(
            titulo: 'Faturamento bruto',
            valor: servico.faturamentoBruto,
            moeda: moeda,
          ),
          _LinhaValorServico(
            titulo: 'Descontos rateados',
            valor: -servico.descontos,
            moeda: moeda,
          ),
          _LinhaValorServico(
            titulo: 'Receita líquida',
            valor: servico.receitaLiquida,
            moeda: moeda,
            destaque: true,
          ),
          _LinhaValorServico(
            titulo: 'Produtos rateados',
            valor: -servico.custoProdutos,
            moeda: moeda,
          ),
          _LinhaValorServico(
            titulo: 'Taxas de cartão rateadas',
            valor: -servico.taxasCartao,
            moeda: moeda,
          ),
          const Divider(height: 18),
          _LinhaValorServico(
            titulo: 'Resultado comercial',
            valor: servico.resultadoComercial,
            moeda: moeda,
            destaque: true,
            complemento: 'Margem ${percentual(servico.margemComercial)}',
          ),
          const Divider(height: 18),
          _LinhaValorServico(
            titulo: 'Horas gerenciais',
            valor: servico.horasGerenciais,
            moeda: moeda,
            texto: '${quantidade(servico.horasGerenciais)}h',
          ),
          _LinhaValorServico(
            titulo: 'Mão de obra estimada',
            valor: -servico.custoMaoObraGerencial,
            moeda: moeda,
          ),
          _LinhaValorServico(
            titulo: 'Estrutura rateada',
            valor: -servico.custoEstruturaRateada,
            moeda: moeda,
          ),
          _LinhaValorServico(
            titulo: 'Resultado gerencial estimado',
            valor: servico.resultadoGerencialEstimado,
            moeda: moeda,
            destaque: true,
            complemento: 'Margem ${percentual(servico.margemGerencial)}',
          ),
          if (preco != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: precisaRevisar
                      ? Colors.orange.withValues(alpha: 0.35)
                      : Colors.green.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        precisaRevisar
                            ? Icons.warning_amber_rounded
                            : Icons.price_check_outlined,
                        size: 19,
                        color: precisaRevisar
                            ? Colors.orange.shade500
                            : Colors.green.shade500,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          precisaRevisar
                              ? 'Precificação recomenda revisão'
                              : 'Precificação dentro da faixa',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _LinhaComparacaoPreco(
                    titulo: 'Preço atual',
                    valor: preco.precoAtual,
                    moeda: moeda,
                  ),
                  _LinhaComparacaoPreco(
                    titulo: 'Preço sugerido',
                    valor: preco.precoSugerido,
                    moeda: moeda,
                    destaque: true,
                  ),
                  _LinhaComparacaoPreco(
                    titulo: 'Margem estimada atual',
                    texto: percentual(preco.margemAtual),
                    moeda: moeda,
                  ),
                  if (margemAlvoPrecificacao > 0)
                    _LinhaComparacaoPreco(
                      titulo: 'Margem alvo',
                      texto: percentual(margemAlvoPrecificacao),
                      moeda: moeda,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAbrirOrdens,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(
                servico.quantidadeOrdens == 1
                    ? 'Ver 1 OS'
                    : 'Ver ${servico.quantidadeOrdens} OS',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaValorServico extends StatelessWidget {
  const _LinhaValorServico({
    required this.titulo,
    required this.valor,
    required this.moeda,
    this.destaque = false,
    this.complemento,
    this.texto,
  });

  final String titulo;
  final double valor;
  final NumberFormat moeda;
  final bool destaque;
  final String? complemento;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: destaque ? FontWeight.w700 : FontWeight.w400,
                    color: destaque
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (complemento != null)
                  Text(
                    complemento!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            texto ?? moeda.format(valor),
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              color: destaque && valor < 0 ? Colors.red.shade400 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaComparacaoPreco extends StatelessWidget {
  const _LinhaComparacaoPreco({
    required this.titulo,
    required this.moeda,
    this.valor,
    this.texto,
    this.destaque = false,
  });

  final String titulo;
  final NumberFormat moeda;
  final double? valor;
  final String? texto;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final valorTexto = texto ?? moeda.format(valor ?? 0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: destaque ? FontWeight.w700 : FontWeight.w400,
                color: destaque
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            valorTexto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplicacaoRegime extends StatelessWidget {
  const _ExplicacaoRegime({required this.regime});

  final DreRegime regime;

  @override
  Widget build(BuildContext context) {
    final competencia = regime == DreRegime.competencia;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            competencia
                ? Icons.lightbulb_outline_rounded
                : Icons.account_balance_wallet_outlined,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              competencia
                  ? 'DRE: mostra o resultado econômico no período em que a '
                        'venda e os custos aconteceram.'
                  : 'Caixa: mostra receitas e despesas conforme o dinheiro '
                        'foi efetivamente recebido ou pago. Não é o saldo das '
                        'contas; o saldo bancário fica no Dashboard.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultadoPrincipal extends StatelessWidget {
  const _ResultadoPrincipal({
    required this.resultado,
    required this.moeda,
    required this.regime,
    required this.percentual,
  });

  final DreResultado resultado;
  final NumberFormat moeda;
  final DreRegime regime;
  final String Function(double) percentual;

  @override
  Widget build(BuildContext context) {
    final positivo = resultado.resultadoGerencial >= 0;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              regime == DreRegime.competencia
                  ? 'Resultado do período'
                  : 'Resultado de caixa do período',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              moeda.format(resultado.resultadoGerencial),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: positivo ? Colors.green.shade500 : Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  positivo
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: positivo
                      ? Colors.green.shade500
                      : Colors.red.shade400,
                ),
                const SizedBox(width: 5),
                Text(
                  regime == DreRegime.competencia
                      ? '${positivo ? 'Positivo' : 'Negativo'} • '
                            'Margem ${percentual(resultado.margemPercentual)}'
                      : '${positivo ? 'Positivo' : 'Negativo'} • '
                            'Sobre entradas '
                            '${percentual(resultado.margemPercentual)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlocoDre extends StatelessWidget {
  const _BlocoDre({
    required this.titulo,
    required this.valor,
    required this.moeda,
    required this.icone,
    this.onTap,
    this.destaque = false,
    this.destaqueFinal = false,
    this.compacto = false,
    this.complemento,
  });

  final String titulo;
  final double valor;
  final NumberFormat moeda;
  final IconData icone;
  final VoidCallback? onTap;
  final bool destaque;
  final bool destaqueFinal;
  final bool compacto;
  final String? complemento;

  @override
  Widget build(BuildContext context) {
    final corResultado = valor >= 0
        ? Colors.green.shade500
        : Colors.red.shade400;

    return Card(
      margin: EdgeInsets.only(bottom: compacto ? 4 : 7),
      elevation: destaqueFinal ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: compacto ? 10 : destaqueFinal ? 16 : 13,
          ),
          child: Row(
            children: [
              Icon(
                icone,
                size: destaqueFinal ? 25 : 21,
                color: destaqueFinal ? corResultado : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: destaqueFinal ? 17 : 15,
                        fontWeight:
                            destaque || destaqueFinal
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    if (complemento != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        complemento!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                moeda.format(valor),
                style: TextStyle(
                  fontSize: destaqueFinal ? 18 : destaque ? 16 : 15,
                  fontWeight:
                      destaque || destaqueFinal
                      ? FontWeight.bold
                      : FontWeight.w600,
                  color: destaqueFinal ? corResultado : null,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right_rounded, size: 19),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetalhamentoCompleto extends StatelessWidget {
  const _DetalhamentoCompleto({
    required this.resultado,
    required this.moeda,
    required this.nomeGrupo,
    required this.onDetalheTap,
  });

  final DreResultado resultado;
  final NumberFormat moeda;
  final String Function(String) nomeGrupo;
  final Future<void> Function(DreDetalhe) onDetalheTap;

  Map<String, List<DreDetalhe>> _agrupar() {
    final grupos = <String, List<DreDetalhe>>{};
    for (final detalhe in resultado.detalhes) {
      grupos.putIfAbsent(detalhe.grupo, () => <DreDetalhe>[]).add(detalhe);
    }
    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agrupar();

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.manage_search_rounded),
        title: const Text(
          'Detalhamento completo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Abra para conferir a composição dos valores',
        ),
        children: grupos.entries.map((grupo) {
          final total = grupo.value.fold<double>(
            0,
            (soma, item) => soma + item.valor,
          );

          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 18),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            title: Text(nomeGrupo(grupo.key)),
            subtitle: Text(moeda.format(total)),
            children: grupo.value
                .map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.nome),
                    subtitle: const Text('Ver origem'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          moeda.format(item.valor),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                    onTap: () => onDetalheTap(item),
                  ),
                )
                .toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _ResumoOrigens extends StatelessWidget {
  const _ResumoOrigens({
    required this.quantidade,
    required this.total,
    required this.moeda,
  });

  final int quantidade;
  final double total;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              quantidade == 1
                  ? '1 origem encontrada'
                  : '$quantidade origens encontradas',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            moeda.format(total),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _OrigemTile extends StatelessWidget {
  const _OrigemTile({
    required this.origem,
    required this.moeda,
    required this.formatarData,
  });

  final DreOrigemDetalhe origem;
  final NumberFormat moeda;
  final String Function(String?) formatarData;

  @override
  Widget build(BuildContext context) {
    final data = formatarData(origem.data);
    final referencias = <String>[
      origem.tipo,
      if (data.isNotEmpty) data,
      if (origem.ordemServicoId != null) 'OS #${origem.ordemServicoId}',
      if (origem.pagamentoId != null) 'Pgto #${origem.pagamentoId}',
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(_iconeOrigem(origem.tipo), size: 19),
      ),
      title: Text(
        origem.titulo,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (origem.subtitulo.trim().isNotEmpty)
            Text(
              origem.subtitulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            referencias.join(' • '),
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Text(
        moeda.format(origem.valor),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  IconData _iconeOrigem(String tipo) {
    final texto = tipo.toLowerCase();

    if (texto.contains('produto')) {
      return Icons.inventory_2_outlined;
    }
    if (texto.contains('taxa')) {
      return Icons.credit_card_outlined;
    }
    if (texto.contains('ordem') || texto.contains('os')) {
      return Icons.receipt_long_outlined;
    }
    if (texto.contains('desconto')) {
      return Icons.sell_outlined;
    }
    return Icons.payments_outlined;
  }
}

class _NotaDre extends StatelessWidget {
  const _NotaDre({required this.regime});

  final DreRegime regime;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.withValues(alpha: 0.06),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                regime == DreRegime.competencia
                    ? 'Compras para estoque não viram custo imediatamente. '
                          'O custo do produto é reconhecido quando ele é '
                          'consumido na Ordem de Serviço.'
                    : 'Esta visão serve para acompanhar o dinheiro efetivamente '
                          'recebido e pago. Para analisar lucro e desempenho do '
                          'negócio, prefira a aba DRE.',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
