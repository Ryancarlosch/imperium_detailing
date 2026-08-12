import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dre_repository.dart';
import '../repositories/meta_financeira_repository.dart';

class MetasFinanceirasPage extends StatefulWidget {
  const MetasFinanceirasPage({super.key});

  @override
  State<MetasFinanceirasPage> createState() => _MetasFinanceirasPageState();
}

class _MetasFinanceirasPageState extends State<MetasFinanceirasPage> {
  final MetaFinanceiraRepository _repository = MetaFinanceiraRepository();
  final DreRepository _dreRepository = DreRepository();

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
  bool _copiando = false;

  DreResultado? _realizado;

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

  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0, 23, 59, 59);

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
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar as metas.\n$erro', erro: true);
    }
  }

  String _formatarNumero(double valor) {
    if (valor <= 0) return '';
    return valor.toStringAsFixed(2).replaceAll('.', ',');
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

  void _alterarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  void _usarResultadoSugerido() {
    final receita = _ler(_receita);
    final despesa = _ler(_despesa);
    final sugerido = receita - despesa;

    if (sugerido <= 0) {
      _mensagem(
        'A meta de resultado sugerida ficou zerada ou negativa. '
        'Revise a meta de receita e o limite de despesas.',
        erro: true,
      );
      return;
    }

    setState(() {
      _resultado.text = _formatarNumero(sugerido);
    });
  }

  Future<void> _copiarMesAnterior() async {
    if (_copiando) return;

    setState(() => _copiando = true);

    try {
      final anterior = DateTime(_mes.year, _mes.month - 1, 1);
      final metas = await _repository.obterResumoMes(
        anterior.year,
        anterior.month,
      );

      final receita = metas['Receita'] ?? 0;
      final despesa = metas['Despesa'] ?? 0;
      final resultado = metas['Resultado'] ?? 0;

      if (receita <= 0 && despesa <= 0 && resultado <= 0) {
        if (!mounted) return;
        setState(() => _copiando = false);
        _mensagem('O mês anterior não possui metas cadastradas.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _receita.text = _formatarNumero(receita);
        _despesa.text = _formatarNumero(despesa);
        _resultado.text = _formatarNumero(resultado);
        _copiando = false;
      });

      _mensagem(
        'Metas do mês anterior copiadas. Confira os valores e toque em Salvar.',
      );
    } catch (erro) {
      if (!mounted) return;

      setState(() => _copiando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    final receita = _ler(_receita);
    final despesa = _ler(_despesa);
    final resultado = _ler(_resultado);

    if (receita <= 0) {
      _mensagem('Informe uma meta de receita maior que zero.', erro: true);
      return;
    }

    if (despesa < 0 || resultado < 0) {
      _mensagem('As metas não podem ser negativas.', erro: true);
      return;
    }

    setState(() => _salvando = true);

    try {
      await Future.wait([
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Receita',
          valor: receita,
        ),
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Despesa',
          valor: despesa,
        ),
        _repository.salvarMetaGeral(
          ano: _mes.year,
          mes: _mes.month,
          tipo: 'Resultado',
          valor: resultado,
        ),
      ]);

      if (!mounted) return;

      setState(() => _salvando = false);
      _mensagem('Metas do mês salvas.');
      await _carregar();
    } catch (erro) {
      if (!mounted) return;

      setState(() => _salvando = false);
      _mensagem('$erro', erro: true);
    }
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

    final receitaMeta = _ler(_receita);
    final despesaMeta = _ler(_despesa);
    final resultadoMeta = _ler(_resultado);

    final receitaRealizada = realizado?.receitaLiquida ?? 0;
    final despesasRealizadas = realizado == null
        ? 0.0
        : realizado.custosVariaveis +
              realizado.despesasOperacionais +
              realizado.resultadoFinanceiro +
              realizado.outrasDespesas;
    final resultadoRealizado = realizado?.resultadoGerencial ?? 0;

    final titulo = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final tituloMes = titulo[0].toUpperCase() + titulo.substring(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas do mês'),
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
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
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
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.flag_outlined),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Defina aqui apenas os objetivos do mês. '
                            'A análise Meta x Resultado fica no DRE Resumo, '
                            'usando estas mesmas metas automaticamente.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _copiando ? null : _copiarMesAnterior,
                  icon: const Icon(Icons.content_copy_outlined),
                  label: Text(
                    _copiando ? 'Copiando...' : 'Copiar mês anterior',
                  ),
                ),
                const SizedBox(height: 14),
                _MetaEditorCard(
                  titulo: 'Meta de receita',
                  descricao: 'Quanto a empresa pretende faturar no mês.',
                  controller: _receita,
                  realizado: receitaRealizada,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                  icone: Icons.trending_up_rounded,
                  positivoQuandoMaior: true,
                ),
                const SizedBox(height: 10),
                _MetaEditorCard(
                  titulo: 'Limite de custos + despesas',
                  descricao:
                      'Quanto a empresa pode gastar sem comprometer o resultado.',
                  controller: _despesa,
                  realizado: despesasRealizadas,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                  icone: Icons.trending_down_rounded,
                  positivoQuandoMaior: false,
                ),
                const SizedBox(height: 10),
                _MetaEditorCard(
                  titulo: 'Meta de resultado',
                  descricao:
                      'Quanto deve sobrar de resultado no fim do período.',
                  controller: _resultado,
                  realizado: resultadoRealizado,
                  moeda: _moeda,
                  onChanged: () => setState(() {}),
                  icone: Icons.account_balance_wallet_outlined,
                  positivoQuandoMaior: true,
                  destaque: true,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: receitaMeta > 0 && despesaMeta >= 0
                      ? _usarResultadoSugerido
                      : null,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text(
                    'Usar Receita - Despesas como meta de resultado',
                  ),
                ),
                if (receitaMeta > 0) ...[
                  const SizedBox(height: 14),
                  _ResumoPlanejamento(
                    receita: receitaMeta,
                    despesas: despesaMeta,
                    resultado: resultadoMeta,
                    moeda: _moeda,
                  ),
                ],
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

class _MetaEditorCard extends StatelessWidget {
  const _MetaEditorCard({
    required this.titulo,
    required this.descricao,
    required this.controller,
    required this.realizado,
    required this.moeda,
    required this.onChanged,
    required this.icone,
    required this.positivoQuandoMaior,
    this.destaque = false,
  });

  final String titulo;
  final String descricao;
  final TextEditingController controller;
  final double realizado;
  final NumberFormat moeda;
  final VoidCallback onChanged;
  final IconData icone;
  final bool positivoQuandoMaior;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final meta = _lerCampo(controller.text);
    final percentual = meta <= 0 ? 0.0 : realizado / meta * 100;
    final diferenca = realizado - meta;

    final favoravel = meta <= 0
        ? true
        : positivoQuandoMaior
        ? diferenca >= 0
        : diferenca <= 0;

    String leitura() {
      if (meta <= 0) return 'Defina uma meta para acompanhar o resultado.';

      if (positivoQuandoMaior) {
        return diferenca >= 0
            ? 'Meta atingida por ${moeda.format(diferenca)}'
            : 'Falta ${moeda.format(diferenca.abs())}';
      }

      return diferenca <= 0
          ? 'Dentro do limite por ${moeda.format(diferenca.abs())}'
          : 'Acima do limite em ${moeda.format(diferenca)}';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(destaque ? 16 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: destaque ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (meta > 0)
                  Text(
                    '${percentual.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: favoravel
                          ? Colors.green.shade500
                          : Colors.orange.shade500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              descricao,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Meta do mês',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Resultado atual',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  moeda.format(realizado),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (meta > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (realizado / meta).clamp(0, 1).toDouble(),
              ),
              const SizedBox(height: 7),
              Text(
                leitura(),
                style: TextStyle(
                  fontSize: 12,
                  color: favoravel
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.orange.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResumoPlanejamento extends StatelessWidget {
  const _ResumoPlanejamento({
    required this.receita,
    required this.despesas,
    required this.resultado,
    required this.moeda,
  });

  final double receita;
  final double despesas;
  final double resultado;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final resultadoCalculado = receita - despesas;
    final margemPlanejada = receita.abs() <= 0.000001
        ? 0.0
        : resultado / receita * 100;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Planejamento do mês',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _LinhaPlanejamento(
              titulo: 'Receita planejada',
              valor: moeda.format(receita),
            ),
            _LinhaPlanejamento(
              titulo: 'Limite de custos + despesas',
              valor: moeda.format(despesas),
            ),
            _LinhaPlanejamento(
              titulo: 'Resultado Receita - Despesas',
              valor: moeda.format(resultadoCalculado),
            ),
            const Divider(height: 18),
            _LinhaPlanejamento(
              titulo: 'Meta de resultado definida',
              valor: moeda.format(resultado),
              destaque: true,
            ),
            _LinhaPlanejamento(
              titulo: 'Margem planejada',
              valor:
                  '${margemPlanejada.toStringAsFixed(1).replaceAll('.', ',')}%',
              destaque: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaPlanejamento extends StatelessWidget {
  const _LinhaPlanejamento({
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: destaque ? FontWeight.w700 : FontWeight.normal,
                color: destaque
                    ? null
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

double _lerCampo(String valor) {
  var texto = valor.trim().replaceAll('R\$', '').replaceAll(' ', '');

  if (texto.contains(',') && texto.contains('.')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  } else {
    texto = texto.replaceAll(',', '.');
  }

  return double.tryParse(texto) ?? 0;
}
