import '../database/app_database.dart';
import '../domain/ordem_servico_valor.dart';
import 'supabase_bootstrap.dart';
import 'web_cloud_dre_service.dart';

class WebRelatoriosExecutor {
  const WebRelatoriosExecutor({
    required this.nome,
    required this.quantidade,
    required this.vendas,
    required this.recebido,
  });

  final String nome;
  final int quantidade;
  final double vendas;
  final double recebido;
}

class WebRelatoriosResumo {
  const WebRelatoriosResumo({
    required this.competencia,
    required this.caixa,
    required this.ordens,
    required this.executores,
    required this.vendas,
    required this.recebido,
    required this.aReceber,
  });

  final WebDreResultado competencia;
  final WebDreResultado caixa;
  final List<Map<String, dynamic>> ordens;
  final List<WebRelatoriosExecutor> executores;
  final double vendas;
  final double recebido;
  final double aReceber;

  int get quantidadeOrdens => ordens.length;
  double get ticketMedio =>
      quantidadeOrdens == 0 ? 0 : vendas / quantidadeOrdens;
}

class WebCloudRelatoriosService {
  WebCloudRelatoriosService._();

  static final WebCloudRelatoriosService instance =
      WebCloudRelatoriosService._();

  Future<WebRelatoriosResumo> carregar({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    if (inicio.isAfter(fim)) {
      throw ArgumentError('A data inicial não pode ser posterior à final.');
    }

    final resultados = await Future.wait<dynamic>([
      WebCloudDreService.instance.calcular(
        inicio: inicio,
        fim: fim,
        regime: WebDreRegime.competencia,
      ),
      WebCloudDreService.instance.calcular(
        inicio: inicio,
        fim: fim,
        regime: WebDreRegime.caixa,
      ),
      _listarOrdens(),
    ]);

    final inicioDia = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);

    final ordens =
        List<Map<String, dynamic>>.from(
          resultados[2] as List<Map<String, dynamic>>,
        ).where((ordem) {
          final data = _parseData(ordem['data_finalizacao']?.toString());
          if (data == null ||
              data.isBefore(inicioDia) ||
              data.isAfter(fimDia)) {
            return false;
          }

          final status = (ordem['status'] ?? '').toString().toLowerCase();
          return !status.contains('cancel') && !status.contains('estorn');
        }).toList();

    ordens.sort((a, b) => vendaOrdem(b).compareTo(vendaOrdem(a)));

    var vendas = 0.0;
    var recebido = 0.0;
    var aReceber = 0.0;
    final executores = <String, _ExecutorAcumulado>{};

    for (final ordem in ordens) {
      final venda = vendaOrdem(ordem);
      final recebidoOs = _double(
        ordem['valor_recebido'],
      ).clamp(0, double.infinity).toDouble();
      final pendente = (venda - recebidoOs)
          .clamp(0, double.infinity)
          .toDouble();
      final executorBruto = (ordem['funcionario_responsavel'] ?? '')
          .toString()
          .trim();
      final executor = executorBruto.isEmpty
          ? 'Sem executor informado'
          : executorBruto;

      vendas += venda;
      recebido += recebidoOs;
      aReceber += pendente;

      final atual = executores.putIfAbsent(executor, _ExecutorAcumulado.new);
      atual.quantidade += 1;
      atual.vendas += venda;
      atual.recebido += recebidoOs;
    }

    final rankingExecutores =
        executores.entries
            .map(
              (entry) => WebRelatoriosExecutor(
                nome: entry.key,
                quantidade: entry.value.quantidade,
                vendas: entry.value.vendas,
                recebido: entry.value.recebido,
              ),
            )
            .toList()
          ..sort((a, b) => b.vendas.compareTo(a.vendas));

    return WebRelatoriosResumo(
      competencia: resultados[0] as WebDreResultado,
      caixa: resultados[1] as WebDreResultado,
      ordens: ordens,
      executores: rankingExecutores,
      vendas: vendas,
      recebido: recebido,
      aReceber: aReceber,
    );
  }

  static double vendaOrdem(Map<String, dynamic> ordem) {
    return OrdemServicoValor.valorNegociadoDeMapa(
      Map<String, Object?>.from(ordem),
    );
  }

  Future<List<Map<String, dynamic>>> _listarOrdens() async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir os relatórios.');
    }

    final raw = await client
        .from('imperium_ordens_servico')
        .select(
          'id,numero,status,data_finalizacao,funcionario_responsavel,'
          'valor_total,desconto,desconto_negociacao,acrescimo_negociacao,'
          'juros_parcelamento,status_pagamento,valor_recebido',
        )
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('data_finalizacao', ascending: false);

    return (raw as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static DateTime? _parseData(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return null;
    return DateTime.tryParse(texto);
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }
}

class _ExecutorAcumulado {
  int quantidade = 0;
  double vendas = 0;
  double recebido = 0;
}
