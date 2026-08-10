import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dre_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../repositories/meta_financeira_repository.dart';

class MetasFinanceirasPage extends StatefulWidget {
  const MetasFinanceirasPage({super.key});

  @override
  State<MetasFinanceirasPage> createState() => _MetasFinanceirasPageState();
}

class _MetasFinanceirasPageState extends State<MetasFinanceirasPage> {
  final MetaFinanceiraRepository _repository = MetaFinanceiraRepository();
  final DreRepository _dreRepository = DreRepository();
  final FinanceiroRepository _financeiroRepository = FinanceiroRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final TextEditingController _receita = TextEditingController();
  final TextEditingController _despesa = TextEditingController();
  final TextEditingController _resultado = TextEditingController();

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _carregando = true;
  bool _salvando = false;
  DreResultado? _realizado;
  Map<String, double> _previstoRealizado = const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _receita.dispose();
    _despesa.dispose();
    _resultado.dispose();
    super.dispose();
  }

  DateTime get _fimMes =>
      DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.obterResumoMes(_mes.year, _mes.month),
        _dreRepository.calcular(
          inicio: _mes,
          fim: _fimMes,
          regime: DreRegime.competencia,
        ),
        _financeiroRepository.obterPrevistoRealizado(
          inicio: _mes,
          fim: _fimMes,
        ),
      ]);

      final metas = Map<String, double>.from(
        resultados[0] as Map<String, double>,
      );

      if (!mounted) return;

      _receita.text = _formatarNumero(metas['Receita'] ?? 0);
      _despesa.text = _formatarNumero(metas['Despesa'] ?? 0);
      _resultado.text = _formatarNumero(metas['Resultado'] ?? 0);

      setState(() {
        _realizado = resultados[1] as DreResultado;
        _previstoRealizado = Map<String, double>.from(
          resultados[2] as Map<String, double>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  String _formatarNumero(double valor) {
    return valor <= 0 ? '' : valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _ler(TextEditingController controller) {
    var texto = controller.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }
    return double.tryParse(texto) ?? 0;
  }

  int _diasRestantes() {
    final hoje = DateTime.now();
    final inicioAtual = DateTime(hoje.year, hoje.month, 1);
    final inicioSelecionado = DateTime(_mes.year, _mes.month, 1);

    if (inicioSelecionado.isBefore(inicioAtual)) {
      return 0;
    }

    final totalDias = DateTime(_mes.year, _mes.month + 1, 0).day;
    if (inicioSelecionado.isAfter(inicioAtual)) {
      return totalDias;
    }

    return totalDias - hoje.day + 1;
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    setState(() => _salvando = true);
    try {
      await Future.wait([
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Receita',
          valor: _ler(_receita),
        ),
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Despesa',
          valor: _ler(_despesa),
        ),
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Resultado',
          valor: _ler(_resultado),
        ),
      ]);

      if (!mounted) return;

      setState(() => _salvando = false);
      _mensagem('Metas salvas.');
      await _carregar();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mensagem('$erro', erro: true);
    }
  }

  void _alterarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta, 1));
    _carregar();
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final realizado = _realizado;
    final faturado = realizado?.receitaLiquida ?? 0;
    final recebido = _previstoRealizado['entrada_realizada'] ?? 0;
    final despesaPrevista = _previstoRealizado['saida_prevista'] ?? 0;
    final despesaPaga = _previstoRealizado['saida_realizada'] ?? 0;
    final resultadoAtual = realizado?.resultadoGerencial ?? 0;
    final titulo = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final diasRestantes = _diasRestantes();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas financeiras'),
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
                const SizedBox(height: 12),
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Metas são referências de gestão. Receita acompanha o '
                      'faturado e mostra também o recebido. Despesas mostram o '
                      'comprometido e o efetivamente pago. Estornos por correção '
                      'não reduzem artificialmente o desempenho.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MetaReceitaCard(
                  controller: _receita,
                  faturado: faturado,
                  recebido: recebido,
                  diasRestantes: diasRestantes,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                _MetaDespesaCard(
                  controller: _despesa,
                  previsto: despesaPrevista,
                  realizado: despesaPaga,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                _MetaResultadoCard(
                  controller: _resultado,
                  realizado: resultadoAtual,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _salvando ? 'Salvando...' : 'Salvar metas do mês',
                  ),
                ),
              ],
            ),
    );
  }
}

class _MetaReceitaCard extends StatelessWidget {
  const _MetaReceitaCard({
    required this.controller,
    required this.faturado,
    required this.recebido,
    required this.diasRestantes,
    required this.moeda,
    required this.onChanged,
  });

  final TextEditingController controller;
  final double faturado;
  final double recebido;
  final int diasRestantes;
  final NumberFormat moeda;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final meta = _lerCampo(controller.text);
    final progresso = meta <= 0
        ? 0.0
        : (faturado / meta).clamp(0, 1).toDouble();
    final falta = (meta - faturado).clamp(0, double.infinity).toDouble();
    final necessarioDia = diasRestantes > 0 ? falta / diasRestantes : 0.0;

    return _MetaBaseCard(
      titulo: 'Meta de faturamento',
      controller: controller,
      progresso: progresso,
      onChanged: onChanged,
      linhas: [
        _LinhaMeta('Faturado', moeda.format(faturado)),
        _LinhaMeta('Recebido', moeda.format(recebido)),
        _LinhaMeta('Falta faturar', moeda.format(falta)),
        if (meta > 0 && diasRestantes > 0)
          _LinhaMeta(
            'Necessário por dia ($diasRestantes dias)',
            moeda.format(necessarioDia),
          ),
      ],
    );
  }
}

class _MetaDespesaCard extends StatelessWidget {
  const _MetaDespesaCard({
    required this.controller,
    required this.previsto,
    required this.realizado,
    required this.moeda,
    required this.onChanged,
  });

  final TextEditingController controller;
  final double previsto;
  final double realizado;
  final NumberFormat moeda;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final meta = _lerCampo(controller.text);
    final comprometido = previsto > realizado ? previsto : realizado;
    final progresso = meta <= 0
        ? 0.0
        : (comprometido / meta).clamp(0, 1).toDouble();
    final disponivel = (meta - comprometido)
        .clamp(0, double.infinity)
        .toDouble();
    final excedido = (comprometido - meta)
        .clamp(0, double.infinity)
        .toDouble();

    return _MetaBaseCard(
      titulo: 'Limite de despesas',
      controller: controller,
      progresso: progresso,
      onChanged: onChanged,
      linhas: [
        _LinhaMeta('Comprometido/previsto', moeda.format(previsto)),
        _LinhaMeta('Pago', moeda.format(realizado)),
        if (meta > 0 && excedido <= 0)
          _LinhaMeta('Disponível no limite', moeda.format(disponivel)),
        if (meta > 0 && excedido > 0)
          _LinhaMeta('Acima do limite', moeda.format(excedido)),
      ],
    );
  }
}

class _MetaResultadoCard extends StatelessWidget {
  const _MetaResultadoCard({
    required this.controller,
    required this.realizado,
    required this.moeda,
    required this.onChanged,
  });

  final TextEditingController controller;
  final double realizado;
  final NumberFormat moeda;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final meta = _lerCampo(controller.text);
    final progresso = meta <= 0
        ? 0.0
        : (realizado / meta).clamp(0, 1).toDouble();
    final falta = (meta - realizado).clamp(0, double.infinity).toDouble();

    return _MetaBaseCard(
      titulo: 'Meta de resultado',
      controller: controller,
      progresso: progresso,
      onChanged: onChanged,
      linhas: [
        _LinhaMeta('Resultado atual', moeda.format(realizado)),
        _LinhaMeta('Falta para a meta', moeda.format(falta)),
      ],
    );
  }
}

class _MetaBaseCard extends StatelessWidget {
  const _MetaBaseCard({
    required this.titulo,
    required this.controller,
    required this.progresso,
    required this.linhas,
    required this.onChanged,
  });

  final String titulo;
  final TextEditingController controller;
  final double progresso;
  final List<_LinhaMeta> linhas;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final percentual = (progresso * 100).clamp(0, 100).toDouble();

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
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('${percentual.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Meta do mês',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progresso),
            const SizedBox(height: 10),
            ...linhas.map(
              (linha) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        linha.titulo,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    Text(
                      linha.valor,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaMeta {
  const _LinhaMeta(this.titulo, this.valor);
  final String titulo;
  final String valor;
}

double _lerCampo(String valor) {
  var texto = valor
      .trim()
      .replaceAll('R\$', '')
      .replaceAll(' ', '');

  if (texto.contains(',') && texto.contains('.')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  } else {
    texto = texto.replaceAll(',', '.');
  }

  return double.tryParse(texto) ?? 0;
}
