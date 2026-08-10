import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../repositories/pagamento_repository.dart';
import 'contas_financeiras_page.dart';
import 'custos_page.dart';
import 'dre_page.dart';
import 'financeiro_dashboard_page.dart';
import 'fluxo_caixa_page.dart';
import 'fornecedores_page.dart';
import 'movimentacoes_financeiras_page.dart';
import 'pagamentos_page.dart';
import 'previsto_realizado_page.dart';
import 'plano_contas_page.dart';
import 'metas_financeiras_page.dart';
import 'regras_taxa_page.dart';
import 'relatorios_financeiros_page.dart';

class FinanceiroPage extends StatefulWidget {
  const FinanceiroPage({super.key});

  @override
  State<FinanceiroPage> createState() => _FinanceiroPageState();
}

class _FinanceiroPageState extends State<FinanceiroPage> {
  final FinanceiroRepository _repository = FinanceiroRepository();
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();
  final PagamentoRepository _pagamentosRepository = PagamentoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  Map<String, double> _resumo = const {
    'entradas_realizadas': 0,
    'saidas_realizadas': 0,
    'saldo_realizado': 0,
    'entradas_previstas': 0,
    'saidas_previstas': 0,
    'vencido_pagar': 0,
  };
  double _saldoContas = 0;
  double _aReceberOs = 0;

  DateTime get _inicioMes {
    final hoje = DateTime.now();
    return DateTime(hoje.year, hoje.month, 1);
  }

  DateTime get _fimMes {
    final hoje = DateTime.now();
    return DateTime(hoje.year, hoje.month + 1, 0, 23, 59, 59);
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
        _repository.obterResumoOperacional(inicio: _inicioMes, fim: _fimMes),
        _contasRepository.listar(),
        _pagamentosRepository.obterResumoGeral(),
      ]);

      final contas = List<ContaFinanceira>.from(resultados[1] as List<dynamic>);
      final saldoContas = contas.fold<double>(
        0,
        (total, item) => total + (item.saldoAtual ?? item.saldoInicial),
      );
      final resumoPagamentos = Map<String, double>.from(
        resultados[2] as Map<String, double>,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _resumo = Map<String, double>.from(
          resultados[0] as Map<String, double>,
        );
        _saldoContas = saldoContas;
        _aReceberOs = resumoPagamentos['a_receber'] ?? 0;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar o financeiro.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrir(Widget pagina) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina));
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    final tituloMes = DateFormat('MMMM yyyy', 'pt_BR').format(hoje);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
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
                  Text(
                    tituloMes[0].toUpperCase() + tituloMes.substring(1),
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  _ResumoPrincipal(
                    saldo: _resumo['saldo_realizado'] ?? 0,
                    entradas: _resumo['entradas_realizadas'] ?? 0,
                    saidas: _resumo['saidas_realizadas'] ?? 0,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniResumo(
                          titulo: 'A receber total',
                          valor: _moeda.format(
                            (_resumo['entradas_previstas'] ?? 0) + _aReceberOs,
                          ),
                          icone: Icons.schedule_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniResumo(
                          titulo: 'A pagar previsto',
                          valor: _moeda.format(
                            _resumo['saidas_previstas'] ?? 0,
                          ),
                          icone: Icons.event_note_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MiniResumo(
                    titulo: 'Saldo vinculado às contas cadastradas',
                    valor: _moeda.format(_saldoContas),
                    icone: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 22),
                  const _TituloSecao(
                    titulo: 'Operação do dia a dia',
                    subtitulo:
                        'Cada ferramenta fica separada para facilitar o uso.',
                  ),
                  const SizedBox(height: 10),
                  _MenuFinanceiro(
                    titulo: 'Movimentações',
                    subtitulo:
                        'Entradas, saídas, previstos, realizados e transferências',
                    icone: Icons.swap_vert_circle_outlined,
                    onTap: () => _abrir(const MovimentacoesFinanceirasPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Contas a pagar',
                    subtitulo: 'Despesas previstas, vencimentos e pagamentos',
                    icone: Icons.event_busy_outlined,
                    badge: (_resumo['vencido_pagar'] ?? 0) > 0
                        ? 'Vencido ${_moeda.format(_resumo['vencido_pagar'])}'
                        : null,
                    onTap: () => _abrir(
                      const MovimentacoesFinanceirasPage(
                        tipoInicial: 'Saída',
                        statusInicial: 'Previsto',
                        titulo: 'Contas a pagar',
                      ),
                    ),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Contas a receber das OS',
                    subtitulo: 'Pagamentos, parcelas, vencidos e comprovantes',
                    icone: Icons.receipt_long_outlined,
                    onTap: () => _abrir(const PagamentosPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Fluxo de caixa',
                    subtitulo:
                        'Evolução diária e mensal, saldo realizado e projetado',
                    icone: Icons.waterfall_chart_rounded,
                    onTap: () => _abrir(const FluxoCaixaPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Previsto x realizado',
                    subtitulo:
                        'Compare receitas e despesas planejadas com o que aconteceu',
                    icone: Icons.compare_arrows_rounded,
                    onTap: () => _abrir(const PrevistoRealizadoPage()),
                  ),
                  const SizedBox(height: 18),
                  const _TituloSecao(
                    titulo: 'Cadastros financeiros',
                    subtitulo: 'Base para organizar o caixa e a futura DRE.',
                  ),
                  const SizedBox(height: 10),
                  _MenuFinanceiro(
                    titulo: 'Plano de contas',
                    subtitulo:
                        'Categorias e subcategorias de receitas e despesas',
                    icone: Icons.account_tree_outlined,
                    onTap: () => _abrir(const PlanoContasPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Contas e caixa',
                    subtitulo: 'Dinheiro, bancos, carteiras e saldo por conta',
                    icone: Icons.account_balance_outlined,
                    onTap: () => _abrir(const ContasFinanceirasPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Fornecedores',
                    subtitulo: 'Cadastro para vincular despesas e compras',
                    icone: Icons.local_shipping_outlined,
                    onTap: () => _abrir(const FornecedoresPage()),
                  ),
                  const SizedBox(height: 18),
                  const _TituloSecao(
                    titulo: 'Gestão e análise',
                    subtitulo:
                        'Custos, DRE, metas, dashboard e relatórios em áreas separadas.',
                  ),
                  const SizedBox(height: 10),
                  _MenuFinanceiro(
                    titulo: 'Dashboard financeiro',
                    subtitulo:
                        'Faturamento, recebido, resultado, metas e evolução mensal',
                    icone: Icons.dashboard_outlined,
                    onTap: () => _abrir(const FinanceiroDashboardPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Custos e mão de obra',
                    subtitulo:
                        'Custos fixos, custo/hora, serviços e resultado por OS',
                    icone: Icons.calculate_outlined,
                    onTap: () => _abrir(const CustosPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'DRE gerencial',
                    subtitulo:
                        'Regime de competência ou caixa, margem e detalhamento',
                    icone: Icons.assessment_outlined,
                    onTap: () => _abrir(const DrePage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Metas financeiras',
                    subtitulo: 'Metas mensais de receita, despesas e resultado',
                    icone: Icons.track_changes_outlined,
                    onTap: () => _abrir(const MetasFinanceirasPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Relatórios financeiros',
                    subtitulo:
                        'Categorias, DRE e rentabilidade das Ordens de Serviço',
                    icone: Icons.summarize_outlined,
                    onTap: () => _abrir(const RelatoriosFinanceirosPage()),
                  ),
                  _MenuFinanceiro(
                    titulo: 'Regras de maquininha',
                    subtitulo:
                        'Taxas automáticas por débito, crédito, parcelas e conta',
                    icone: Icons.credit_card_outlined,
                    onTap: () => _abrir(const RegrasTaxaPage()),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResumoPrincipal extends StatelessWidget {
  const _ResumoPrincipal({
    required this.saldo,
    required this.entradas,
    required this.saidas,
    required this.moeda,
  });

  final double saldo;
  final double entradas;
  final double saidas;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resultado de caixa do mês'),
            const SizedBox(height: 5),
            Text(
              moeda.format(saldo),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _LinhaResumo(
                    titulo: 'Entradas',
                    valor: moeda.format(entradas),
                    icone: Icons.south_west_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LinhaResumo(
                    titulo: 'Saídas',
                    valor: moeda.format(saidas),
                    icone: Icons.north_east_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 20, color: const Color(0xFFD6A84B)),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(color: Colors.white60)),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icone, color: const Color(0xFFD6A84B)),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
          ],
        ),
      ),
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
        Text(subtitulo, style: const TextStyle(color: Colors.white60)),
      ],
    );
  }
}

class _MenuFinanceiro extends StatelessWidget {
  const _MenuFinanceiro({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.onTap,
    this.badge,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Icon(icone, color: const Color(0xFFD6A84B)),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitulo),
        trailing: badge == null
            ? const Icon(Icons.chevron_right_rounded)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
        onTap: onTap,
      ),
    );
  }
}
