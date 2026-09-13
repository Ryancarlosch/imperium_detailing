import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class WebCloudGestaoService {
  WebCloudGestaoService._();

  static final WebCloudGestaoService instance = WebCloudGestaoService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de usar o módulo.');
    }
    return empresa;
  }

  Future<List<Map<String, dynamic>>> _listar(
    String tabela, {
    String? orderBy,
    bool ascending = true,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    dynamic query = client.from(tabela).select().eq('empresa_id', empresaId);

    if (orderBy != null && orderBy.isNotEmpty) {
      query = query.order(orderBy, ascending: ascending);
    }

    final resposta = await query;

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final excluido = item['excluido_em']?.toString().trim() ?? '';
          return excluido.isEmpty;
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarItensEstoque() {
    return _listar('imperium_estoque_itens', orderBy: 'nome');
  }

  Future<List<Map<String, dynamic>>> listarAlertasEstoque() {
    return _listar(
      'imperium_estoque_alertas',
      orderBy: 'atualizado_em',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarContasFinanceiras() {
    return _listar('imperium_financeiro_contas', orderBy: 'nome');
  }

  Future<List<Map<String, dynamic>>> listarMovimentosFinanceiros() {
    return _listar(
      'imperium_financeiro_movimentos',
      orderBy: 'data',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarPagamentosOs() {
    return _listar(
      'imperium_financeiro_pagamentos_os',
      orderBy: 'data_pagamento',
      ascending: false,
    );
  }

  Future<Map<String, Object?>> resumoEstoque() async {
    final resultados = await Future.wait([
      listarItensEstoque(),
      listarAlertasEstoque(),
    ]);

    final itens = resultados[0];
    final alertas = resultados[1];

    var abaixoMinimo = 0;
    var valorEstoque = 0.0;

    for (final item in itens) {
      if (item['ativo'] == false) continue;

      final quantidade = _double(item['quantidade']);
      final minimo = _double(item['quantidade_minima']);
      final custo = _double(item['custo_unitario_calculado']) > 0
          ? _double(item['custo_unitario_calculado'])
          : _double(item['custo_unitario']);

      if (minimo > 0 && quantidade <= minimo) {
        abaixoMinimo++;
      }

      valorEstoque += quantidade * custo;
    }

    final alertasAtivos = alertas.where((item) {
      return (item['status'] ?? 'Ativo').toString().toLowerCase() == 'ativo';
    }).length;

    return <String, Object?>{
      'itens': itens.where((item) => item['ativo'] != false).length,
      'abaixo_minimo': abaixoMinimo,
      'alertas_ativos': alertasAtivos,
      'valor_estoque': valorEstoque,
    };
  }

  Future<Map<String, Object?>> resumoFinanceiro() async {
    final resultados = await Future.wait([
      listarContasFinanceiras(),
      listarMovimentosFinanceiros(),
      listarPagamentosOs(),
    ]);

    final contas = resultados[0];
    final movimentos = resultados[1];
    final pagamentos = resultados[2];

    final saldos = <String, double>{
      for (final conta in contas)
        conta['id'].toString(): _double(conta['saldo_inicial']),
    };

    final agora = DateTime.now();
    var entradasMes = 0.0;
    var saidasMes = 0.0;

    for (final movimento in movimentos) {
      final status = (movimento['status'] ?? 'Realizado')
          .toString()
          .toLowerCase();

      if (status != 'realizado') continue;

      final valor = _double(movimento['valor']);
      final tipo = (movimento['tipo'] ?? '').toString().toLowerCase();
      final contaId = movimento['conta_id']?.toString();

      final entrada = tipo.contains('entrada') || tipo.contains('receita');
      final saida =
          tipo.startsWith('sa') ||
          tipo.contains('despesa') ||
          tipo.contains('custo');

      if (contaId != null && saldos.containsKey(contaId)) {
        if (entrada) {
          saldos[contaId] = (saldos[contaId] ?? 0) + valor;
        } else if (saida) {
          saldos[contaId] = (saldos[contaId] ?? 0) - valor;
        }
      }

      final data = _parseData(movimento['data']?.toString());
      if (data != null &&
          data.year == agora.year &&
          data.month == agora.month) {
        if (entrada) entradasMes += valor;
        if (saida) saidasMes += valor;
      }
    }

    var aReceber = 0.0;
    for (final pagamento in pagamentos) {
      final status = (pagamento['status'] ?? '').toString().toLowerCase();
      if (status == 'pago' || status == 'cancelado' || status == 'estornado') {
        continue;
      }
      aReceber += _double(pagamento['valor']);
    }

    return <String, Object?>{
      'contas': contas.length,
      'saldo_total': saldos.values.fold<double>(0, (a, b) => a + b),
      'entradas_mes': entradasMes,
      'saidas_mes': saidasMes,
      'resultado_caixa_mes': entradasMes - saidasMes,
      'a_receber': aReceber,
      'saldos': saldos,
    };
  }

  Future<String> criarOrdemAberta({
    required String clienteId,
    String? veiculoId,
    required String funcionarioResponsavel,
    required String observacoes,
    required List<Map<String, Object?>> itens,
  }) async {
    if (itens.isEmpty) {
      throw ArgumentError('Inclua pelo menos um serviço na OS.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    final agora = DateTime.now();
    final numero = 'WEB-${agora.millisecondsSinceEpoch}';

    var valorTotal = 0.0;
    for (final item in itens) {
      valorTotal +=
          _double(item['quantidade']) * _double(item['valor_unitario']);
    }

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'veiculo_id': _textoNulo(veiculoId),
      'agendamento_id': null,
      'numero': numero,
      'status': 'Aberta',
      'data_abertura': agora.toIso8601String(),
      'data_inicio': null,
      'data_finalizacao': null,
      'hora_entrada': null,
      'hora_saida': null,
      'funcionario_responsavel': funcionarioResponsavel.trim(),
      'observacoes': observacoes.trim(),
      'valor_total': valorTotal,
      'desconto': 0,
      'forma_pagamento': null,
      'quilometragem_entrada': '',
      'combustivel_entrada': '',
      'revisada_em': null,
      'motivo_ultima_revisao': '',
      'quantidade_revisoes': 0,
      'assinatura_desatualizada': false,
      'status_pagamento': 'Pendente',
      'valor_recebido': 0,
      'vencimento_pagamento': null,
      'pagamento_atualizado_em': null,
      'desconto_negociacao': 0,
      'acrescimo_negociacao': 0,
      'juros_parcelamento': 0,
      'excluido_em': null,
    };

    final ordem = await client
        .from('imperium_ordens_servico')
        .insert(payload)
        .select('id,numero')
        .single();

    final ordemId = ordem['id'].toString();

    try {
      final itensPayload = <Map<String, dynamic>>[];

      for (var indice = 0; indice < itens.length; indice++) {
        final item = itens[indice];

        itensPayload.add(<String, dynamic>{
          'empresa_id': empresaId,
          'ordem_servico_id': ordemId,
          'servico': (item['servico'] ?? '').toString().trim(),
          'descricao': (item['descricao'] ?? '').toString().trim(),
          'quantidade': _double(item['quantidade']),
          'valor_unitario': _double(item['valor_unitario']),
          'concluido': false,
          'ordem': indice,
          'excluido_em': null,
        });
      }

      await client.from('imperium_ordem_servico_itens').insert(itensPayload);
    } catch (_) {
      await client
          .from('imperium_ordens_servico')
          .update(<String, dynamic>{
            'excluido_em': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('empresa_id', empresaId)
          .eq('id', ordemId);
      rethrow;
    }

    return (ordem['numero'] ?? numero).toString();
  }

  Future<List<Map<String, dynamic>>> listarItensOrdem(String ordemId) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    final resposta = await client
        .from('imperium_ordem_servico_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemId)
        .order('ordem');

    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final excluido = item['excluido_em']?.toString().trim() ?? '';
          return excluido.isEmpty;
        })
        .toList();
  }

  static String? _textoNulo(dynamic valor) {
    if (valor == null) return null;
    final texto = valor.toString().trim();
    return texto.isEmpty ? null : texto;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static DateTime? _parseData(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso;

    final partes = texto.split('/');
    if (partes.length != 3) return null;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);

    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }
}
