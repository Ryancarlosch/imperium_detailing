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
  DreResultado? _dre;
  List<Map<String, dynamic>> _ordens = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final resultados = await Future.wait<dynamic>([
        _dreRepository.calcular(
          inicio: _periodo.start,
          fim: _periodo.end,
          regime: DreRegime.competencia,
        ),
        _custosRepository.listarResultadoOrdens(),
      ]);
      final ordens =
          List<Map<String, dynamic>>.from(resultados[1] as List<dynamic>).where(
            (item) {
              final data = DateTime.tryParse(
                (item['data_finalizacao'] ?? '').toString(),
              );
              if (data == null) {
                return false;
              }
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
              return !data.isBefore(inicio) && !data.isAfter(fim);
            },
          ).toList();
      ordens.sort(
        (a, b) =>
            _double(b['resultado_os']).compareTo(_double(a['resultado_os'])),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dre = resultados[0] as DreResultado;
        _ordens = ordens;
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

  Future<void> _selecionarPeriodo() async {
    final novo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      initialDateRange: _periodo,
      locale: const Locale('pt', 'BR'),
    );
    if (novo == null || !mounted) {
      return;
    }
    setState(() => _periodo = novo);
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final dre = _dre;
    final detalhes = dre?.detalhes.toList() ?? <DreDetalhe>[];
    detalhes.sort((a, b) => b.valor.compareTo(a.valor));

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios financeiros')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                OutlinedButton.icon(
                  onPressed: _selecionarPeriodo,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    '${_data.format(_periodo.start)} até ${_data.format(_periodo.end)}',
                  ),
                ),
                const SizedBox(height: 12),
                if (dre != null)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resumo do período',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          _linha('Receita líquida', dre.receitaLiquida),
                          _linha('Custos variáveis', -dre.custosVariaveis),
                          _linha(
                            'Despesas operacionais',
                            -dre.despesasOperacionais,
                          ),
                          _linha(
                            'Resultado gerencial',
                            dre.resultadoGerencial,
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                const Text(
                  'Maiores categorias',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (detalhes.isEmpty)
                  const Text('Sem categorias no período.')
                else
                  ...detalhes
                      .take(12)
                      .map(
                        (item) => Card(
                          margin: const EdgeInsets.only(bottom: 7),
                          child: ListTile(
                            title: Text(item.nome),
                            subtitle: Text(
                              '${item.grupo}${item.codigo.isEmpty ? '' : ' • ${item.codigo}'}',
                            ),
                            trailing: Text(_moeda.format(item.valor)),
                          ),
                        ),
                      ),
                const SizedBox(height: 18),
                const Text(
                  'Rentabilidade por OS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_ordens.isEmpty)
                  const Text('Nenhuma OS finalizada no período.')
                else
                  ..._ordens.map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        title: Text((item['numero'] ?? 'OS').toString()),
                        subtitle: Text(
                          '${(item['cliente_nome'] ?? '').toString()} • '
                          'Margem ${_double(item['margem_os']).toStringAsFixed(1).replaceAll('.', ',')}%',
                        ),
                        trailing: Text(
                          _moeda.format(_double(item['resultado_os'])),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _linha(String titulo, double valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(fontWeight: destaque ? FontWeight.bold : null),
            ),
          ),
          Text(
            _moeda.format(valor),
            style: TextStyle(fontWeight: destaque ? FontWeight.bold : null),
          ),
        ],
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
