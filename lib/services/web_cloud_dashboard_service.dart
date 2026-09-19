import '../domain/ordem_servico_valor.dart';
import 'web_cloud_contas_service.dart';
import 'comercial_growth_cloud_service.dart';
import 'web_cloud_expansao_service.dart';
import 'web_estoque_cloud_service.dart';
import 'web_cloud_operacional_service.dart';
import 'web_cloud_relatorios_service.dart';

class WebDashboardComercialResumo {
  const WebDashboardComercialResumo({
    required this.leadsAbertos,
    required this.leadsGanhos,
    required this.potencial,
    required this.posVendaAcoes,
    required this.posVendaReativacao,
    required this.campanhasAtivas,
    required this.marketingLeads,
    required this.marketingRoas,
    required this.marketingFaturamento,
  });

  final int leadsAbertos;
  final int leadsGanhos;
  final double potencial;
  final int posVendaAcoes;
  final int posVendaReativacao;
  final int campanhasAtivas;
  final int marketingLeads;
  final double marketingRoas;
  final double marketingFaturamento;

  static const vazio = WebDashboardComercialResumo(
    leadsAbertos: 0,
    leadsGanhos: 0,
    potencial: 0,
    posVendaAcoes: 0,
    posVendaReativacao: 0,
    campanhasAtivas: 0,
    marketingLeads: 0,
    marketingRoas: 0,
    marketingFaturamento: 0,
  );
}

class WebDashboardGerencialResumo {
  const WebDashboardGerencialResumo({
    required this.operacional,
    required this.financeiro,
    required this.contas,
    required this.saldoConsolidado,
    required this.agendaHoje,
    required this.ordensAbertas,
    required this.comercial,
    required this.estoqueAlertas,
  });

  final Map<String, Object?> operacional;
  final WebRelatoriosResumo financeiro;
  final List<WebContaFinanceiraResumo> contas;
  final double saldoConsolidado;
  final List<Map<String, dynamic>> agendaHoje;
  final List<Map<String, dynamic>> ordensAbertas;
  final WebDashboardComercialResumo comercial;
  final int estoqueAlertas;
}

class WebCloudDashboardService {
  WebCloudDashboardService._();

  static final WebCloudDashboardService instance = WebCloudDashboardService._();

  Future<WebDashboardGerencialResumo> carregar() async {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, 1);
    final fim = DateTime(agora.year, agora.month + 1, 0);
    final operacional = WebCloudOperacionalService.instance;

    final resultados = await Future.wait<dynamic>([
      operacional.carregarResumo(),
      WebCloudRelatoriosService.instance.carregar(inicio: inicio, fim: fim),
      WebCloudContasService.instance.listarContas(incluirInativas: false),
      operacional.listarClientes(),
      operacional.listarVeiculos(),
      operacional.listarAgendamentos(),
      operacional.listarOrdens(),
    ]);

    final contas = List<WebContaFinanceiraResumo>.from(
      resultados[2] as List<WebContaFinanceiraResumo>,
    );
    final clientes = resultados[3] as List<Map<String, dynamic>>;
    final veiculos = resultados[4] as List<Map<String, dynamic>>;
    final agenda = resultados[5] as List<Map<String, dynamic>>;
    final ordens = resultados[6] as List<Map<String, dynamic>>;

    final nomes = <String, String>{
      for (final cliente in clientes)
        (cliente['id'] ?? '').toString(): (cliente['nome'] ?? 'Cliente')
            .toString(),
    };
    final carros = <String, String>{
      for (final veiculo in veiculos)
        (veiculo['id'] ?? '').toString(): [
          (veiculo['marca'] ?? '').toString(),
          (veiculo['modelo'] ?? '').toString(),
          (veiculo['placa'] ?? '').toString(),
        ].where((e) => e.trim().isNotEmpty).join(' '),
    };

    final hoje = DateTime(agora.year, agora.month, agora.day);

    final agendaHoje =
        agenda
            .where((item) {
              if (!_statusAgendaAberto(item['status'])) return false;
              final data = _parseData(item['data']);
              if (data == null) return false;
              return data.year == hoje.year &&
                  data.month == hoje.month &&
                  data.day == hoje.day;
            })
            .map((item) {
              return <String, dynamic>{
                ...item,
                '_cliente_nome':
                    nomes[(item['cliente_id'] ?? '').toString()] ?? 'Cliente',
                '_veiculo_nome':
                    carros[(item['veiculo_id'] ?? '').toString()] ?? '',
              };
            })
            .toList()
          ..sort(
            (a, b) => (a['hora'] ?? '').toString().compareTo(
              (b['hora'] ?? '').toString(),
            ),
          );

    final ordensAbertas =
        ordens
            .where((item) {
              final status = (item['status'] ?? '').toString();
              return status == 'Aberta' || status == 'Em andamento';
            })
            .map((item) {
              final negociado = OrdemServicoValor.valorNegociado(
                valorTotal: _double(item['valor_total']),
                desconto: _double(item['desconto']),
                descontoNegociacao: _double(item['desconto_negociacao']),
                acrescimoNegociacao: _double(item['acrescimo_negociacao']),
                jurosParcelamento: _double(item['juros_parcelamento']),
              );
              final recebido = _double(item['valor_recebido']);

              return <String, dynamic>{
                ...item,
                '_cliente_nome':
                    nomes[(item['cliente_id'] ?? '').toString()] ?? 'Cliente',
                '_veiculo_nome':
                    carros[(item['veiculo_id'] ?? '').toString()] ?? '',
                '_valor_negociado': negociado,
                '_pendente': (negociado - recebido).clamp(0, double.infinity),
              };
            })
            .toList()
          ..sort((a, b) {
            final statusA = (a['status'] ?? '').toString();
            final statusB = (b['status'] ?? '').toString();
            if (statusA != statusB) {
              if (statusA == 'Em andamento') return -1;
              if (statusB == 'Em andamento') return 1;
            }

            final dataA = _parseData(a['data_abertura']) ?? DateTime(2000);
            final dataB = _parseData(b['data_abertura']) ?? DateTime(2000);
            return dataB.compareTo(dataA);
          });

    final saldo = contas.fold<double>(
      0,
      (total, conta) => total + conta.saldoAtual,
    );

    var comercial = WebDashboardComercialResumo.vazio;

    try {
      final leads = await WebCloudExpansaoService.instance.listarLeads();
      final leadsAbertos = leads
          .where((e) => e['etapa'] != 'Ganho' && e['etapa'] != 'Perdido')
          .length;
      final leadsGanhos = leads.where((e) => e['etapa'] == 'Ganho').length;
      final potencial = leads
          .where((e) => e['etapa'] != 'Perdido')
          .fold<double>(0, (total, e) => total + _double(e['valor_potencial']));

      var posVendaAcoes = 0;
      var posVendaReativacao = 0;
      var campanhasAtivas = 0;
      var marketingLeads = 0;
      var marketingRoas = 0.0;
      var marketingFaturamento = 0.0;

      try {
        final painel = await ComercialGrowthCloudService.instance
            .carregarPosVenda();
        posVendaAcoes = painel.precisamAcao;
        posVendaReativacao = painel.reativacao;
      } catch (_) {
        // Mantém o dashboard principal disponível mesmo se o pós-venda falhar.
      }

      try {
        final marketing = await ComercialGrowthCloudService.instance
            .carregarResumoMarketing();
        campanhasAtivas = marketing.campanhasAtivas;
        marketingLeads = marketing.leads;
        marketingRoas = marketing.roas;
        marketingFaturamento = marketing.faturamentoAtribuido;
      } catch (_) {
        // Mantém o dashboard principal disponível mesmo se marketing falhar.
      }

      comercial = WebDashboardComercialResumo(
        leadsAbertos: leadsAbertos,
        leadsGanhos: leadsGanhos,
        potencial: potencial,
        posVendaAcoes: posVendaAcoes,
        posVendaReativacao: posVendaReativacao,
        campanhasAtivas: campanhasAtivas,
        marketingLeads: marketingLeads,
        marketingRoas: marketingRoas,
        marketingFaturamento: marketingFaturamento,
      );
    } catch (_) {
      // CRM é complementar ao resumo operacional/financeiro.
    }

    var estoqueAlertas = 0;
    try {
      estoqueAlertas =
          (await WebEstoqueCloudService.instance.listarAlertas()).length;
    } catch (_) {
      // Estoque é complementar ao resumo principal do dashboard.
    }

    return WebDashboardGerencialResumo(
      operacional: Map<String, Object?>.from(
        resultados[0] as Map<String, Object?>,
      ),
      financeiro: resultados[1] as WebRelatoriosResumo,
      contas: contas,
      saldoConsolidado: saldo,
      agendaHoje: agendaHoje,
      ordensAbertas: ordensAbertas,
      comercial: comercial,
      estoqueAlertas: estoqueAlertas,
    );
  }

  static bool _statusAgendaAberto(dynamic raw) {
    final status = raw?.toString().trim().toLowerCase() ?? '';
    return !{
      'cancelado',
      'cancelada',
      'concluído',
      'concluido',
      'finalizado',
      'finalizada',
    }.contains(status);
  }

  static DateTime? _parseData(dynamic raw) {
    final texto = raw?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso.toLocal();

    final barras = texto.split('/');
    if (barras.length == 3) {
      final dia = int.tryParse(barras[0]);
      final mes = int.tryParse(barras[1]);
      final ano = int.tryParse(barras[2]);
      if (dia != null && mes != null && ano != null) {
        return DateTime(ano, mes, dia);
      }
    }

    return null;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
