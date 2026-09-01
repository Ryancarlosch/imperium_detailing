import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/fluxo_caixa_repository.dart';

// fluxo-caixa-ui-limpa-v1
class FluxoCaixaPage extends StatefulWidget {
  const FluxoCaixaPage({super.key});

  @override
  State<FluxoCaixaPage> createState() => _FluxoCaixaPageState();
}

class _FluxoCaixaPageState extends State<FluxoCaixaPage> {
  final FluxoCaixaRepository _repository = FluxoCaixaRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _dia = DateFormat('dd/MM');
  final DateFormat _mesTexto = DateFormat('MMM/yyyy', 'pt_BR');

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _mensal = false;
  bool _carregando = true;
  Map<String, double> _resumo = const {};
  List<Map<String, dynamic>> _linhas = const [];

  DateTime get _inicioMes => DateTime(_mes.year, _mes.month, 1);
  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);

    try {
      final inicioLista = _mensal
          ? DateTime(_mes.year, _mes.month - 5, 1)
          : _inicioMes;

      final resultados = await Future.wait<dynamic>([
        _repository.obterResumo(inicio: _inicioMes, fim: _fimMes),
        _mensal
            ? _repository.listarFluxoMensal(inicio: inicioLista, fim: _fimMes)
            : _repository.listarFluxoDiario(inicio: inicioLista, fim: _fimMes),
      ]);

      if (!mounted) return;

      setState(() {
        _resumo = Map<String, double>.from(
          resultados[0] as Map<String, double>,
        );
        _linhas = List<Map<String, dynamic>>.from(
          resultados[1] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar o fluxo de caixa.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _mudarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta, 1));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final tituloFormatado =
        titulo.substring(0, 1).toUpperCase() + titulo.substring(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo de caixa'),
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _mudarMes(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          tituloFormatado,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _mudarMes(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ResumoFluxoLimpo(resumo: _resumo, moeda: _moeda),
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Dia a dia'),
                        icon: Icon(Icons.calendar_view_day_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Últimos 6 meses'),
                        icon: Icon(Icons.calendar_view_month_outlined),
                      ),
                    ],
                    selected: {_mensal},
                    onSelectionChanged: (selecionados) {
                      setState(() => _mensal = selecionados.first);
                      _carregar();
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_linhas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 50),
                      child: Center(
                        child: Text('Sem movimentações neste período.'),
                      ),
                    )
                  else
                    ..._linhas.map(
                      (linha) => _LinhaFluxoCompacta(
                        linha: linha,
                        mensal: _mensal,
                        moeda: _moeda,
                        dia: _dia,
                        mes: _mesTexto,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Realizado usa a data em que o dinheiro entrou ou saiu. '
                    'Previsto usa o vencimento. O saldo projetado soma os dois.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResumoFluxoLimpo extends StatelessWidget {
  const _ResumoFluxoLimpo({required this.resumo, required this.moeda});

  final Map<String, double> resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final saldo = resumo['saldo_final'] ?? 0;
    final projetado = resumo['saldo_projetado'] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ValorFluxo(
                titulo: 'Saldo atual',
                valor: moeda.format(saldo),
                icone: Icons.account_balance_wallet_outlined,
                destaque: true,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ValorFluxo(
                titulo: 'Saldo projetado',
                valor: moeda.format(projetado),
                icone: Icons.timeline_rounded,
                destaque: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _ValorFluxo(
                titulo: 'Entrou',
                valor: moeda.format(resumo['entradas_realizadas'] ?? 0),
                icone: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ValorFluxo(
                titulo: 'Saiu',
                valor: moeda.format(resumo['saidas_realizadas'] ?? 0),
                icone: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _ValorFluxo(
                titulo: 'A entrar',
                valor: moeda.format(resumo['entradas_previstas'] ?? 0),
                icone: Icons.schedule_rounded,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ValorFluxo(
                titulo: 'A sair',
                valor: moeda.format(resumo['saidas_previstas'] ?? 0),
                icone: Icons.event_note_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ValorFluxo extends StatelessWidget {
  const _ValorFluxo({
    required this.titulo,
    required this.valor,
    required this.icone,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 21),
            const SizedBox(height: 10),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: destaque ? 15 : 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              titulo,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaFluxoCompacta extends StatelessWidget {
  const _LinhaFluxoCompacta({
    required this.linha,
    required this.mensal,
    required this.moeda,
    required this.dia,
    required this.mes,
  });

  final Map<String, dynamic> linha;
  final bool mensal;
  final NumberFormat moeda;
  final DateFormat dia;
  final DateFormat mes;

  @override
  Widget build(BuildContext context) {
    final referencia = mensal
        ? '${linha['mes_ref']}-01'
        : linha['data_ref']?.toString();
    final dataRef = DateTime.tryParse(referencia ?? '');
    final titulo = dataRef == null
        ? referencia ?? '-'
        : mensal
        ? mes.format(dataRef)
        : dia.format(dataRef);
    final realizado = _double(linha['resultado_realizado']);
    final previsto = _double(linha['resultado_previsto']);
    final saldoProjetado = _double(linha['saldo_projetado_acumulado']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Realizado ${moeda.format(realizado)} • '
          'Previsto ${moeda.format(previsto)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moeda.format(saldoProjetado),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'projetado',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
