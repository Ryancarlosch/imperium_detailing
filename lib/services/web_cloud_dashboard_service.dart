import 'web_cloud_contas_service.dart';
import 'web_cloud_operacional_service.dart';
import 'web_cloud_relatorios_service.dart';

class WebDashboardGerencialResumo {
  const WebDashboardGerencialResumo({
    required this.operacional,
    required this.financeiro,
    required this.contas,
    required this.saldoConsolidado,
  });

  final Map<String, Object?> operacional;
  final WebRelatoriosResumo financeiro;
  final List<WebContaFinanceiraResumo> contas;
  final double saldoConsolidado;
}

class WebCloudDashboardService {
  WebCloudDashboardService._();

  static final WebCloudDashboardService instance = WebCloudDashboardService._();

  Future<WebDashboardGerencialResumo> carregar() async {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, 1);
    final fim = DateTime(agora.year, agora.month + 1, 0);

    final resultados = await Future.wait<dynamic>([
      WebCloudOperacionalService.instance.carregarResumo(),
      WebCloudRelatoriosService.instance.carregar(inicio: inicio, fim: fim),
      WebCloudContasService.instance.listarContas(incluirInativas: false),
    ]);

    final contas = List<WebContaFinanceiraResumo>.from(
      resultados[2] as List<WebContaFinanceiraResumo>,
    );
    final saldo = contas.fold<double>(
      0,
      (total, conta) => total + conta.saldoAtual,
    );

    return WebDashboardGerencialResumo(
      operacional: Map<String, Object?>.from(
        resultados[0] as Map<String, Object?>,
      ),
      financeiro: resultados[1] as WebRelatoriosResumo,
      contas: contas,
      saldoConsolidado: saldo,
    );
  }
}
