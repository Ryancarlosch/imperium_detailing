import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/crm_operacao_repository.dart';

class CrmDesempenhoPage extends StatefulWidget {
  const CrmDesempenhoPage({super.key});

  @override
  State<CrmDesempenhoPage> createState() => _CrmDesempenhoPageState();
}

class _CrmDesempenhoPageState extends State<CrmDesempenhoPage> {
  final CrmOperacaoRepository _repository = CrmOperacaoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _mesAno = DateFormat('MMMM yyyy', 'pt_BR');

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool _carregando = true;
  CrmDesempenhoResumo? _resumo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    final inicio = DateTime(_mes.year, _mes.month, 1);
    final fim = DateTime(_mes.year, _mes.month + 1, 0);
    try {
      final resumo = await _repository.carregarDesempenho(
        inicio: inicio,
        fim: fim,
      );
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar o desempenho do CRM.\n$erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
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
    if (proximo.isAfter(atual)) return;
    setState(() => _mes = proximo);
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    final atual = DateTime(DateTime.now().year, DateTime.now().month);
    final podeAvancar =
        DateTime(_mes.year, _mes.month + 1).compareTo(atual) <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Desempenho do CRM'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando && resumo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Mês anterior',
                          onPressed: _mesAnterior,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(
                            _capitalizar(_mesAno.format(_mes)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Mês seguinte',
                          onPressed: podeAvancar ? _mesSeguinte : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (resumo == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum dado disponível para o período.'),
                    ),
                  )
                else ...[
                  _cardFunil(resumo),
                  const SizedBox(height: 12),
                  _cardOrcamentos(resumo),
                  const SizedBox(height: 12),
                  _cardOrigens(resumo),
                  const SizedBox(height: 12),
                  _cardPerdas(resumo),
                  const SizedBox(height: 12),
                  _cardCampanhas(resumo),
                ],
              ],
            ),
    );
  }

  Widget _cardFunil(CrmDesempenhoResumo resumo) {
    return _Secao(
      titulo: 'Funil comercial',
      subtitulo: 'Leads criados no mês e situação atual dessas oportunidades.',
      icone: Icons.account_tree_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Indicador(titulo: 'Leads', valor: '${resumo.leadsCriados}'),
            _Indicador(titulo: 'Ganhos', valor: '${resumo.ganhos}'),
            _Indicador(titulo: 'Perdidos', valor: '${resumo.perdidos}'),
            _Indicador(titulo: 'Abertos', valor: '${resumo.abertos}'),
            _Indicador(
              titulo: 'Conversão',
              valor: '${resumo.conversaoLeads.toStringAsFixed(1)}%',
            ),
            _Indicador(
              titulo: 'Potencial',
              valor: _moeda.format(resumo.valorPotencial),
            ),
            _Indicador(
              titulo: 'Potencial ganho',
              valor: _moeda.format(resumo.valorGanho),
            ),
            _Indicador(
              titulo: 'Ações concluídas',
              valor: '${resumo.acoesConcluidas}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _cardOrcamentos(CrmDesempenhoResumo resumo) {
    return _Secao(
      titulo: 'Orçamentos',
      subtitulo: 'Orçamentos emitidos no mês e aprovação registrada.',
      icone: Icons.request_quote_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Indicador(
              titulo: 'Emitidos',
              valor: '${resumo.orcamentosCriados}',
            ),
            _Indicador(
              titulo: 'Aprovados',
              valor: '${resumo.orcamentosAprovados}',
            ),
            _Indicador(
              titulo: 'Taxa aprovação',
              valor: '${resumo.aprovacaoOrcamentos.toStringAsFixed(1)}%',
            ),
            _Indicador(
              titulo: 'Valor emitido',
              valor: _moeda.format(resumo.valorOrcamentos),
            ),
            _Indicador(
              titulo: 'Valor aprovado',
              valor: _moeda.format(resumo.valorOrcamentosAprovados),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cardOrigens(CrmDesempenhoResumo resumo) {
    return _Secao(
      titulo: 'Origem dos leads',
      subtitulo: 'Mostra quais canais estão trazendo oportunidades e ganhos.',
      icone: Icons.travel_explore_outlined,
      children: [
        if (resumo.origens.isEmpty)
          const Text('Nenhum lead criado neste mês.')
        else
          ...resumo.origens.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.origem),
              subtitle: Text(
                '${item.total} lead(s) • ${item.ganhos} ganho(s) • '
                '${item.conversao.toStringAsFixed(1)}% conversão',
              ),
              trailing: Text(
                _moeda.format(item.valorGanho),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardPerdas(CrmDesempenhoResumo resumo) {
    return _Secao(
      titulo: 'Motivos de perda',
      subtitulo:
          'Ajuda a identificar preço, prazo, concorrência e outros gargalos.',
      icone: Icons.trending_down_outlined,
      children: [
        if (resumo.motivosPerda.isEmpty)
          const Text('Nenhuma oportunidade perdida registrada neste mês.')
        else
          ...resumo.motivosPerda.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.motivo),
              trailing: CircleAvatar(
                radius: 16,
                child: Text('${item.quantidade}'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardCampanhas(CrmDesempenhoResumo resumo) {
    return _Secao(
      titulo: 'Campanhas e benefícios',
      subtitulo: 'Receita atribuída considera OS vinculadas a cupons usados.',
      icone: Icons.campaign_outlined,
      children: [
        if (resumo.campanhas.isEmpty)
          const Text('Nenhum cupom gerado no período.')
        else
          ...resumo.campanhas.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.nome),
              subtitle: Text(
                '${item.gerados} gerado(s) • ${item.ativos} ativo(s) • '
                '${item.usados} usado(s) • ${item.expirados} expirado(s)',
              ),
              trailing: Text(
                _moeda.format(item.receitaAtribuida),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) return texto;
    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }
}

class _Secao extends StatelessWidget {
  const _Secao({
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
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          color: Colors.white60,
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

class _Indicador extends StatelessWidget {
  const _Indicador({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
