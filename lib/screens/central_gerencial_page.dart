import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../repositories/central_gerencial_repository.dart';

class CentralGerencialPage extends StatefulWidget {
  const CentralGerencialPage({super.key});

  @override
  State<CentralGerencialPage> createState() => _CentralGerencialPageState();
}

enum _PeriodoGerencial { mesAtual, ultimos30Dias, anoAtual, personalizado }

class _CentralGerencialPageState extends State<CentralGerencialPage> {
  final CentralGerencialRepository _repository = CentralGerencialRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _numero = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final DateFormat _mesAno = DateFormat('MMM/yy', 'pt_BR');

  _PeriodoGerencial _periodo = _PeriodoGerencial.mesAtual;
  DateTimeRange? _personalizado;
  bool _carregando = true;
  String? _erro;
  CentralGerencialResumo? _resumo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  (DateTime, DateTime) _periodoAtual() {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    switch (_periodo) {
      case _PeriodoGerencial.mesAtual:
        return (DateTime(hoje.year, hoje.month, 1), hoje);
      case _PeriodoGerencial.ultimos30Dias:
        return (hoje.subtract(const Duration(days: 29)), hoje);
      case _PeriodoGerencial.anoAtual:
        return (DateTime(hoje.year, 1, 1), hoje);
      case _PeriodoGerencial.personalizado:
        final faixa = _personalizado;
        if (faixa == null) {
          return (DateTime(hoje.year, hoje.month, 1), hoje);
        }
        return (faixa.start, faixa.end);
    }
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final periodo = _periodoAtual();
      final resumo = await _repository.carregar(
        inicio: periodo.$1,
        fim: periodo.$2,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() {
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  Future<void> _selecionarPersonalizado() async {
    final agora = DateTime.now();
    final inicial =
        _personalizado ??
        DateTimeRange(
          start: DateTime(agora.year, agora.month, 1),
          end: DateTime(agora.year, agora.month, agora.day),
        );
    final escolhido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(agora.year + 2, 12, 31),
      initialDateRange: inicial,
      helpText: 'Período da Central Gerencial',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (escolhido == null || !mounted) {
      return;
    }
    setState(() {
      _periodo = _PeriodoGerencial.personalizado;
      _personalizado = escolhido;
    });
    await _carregar();
  }

  Future<void> _copiarResumo() async {
    final resumo = _resumo;
    if (resumo == null) {
      return;
    }

    final buffer = StringBuffer()
      ..writeln('IMPERIUM MANAGER - CENTRAL GERENCIAL')
      ..writeln(
        'Período: ${_data.format(resumo.inicio)} a ${_data.format(resumo.fim)}',
      )
      ..writeln(
        'Comparação: ${_data.format(resumo.inicioAnterior)} a ${_data.format(resumo.fimAnterior)}',
      )
      ..writeln('');

    for (final indicador in resumo.indicadores) {
      buffer.writeln(
        '- ${indicador.titulo}: ${_formatarIndicador(indicador)} '
        '(${_formatarVariacao(indicador)})',
      );
    }

    buffer
      ..writeln('')
      ..writeln('FINANCEIRO')
      ..writeln('- Saldo em contas: ${_moeda.format(resumo.saldoContas)}')
      ..writeln('- A receber: ${_moeda.format(resumo.aReceber)}')
      ..writeln('- Vencido: ${_moeda.format(resumo.vencido)}')
      ..writeln('')
      ..writeln('OPERAÇÃO')
      ..writeln('- Estoque: ${_moeda.format(resumo.valorEstoque)}')
      ..writeln('- Estoque baixo: ${resumo.itensEstoqueBaixo}')
      ..writeln('- Estoque zerado: ${resumo.itensEstoqueZerado}')
      ..writeln('- Serviços abaixo do mínimo: ${resumo.servicosAbaixoMinimo}')
      ..writeln(
        '- Horas trabalhadas: ${resumo.horasTrabalhadas.toStringAsFixed(1)}h',
      )
      ..writeln('')
      ..writeln('ALERTAS');

    for (final alerta in resumo.alertas) {
      buffer.writeln('- ${alerta.titulo}: ${alerta.detalhe}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Resumo gerencial copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Central Gerencial'),
        actions: [
          IconButton(
            tooltip: 'Copiar resumo',
            onPressed: _resumo == null ? null : _copiarResumo,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
          children: [
            _filtros(),
            const SizedBox(height: 14),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              _erroCard()
            else if (_resumo != null)
              ..._conteudo(_resumo!),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Período de análise',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _periodoChip(_PeriodoGerencial.mesAtual, 'Mês atual'),
                _periodoChip(
                  _PeriodoGerencial.ultimos30Dias,
                  'Últimos 30 dias',
                ),
                _periodoChip(_PeriodoGerencial.anoAtual, 'Ano atual'),
                ActionChip(
                  avatar: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _periodo == _PeriodoGerencial.personalizado &&
                            _personalizado != null
                        ? '${_data.format(_personalizado!.start)} – ${_data.format(_personalizado!.end)}'
                        : 'Personalizado',
                  ),
                  onPressed: _selecionarPersonalizado,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodoChip(_PeriodoGerencial periodo, String texto) {
    return ChoiceChip(
      label: Text(texto),
      selected: _periodo == periodo,
      onSelected: (_) async {
        if (_periodo == periodo) {
          return;
        }
        setState(() {
          _periodo = periodo;
        });
        await _carregar();
      },
    );
  }

  List<Widget> _conteudo(CentralGerencialResumo resumo) {
    return [
      _cabecalhoPeriodo(resumo),
      const SizedBox(height: 14),
      _kpis(resumo),
      const SizedBox(height: 14),
      _alertas(resumo),
      const SizedBox(height: 14),
      _financeiro(resumo),
      const SizedBox(height: 14),
      _operacao(resumo),
      const SizedBox(height: 14),
      _topServicos(resumo),
      const SizedBox(height: 14),
      _evolucao(resumo),
    ];
  }

  Widget _cabecalhoPeriodo(CentralGerencialResumo resumo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.insights_outlined,
            color: Color(0xFFD6A84B),
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visão executiva do negócio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_data.format(resumo.inicio)} a ${_data.format(resumo.fim)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  'Comparado com ${_data.format(resumo.inicioAnterior)} a ${_data.format(resumo.fimAnterior)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(CentralGerencialResumo resumo) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final colunas = largura >= 900
            ? 4
            : largura >= 560
            ? 3
            : 2;
        final larguraCard = (largura - (colunas - 1) * 10) / colunas;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: resumo.indicadores
              .map(
                (indicador) => SizedBox(
                  width: larguraCard,
                  child: _KpiCard(
                    titulo: indicador.titulo,
                    valor: _formatarIndicador(indicador),
                    variacao: _formatarVariacao(indicador),
                    evoluiu: indicador.evoluiu,
                    neutro: indicador.diferenca.abs() <= 0.000001,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _alertas(CentralGerencialResumo resumo) {
    return _SecaoCard(
      titulo: 'Alertas gerenciais',
      subtitulo: 'Gatilhos automáticos para decisões que merecem atenção.',
      icone: Icons.notifications_active_outlined,
      children: resumo.alertas.map((alerta) => _alertaTile(alerta)).toList(),
    );
  }

  Widget _alertaTile(CentralGerencialAlerta alerta) {
    final (icone, cor) = switch (alerta.nivel) {
      CentralGerencialAlertaNivel.critico => (
        Icons.error_outline,
        Colors.redAccent,
      ),
      CentralGerencialAlertaNivel.atencao => (
        Icons.warning_amber_rounded,
        Colors.orangeAccent,
      ),
      CentralGerencialAlertaNivel.oportunidade => (
        Icons.trending_up_rounded,
        Colors.greenAccent,
      ),
      CentralGerencialAlertaNivel.informacao => (
        Icons.info_outline,
        Colors.lightBlueAccent,
      ),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone, color: cor),
      title: Text(
        alerta.titulo,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(alerta.detalhe),
    );
  }

  Widget _financeiro(CentralGerencialResumo resumo) {
    return _SecaoCard(
      titulo: 'Financeiro e estrutura',
      subtitulo:
          'Posição financeira e custos estruturais do mês de referência.',
      icone: Icons.account_balance_wallet_outlined,
      children: [
        _linha('Saldo disponível em contas', _moeda.format(resumo.saldoContas)),
        _linha('A receber', _moeda.format(resumo.aReceber)),
        _linha(
          'Vencido',
          _moeda.format(resumo.vencido),
          alerta: resumo.vencido > 0,
        ),
        const Divider(height: 22),
        _linha(
          'Receita prevista no mês',
          _moeda.format(resumo.receitaPrevistaMes),
        ),
        _linha(
          'Receita realizada no mês',
          _moeda.format(resumo.receitaRealizadaMes),
        ),
        _linha(
          'Despesa prevista no mês',
          _moeda.format(resumo.despesaPrevistaMes),
        ),
        _linha(
          'Despesa realizada no mês',
          _moeda.format(resumo.despesaRealizadaMes),
        ),
        const Divider(height: 22),
        _linha('Custos fixos mensais', _moeda.format(resumo.custoFixoMensal)),
        _linha('Mão de obra mensal', _moeda.format(resumo.custoMaoObraMensal)),
      ],
    );
  }

  Widget _operacao(CentralGerencialResumo resumo) {
    return _SecaoCard(
      titulo: 'Operação, estoque e equipe',
      subtitulo: 'Capacidade operacional e riscos que afetam margem e entrega.',
      icone: Icons.precision_manufacturing_outlined,
      children: [
        _linha('Valor estimado em estoque', _moeda.format(resumo.valorEstoque)),
        _linha(
          'Itens com estoque baixo',
          _numero.format(resumo.itensEstoqueBaixo),
          alerta: resumo.itensEstoqueBaixo > 0,
        ),
        _linha(
          'Itens zerados',
          _numero.format(resumo.itensEstoqueZerado),
          alerta: resumo.itensEstoqueZerado > 0,
        ),
        const Divider(height: 22),
        _linha(
          'Serviços abaixo do preço mínimo',
          _numero.format(resumo.servicosAbaixoMinimo),
          alerta: resumo.servicosAbaixoMinimo > 0,
        ),
        _linha(
          'Potencial de reajuste unitário',
          _moeda.format(resumo.potencialReajuste),
        ),
        const Divider(height: 22),
        _linha(
          'Horas trabalhadas',
          '${resumo.horasTrabalhadas.toStringAsFixed(1)}h',
        ),
        _linha('Horas extras', '${resumo.horasExtras.toStringAsFixed(1)}h'),
        _linha(
          'Horas faltantes',
          '${resumo.horasFaltantes.toStringAsFixed(1)}h',
          alerta: resumo.horasFaltantes >= 8,
        ),
        _linha(
          'Faltas',
          _numero.format(resumo.faltas),
          alerta: resumo.faltas > 0,
        ),
      ],
    );
  }

  Widget _topServicos(CentralGerencialResumo resumo) {
    return _SecaoCard(
      titulo: 'Serviços com maior receita',
      subtitulo:
          'Ranking do período com resultado e margem gerencial estimada.',
      icone: Icons.workspace_premium_outlined,
      children: resumo.topServicos.isEmpty
          ? const [Text('Nenhuma OS finalizada com serviços no período.')]
          : [
              for (var i = 0; i < resumo.topServicos.length; i++)
                _servicoTile(i + 1, resumo.topServicos[i]),
            ],
    );
  }

  Widget _servicoTile(int posicao, CentralGerencialServico item) {
    final margemOk = item.margem >= 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        child: Text('$posicao'),
      ),
      title: Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_quantidade(item.quantidade)} venda(s) • resultado ${_moeda.format(item.resultado)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _moeda.format(item.receita),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            '${item.margem.toStringAsFixed(1)}%',
            style: TextStyle(
              color: margemOk ? Colors.greenAccent : Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evolucao(CentralGerencialResumo resumo) {
    final itens = resumo.evolucaoMensal;
    final maiorReceita = itens.fold<double>(
      0,
      (maior, item) => item.receita > maior ? item.receita : maior,
    );

    return _SecaoCard(
      titulo: 'Evolução mensal',
      subtitulo: 'Receita e resultado gerencial do ano de referência.',
      icone: Icons.show_chart_rounded,
      children: itens.isEmpty
          ? const [Text('Ainda não há histórico mensal suficiente.')]
          : [
              for (final item in itens)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 58,
                            child: Text(
                              _mesAno.format(DateTime(item.ano, item.mes)),
                            ),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: maiorReceita <= 0
                                  ? 0
                                  : (item.receita / maiorReceita)
                                        .clamp(0, 1)
                                        .toDouble(),
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 92,
                            child: Text(
                              _moeda.format(item.receita),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 58, top: 3),
                        child: Text(
                          'Resultado ${_moeda.format(item.resultado)} • margem ${item.margem.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
  }

  Widget _linha(String titulo, String valor, {bool alerta = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo, style: const TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 12),
          Text(
            valor,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: alerta ? Colors.orangeAccent : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _erroCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 10),
            const Text('Não foi possível montar a visão gerencial.'),
            const SizedBox(height: 6),
            Text(_erro ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatarIndicador(CentralGerencialComparativo indicador) {
    if (indicador.percentual) {
      return '${indicador.atual.toStringAsFixed(1)}%';
    }
    if (indicador.inteiro) {
      return _numero.format(indicador.atual.round());
    }
    return _moeda.format(indicador.atual);
  }

  String _formatarVariacao(CentralGerencialComparativo indicador) {
    final variacao = indicador.variacaoPercentual;
    if (variacao == null) {
      return 'sem base anterior';
    }
    final prefixo = variacao > 0 ? '+' : '';
    return '$prefixo${variacao.toStringAsFixed(1)}% vs. anterior';
  }

  String _quantidade(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }
    return valor.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto.length > 700 ? texto.substring(0, 700) : texto;
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.titulo,
    required this.valor,
    required this.variacao,
    required this.evoluiu,
    required this.neutro,
  });

  final String titulo;
  final String valor;
  final String variacao;
  final bool evoluiu;
  final bool neutro;

  @override
  Widget build(BuildContext context) {
    final cor = neutro
        ? Colors.white54
        : evoluiu
        ? Colors.greenAccent
        : Colors.orangeAccent;
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const Spacer(),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                neutro
                    ? Icons.remove_rounded
                    : evoluiu
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 15,
                color: cor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  variacao,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cor, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecaoCard extends StatelessWidget {
  const _SecaoCard({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.children,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: const Color(0xFFD6A84B)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
