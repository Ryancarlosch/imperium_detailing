import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/fluxo_caixa_repository.dart';

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
  final DateFormat _mes = DateFormat('MMM/yyyy', 'pt_BR');

  bool _carregando = true;
  String _modo = 'Diário';
  DateTime _referencia = DateTime.now();
  Map<String, double> _resumo = const {};
  List<Map<String, dynamic>> _linhas = [];

  DateTime get _inicio {
    if (_modo == 'Diário') {
      return DateTime(_referencia.year, _referencia.month, 1);
    }
    return DateTime(_referencia.year, 1, 1);
  }

  DateTime get _fim {
    if (_modo == 'Diário') {
      return DateTime(_referencia.year, _referencia.month + 1, 0, 23, 59, 59);
    }
    return DateTime(_referencia.year, 12, 31, 23, 59, 59);
  }

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
        _repository.obterResumo(inicio: _inicio, fim: _fim),
        if (_modo == 'Diário')
          _repository.listarFluxoDiario(inicio: _inicio, fim: _fim)
        else
          _repository.listarFluxoMensal(inicio: _inicio, fim: _fim),
      ]);

      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar o fluxo de caixa.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _anterior() {
    setState(() {
      _referencia = _modo == 'Diário'
          ? DateTime(_referencia.year, _referencia.month - 1, 1)
          : DateTime(_referencia.year - 1, 1, 1);
    });
    _carregar();
  }

  void _proximo() {
    setState(() {
      _referencia = _modo == 'Diário'
          ? DateTime(_referencia.year, _referencia.month + 1, 1)
          : DateTime(_referencia.year + 1, 1, 1);
    });
    _carregar();
  }

  String get _tituloPeriodo {
    if (_modo == 'Diário') {
      final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_referencia);
      return texto[0].toUpperCase() + texto.substring(1);
    }
    return _referencia.year.toString();
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Diário',
                        label: Text('Diário'),
                        icon: Icon(Icons.calendar_view_day_outlined),
                      ),
                      ButtonSegment(
                        value: 'Mensal',
                        label: Text('Mensal'),
                        icon: Icon(Icons.calendar_month_outlined),
                      ),
                    ],
                    selected: {_modo},
                    onSelectionChanged: (selecionados) {
                      setState(() {
                        _modo = selecionados.first;
                      });
                      _carregar();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Período anterior',
                        onPressed: _anterior,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _tituloPeriodo,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Próximo período',
                        onPressed: _proximo,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ResumoFluxo(resumo: _resumo, moeda: _moeda),
                  const SizedBox(height: 18),
                  const Text(
                    'Evolução do caixa',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Realizado mostra o dinheiro que efetivamente entrou ou saiu. '
                    'Projetado soma lançamentos previstos e parcelas pendentes das OS '
                    'nas respectivas datas de vencimento.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  if (_linhas.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(22),
                        child: Text(
                          'Nenhuma movimentação encontrada neste período.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._linhas.map(
                      (linha) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LinhaFluxo(
                          linha: linha,
                          modo: _modo,
                          moeda: _moeda,
                          dia: _dia,
                          mes: _mes,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ResumoFluxo extends StatelessWidget {
  const _ResumoFluxo({required this.resumo, required this.moeda});

  final Map<String, double> resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final saldoInicial = resumo['saldo_inicial'] ?? 0;
    final saldoFinal = resumo['saldo_final'] ?? 0;
    final saldoProjetado = resumo['saldo_projetado'] ?? 0;

    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _ValorResumo(
                  titulo: 'Saldo no início do período',
                  valor: moeda.format(saldoInicial),
                ),
                const Divider(),
                _ValorResumo(
                  titulo: 'Saldo realizado',
                  valor: moeda.format(saldoFinal),
                  destaque: true,
                ),
                _ValorResumo(
                  titulo: 'Saldo projetado',
                  valor: moeda.format(saldoProjetado),
                  destaque: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniResumo(
                titulo: 'Entrou',
                valor: moeda.format(resumo['entradas_realizadas'] ?? 0),
                icone: Icons.south_west_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniResumo(
                titulo: 'Saiu',
                valor: moeda.format(resumo['saidas_realizadas'] ?? 0),
                icone: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniResumo(
                titulo: 'Entradas previstas',
                valor: moeda.format(resumo['entradas_previstas'] ?? 0),
                icone: Icons.schedule_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniResumo(
                titulo: 'Saídas previstas',
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

class _ValorResumo extends StatelessWidget {
  const _ValorResumo({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontSize: destaque ? 18 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniResumo extends StatelessWidget {
  const _MiniResumo({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

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
            const SizedBox(height: 7),
            Text(titulo, style: const TextStyle(color: Colors.white60)),
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

class _LinhaFluxo extends StatelessWidget {
  const _LinhaFluxo({
    required this.linha,
    required this.modo,
    required this.moeda,
    required this.dia,
    required this.mes,
  });

  final Map<String, dynamic> linha;
  final String modo;
  final NumberFormat moeda;
  final DateFormat dia;
  final DateFormat mes;

  @override
  Widget build(BuildContext context) {
    final referencia = modo == 'Diário'
        ? linha['data_ref']?.toString()
        : '${linha['mes_ref']}-01';
    final data = DateTime.tryParse(referencia ?? '');
    final titulo = data == null
        ? referencia ?? '-'
        : modo == 'Diário'
        ? dia.format(data)
        : _capitalizar(mes.format(data));
    final realizado = _double(linha['resultado_realizado']);
    final previsto = _double(linha['resultado_previsto']);
    final saldoRealizado = _double(linha['saldo_realizado_acumulado']);
    final saldoProjetado = _double(linha['saldo_projetado_acumulado']);

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
                    titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  moeda.format(realizado),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 5,
              children: [
                Text(
                  'Previsto no período: ${moeda.format(previsto)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'Saldo: ${moeda.format(saldoRealizado)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  'Projetado: ${moeda.format(saldoProjetado)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalizar(String texto) {
  if (texto.isEmpty) {
    return texto;
  }
  return texto[0].toUpperCase() + texto.substring(1);
}

double _double(dynamic valor) {
  if (valor is num) {
    return valor.toDouble();
  }
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
