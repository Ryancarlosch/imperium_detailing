import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebOsFinalizacaoV4Service {
  WebOsFinalizacaoV4Service._();

  static final WebOsFinalizacaoV4Service instance =
      WebOsFinalizacaoV4Service._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de finalizar a OS.');
    }
    return empresa;
  }

  Future<List<Map<String, dynamic>>> listarContasAtivas() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final raw = await client
        .from('imperium_financeiro_contas')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ativo', true)
        .isFilter('excluido_em', null)
        .order('nome');

    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> carregarContexto(String ordemId) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();

    final ordem = await client
        .from('imperium_ordens_servico')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', ordemId)
        .isFilter('excluido_em', null)
        .single();

    final estado = await client
        .from('imperium_ordem_servico_produtos_estado')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemId)
        .maybeSingle();

    final produtosRaw = await client
        .from('imperium_ordem_servico_produtos')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemId)
        .isFilter('excluido_em', null)
        .order('criado_em');

    final estoqueRaw = await client
        .from('imperium_estoque_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ativo', true)
        .isFilter('excluido_em', null)
        .order('nome');

    final contas = await listarContasAtivas();

    return <String, dynamic>{
      'ordem': Map<String, dynamic>.from(ordem),
      'estado': estado == null ? null : Map<String, dynamic>.from(estado),
      'produtos': (produtosRaw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      'estoque': (estoqueRaw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      'contas': contas,
    };
  }

  Future<Map<String, dynamic>> salvarProdutos({
    required Map<String, dynamic> contexto,
    required List<Map<String, Object?>> produtos,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final ordem = Map<String, dynamic>.from(contexto['ordem'] as Map);
    final estadoRaw = contexto['estado'];
    final estado = estadoRaw == null
        ? null
        : Map<String, dynamic>.from(estadoRaw as Map);

    final status = (ordem['status'] ?? '').toString();
    if (status != 'Aberta' && status != 'Em andamento') {
      throw StateError(
        'Produtos só podem ser preparados enquanto a OS estiver '
        'Aberta ou Em andamento.',
      );
    }

    final dispositivoId = await WebOrigemService.instance.dispositivoId();
    final enviados = <Map<String, Object?>>[];

    for (final original in produtos) {
      final item = Map<String, Object?>.from(original);
      final itemEstoqueId = (item['item_estoque_id'] ?? '').toString().trim();
      final nome = (item['produto_nome'] ?? '').toString().trim();
      final quantidade = _double(item['quantidade']);

      if (itemEstoqueId.isEmpty) {
        throw ArgumentError('Selecione um item de estoque para cada produto.');
      }
      if (nome.isEmpty) {
        throw ArgumentError('O produto precisa ter nome.');
      }
      if (quantidade <= 0) {
        throw ArgumentError('A quantidade de produto precisa ser positiva.');
      }

      if ((item['id'] ?? '').toString().trim().isEmpty) {
        item['origem_local_id'] = await WebOrigemService.instance
            .proximoLocalId();
      }

      item['quantidade'] = quantidade;
      item['custo_unitario'] = _double(item['custo_unitario']);
      item['custo_unitario_no_momento'] = 0.0;
      item['custo_total_no_momento'] = 0.0;
      item['composicao_lotes_json'] = const <Object?>[];
      item['baixado_estoque'] = false;
      enviados.add(item);
    }

    final canonicos =
        enviados
            .map(
              (item) => <String, Object?>{
                'item_estoque_id': item['item_estoque_id'],
                'produto_nome': item['produto_nome'],
                'quantidade': item['quantidade'],
                'unidade': item['unidade'],
                'custo_unitario': item['custo_unitario'],
              },
            )
            .map(jsonEncode)
            .toList()
          ..sort();

    final contratoHash = sha256
        .convert(utf8.encode(jsonEncode(canonicos)))
        .toString();

    final raw = await client.rpc(
      'imperium_os_produtos_publicar_v4',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_ordem_servico_id': ordem['id'].toString(),
        'p_estado_atualizado_em': estado?['atualizado_em']?.toString(),
        'p_contrato_hash': contratoHash,
        'p_produtos': enviados,
        'p_lotes': const <Object?>[],
        'p_origem_dispositivo': dispositivoId,
        'p_origem_os_local_id': null,
      },
    );

    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> finalizar({
    required Map<String, dynamic> contexto,
    required String dataEntrada,
    required String horaEntrada,
    required String dataSaida,
    required String horaSaida,
    String? formaPagamento,
    double? valorPagamento,
    String? dataPagamento,
    String? horaPagamento,
    String? vencimentoPagamento,
    String? contaId,
    int parcelasTaxa = 1,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final ordem = Map<String, dynamic>.from(contexto['ordem'] as Map);
    final estadoRaw = contexto['estado'];

    if (estadoRaw == null) {
      throw StateError(
        'Prepare o contrato de produtos da OS antes de finalizar.',
      );
    }

    final estado = Map<String, dynamic>.from(estadoRaw as Map);
    if (estado['pronto'] != true) {
      throw StateError('O contrato de produtos ainda não está pronto.');
    }

    if ((ordem['status'] ?? '').toString() != 'Em andamento') {
      throw StateError('A OS precisa estar Em andamento para finalizar.');
    }

    final entrada = _instanteSaoPaulo(dataEntrada, horaEntrada);
    final saida = _instanteSaoPaulo(dataSaida, horaSaida);

    if (saida.isBefore(entrada)) {
      throw ArgumentError('A saída não pode acontecer antes da entrada.');
    }

    final forma = (formaPagamento ?? '').trim();
    final valor = valorPagamento ?? 0;

    if (valor < 0) {
      throw ArgumentError('O valor recebido não pode ser negativo.');
    }

    if (valor > 0 && forma.isEmpty) {
      throw ArgumentError('Informe a forma de pagamento.');
    }

    if (valor > 0 && (contaId ?? '').trim().isEmpty) {
      throw ArgumentError('Informe a conta financeira do recebimento.');
    }

    final origem = await WebOrigemService.instance.proxima();
    final idempotencyKey = 'web-finalizar-${ordem['id']}-${origem.localId}';

    DateTime? pagamentoEm;
    if (valor > 0) {
      pagamentoEm = _instanteSaoPaulo(
        (dataPagamento ?? '').trim().isEmpty ? dataSaida : dataPagamento!,
        (horaPagamento ?? '').trim().isEmpty ? horaSaida : horaPagamento!,
      );
    }

    final raw = await client.rpc(
      'imperium_os_finalizar_web_v4',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_ordem_id': ordem['id'].toString(),
        'p_os_atualizado_em': ordem['atualizado_em']?.toString(),
        'p_produtos_atualizado_em': estado['atualizado_em']?.toString(),
        'p_idempotency_key': idempotencyKey,
        'p_origem_dispositivo': origem.dispositivoId,
        'p_origem_base': origem.localId,
        'p_entrada': entrada.toUtc().toIso8601String(),
        'p_saida': saida.toUtc().toIso8601String(),
        'p_forma_pagamento': forma.isEmpty ? null : forma,
        'p_valor_pagamento': valor,
        'p_data_pagamento': pagamentoEm?.toUtc().toIso8601String(),
        'p_vencimento_pagamento': _nulo(vencimentoPagamento),
        'p_conta_id': _nulo(contaId),
        'p_parcelas_taxa': parcelasTaxa.clamp(1, 12),
        'p_timezone': 'America/Sao_Paulo',
      },
    );

    return Map<String, dynamic>.from(raw as Map);
  }

  static DateTime _instanteSaoPaulo(String data, String hora) {
    final d = data.trim();
    final h = hora.trim();

    final dataMatch = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d);
    final horaMatch = RegExp(r'^\d{2}:\d{2}$').hasMatch(h);

    if (!dataMatch || !horaMatch) {
      throw ArgumentError('Use data AAAA-MM-DD e hora HH:mm.');
    }

    return DateTime.parse('${d}T$h:00-03:00');
  }

  static String? _nulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
