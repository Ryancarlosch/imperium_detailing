import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/cliente_repository.dart';
import '../repositories/configuracao_repository.dart';
import '../repositories/dashboard_repository.dart';
import '../services/primeiro_uso_assistente.dart';
import 'agenda_page.dart';
import 'cliente_detalhes_page.dart';
import 'clientes_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'fotos_page.dart';
import 'orcamentos_page.dart';
import 'ordens_servico_page.dart';
import 'servicos_page.dart';
import 'veiculos_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashboardRepository _dashboardRepository = DashboardRepository();
  final ClienteRepository _clienteRepository = ClienteRepository();
  final ConfiguracaoRepository _configuracaoRepository =
      ConfiguracaoRepository();
  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String? _mensagemErro;
  String _nomeEmpresa = 'Sua empresa';
  bool _assistenteExibido = false;

  DashboardPeriodo _periodoSelecionado = DashboardPeriodo.mesAtual;
  DateTimeRange? _periodoPersonalizado;
  DashboardData? _dados;

  @override
  void initState() {
    super.initState();
    _carregarResumo();
    _carregarNomeEmpresa();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mostrarAssistentePrimeiroUso();
    });
  }

  Future<void> _carregarNomeEmpresa() async {
    try {
      final configuracao = await _configuracaoRepository.obterConfiguracao();

      if (!mounted) {
        return;
      }

      final nome = configuracao.nomeFantasia.trim().isEmpty
          ? 'Sua empresa'
          : configuracao.nomeFantasia.trim();

      setState(() {
        _nomeEmpresa = nome;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _nomeEmpresa = 'Sua empresa';
      });
    }
  }

  Future<void> _mostrarAssistentePrimeiroUso() async {
    if (_assistenteExibido) {
      return;
    }

    _assistenteExibido = true;

    await mostrarAssistentePrimeiroUso(context);
  }

  Future<void> _carregarResumo() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _carregando = true;
      _mensagemErro = null;
    });

    try {
      final dados = await _dashboardRepository.carregarDashboard(
        periodo: _periodoSelecionado,
        inicioPersonalizado: _periodoPersonalizado?.start,
        fimPersonalizado: _periodoPersonalizado?.end,
      );

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

      setState(() {
        _carregando = false;
        _mensagemErro = 'Não foi possível carregar o dashboard.';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Falha ao carregar o dashboard: $erro'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  Future<void> _selecionarPeriodo(DashboardPeriodo periodo) async {
    if (_periodoSelecionado == periodo &&
        periodo != DashboardPeriodo.personalizado) {
      return;
    }

    if (periodo == DashboardPeriodo.personalizado) {
      final resultado = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange:
            _periodoPersonalizado ??
            DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 6)),
              end: DateTime.now(),
            ),
        helpText: 'Selecionar período personalizado',
        saveText: 'Aplicar',
        cancelText: 'Cancelar',
      );

      if (resultado == null) {
        return;
      }

      setState(() {
        _periodoSelecionado = periodo;
        _periodoPersonalizado = resultado;
      });
    } else {
      setState(() {
        _periodoSelecionado = periodo;
        _periodoPersonalizado = null;
      });
    }

    await _carregarResumo();
  }

  Future<void> _abrirPagina(Widget pagina) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
    await _carregarNomeEmpresa();
    await _carregarResumo();
  }

  Future<void> _abrirFinanceiro() async {
    await _abrirPagina(const FinanceiroPage());
  }

  Future<void> _abrirClientes() async {
    await _abrirPagina(const ClientesPage());
  }

  Future<void> _abrirVeiculos() async {
    await _abrirPagina(const VeiculosPage());
  }

  Future<void> _abrirAgenda() async {
    await _abrirPagina(const AgendaPage());
  }

  Future<void> _abrirOrdens([String? statusInicial]) async {
    await _abrirPagina(OrdensServicoPage(statusInicial: statusInicial));
  }

  Future<void> _abrirServicos() async {
    await _abrirPagina(const ServicosPage());
  }

  Future<void> _abrirEstoque() async {
    await _abrirPagina(const EstoquePage());
  }

  Future<void> _abrirFotos() async {
    await _abrirPagina(const FotosPage());
  }

  Future<void> _abrirOrcamentos() async {
    await _abrirPagina(const OrcamentosPage());
  }

  int? _normalizarIdCliente(dynamic valor) {
    if (valor is int && valor > 0) {
      return valor;
    }

    if (valor is String) {
      final id = int.tryParse(valor);
      if (id != null && id > 0) {
        return id;
      }
    }

    return null;
  }

  int? _extrairIdClienteRanking(DashboardRankingCliente item) {
    try {
      final dinamico = item as dynamic;
      return _normalizarIdCliente(dinamico.clienteId ?? dinamico.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _abrirClienteDoRanking(DashboardRankingCliente item) async {
    final clienteId = _extrairIdClienteRanking(item);
    if (clienteId == null) {
      await _abrirClientes();
      return;
    }

    final cliente = await _clienteRepository.buscarClientePorId(clienteId);
    if (!mounted) {
      return;
    }

    if (cliente == null) {
      await _abrirClientes();
      return;
    }

    await _abrirPagina(ClienteDetalhesPage(cliente: cliente));
  }

  String _saudacao() {
    final hora = DateTime.now().hour;

    if (hora < 12) {
      return 'Bom dia';
    }

    if (hora < 18) {
      return 'Boa tarde';
    }

    return 'Boa noite';
  }

  String _labelPeriodo() {
    switch (_periodoSelecionado) {
      case DashboardPeriodo.hoje:
        return 'Hoje';
      case DashboardPeriodo.ultimos7Dias:
        return 'Últimos 7 dias';
      case DashboardPeriodo.mesAtual:
        return 'Mês atual';
      case DashboardPeriodo.anoAtual:
        return 'Ano atual';
      case DashboardPeriodo.personalizado:
        if (_periodoPersonalizado == null) {
          return 'Período personalizado';
        }

        final formato = DateFormat('dd/MM/yyyy');
        return '${formato.format(_periodoPersonalizado!.start)} - ${formato.format(_periodoPersonalizado!.end)}';
    }
  }

  List<_PontoGrafico> _montarPontosGrafico(DashboardData dados) {
    return dados.serieFinanceira
        .map(
          (item) => _PontoGrafico(
            data: item.data,
            valor: item.entradas - item.saidas,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final alertasAgenda = dados == null
        ? <DashboardAlertaItem>[]
        : dados.alertas
              .where((alerta) => alerta.tipo == DashboardAlertaTipo.agendamento)
              .toList();
    final alertasOrdens = dados == null
        ? <DashboardAlertaItem>[]
        : dados.alertas
              .where(
                (alerta) => alerta.tipo == DashboardAlertaTipo.ordemServico,
              )
              .toList();
    final alertasEstoque = dados == null
        ? <DashboardAlertaItem>[]
        : dados.alertas
              .where((alerta) => alerta.tipo == DashboardAlertaTipo.estoque)
              .toList();
    final temAlertaAgenda =
        dados != null &&
        (dados.agendamentosHoje > 0 || alertasAgenda.isNotEmpty);
    final temAlertaOrdens =
        dados != null &&
        (dados.ordensAbertasAntigas > 0 ||
            dados.ordensEmAndamentoAntigas > 0 ||
            alertasOrdens.isNotEmpty);
    final temAlertaEstoque =
        dados != null &&
        (dados.produtosBaixoEstoque > 0 ||
            dados.produtosZerados > 0 ||
            alertasEstoque.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        elevation: 0,
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            onPressed: _carregarResumo,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarResumo,
        color: const Color(0xFFD6A84B),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _CabecalhoDashboard(
              empresa: _nomeEmpresa,
              periodo: _labelPeriodo(),
              onAtualizar: _carregarResumo,
              periodoSelecionado: _periodoSelecionado,
              onSelecionarPeriodo: _selecionarPeriodo,
            ),
            const SizedBox(height: 14),
            if (_carregando)
              const _LoadingCard()
            else if (_mensagemErro != null)
              _ErroCard(
                mensagem: _mensagemErro!,
                onTentarNovamente: _carregarResumo,
              )
            else if (dados != null) ...[
              _ResumoRapidoSection(
                dados: dados,
                formatoMoeda: _formatoMoeda,
                onAbrirFinanceiro: _abrirFinanceiro,
                onAbrirAgenda: _abrirAgenda,
                onAbrirOrdensEmAndamento: () => _abrirOrdens('Em andamento'),
              ),
              const SizedBox(height: 14),
              _GraficoEvolucaoCard(
                pontos: _montarPontosGrafico(dados),
                formatoMoeda: _formatoMoeda,
                periodoSelecionado: _periodoSelecionado,
              ),
              const SizedBox(height: 14),
              _GraficoFinanceiroCard(
                dados: dados,
                formatoMoeda: _formatoMoeda,
                periodoSelecionado: _periodoSelecionado,
              ),
              const SizedBox(height: 14),
              _RankingsSection(
                topServicos: dados.topServicos,
                topClientes: dados.topClientes,
                onAbrirServicos: _abrirServicos,
                onAbrirClientes: _abrirClientes,
                onAbrirClienteRanking: _abrirClienteDoRanking,
              ),
              if (temAlertaAgenda || temAlertaOrdens || temAlertaEstoque) ...[
                const SizedBox(height: 14),
                _AlertasUteisSection(
                  agendamentosHoje: dados.agendamentosHoje,
                  ordensAbertasAntigas: dados.ordensAbertasAntigas,
                  ordensEmAndamentoAntigas: dados.ordensEmAndamentoAntigas,
                  produtosBaixoEstoque: dados.produtosBaixoEstoque,
                  produtosZerados: dados.produtosZerados,
                  alertasAgenda: alertasAgenda,
                  alertasOrdens: alertasOrdens,
                  alertasEstoque: alertasEstoque,
                  onAbrirAgenda: _abrirAgenda,
                  onAbrirOrdens: () => _abrirOrdens('Todos'),
                  onAbrirEstoque: _abrirEstoque,
                ),
              ],
              const SizedBox(height: 14),
              _AtalhosRapidos(
                onAbrirAgenda: _abrirAgenda,
                onAbrirClientes: _abrirClientes,
                onAbrirVeiculos: _abrirVeiculos,
                onAbrirFinanceiro: _abrirFinanceiro,
                onAbrirEstoque: _abrirEstoque,
                onAbrirFotos: _abrirFotos,
                onAbrirOrcamentos: _abrirOrcamentos,
                onAbrirOrdens: () => _abrirOrdens('Todos'),
                onAbrirServicos: _abrirServicos,
                onAbrirConfiguracoes: () =>
                    _abrirPagina(const ConfiguracoesPage()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CabecalhoDashboard extends StatelessWidget {
  const _CabecalhoDashboard({
    required this.empresa,
    required this.periodo,
    required this.onAtualizar,
    required this.periodoSelecionado,
    required this.onSelecionarPeriodo,
  });

  final String empresa;
  final String periodo;
  final Future<void> Function() onAtualizar;
  final DashboardPeriodo periodoSelecionado;
  final Future<void> Function(DashboardPeriodo periodo) onSelecionarPeriodo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D1D1D), Color(0xFF111111)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empresa,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Período selecionado: $periodo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onAtualizar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD6A84B),
                  side: BorderSide(
                    color: const Color(0xFFD6A84B).withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FiltrosPeriodo(
            periodoSelecionado: periodoSelecionado,
            onSelecionar: onSelecionarPeriodo,
          ),
        ],
      ),
    );
  }
}

class _ResumoRapidoSection extends StatelessWidget {
  const _ResumoRapidoSection({
    required this.dados,
    required this.formatoMoeda,
    required this.onAbrirFinanceiro,
    required this.onAbrirAgenda,
    required this.onAbrirOrdensEmAndamento,
  });

  final DashboardData dados;
  final NumberFormat formatoMoeda;
  final VoidCallback onAbrirFinanceiro;
  final VoidCallback onAbrirAgenda;
  final VoidCallback onAbrirOrdensEmAndamento;

  @override
  Widget build(BuildContext context) {
    final itens = [
      _IndicadorResumo(
        'Faturamento',
        formatoMoeda.format(dados.faturamento),
        Icons.payments_outlined,
        const Color(0xFFD6A84B),
        onAbrirFinanceiro,
      ),
      _IndicadorResumo(
        'Saldo',
        formatoMoeda.format(dados.saldo),
        Icons.account_balance_wallet_outlined,
        dados.saldo >= 0 ? Colors.greenAccent : Colors.orangeAccent,
        onAbrirFinanceiro,
      ),
      _IndicadorResumo(
        'Agendamentos de hoje',
        dados.agendamentosHoje.toString(),
        Icons.today_outlined,
        Colors.lightBlueAccent,
        onAbrirAgenda,
      ),
      _IndicadorResumo(
        'OS em andamento',
        dados.ordensEmAndamento.toString(),
        Icons.car_repair_outlined,
        Colors.orangeAccent,
        onAbrirOrdensEmAndamento,
      ),
    ];

    return _MatrizIndicadores(itens: itens, aspecto: 2.3);
  }
}

class _RankingsSection extends StatelessWidget {
  const _RankingsSection({
    required this.topServicos,
    required this.topClientes,
    required this.onAbrirServicos,
    required this.onAbrirClientes,
    required this.onAbrirClienteRanking,
  });

  final List<DashboardRankingItem> topServicos;
  final List<DashboardRankingCliente> topClientes;
  final VoidCallback onAbrirServicos;
  final VoidCallback onAbrirClientes;
  final Future<void> Function(DashboardRankingCliente item)
  onAbrirClienteRanking;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rankings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _RankingServicosCard(
            itens: topServicos,
            onAbrirServicos: onAbrirServicos,
          ),
          const SizedBox(height: 12),
          _RankingClientesCard(
            itens: topClientes,
            onAbrirClientes: onAbrirClientes,
            onAbrirClienteRanking: onAbrirClienteRanking,
          ),
        ],
      ),
    );
  }
}

class _AlertasUteisSection extends StatelessWidget {
  const _AlertasUteisSection({
    required this.agendamentosHoje,
    required this.ordensAbertasAntigas,
    required this.ordensEmAndamentoAntigas,
    required this.produtosBaixoEstoque,
    required this.produtosZerados,
    required this.alertasAgenda,
    required this.alertasOrdens,
    required this.alertasEstoque,
    required this.onAbrirAgenda,
    required this.onAbrirOrdens,
    required this.onAbrirEstoque,
  });

  final int agendamentosHoje;
  final int ordensAbertasAntigas;
  final int ordensEmAndamentoAntigas;
  final int produtosBaixoEstoque;
  final int produtosZerados;
  final List<DashboardAlertaItem> alertasAgenda;
  final List<DashboardAlertaItem> alertasOrdens;
  final List<DashboardAlertaItem> alertasEstoque;
  final VoidCallback onAbrirAgenda;
  final VoidCallback onAbrirOrdens;
  final VoidCallback onAbrirEstoque;

  @override
  Widget build(BuildContext context) {
    final mostrarAgenda = agendamentosHoje > 0 || alertasAgenda.isNotEmpty;
    final mostrarOrdens =
        ordensAbertasAntigas > 0 ||
        ordensEmAndamentoAntigas > 0 ||
        alertasOrdens.isNotEmpty;
    final mostrarEstoque =
        produtosBaixoEstoque > 0 ||
        produtosZerados > 0 ||
        alertasEstoque.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alertas úteis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (mostrarAgenda) ...[
            const SizedBox(height: 12),
            _CardResumoTitulo(
              titulo: 'Agendamentos de hoje',
              actionLabel: 'Abrir agenda',
              onAction: onAbrirAgenda,
              child: Column(
                children: [
                  if (agendamentosHoje > 0)
                    _LinhaRankingClicavel(
                      titulo: 'Agendamentos para hoje',
                      quantidade: agendamentosHoje.toString(),
                      total: '0',
                      onTap: onAbrirAgenda,
                      mostraTotal: false,
                    ),
                  for (final alerta in alertasAgenda)
                    _LinhaRankingClicavel(
                      titulo: alerta.titulo,
                      subtitulo: alerta.descricao,
                      quantidade: alerta.quantidade.toString(),
                      total: '0',
                      onTap: onAbrirAgenda,
                      mostraTotal: false,
                    ),
                ],
              ),
            ),
          ],
          if (mostrarOrdens) ...[
            const SizedBox(height: 12),
            _CardResumoTitulo(
              titulo: 'OS atrasadas ou antigas',
              actionLabel: 'Abrir ordens',
              onAction: onAbrirOrdens,
              child: Column(
                children: [
                  if (ordensAbertasAntigas > 0)
                    _LinhaRankingClicavel(
                      titulo: 'OS abertas antigas',
                      quantidade: ordensAbertasAntigas.toString(),
                      total: '0',
                      onTap: onAbrirOrdens,
                      mostraTotal: false,
                    ),
                  if (ordensEmAndamentoAntigas > 0)
                    _LinhaRankingClicavel(
                      titulo: 'OS em andamento antigas',
                      quantidade: ordensEmAndamentoAntigas.toString(),
                      total: '0',
                      onTap: onAbrirOrdens,
                      mostraTotal: false,
                    ),
                  for (final alerta in alertasOrdens)
                    _LinhaRankingClicavel(
                      titulo: alerta.titulo,
                      subtitulo: alerta.descricao,
                      quantidade: alerta.quantidade.toString(),
                      total: '0',
                      onTap: onAbrirOrdens,
                      mostraTotal: false,
                    ),
                ],
              ),
            ),
          ],
          if (mostrarEstoque) ...[
            const SizedBox(height: 12),
            _CardResumoTitulo(
              titulo: 'Estoque baixo ou zerado',
              actionLabel: 'Abrir estoque',
              onAction: onAbrirEstoque,
              child: Column(
                children: [
                  if (produtosBaixoEstoque > 0)
                    _LinhaRankingClicavel(
                      titulo: 'Produtos com estoque baixo',
                      quantidade: produtosBaixoEstoque.toString(),
                      total: '0',
                      onTap: onAbrirEstoque,
                      mostraTotal: false,
                    ),
                  if (produtosZerados > 0)
                    _LinhaRankingClicavel(
                      titulo: 'Produtos zerados',
                      quantidade: produtosZerados.toString(),
                      total: '0',
                      onTap: onAbrirEstoque,
                      mostraTotal: false,
                    ),
                  for (final alerta in alertasEstoque)
                    _LinhaRankingClicavel(
                      titulo: alerta.titulo,
                      subtitulo: alerta.descricao,
                      quantidade: alerta.quantidade.toString(),
                      total: '0',
                      onTap: onAbrirEstoque,
                      mostraTotal: false,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatrizIndicadores extends StatelessWidget {
  const _MatrizIndicadores({required this.itens, this.aspecto = 2.0});

  final List<_IndicadorResumo> itens;
  final double aspecto;

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return const _EstadoVazio(
        titulo: 'Sem indicadores',
        mensagem: 'Não há dados suficientes para este bloco.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth < 520 ? 1 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itens.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colunas,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: colunas == 1 ? 3.6 : aspecto,
          ),
          itemBuilder: (context, index) {
            return _IndicadorCard(item: itens[index]);
          },
        );
      },
    );
  }
}

class _GraficoFinanceiroCard extends StatelessWidget {
  const _GraficoFinanceiroCard({
    required this.dados,
    required this.formatoMoeda,
    required this.periodoSelecionado,
  });

  final DashboardData dados;
  final NumberFormat formatoMoeda;
  final DashboardPeriodo periodoSelecionado;

  @override
  Widget build(BuildContext context) {
    final pontos = dados.serieFinanceira;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Entradas e saídas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Comparativo financeiro do período selecionado.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: pontos.isEmpty
                ? const _EstadoVazio(
                    titulo: 'Sem movimentação',
                    mensagem: 'Não há entradas ou saídas no período.',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final datas = pontos.map((item) => item.data).toList();
                      final axisConfig = _DashboardBottomAxisConfig.criar(
                        periodo: periodoSelecionado,
                        datas: datas,
                        maxWidth: constraints.maxWidth,
                      );

                      return BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: BarTouchData(enabled: false),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.white.withValues(alpha: 0.08),
                              strokeWidth: 1,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: axisConfig.interval,
                                minIncluded: axisConfig.minIncluded,
                                maxIncluded: axisConfig.maxIncluded,
                                reservedSize: axisConfig.reservedSize,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= pontos.length) {
                                    return const SizedBox.shrink();
                                  }

                                  if (!axisConfig.visibleIndices.contains(
                                    index,
                                  )) {
                                    return const SizedBox.shrink();
                                  }

                                  final texto = axisConfig.formatarLabel(
                                    periodo: periodoSelecionado,
                                    datas: datas,
                                    index: index,
                                  );
                                  final alinhamento = index == 0
                                      ? TextAlign.left
                                      : index == pontos.length - 1
                                      ? TextAlign.right
                                      : TextAlign.center;

                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 10,
                                    fitInside: SideTitleFitInsideData(
                                      enabled: true,
                                      distanceFromEdge: 8,
                                      parentAxisSize: meta.parentAxisSize,
                                      axisPosition: meta.axisPosition,
                                    ),
                                    child: SizedBox(
                                      width: axisConfig.labelWidth,
                                      child: Text(
                                        texto,
                                        maxLines: 1,
                                        textAlign: alinhamento,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < pontos.length; i++)
                              BarChartGroupData(
                                x: i,
                                barsSpace: 6,
                                barRods: [
                                  BarChartRodData(
                                    toY: pontos[i].entradas,
                                    width: 8,
                                    color: const Color(0xFFD6A84B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  BarChartRodData(
                                    toY: pontos[i].saidas,
                                    width: 8,
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _LegendaGrafico(
                cor: const Color(0xFFD6A84B),
                texto: 'Entradas',
                valor: formatoMoeda.format(dados.faturamento),
              ),
              _LegendaGrafico(
                cor: Colors.redAccent,
                texto: 'Saídas',
                valor: formatoMoeda.format(dados.saidas),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GraficoEvolucaoCard extends StatelessWidget {
  const _GraficoEvolucaoCard({
    required this.pontos,
    required this.formatoMoeda,
    required this.periodoSelecionado,
  });

  final List<_PontoGrafico> pontos;
  final NumberFormat formatoMoeda;
  final DashboardPeriodo periodoSelecionado;

  @override
  Widget build(BuildContext context) {
    final total = pontos.fold<double>(0, (soma, item) => soma + item.valor);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatoMoeda.format(total),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Evolução líquida do período.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: pontos.isEmpty
                ? const _EstadoVazio(
                    titulo: 'Sem série disponível',
                    mensagem:
                        'A evolução do período será exibida quando houver dados.',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final datas = pontos.map((item) => item.data).toList();
                      final axisConfig = _DashboardBottomAxisConfig.criar(
                        periodo: periodoSelecionado,
                        datas: datas,
                        maxWidth: constraints.maxWidth,
                      );

                      return LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.white.withValues(alpha: 0.08),
                              strokeWidth: 1,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: axisConfig.interval,
                                minIncluded: axisConfig.minIncluded,
                                maxIncluded: axisConfig.maxIncluded,
                                reservedSize: axisConfig.reservedSize,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= pontos.length) {
                                    return const SizedBox.shrink();
                                  }

                                  if (!axisConfig.visibleIndices.contains(
                                    index,
                                  )) {
                                    return const SizedBox.shrink();
                                  }

                                  final texto = axisConfig.formatarLabel(
                                    periodo: periodoSelecionado,
                                    datas: datas,
                                    index: index,
                                  );
                                  final alinhamento = index == 0
                                      ? TextAlign.left
                                      : index == pontos.length - 1
                                      ? TextAlign.right
                                      : TextAlign.center;

                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 10,
                                    fitInside: SideTitleFitInsideData(
                                      enabled: true,
                                      distanceFromEdge: 8,
                                      parentAxisSize: meta.parentAxisSize,
                                      axisPosition: meta.axisPosition,
                                    ),
                                    child: SizedBox(
                                      width: axisConfig.labelWidth,
                                      child: Text(
                                        texto,
                                        maxLines: 1,
                                        textAlign: alinhamento,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          minY: 0,
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < pontos.length; i++)
                                  FlSpot(i.toDouble(), pontos[i].valor),
                              ],
                              isCurved: true,
                              color: const Color(0xFFD6A84B),
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(
                                      0xFFD6A84B,
                                    ).withValues(alpha: 0.25),
                                    const Color(
                                      0xFFD6A84B,
                                    ).withValues(alpha: 0.03),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankingClientesCard extends StatelessWidget {
  const _RankingClientesCard({
    required this.itens,
    required this.onAbrirClientes,
    required this.onAbrirClienteRanking,
  });

  final List<DashboardRankingCliente> itens;
  final VoidCallback onAbrirClientes;
  final Future<void> Function(DashboardRankingCliente item)
  onAbrirClienteRanking;

  @override
  Widget build(BuildContext context) {
    return _CardResumoTitulo(
      titulo: 'Top 5 clientes',
      actionLabel: 'Abrir clientes',
      onAction: onAbrirClientes,
      child: itens.isEmpty
          ? const _EstadoVazio(
              titulo: 'Sem clientes no período',
              mensagem:
                  'Os clientes aparecerão quando houver ordens finalizadas.',
            )
          : Column(
              children: [
                for (var i = 0; i < itens.length; i++)
                  _LinhaRankingClicavel(
                    titulo: itens[i].nome,
                    posicao: i + 1,
                    quantidade: itens[i].quantidade.toString(),
                    total: NumberFormat.currency(
                      locale: 'pt_BR',
                      symbol: 'R\$',
                    ).format(itens[i].total),
                    onTap: () => onAbrirClienteRanking(itens[i]),
                  ),
              ],
            ),
    );
  }
}

class _RankingServicosCard extends StatelessWidget {
  const _RankingServicosCard({
    required this.itens,
    required this.onAbrirServicos,
  });

  final List<DashboardRankingItem> itens;
  final VoidCallback onAbrirServicos;

  @override
  Widget build(BuildContext context) {
    return _CardResumoTitulo(
      titulo: 'Top 5 serviços',
      actionLabel: 'Abrir serviços',
      onAction: onAbrirServicos,
      child: itens.isEmpty
          ? const _EstadoVazio(
              titulo: 'Sem serviços no período',
              mensagem:
                  'Os serviços aparecerão quando houver execução registrada.',
            )
          : Column(
              children: [
                for (var i = 0; i < itens.length; i++)
                  _LinhaRankingClicavel(
                    titulo: itens[i].nome,
                    posicao: i + 1,
                    quantidade: itens[i].quantidade.toString(),
                    total: NumberFormat.currency(
                      locale: 'pt_BR',
                      symbol: 'R\$',
                    ).format(itens[i].total),
                    onTap: onAbrirServicos,
                  ),
              ],
            ),
    );
  }
}

class _CardResumoTitulo extends StatelessWidget {
  const _CardResumoTitulo({
    required this.titulo,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String titulo;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.chevron_right_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _LinhaRankingClicavel extends StatelessWidget {
  const _LinhaRankingClicavel({
    required this.titulo,
    required this.quantidade,
    required this.total,
    required this.onTap,
    this.subtitulo,
    this.mostraTotal = true,
    this.posicao,
  });

  final String titulo;
  final String quantidade;
  final String total;
  final String? subtitulo;
  final VoidCallback onTap;
  final bool mostraTotal;
  final int? posicao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    (posicao ?? 0) > 0 ? posicao.toString() : quantidade,
                    style: const TextStyle(
                      color: Color(0xFFD6A84B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if ((subtitulo ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (mostraTotal) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Qtd: $quantidade',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        total,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(width: 10),
                  Text(
                    'Qtd: $quantidade',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.titulo, required this.mensagem});

  final String titulo;
  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, color: Colors.white38, size: 28),
          const SizedBox(height: 8),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LegendaGrafico extends StatelessWidget {
  const _LegendaGrafico({
    required this.cor,
    required this.texto,
    required this.valor,
  });

  final Color cor;
  final String texto;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$texto: $valor',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _HeroCabecalho extends StatelessWidget {
  const _HeroCabecalho({
    required this.saudacao,
    required this.periodo,
    required this.empresa,
  });

  final String saudacao;
  final String periodo;
  final String empresa;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E1E), Color(0xFF121212)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$saudacao, $empresa',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Dashboard premium pronta para uso diário.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              periodo,
              style: const TextStyle(
                color: Color(0xFFD6A84B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltrosPeriodo extends StatelessWidget {
  const _FiltrosPeriodo({
    required this.periodoSelecionado,
    required this.onSelecionar,
  });

  final DashboardPeriodo periodoSelecionado;
  final Future<void> Function(DashboardPeriodo periodo) onSelecionar;

  @override
  Widget build(BuildContext context) {
    final opcoes = <DashboardPeriodo, String>{
      DashboardPeriodo.hoje: 'Hoje',
      DashboardPeriodo.ultimos7Dias: 'Últimos 7 dias',
      DashboardPeriodo.mesAtual: 'Mês atual',
      DashboardPeriodo.anoAtual: 'Ano atual',
      DashboardPeriodo.personalizado: 'Período personalizado',
    };

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: opcoes.entries.map((entry) {
        final selecionado = entry.key == periodoSelecionado;
        return ChoiceChip(
          label: Text(entry.value),
          selected: selecionado,
          selectedColor: const Color(0xFFD6A84B),
          backgroundColor: const Color(0xFF1B1B1B),
          labelStyle: TextStyle(
            color: selecionado ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(
            color: selecionado
                ? const Color(0xFFD6A84B)
                : Colors.white.withValues(alpha: 0.12),
          ),
          onSelected: (_) => onSelecionar(entry.key),
        );
      }).toList(),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFFD6A84B)),
      ),
    );
  }
}

class _ErroCard extends StatelessWidget {
  const _ErroCard({required this.mensagem, required this.onTentarNovamente});

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1717),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Falha ao carregar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(mensagem, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onTentarNovamente,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _IndicadorResumo {
  const _IndicadorResumo(
    this.titulo,
    this.valor,
    this.icone,
    this.cor,
    this.onTap,
  );

  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;
  final VoidCallback? onTap;
}

class _IndicadorCard extends StatelessWidget {
  const _IndicadorCard({required this.item});

  final _IndicadorResumo item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: item.cor.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(item.icone, color: item.cor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumoExecutivoCard extends StatelessWidget {
  const _ResumoExecutivoCard({required this.dados});

  final DashboardData dados;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo executivo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Clientes',
                  valor: dados.clientesTotal.toString(),
                  icone: Icons.groups_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Veículos',
                  valor: dados.veiculosTotal.toString(),
                  icone: Icons.directions_car_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'OS antigas abertas',
                  valor: dados.ordensAbertasAntigas.toString(),
                  icone: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'OS antigas em andamento',
                  valor: dados.ordensEmAndamentoAntigas.toString(),
                  icone: Icons.timelapse_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Produtos baixo estoque',
                  valor: dados.produtosBaixoEstoque.toString(),
                  icone: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResumoPequeno(
                  titulo: 'Produtos zerados',
                  valor: dados.produtosZerados.toString(),
                  icone: Icons.do_not_disturb_on_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumoPequeno extends StatelessWidget {
  const _ResumoPequeno({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: const Color(0xFFD6A84B), size: 20),
          const SizedBox(height: 10),
          Text(
            valor,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _GraficoReceitaCard extends StatelessWidget {
  const _GraficoReceitaCard({required this.pontos, required this.formatoMoeda});

  final List<_PontoGrafico> pontos;
  final NumberFormat formatoMoeda;

  @override
  Widget build(BuildContext context) {
    final total = pontos.fold<double>(0, (soma, item) => soma + item.valor);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatoMoeda.format(total),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Faturamento líquido do período',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: pontos.isEmpty
                ? const Center(
                    child: Text(
                      'Sem movimentação para o período selecionado.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white.withValues(alpha: 0.08),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= pontos.length) {
                                return const SizedBox.shrink();
                              }

                              final data = pontos[index].data;
                              final texto = pontos.length > 7
                                  ? DateFormat('MM/yy').format(data)
                                  : DateFormat('dd/MM').format(data);

                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  texto,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < pontos.length; i++)
                              FlSpot(i.toDouble(), pontos[i].valor),
                          ],
                          isCurved: true,
                          color: const Color(0xFFD6A84B),
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFD6A84B).withValues(alpha: 0.35),
                                const Color(0xFFD6A84B).withValues(alpha: 0.03),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.dados});

  final DashboardData dados;

  @override
  Widget build(BuildContext context) {
    if (!dados.temAlertas) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Text(
          'Nenhum alerta relevante para o momento.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alertas operacionais',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...dados.alertas.map(
            (alerta) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: alerta.tipo == DashboardAlertaTipo.estoque
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: alerta.tipo == DashboardAlertaTipo.estoque
                        ? Colors.orange.withValues(alpha: 0.22)
                        : Colors.red.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      alerta.tipo == DashboardAlertaTipo.agendamento
                          ? Icons.event_available_outlined
                          : alerta.tipo == DashboardAlertaTipo.estoque
                          ? Icons.inventory_2_outlined
                          : Icons.warning_amber_rounded,
                      color: const Color(0xFFD6A84B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alerta.titulo,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            alerta.descricao,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      alerta.quantidade.toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD6A84B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.titulo, required this.itens});

  final String titulo;
  final List<_RankingLinha> itens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (itens.isEmpty)
            const Text(
              'Sem dados suficientes.',
              style: TextStyle(color: Colors.white60),
            )
          else
            ...itens.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.quantidade.toString(),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      NumberFormat.currency(
                        locale: 'pt_BR',
                        symbol: 'R\$',
                      ).format(item.total),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingLinha {
  const _RankingLinha({
    required this.nome,
    required this.quantidade,
    required this.total,
  });

  final String nome;
  final int quantidade;
  final double total;
}

class _AtalhosRapidos extends StatelessWidget {
  const _AtalhosRapidos({
    required this.onAbrirAgenda,
    required this.onAbrirClientes,
    required this.onAbrirVeiculos,
    required this.onAbrirFinanceiro,
    required this.onAbrirEstoque,
    required this.onAbrirFotos,
    required this.onAbrirOrcamentos,
    required this.onAbrirOrdens,
    required this.onAbrirServicos,
    required this.onAbrirConfiguracoes,
  });

  final VoidCallback onAbrirAgenda;
  final VoidCallback onAbrirClientes;
  final VoidCallback onAbrirVeiculos;
  final VoidCallback onAbrirFinanceiro;
  final VoidCallback onAbrirEstoque;
  final VoidCallback onAbrirFotos;
  final VoidCallback onAbrirOrcamentos;
  final VoidCallback onAbrirOrdens;
  final VoidCallback onAbrirServicos;
  final VoidCallback onAbrirConfiguracoes;

  @override
  Widget build(BuildContext context) {
    final itens = <_AtalhoItem>[
      _AtalhoItem('Agenda', Icons.calendar_month_outlined, onAbrirAgenda),
      _AtalhoItem('Clientes', Icons.people_outline, onAbrirClientes),
      _AtalhoItem('Veículos', Icons.directions_car_outlined, onAbrirVeiculos),
      _AtalhoItem('Financeiro', Icons.payments_outlined, onAbrirFinanceiro),
      _AtalhoItem('Estoque', Icons.inventory_2_outlined, onAbrirEstoque),
      _AtalhoItem('Fotos', Icons.photo_library_outlined, onAbrirFotos),
      _AtalhoItem(
        'Orçamentos',
        Icons.request_quote_outlined,
        onAbrirOrcamentos,
      ),
      _AtalhoItem('Ordens', Icons.assignment_outlined, onAbrirOrdens),
      _AtalhoItem(
        'Serviços',
        Icons.miscellaneous_services_outlined,
        onAbrirServicos,
      ),
      _AtalhoItem(
        'Configurações',
        Icons.settings_outlined,
        onAbrirConfiguracoes,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acesso rápido',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itens.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5,
            ),
            itemBuilder: (context, index) {
              final item = itens[index];
              return InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(item.icone, color: const Color(0xFFD6A84B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AtalhoItem {
  const _AtalhoItem(this.titulo, this.icone, this.onTap);

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;
}

class _PontoGrafico {
  const _PontoGrafico({required this.data, required this.valor});

  final DateTime data;
  final double valor;
}

class _DashboardBottomAxisConfig {
  const _DashboardBottomAxisConfig({
    required this.visibleIndices,
    required this.interval,
    required this.reservedSize,
    required this.labelWidth,
    required this.minIncluded,
    required this.maxIncluded,
  });

  final Set<int> visibleIndices;
  final double interval;
  final double reservedSize;
  final double labelWidth;
  final bool minIncluded;
  final bool maxIncluded;

  static const List<String> _mesesAbreviados = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];

  static _DashboardBottomAxisConfig criar({
    required DashboardPeriodo periodo,
    required List<DateTime> datas,
    required double maxWidth,
  }) {
    final total = datas.length;

    if (total <= 0) {
      return const _DashboardBottomAxisConfig(
        visibleIndices: <int>{},
        interval: 1,
        reservedSize: 0,
        labelWidth: 0,
        minIncluded: false,
        maxIncluded: false,
      );
    }

    final espacamentoMinimo = _espacamentoMinimo(periodo);
    final maximoPorLargura = (maxWidth / espacamentoMinimo).floor().clamp(
      1,
      total,
    );
    final alvo = _alvoLabels(periodo, total, datas);
    final quantidade = periodo == DashboardPeriodo.anoAtual
        ? total.clamp(1, 12)
        : alvo.clamp(1, maximoPorLargura);
    final indices = _indicesVisiveis(
      total: total,
      quantidade: quantidade,
      centralizarUnico: periodo == DashboardPeriodo.hoje,
    );
    final larguraLabel = maxWidth <= 0
        ? espacamentoMinimo
        : (maxWidth / indices.length).clamp(espacamentoMinimo, maxWidth);

    return _DashboardBottomAxisConfig(
      visibleIndices: indices,
      interval: _calcularIntervalo(indices),
      reservedSize: _reservedSize(periodo),
      labelWidth: larguraLabel,
      minIncluded: periodo != DashboardPeriodo.hoje,
      maxIncluded: periodo != DashboardPeriodo.hoje,
    );
  }

  String formatarLabel({
    required DashboardPeriodo periodo,
    required List<DateTime> datas,
    required int index,
  }) {
    final data = datas[index];

    switch (periodo) {
      case DashboardPeriodo.hoje:
        return 'Hoje';
      case DashboardPeriodo.ultimos7Dias:
      case DashboardPeriodo.mesAtual:
        return DateFormat('dd/MM').format(data);
      case DashboardPeriodo.anoAtual:
        return _mesesAbreviados[data.month - 1];
      case DashboardPeriodo.personalizado:
        return _usarFormatoMensal(datas)
            ? _formatarMesAno(data)
            : DateFormat('dd/MM').format(data);
    }
  }

  static int _alvoLabels(
    DashboardPeriodo periodo,
    int totalPontos,
    List<DateTime> datas,
  ) {
    switch (periodo) {
      case DashboardPeriodo.hoje:
        return 1;
      case DashboardPeriodo.ultimos7Dias:
        return totalPontos.clamp(1, 7);
      case DashboardPeriodo.mesAtual:
        return totalPontos <= 7 ? totalPontos : 6;
      case DashboardPeriodo.anoAtual:
        return totalPontos.clamp(1, 12);
      case DashboardPeriodo.personalizado:
        return _usarFormatoMensal(datas) ? 6 : 7;
    }
  }

  static Set<int> _indicesVisiveis({
    required int total,
    required int quantidade,
    required bool centralizarUnico,
  }) {
    if (quantidade >= total) {
      return {for (var i = 0; i < total; i++) i};
    }

    if (quantidade <= 1) {
      return {centralizarUnico ? total ~/ 2 : 0};
    }

    final passo = ((total - 1) / (quantidade - 1)).ceil().clamp(1, total - 1);
    final indices = <int>{};

    for (var indice = 0; indice < total; indice += passo) {
      indices.add(indice);
    }

    indices.add(total - 1);

    return indices;
  }

  static double _calcularIntervalo(Set<int> indices) {
    if (indices.length <= 1) {
      return 1;
    }

    final ordenados = indices.toList()..sort();
    final primeiroIntervalo = ordenados[1] - ordenados[0];

    return primeiroIntervalo <= 0 ? 1 : primeiroIntervalo.toDouble();
  }

  static double _espacamentoMinimo(DashboardPeriodo periodo) {
    switch (periodo) {
      case DashboardPeriodo.hoje:
        return 64;
      case DashboardPeriodo.ultimos7Dias:
        return 40;
      case DashboardPeriodo.mesAtual:
        return 52;
      case DashboardPeriodo.anoAtual:
        return 28;
      case DashboardPeriodo.personalizado:
        return 54;
    }
  }

  static double _reservedSize(DashboardPeriodo periodo) {
    switch (periodo) {
      case DashboardPeriodo.anoAtual:
        return 30;
      case DashboardPeriodo.hoje:
        return 36;
      case DashboardPeriodo.ultimos7Dias:
      case DashboardPeriodo.mesAtual:
      case DashboardPeriodo.personalizado:
        return 40;
    }
  }

  static bool _usarFormatoMensal(List<DateTime> datas) {
    if (datas.length <= 1) {
      return false;
    }

    return datas.last.difference(datas.first).inDays > 62;
  }

  static String _formatarMesAno(DateTime data) {
    final texto = DateFormat('MMM/yy', 'pt_BR').format(data);
    return texto.substring(0, 1).toUpperCase() + texto.substring(1);
  }
}
