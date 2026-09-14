import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

enum WebDreRegime { competencia, caixa }

class WebDreDetalhe {
  const WebDreDetalhe({
    required this.grupo,
    required this.codigo,
    required this.nome,
    required this.valor,
  });

  final String grupo;
  final String codigo;
  final String nome;
  final double valor;
}

class WebDreResultado {
  const WebDreResultado({
    required this.regime,
    required this.inicio,
    required this.fim,
    required this.receitaBruta,
    required this.deducoes,
    required this.receitaLiquida,
    required this.custosVariaveis,
    required this.margemContribuicao,
    required this.despesasOperacionais,
    required this.resultadoFinanceiro,
    required this.outrasReceitas,
    required this.outrasDespesas,
    required this.resultadoGerencial,
    required this.detalhes,
  });

  final WebDreRegime regime;
  final DateTime inicio;
  final DateTime fim;
  final double receitaBruta;
  final double deducoes;
  final double receitaLiquida;
  final double custosVariaveis;
  final double margemContribuicao;
  final double despesasOperacionais;
  final double resultadoFinanceiro;
  final double outrasReceitas;
  final double outrasDespesas;
  final double resultadoGerencial;
  final List<WebDreDetalhe> detalhes;
}

class WebCloudDreService {
  WebCloudDreService._();

  static final WebCloudDreService instance = WebCloudDreService._();

  Future<WebDreResultado> calcular({
    required DateTime inicio,
    required DateTime fim,
    required WebDreRegime regime,
  }) async {
    if (inicio.isAfter(fim)) {
      throw ArgumentError('A data inicial não pode ser posterior à final.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir o DRE.');
    }

    final resposta = await client.rpc(
      'imperium_dre_detalhes_v1',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_inicio': _data(inicio),
        'p_fim': _data(fim),
        'p_regime': regime.name,
      },
    );

    final detalhes = <WebDreDetalhe>[];
    if (resposta is List) {
      for (final item in resposta.whereType<Map>()) {
        detalhes.add(
          WebDreDetalhe(
            grupo: '${item['grupo'] ?? 'Não DRE'}',
            codigo: '${item['codigo'] ?? ''}',
            nome: '${item['nome'] ?? 'Sem categoria'}',
            valor: _double(item['valor']),
          ),
        );
      }
    }

    final porGrupo = <String, double>{};
    for (final detalhe in detalhes) {
      porGrupo[detalhe.grupo] =
          (porGrupo[detalhe.grupo] ?? 0) + detalhe.valor;
    }

    final receitaBruta = porGrupo['Receita Bruta'] ?? 0;
    final deducoes = porGrupo['Deduções'] ?? 0;
    final receitaLiquida = receitaBruta - deducoes;
    final custosVariaveis = porGrupo['Custos Variáveis'] ?? 0;
    final margemContribuicao = receitaLiquida - custosVariaveis;
    final despesasOperacionais = porGrupo['Despesas Operacionais'] ?? 0;
    final resultadoFinanceiro = porGrupo['Resultado Financeiro'] ?? 0;
    final outrasReceitas = porGrupo['Outras Receitas'] ?? 0;
    final outrasDespesas = porGrupo['Outras Despesas'] ?? 0;
    final resultadoGerencial =
        margemContribuicao -
        despesasOperacionais -
        resultadoFinanceiro +
        outrasReceitas -
        outrasDespesas;

    return WebDreResultado(
      regime: regime,
      inicio: inicio,
      fim: fim,
      receitaBruta: receitaBruta,
      deducoes: deducoes,
      receitaLiquida: receitaLiquida,
      custosVariaveis: custosVariaveis,
      margemContribuicao: margemContribuicao,
      despesasOperacionais: despesasOperacionais,
      resultadoFinanceiro: resultadoFinanceiro,
      outrasReceitas: outrasReceitas,
      outrasDespesas: outrasDespesas,
      resultadoGerencial: resultadoGerencial,
      detalhes: detalhes,
    );
  }

  static String _data(DateTime data) {
    return '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
