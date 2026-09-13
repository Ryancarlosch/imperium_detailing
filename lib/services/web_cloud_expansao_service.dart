import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebCloudExpansaoService {
  WebCloudExpansaoService._();

  static final WebCloudExpansaoService instance = WebCloudExpansaoService._();

  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de usar este módulo.');
    }
    return empresa;
  }

  Future<List<Map<String, dynamic>>> _listar(
    String tabela, {
    String? orderBy,
    bool ascending = true,
    bool softDelete = true,
  }) async {
    final empresaId = await _empresaId();
    dynamic query = _client.from(tabela).select().eq('empresa_id', empresaId);

    if (orderBy != null) {
      query = query.order(orderBy, ascending: ascending);
    }

    final resposta = await query;
    final itens = (resposta as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    if (!softDelete) return itens;

    return itens.where((item) {
      return (item['excluido_em']?.toString().trim() ?? '').isEmpty;
    }).toList();
  }

  Future<Map<String, dynamic>> _atualizarCas({
    required String tabela,
    required String id,
    required String atualizadoEmEsperado,
    required Map<String, dynamic> payload,
  }) async {
    final empresaId = await _empresaId();

    if (atualizadoEmEsperado.trim().isEmpty) {
      throw StateError(
        'O registro não possui versão de sincronização. Atualize a tela.',
      );
    }

    final rows = await _client
        .from(tabela)
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', id)
        .eq('atualizado_em', atualizadoEmEsperado)
        .select();

    if ((rows as List).isEmpty) {
      throw StateError(
        'Outro dispositivo alterou este registro. Atualize a tela antes de '
        'tentar novamente.',
      );
    }

    return Map<String, dynamic>.from(rows.first as Map);
  }

  // ---------------------------------------------------------------------------
  // CRM
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listarLeads() {
    return _listar(
      'imperium_crm_leads',
      orderBy: 'atualizado_em',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarCampanhas() {
    return _listar(
      'imperium_crm_campanhas',
      orderBy: 'atualizado_em',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarCupons() {
    return _listar(
      'imperium_crm_cupons',
      orderBy: 'atualizado_em',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarInteracoes(String leadId) async {
    final empresaId = await _empresaId();

    final resposta = await _client
        .from('imperium_crm_interacoes')
        .select()
        .eq('empresa_id', empresaId)
        .eq('lead_id', leadId)
        .order('data_interacao', ascending: false);

    return (resposta as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((item) => (item['excluido_em']?.toString().trim() ?? '').isEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> salvarLead({
    String? id,
    String? atualizadoEmEsperado,
    required String nome,
    required String telefone,
    required String email,
    required String origem,
    required String servicoInteresse,
    required String veiculoInteresse,
    required double valorPotencial,
    required String etapa,
    required String responsavel,
    String? proximoContato,
    required String observacoes,
    required String motivoPerda,
    String? convertidoEmAtual,
  }) async {
    final empresaId = await _empresaId();
    final agora = DateTime.now().toUtc().toIso8601String();

    final payload = <String, dynamic>{
      'nome': nome.trim(),
      'telefone': telefone.trim(),
      'email': email.trim(),
      'origem': origem,
      'servico_interesse': servicoInteresse.trim(),
      'veiculo_interesse': veiculoInteresse.trim(),
      'valor_potencial': max(0, valorPotencial),
      'etapa': etapa,
      'responsavel': responsavel.trim(),
      'proximo_contato': _textoNulo(proximoContato),
      'observacoes': observacoes.trim(),
      'motivo_perda': etapa == 'Perdido' ? motivoPerda.trim() : '',
      'origem_atualizado_em': agora,
      'convertido_em': etapa == 'Ganho'
          ? (_textoNulo(convertidoEmAtual) ?? agora)
          : null,
      'excluido_em': null,
    };

    if (id == null || id.trim().isEmpty) {
      final origemWeb = await WebOrigemService.instance.proxima();

      final resposta = await _client
          .from('imperium_crm_leads')
          .insert(<String, dynamic>{
            'empresa_id': empresaId,
            'origem_dispositivo': origemWeb.dispositivoId,
            'origem_local_id': origemWeb.localId,
            'cliente_id': null,
            'veiculo_id': null,
            'agendamento_id': null,
            'origem_criado_em': agora,
            ...payload,
          })
          .select()
          .single();

      return Map<String, dynamic>.from(resposta);
    }

    return _atualizarCas(
      tabela: 'imperium_crm_leads',
      id: id,
      atualizadoEmEsperado: atualizadoEmEsperado ?? '',
      payload: payload,
    );
  }

  Future<void> excluirLead({
    required String id,
    required String atualizadoEmEsperado,
  }) async {
    await _atualizarCas(
      tabela: 'imperium_crm_leads',
      id: id,
      atualizadoEmEsperado: atualizadoEmEsperado,
      payload: <String, dynamic>{
        'excluido_em': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> adicionarInteracao({
    required String leadId,
    required String tipo,
    required String descricao,
  }) async {
    if (descricao.trim().isEmpty) {
      throw ArgumentError('Informe a descrição da interação.');
    }

    final empresaId = await _empresaId();
    final origemWeb = await WebOrigemService.instance.proxima();
    final agora = DateTime.now().toUtc().toIso8601String();

    await _client.from('imperium_crm_interacoes').insert(<String, dynamic>{
      'empresa_id': empresaId,
      'origem_dispositivo': origemWeb.dispositivoId,
      'origem_local_id': origemWeb.localId,
      'lead_id': leadId,
      'tipo': tipo,
      'descricao': descricao.trim(),
      'data_interacao': agora,
      'origem_criado_em': agora,
      'excluido_em': null,
    });
  }

  // ---------------------------------------------------------------------------
  // Orçamentos
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listarOrcamentos() {
    return _listar(
      'imperium_orcamentos',
      orderBy: 'atualizado_em',
      ascending: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarItensOrcamento(
    String orcamentoId,
  ) async {
    final empresaId = await _empresaId();

    final resposta = await _client
        .from('imperium_orcamento_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('orcamento_id', orcamentoId)
        .order('ordem');

    return (resposta as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((item) => (item['excluido_em']?.toString().trim() ?? '').isEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> criarOrcamento({
    required String clienteId,
    String? veiculoId,
    required String validade,
    required String observacoes,
    required double desconto,
    required String perfilPreco,
    required List<Map<String, Object?>> itens,
  }) async {
    if (itens.isEmpty) {
      throw ArgumentError('Adicione pelo menos um serviço.');
    }

    final empresaId = await _empresaId();
    final origemCabecalho = await WebOrigemService.instance.proxima();
    final agora = DateTime.now();
    final emissao = _formatarData(agora);

    var subtotal = 0.0;
    for (final item in itens) {
      subtotal +=
          max(0, _double(item['quantidade'])) *
          max(0, _double(item['valor_unitario']));
    }

    final descontoSeguro = desconto.clamp(0, subtotal).toDouble();
    final total = max(0.0, subtotal - descontoSeguro);
    final primeiro = itens.first;

    final resposta = await _client
        .from('imperium_orcamentos')
        .insert(<String, dynamic>{
          'empresa_id': empresaId,
          'origem_dispositivo': origemCabecalho.dispositivoId,
          'origem_local_id': origemCabecalho.localId,
          'cliente_id': clienteId,
          'veiculo_id': _textoNulo(veiculoId),
          'servico': (primeiro['servico'] ?? '').toString().trim(),
          'descricao': (primeiro['descricao'] ?? '').toString().trim(),
          'valor': total,
          'data_emissao': emissao,
          'validade': validade.trim(),
          'status': 'Pendente',
          'observacoes': observacoes.trim(),
          'desconto': descontoSeguro,
          'perfil_preco': perfilPreco,
          'origem_atualizado_em': agora.toUtc().toIso8601String(),
          'excluido_em': null,
        })
        .select()
        .single();

    final orcamento = Map<String, dynamic>.from(resposta);
    final orcamentoId = orcamento['id'].toString();

    try {
      final payloadItens = <Map<String, dynamic>>[];

      for (var i = 0; i < itens.length; i++) {
        final item = itens[i];
        final origemItem = await WebOrigemService.instance.proxima();

        payloadItens.add(<String, dynamic>{
          'empresa_id': empresaId,
          'origem_dispositivo': origemItem.dispositivoId,
          'origem_local_id': origemItem.localId,
          'orcamento_id': orcamentoId,
          'servico_catalogo_id': _textoNulo(item['servico_catalogo_id']),
          'origem_servico_catalogo_local_id': null,
          'servico': (item['servico'] ?? '').toString().trim(),
          'descricao': (item['descricao'] ?? '').toString().trim(),
          'quantidade': max(0, _double(item['quantidade'])),
          'valor_unitario': max(0, _double(item['valor_unitario'])),
          'ordem': i,
          'excluido_em': null,
        });
      }

      await _client.from('imperium_orcamento_itens').insert(payloadItens);
    } catch (_) {
      await _client
          .from('imperium_orcamentos')
          .update(<String, dynamic>{
            'excluido_em': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('empresa_id', empresaId)
          .eq('id', orcamentoId);
      rethrow;
    }

    return orcamento;
  }

  Future<Map<String, dynamic>> alterarStatusOrcamento({
    required String id,
    required String status,
    required String atualizadoEmEsperado,
  }) async {
    const permitidos = <String>{'Pendente', 'Aprovado', 'Recusado'};

    if (!permitidos.contains(status)) {
      throw ArgumentError('Status de orçamento inválido.');
    }

    return _atualizarCas(
      tabela: 'imperium_orcamentos',
      id: id,
      atualizadoEmEsperado: atualizadoEmEsperado,
      payload: <String, dynamic>{
        'status': status,
        'origem_atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> excluirOrcamento({
    required String id,
    required String atualizadoEmEsperado,
  }) async {
    await _atualizarCas(
      tabela: 'imperium_orcamentos',
      id: id,
      atualizadoEmEsperado: atualizadoEmEsperado,
      payload: <String, dynamic>{
        'excluido_em': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Precificação
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> carregarConfigPrecificacao() async {
    final empresaId = await _empresaId();
    final resposta = await _client
        .from('imperium_precificacao_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    return resposta == null ? null : Map<String, dynamic>.from(resposta);
  }

  Future<List<Map<String, dynamic>>> listarCatalogoPrecificacao() {
    return _listar('imperium_precificacao_servicos_catalogo', orderBy: 'nome');
  }

  Future<List<Map<String, dynamic>>> listarSnapshotsPrecificacao() {
    return _listar(
      'imperium_precificacao_snapshots',
      orderBy: 'calculado_em',
      ascending: false,
      softDelete: false,
    );
  }

  Future<List<Map<String, dynamic>>> listarSimulacoesPrecificacao() {
    return _listar(
      'imperium_precificacao_simulacoes',
      orderBy: 'criado_em',
      ascending: false,
      softDelete: false,
    );
  }

  Future<Map<String, dynamic>> salvarConfigPrecificacao({
    String? atualizadoEmEsperado,
    required int mesesMedia,
    required double margemCliente,
    required double margemRevenda1a4,
    required double margemRevenda5a9,
    required double margemRevenda10Mais,
    required double margemMinima,
  }) async {
    _validarMargens(
      margemCliente,
      margemRevenda1a4,
      margemRevenda5a9,
      margemRevenda10Mais,
      margemMinima,
    );

    final empresaId = await _empresaId();
    final dispositivoId = await WebOrigemService.instance.dispositivoId();
    final agora = DateTime.now().toUtc().toIso8601String();

    final payload = <String, dynamic>{
      'horas_produtivas_mes': ImperiumRegrasNegocio.horasMensaisPadrao,
      'meses_media': mesesMedia.clamp(1, 12),
      'margem_cliente': margemCliente,
      'margem_revenda_1_4': margemRevenda1a4,
      'margem_revenda_5_9': margemRevenda5a9,
      'margem_revenda_10_mais': margemRevenda10Mais,
      'margem_minima': margemMinima,
      'origem_dispositivo': dispositivoId,
      'origem_atualizado_em': agora,
    };

    if ((atualizadoEmEsperado ?? '').trim().isEmpty) {
      final resposta = await _client
          .from('imperium_precificacao_config')
          .upsert(<String, dynamic>{
            'empresa_id': empresaId,
            ...payload,
          }, onConflict: 'empresa_id')
          .select()
          .single();

      return Map<String, dynamic>.from(resposta);
    }

    final rows = await _client
        .from('imperium_precificacao_config')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('atualizado_em', atualizadoEmEsperado!)
        .select();

    if ((rows as List).isEmpty) {
      throw StateError(
        'As margens foram alteradas em outro dispositivo. Atualize a tela.',
      );
    }

    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<void> criarSimulacaoPrecificacao({
    required String nome,
    required double margemCliente,
    required double margemRevenda1a4,
    required double margemRevenda5a9,
    required double margemRevenda10Mais,
    required double margemMinima,
    required double taxaCartaoPercentual,
    required double custoHora,
    required double metaFaturamento,
    required int mesesMedia,
    required String observacoes,
  }) async {
    if (nome.trim().isEmpty) {
      throw ArgumentError('Informe um nome para o cenário.');
    }

    _validarMargens(
      margemCliente,
      margemRevenda1a4,
      margemRevenda5a9,
      margemRevenda10Mais,
      margemMinima,
      taxaCartao: taxaCartaoPercentual,
    );

    final empresaId = await _empresaId();
    final origemWeb = await WebOrigemService.instance.proxima();
    final snapshots = await listarSnapshotsPrecificacao();
    final catalogo = await listarCatalogoPrecificacao();

    final nomes = <String, String>{
      for (final item in catalogo)
        item['id'].toString(): (item['nome'] ?? 'Serviço').toString(),
    };

    final servicos = snapshots.map((item) {
      final custoProdutos = _double(item['custo_produtos']);
      final tempo = _double(item['tempo_precificacao_minutos']);
      final custoEstrutura = (tempo / 60.0) * max(0, custoHora);
      final custoBase = custoProdutos + custoEstrutura;

      return <String, Object?>{
        'servico_id': item['servico_id']?.toString(),
        'nome': nomes[item['servico_id']?.toString()] ?? 'Serviço',
        'preco_atual': _double(item['preco_atual']),
        'custo_produtos': custoProdutos,
        'custo_estrutura': custoEstrutura,
        'custo_base': custoBase,
        'preco_equilibrio': _precoComMargem(custoBase, 0, taxaCartaoPercentual),
        'preco_minimo_seguro': _precoComMargem(
          custoBase,
          margemMinima,
          taxaCartaoPercentual,
        ),
        'preco_sugerido': _arredondarPreco(
          _precoComMargem(custoBase, margemCliente, taxaCartaoPercentual),
        ),
        'preco_revenda_1_4': _arredondarPreco(
          _precoComMargem(custoBase, margemRevenda1a4, taxaCartaoPercentual),
        ),
        'preco_revenda_5_9': _arredondarPreco(
          _precoComMargem(custoBase, margemRevenda5a9, taxaCartaoPercentual),
        ),
        'preco_revenda_10_mais': _arredondarPreco(
          _precoComMargem(custoBase, margemRevenda10Mais, taxaCartaoPercentual),
        ),
      };
    }).toList();

    final resultado = <String, Object?>{
      'versao': 3,
      'origem': 'web',
      'horas_mensais_empresa': ImperiumRegrasNegocio.horasMensaisPadrao,
      'custo_hora_cenario': custoHora,
      'taxa_cartao_cenario': taxaCartaoPercentual,
      'meta_faturamento': metaFaturamento,
      'quantidade_servicos': servicos.length,
      'servicos': servicos,
    };

    await _client
        .from('imperium_precificacao_simulacoes')
        .insert(<String, dynamic>{
          'empresa_id': empresaId,
          'origem_dispositivo': origemWeb.dispositivoId,
          'origem_local_id': origemWeb.localId,
          'nome': nome.trim(),
          'margem_cliente': margemCliente,
          'margem_revenda_1_4': margemRevenda1a4,
          'margem_revenda_5_9': margemRevenda5a9,
          'margem_revenda_10_mais': margemRevenda10Mais,
          'margem_minima': margemMinima,
          'taxa_cartao_percentual': taxaCartaoPercentual,
          'custo_hora': custoHora,
          'meta_faturamento': metaFaturamento,
          'meses_media': mesesMedia.clamp(1, 12),
          'resultado_json': resultado,
          'observacoes': observacoes.trim(),
        });
  }

  // ---------------------------------------------------------------------------
  // Central Web
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> diagnosticarCentral() async {
    final empresaId = await _empresaId();

    const tabelas = <String, String>{
      'Clientes': 'imperium_clientes',
      'Veículos': 'imperium_veiculos',
      'Agenda': 'imperium_agendamentos',
      'Ordens de serviço': 'imperium_ordens_servico',
      'Estoque': 'imperium_estoque_itens',
      'Financeiro': 'imperium_financeiro_movimentos',
      'CRM': 'imperium_crm_leads',
      'Orçamentos': 'imperium_orcamentos',
      'Precificação': 'imperium_precificacao_snapshots',
    };

    final modulos = <Map<String, Object?>>[];
    DateTime? ultimaAtualizacao;

    for (final entry in tabelas.entries) {
      try {
        final rows = await _client
            .from(entry.value)
            .select('atualizado_em')
            .eq('empresa_id', empresaId)
            .order('atualizado_em', ascending: false)
            .limit(500);

        final lista = rows as List;
        DateTime? ultima;

        if (lista.isNotEmpty) {
          ultima = DateTime.tryParse(
            (lista.first['atualizado_em'] ?? '').toString(),
          );
        }

        if (ultima != null &&
            (ultimaAtualizacao == null || ultima.isAfter(ultimaAtualizacao))) {
          ultimaAtualizacao = ultima;
        }

        modulos.add(<String, Object?>{
          'nome': entry.key,
          'registros': lista.length,
          'ultima_atualizacao': ultima?.toIso8601String(),
          'status': 'Disponível',
        });
      } catch (error) {
        modulos.add(<String, Object?>{
          'nome': entry.key,
          'registros': null,
          'ultima_atualizacao': null,
          'status': _semPermissao(error) ? 'Sem permissão' : 'Erro',
        });
      }
    }

    return <String, Object?>{
      'empresa_id': empresaId,
      'usuario':
          _client.auth.currentUser?.email ?? _client.auth.currentUser?.id ?? '',
      'plataforma': 'Web online-first',
      'horas_mensais_empresa': ImperiumRegrasNegocio.horasMensaisPadrao,
      'ultima_atualizacao': ultimaAtualizacao?.toIso8601String(),
      'modulos': modulos,
    };
  }

  bool _semPermissao(Object error) {
    final texto = error.toString();
    return texto.contains('42501') ||
        texto.toLowerCase().contains('permission') ||
        texto.toLowerCase().contains('policy');
  }

  void _validarMargens(
    double cliente,
    double revenda14,
    double revenda59,
    double revenda10,
    double minima, {
    double taxaCartao = 0,
  }) {
    for (final margem in <double>[
      cliente,
      revenda14,
      revenda59,
      revenda10,
      minima,
      taxaCartao,
    ]) {
      if (margem < 0 || margem >= 100) {
        throw ArgumentError('Margens e taxas devem ficar entre 0% e 99,99%.');
      }
    }

    if (cliente + taxaCartao >= 100 ||
        revenda14 + taxaCartao >= 100 ||
        revenda59 + taxaCartao >= 100 ||
        revenda10 + taxaCartao >= 100 ||
        minima + taxaCartao >= 100) {
      throw ArgumentError(
        'Margem + taxa de cartão precisa ser menor que 100%.',
      );
    }
  }

  double _precoComMargem(double custoBase, double margem, double taxa) {
    final denominador = 1 - (margem / 100) - (taxa / 100);
    if (denominador <= 0) {
      throw ArgumentError('Margem/taxa inválida para precificação.');
    }
    return max(0, custoBase) / denominador;
  }

  double _arredondarPreco(double valor) {
    if (valor <= 0) return 0;
    final passo = valor < 100 ? 5.0 : 10.0;
    return (valor / passo).ceil() * passo;
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

  static String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}
