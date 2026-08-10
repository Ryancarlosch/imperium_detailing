import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/financeiro_repository.dart';

class PrevistoRealizadoPage extends StatefulWidget {
  const PrevistoRealizadoPage({super.key});

  @override
  State<PrevistoRealizadoPage> createState() => _PrevistoRealizadoPageState();
}

class _PrevistoRealizadoPageState extends State<PrevistoRealizadoPage> {
  final FinanceiroRepository _repository = FinanceiroRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _referencia = DateTime.now();
  bool _carregando = true;
  Map<String, double> _resumo = const {};
  List<Map<String, dynamic>> _categorias = [];

  DateTime get _inicio => DateTime(_referencia.year, _referencia.month, 1);
  DateTime get _fim =>
      DateTime(_referencia.year, _referencia.month + 1, 0, 23, 59, 59);

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
        _repository.obterPrevistoRealizado(inicio: _inicio, fim: _fim),
        _repository.listarPrevistoRealizadoPorCategoria(
          inicio: _inicio,
          fim: _fim,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _resumo = Map<String, double>.from(
          resultados[0] as Map<String, double>,
        );
        _categorias = List<Map<String, dynamic>>.from(
          resultados[1] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar o previsto x realizado.\n$erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _alterarMes(int delta) {
    setState(() {
      _referencia = DateTime(_referencia.year, _referencia.month + delta, 1);
    });
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final textoMes = DateFormat('MMMM yyyy', 'pt_BR').format(_referencia);
    final tituloMes = textoMes[0].toUpperCase() + textoMes.substring(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsto x realizado'),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Mês anterior',
                        onPressed: () => _alterarMes(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          tituloMes,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Próximo mês',
                        onPressed: () => _alterarMes(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFD6A84B),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Previsto mantém o valor originalmente programado, '
                              'mesmo depois que ele for pago/recebido. Realizado '
                              'mostra o dinheiro que efetivamente aconteceu no '
                              'período. Pagamentos estornados por correção ficam '
                              'neutros nesta análise.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ResumoPrevistoRealizado(resumo: _resumo, moeda: _moeda),
                  const SizedBox(height: 18),
                  const Text(
                    'Por categoria',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Planejamento e execução lado a lado. Transferências e itens '
                    'marcados como não DRE ficam fora da comparação.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  if (_categorias.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(22),
                        child: Text(
                          'Nenhum lançamento classificado neste mês.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._categorias.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CategoriaPrevistoRealizado(
                          item: item,
                          moeda: _moeda,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ResumoPrevistoRealizado extends StatelessWidget {
  const _ResumoPrevistoRealizado({
    required this.resumo,
    required this.moeda,
  });

  final Map<String, double> resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final entradaPrevista = resumo['entrada_prevista'] ?? 0;
    final entradaRealizada = resumo['entrada_realizada'] ?? 0;
    final saidaPrevista = resumo['saida_prevista'] ?? 0;
    final saidaRealizada = resumo['saida_realizada'] ?? 0;
    final resultadoPrevisto = resumo['resultado_previsto'] ?? 0;
    final resultadoRealizado = resumo['resultado_realizado'] ?? 0;

    return Column(
      children: [
        _ComparacaoCard(
          titulo: 'Receitas',
          previsto: entradaPrevista,
          realizado: entradaRealizada,
          moeda: moeda,
          icone: Icons.south_west_rounded,
          despesa: false,
        ),
        const SizedBox(height: 10),
        _ComparacaoCard(
          titulo: 'Despesas',
          previsto: saidaPrevista,
          realizado: saidaRealizada,
          moeda: moeda,
          icone: Icons.north_east_rounded,
          despesa: true,
        ),
        const SizedBox(height: 10),
        _ComparacaoCard(
          titulo: 'Resultado líquido',
          previsto: resultadoPrevisto,
          realizado: resultadoRealizado,
          moeda: moeda,
          icone: Icons.account_balance_wallet_outlined,
          despesa: false,
        ),
      ],
    );
  }
}

class _ComparacaoCard extends StatelessWidget {
  const _ComparacaoCard({
    required this.titulo,
    required this.previsto,
    required this.realizado,
    required this.moeda,
    required this.icone,
    required this.despesa,
  });

  final String titulo;
  final double previsto;
  final double realizado;
  final NumberFormat moeda;
  final IconData icone;
  final bool despesa;

  @override
  Widget build(BuildContext context) {
    final diferenca = realizado - previsto;
    final percentual = previsto.abs() <= 0.000001
        ? null
        : (realizado / previsto) * 100;

    String leituraDiferenca() {
      if (previsto.abs() <= 0.000001) {
        return realizado.abs() <= 0.000001
            ? 'Sem movimento'
            : 'Sem valor previsto para comparar';
      }

      if (despesa) {
        final saldo = previsto - realizado;
        if (saldo >= 0) {
          return 'Ainda disponível no previsto: ${moeda.format(saldo)}';
        }
        return 'Acima do previsto: ${moeda.format(saldo.abs())}';
      }

      if (diferenca >= 0) {
        return 'Acima do previsto: ${moeda.format(diferenca)}';
      }
      return 'Falta realizar: ${moeda.format(diferenca.abs())}';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: const Color(0xFFD6A84B)),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ValorComparacao(
                    titulo: 'Previsto',
                    valor: moeda.format(previsto),
                  ),
                ),
                Expanded(
                  child: _ValorComparacao(
                    titulo: 'Realizado',
                    valor: moeda.format(realizado),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              leituraDiferenca(),
              style: const TextStyle(color: Colors.white70),
            ),
            if (percentual != null) ...[
              const SizedBox(height: 4),
              Text(
                '${percentual.toStringAsFixed(1).replaceAll('.', ',')}% do previsto',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValorComparacao extends StatelessWidget {
  const _ValorComparacao({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 2),
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _CategoriaPrevistoRealizado extends StatelessWidget {
  const _CategoriaPrevistoRealizado({
    required this.item,
    required this.moeda,
  });

  final Map<String, dynamic> item;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final previsto = _double(item['previsto']);
    final realizado = _double(item['realizado']);
    final tipo = item['tipo']?.toString() ?? '';
    final categoria = item['categoria']?.toString() ?? 'Sem categoria';
    final percentual = previsto.abs() <= 0.000001
        ? null
        : (realizado / previsto).clamp(0, 9.99).toDouble();
    final diferenca = realizado - previsto;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    categoria,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  tipo,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Previsto: ${moeda.format(previsto)}')),
                Expanded(child: Text('Realizado: ${moeda.format(realizado)}')),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Diferença: ${moeda.format(diferenca)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (percentual != null) ...[
              const SizedBox(height: 9),
              LinearProgressIndicator(
                value: percentual.clamp(0, 1).toDouble(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
