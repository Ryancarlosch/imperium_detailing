import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_dashboard_repository.dart';
import 'contas_financeiras_page.dart';
import 'custos_page.dart';
import 'dre_page.dart';
import 'financeiro_dashboard_page.dart';
import 'fluxo_caixa_page.dart';
import 'fornecedores_page.dart';
import 'lancamento_financeiro_page.dart';
import 'metas_financeiras_page.dart';
import 'movimentacoes_financeiras_page.dart';
import 'pagamentos_page.dart';
import 'plano_contas_page.dart';
import 'previsto_realizado_page.dart';
import 'regras_taxa_page.dart';
import 'relatorios_financeiros_page.dart';
import 'transferencia_financeira_page.dart';

// financeiro-home-limpo-v1
class FinanceiroPage extends StatefulWidget {
  const FinanceiroPage({super.key});

  @override
  State<FinanceiroPage> createState() => _FinanceiroPageState();
}

class _FinanceiroPageState extends State<FinanceiroPage> {
  final FinanceiroDashboardRepository _dashboard =
      FinanceiroDashboardRepository();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  bool _valoresVisiveis = false; // financeiro-privacidade-v1
  FinanceiroDashboardData? _dados;
  double _saldoContas = 0;

  DateTime get _mes {
    final hoje = DateTime.now();
    return DateTime(hoje.year, hoje.month, 1);
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
        _dashboard.carregar(mes: _mes),
        _contasRepository.listar(),
      ]);

      final contas = List<ContaFinanceira>.from(resultados[1] as List<dynamic>);
      final saldo = contas.fold<double>(
        0,
        (total, item) => total + (item.saldoAtual ?? item.saldoInicial),
      );

      if (!mounted) return;

      setState(() {
        _dados = resultados[0] as FinanceiroDashboardData;
        _saldoContas = saldo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar o financeiro.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _valor(double valor) {
    return _valoresVisiveis ? _moeda.format(valor) : 'R\$ ••••••';
  }

  Future<void> _abrir(Widget pagina) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina));
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final tituloMes = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    final tituloFormatado =
        tituloMes.substring(0, 1).toUpperCase() + tituloMes.substring(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
        actions: [
          IconButton(
            tooltip: _valoresVisiveis ? 'Ocultar valores' : 'Mostrar valores',
            onPressed: () {
              setState(() => _valoresVisiveis = !_valoresVisiveis);
            },
            icon: Icon(
              _valoresVisiveis
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
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
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : dados == null
            ? const Center(child: Text('Sem dados financeiros para exibir.'))
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    tituloFormatado,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // financeiro-kpis-semantica-v1
                  _GradeKpis(
                    itens: [
                      _KpiDados(
                        titulo: 'Faturamento',
                        valor: _valor(dados.dreCompetencia.receitaLiquida),
                        icone: Icons.receipt_long_outlined,
                        subtitulo: 'Competência do mês',
                      ),
                      _KpiDados(
                        titulo: 'Recebido',
                        valor: _valor(dados.recebido),
                        icone: Icons.payments_outlined,
                        subtitulo: 'Dinheiro que entrou',
                      ),
                      _KpiDados(
                        titulo: 'A receber',
                        valor: _valor(dados.aReceber),
                        icone: Icons.schedule_rounded,
                        subtitulo: dados.vencido > 0
                            ? 'Vencido: ${_valor(dados.vencido)}'
                            : 'Saldo aberto dos clientes',
                      ),
                      _KpiDados(
                        titulo: 'Resultado do mês',
                        valor: _valor(dados.dreCompetencia.resultadoGerencial),
                        icone: Icons.insights_rounded,
                        subtitulo:
                            'Margem ${dados.dreCompetencia.margemPercentual.toStringAsFixed(1).replaceAll('.', ',')}%',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Saldo total nas contas'),
                      subtitle: const Text(
                        'Dinheiro disponível nas contas e caixas cadastrados.',
                      ),
                      trailing: Text(
                        _valor(_saldoContas),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Faturamento segue a competência. Recebido mostra dinheiro '
                    'que entrou. A receber é o saldo aberto. Saldo é o dinheiro '
                    'existente nas contas.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Ações rápidas',
                    subtitulo: 'O que você mais usa no dia a dia.',
                  ),
                  const SizedBox(height: 10),
                  // financeiro-acoes-rapidas-v1
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      _AcaoRapida(
                        titulo: 'Despesa',
                        icone: Icons.remove_circle_outline_rounded,
                        onTap: () => _abrir(
                          const LancamentoFinanceiroPage(tipoInicial: 'Saída'),
                        ),
                      ),
                      _AcaoRapida(
                        titulo: 'Receita',
                        icone: Icons.add_circle_outline_rounded,
                        onTap: () => _abrir(
                          const LancamentoFinanceiroPage(
                            tipoInicial: 'Entrada',
                          ),
                        ),
                      ),
                      _AcaoRapida(
                        titulo: 'Receber OS',
                        icone: Icons.point_of_sale_outlined,
                        onTap: () => _abrir(const PagamentosPage()),
                      ),
                      _AcaoRapida(
                        titulo: 'Transferir',
                        icone: Icons.swap_horiz_rounded,
                        onTap: () =>
                            _abrir(const TransferenciaFinanceiraPage()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _TituloSecao(
                    titulo: 'Financeiro',
                    subtitulo: 'Quatro áreas principais para consultar e agir.',
                  ),
                  const SizedBox(height: 10),
                  _DestinoPrincipal(
                    titulo: 'Movimentações',
                    subtitulo:
                        'Receitas, despesas, previstos e realizados em uma lista compacta.',
                    icone: Icons.swap_vert_circle_outlined,
                    onTap: () => _abrir(const MovimentacoesFinanceirasPage()),
                  ),
                  _DestinoPrincipal(
                    titulo: 'Contas',
                    subtitulo:
                        'Bancos, dinheiro, maquininhas, extratos e conciliação.',
                    icone: Icons.account_balance_outlined,
                    onTap: () => _abrir(const ContasFinanceirasPage()),
                  ),
                  _DestinoPrincipal(
                    titulo: 'Fluxo de caixa',
                    subtitulo:
                        'Saldo realizado, projeção e evolução diária ou mensal.',
                    icone: Icons.waterfall_chart_rounded,
                    onTap: () => _abrir(const FluxoCaixaPage()),
                  ),
                  _DestinoPrincipal(
                    titulo: 'DRE',
                    subtitulo:
                        'Resultado por competência ou caixa, detalhes e PDF.',
                    icone: Icons.assessment_outlined,
                    onTap: () => _abrir(const DrePage()),
                  ),
                  const SizedBox(height: 12),
                  // financeiro-gestao-expansivel-v1
                  Card(
                    margin: EdgeInsets.zero,
                    child: ExpansionTile(
                      leading: const Icon(Icons.tune_rounded),
                      title: const Text('Gestão e configurações financeiras'),
                      subtitle: const Text(
                        'Ferramentas que você usa com menos frequência',
                      ),
                      children: [
                        _ItemGestao(
                          titulo: 'Contas a pagar',
                          icone: Icons.event_busy_outlined,
                          onTap: () => _abrir(
                            const MovimentacoesFinanceirasPage(
                              tipoInicial: 'Saída',
                              statusInicial: 'Previsto',
                              titulo: 'Contas a pagar',
                            ),
                          ),
                        ),
                        _ItemGestao(
                          titulo: 'Contas a receber das OS',
                          icone: Icons.receipt_long_outlined,
                          onTap: () => _abrir(const PagamentosPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Previsto x realizado',
                          icone: Icons.compare_arrows_rounded,
                          onTap: () => _abrir(const PrevistoRealizadoPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Dashboard financeiro',
                          icone: Icons.dashboard_outlined,
                          onTap: () => _abrir(const FinanceiroDashboardPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Custos e mão de obra',
                          icone: Icons.calculate_outlined,
                          onTap: () => _abrir(const CustosPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Metas financeiras',
                          icone: Icons.track_changes_outlined,
                          onTap: () => _abrir(const MetasFinanceirasPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Fornecedores',
                          icone: Icons.local_shipping_outlined,
                          onTap: () => _abrir(const FornecedoresPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Plano de contas',
                          icone: Icons.account_tree_outlined,
                          onTap: () => _abrir(const PlanoContasPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Regras de maquininha',
                          icone: Icons.credit_card_outlined,
                          onTap: () => _abrir(const RegrasTaxaPage()),
                        ),
                        _ItemGestao(
                          titulo: 'Relatórios financeiros',
                          icone: Icons.summarize_outlined,
                          onTap: () =>
                              _abrir(const RelatoriosFinanceirosPage()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _KpiDados {
  const _KpiDados({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.subtitulo,
  });

  final String titulo;
  final String valor;
  final IconData icone;
  final String subtitulo;
}

class _GradeKpis extends StatelessWidget {
  const _GradeKpis({required this.itens});

  final List<_KpiDados> itens;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 720 ? 4 : 2;
        const espaco = 9.0;
        final largura =
            (constraints.maxWidth - espaco * (colunas - 1)) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icone, size: 22),
                        const SizedBox(height: 12),
                        Text(
                          item.valor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.titulo,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AcaoRapida extends StatelessWidget {
  const _AcaoRapida({
    required this.titulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icone),
      label: Text(titulo),
    );
  }
}

class _DestinoPrincipal extends StatelessWidget {
  const _DestinoPrincipal({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Icon(icone),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _ItemGestao extends StatelessWidget {
  const _ItemGestao({
    required this.titulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icone),
      title: Text(titulo),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _TituloSecao extends StatelessWidget {
  const _TituloSecao({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          subtitulo,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
