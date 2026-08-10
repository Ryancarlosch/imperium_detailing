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
  FinanceiroDashboardData? _dados;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final dados = await _repository.carregar(mes: _mes);
      if (!mounted) {
        return;
      }
      setState(() {
        _dados = dados;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  void _alterarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta, 1));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final titulo = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard financeiro'),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : dados == null
          ? const Center(child: Text('Sem dados para exibir.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _alterarMes(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        titulo[0].toUpperCase() + titulo.substring(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _alterarMes(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _KpiPrincipal(
                  titulo: 'Resultado gerencial',
                  valor: _moeda.format(dados.dreCompetencia.resultadoGerencial),
                  subtitulo:
                      'Margem ${dados.dreCompetencia.margemPercentual.toStringAsFixed(1).replaceAll('.', ',')}%',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Kpi(
                        titulo: 'Faturado no mês',
                        valor: _moeda.format(
                          dados.dreCompetencia.receitaLiquida,
                        ),
                        icone: Icons.trending_up_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Kpi(
                        titulo: 'Recebido no mês',
                        valor: _moeda.format(dados.recebido),
                        icone: Icons.payments_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Kpi(
                        titulo: 'A receber total',
                        valor: _moeda.format(dados.aReceber),
                        icone: Icons.schedule_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Kpi(
                        titulo: 'Vencido total',
                        valor: _moeda.format(dados.vencido),
                        icone: Icons.warning_amber_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Kpi(
                        titulo: 'Taxas de cartão no mês',
                        valor: _moeda.format(dados.taxas),
                        icone: Icons.credit_card_off_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Kpi(
                        titulo: 'Resultado de caixa',
                        valor: _moeda.format(
                          dados.receitaRealizada - dados.despesaRealizada,
                        ),
                        icone: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Metas do mês',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _MetaResumoCard(
                  titulo: 'Faturamento',
                  referencia: dados.dreCompetencia.receitaLiquida,
                  meta: dados.metaReceita,
                  moeda: _moeda,
                  linhas: [
                    _MetaLinha(
                      'Faturado',
                      dados.dreCompetencia.receitaLiquida,
                    ),
                    _MetaLinha('Recebido', dados.recebido),
                    _MetaLinha(
                      'Falta faturar',
                      (dados.metaReceita -
                              dados.dreCompetencia.receitaLiquida)
                          .clamp(0, double.infinity)
                          .toDouble(),
                    ),
                  ],
                ),
                _MetaResumoCard(
                  titulo: 'Limite de despesas',
                  referencia: dados.despesaPrevista > dados.despesaRealizada
                      ? dados.despesaPrevista
                      : dados.despesaRealizada,
                  meta: dados.metaDespesa,
                  moeda: _moeda,
                  linhas: [
                    _MetaLinha('Previsto', dados.despesaPrevista),
                    _MetaLinha('Pago', dados.despesaRealizada),
                    _MetaLinha(
                      'Disponível',
                      (dados.metaDespesa -
                              (dados.despesaPrevista >
                                      dados.despesaRealizada
                                  ? dados.despesaPrevista
                                  : dados.despesaRealizada))
                          .clamp(0, double.infinity)
                          .toDouble(),
                    ),
                  ],
                ),
                _MetaResumoCard(
                  titulo: 'Resultado',
                  referencia: dados.dreCompetencia.resultadoGerencial,
                  meta: dados.metaResultado,
                  moeda: _moeda,
                  linhas: [
                    _MetaLinha(
                      'Resultado atual',
                      dados.dreCompetencia.resultadoGerencial,
                    ),
                    _MetaLinha(
                      'Falta para meta',
                      (dados.metaResultado -
                              dados.dreCompetencia.resultadoGerencial)
                          .clamp(0, double.infinity)
                          .toDouble(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Estrutura de custos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Kpi(
                        titulo: 'Custos fixos p/ precificação',
                        valor: _moeda.format(dados.custoFixoMensal),
                        icone: Icons.home_work_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Kpi(
                        titulo: 'Mão de obra de referência',
                        valor: _moeda.format(dados.custoMaoObraMensal),
                        icone: Icons.engineering_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Evolução dos últimos 6 meses',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...dados.evolucao.map((item) {
                  final data = DateTime(
                    (item['ano'] as num).toInt(),
                    (item['mes'] as num).toInt(),
                    1,
                  );
                  final label = DateFormat('MMM/yy', 'pt_BR').format(data);
                  final receita = (item['receita'] as num).toDouble();
                  final resultado = (item['resultado'] as num).toDouble();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 7),
                    child: ListTile(
                      title: Text(label.toUpperCase()),
                      subtitle: Text('Receita ${_moeda.format(receita)}'),
                      trailing: Text(
                        _moeda.format(resultado),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
                if (dados.topResultadosOs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'OS com maior resultado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...dados.topResultadosOs.map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        title: Text((item['numero'] ?? 'OS').toString()),
                        subtitle: Text((item['cliente_nome'] ?? '').toString()),
                        trailing: Text(
                          _moeda.format(
                            (item['resultado_os'] as num?)?.toDouble() ?? 0,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _KpiPrincipal extends StatelessWidget {
  const _KpiPrincipal({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
  });
  final String titulo;
  final String valor;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 5),
            Text(
              valor,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(subtitulo, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.titulo, required this.valor, required this.icone});
  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: const Color(0xFFD6A84B)),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaResumoCard extends StatelessWidget {
  const _MetaResumoCard({
    required this.titulo,
    required this.referencia,
    required this.meta,
    required this.moeda,
    required this.linhas,
  });

  final String titulo;
  final double referencia;
  final double meta;
  final NumberFormat moeda;
  final List<_MetaLinha> linhas;

  @override
  Widget build(BuildContext context) {
    final progresso = meta <= 0
        ? 0.0
        : (referencia / meta).clamp(0, 1).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  meta <= 0
                      ? 'Sem meta'
                      : '${(progresso * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progresso),
            const SizedBox(height: 9),
            for (final linha in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        linha.titulo,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      moeda.format(linha.valor),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (meta > 0) ...[
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Meta',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                  Text(
                    moeda.format(meta),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLinha {
  const _MetaLinha(this.titulo, this.valor);

  final String titulo;
  final double valor;
}

