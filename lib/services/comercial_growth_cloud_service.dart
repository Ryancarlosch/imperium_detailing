import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class GrowthPosVendaConfig {
  const GrowthPosVendaConfig({
    required this.ativo,
    required this.diasRetorno,
    required this.diasReativacao,
  });

  final bool ativo;
  final int diasRetorno;
  final int diasReativacao;

  factory GrowthPosVendaConfig.fromMap(Map<String, dynamic>? map) {
    return GrowthPosVendaConfig(
      ativo: map?['ativo'] != false,
      diasRetorno: _int(map?['dias_retorno'], 90),
      diasReativacao: _int(map?['dias_reativacao'], 180),
    );
  }

  static int _int(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class GrowthPosVendaCliente {
  const GrowthPosVendaCliente({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.email,
    required this.status,
    required this.ultimaOsId,
    required this.ultimaOsNumero,
    required this.ultimaVisita,
    required this.diasSemRetorno,
    required this.quantidadeOs,
    required this.valorTotal,
    required this.temAgendamento,
    required this.proximoAgendamento,
    required this.ultimoContato,
    required this.proximoContato,
  });

  final String id;
  final String nome;
  final String telefone;
  final String email;
  final String status;
  final String ultimaOsId;
  final String ultimaOsNumero;
  final DateTime? ultimaVisita;
  final int diasSemRetorno;
  final int quantidadeOs;
  final double valorTotal;
  final bool temAgendamento;
  final DateTime? proximoAgendamento;
  final DateTime? ultimoContato;
  final DateTime? proximoContato;

  bool get precisaAcao => status == 'Hora do retorno' || status == 'Reativação';
}

class GrowthPosVendaPainel {
  const GrowthPosVendaPainel({required this.config, required this.clientes});

  final GrowthPosVendaConfig config;
  final List<GrowthPosVendaCliente> clientes;

  int get emDia => clientes.where((e) => e.status == 'Em dia').length;
  int get retorno =>
      clientes.where((e) => e.status == 'Hora do retorno').length;
  int get reativacao => clientes.where((e) => e.status == 'Reativação').length;
  int get agendados => clientes.where((e) => e.status == 'Agendado').length;
  int get precisamAcao => clientes.where((e) => e.precisaAcao).length;
}

class GrowthMarketingResumo {
  const GrowthMarketingResumo({
    required this.investimento,
    required this.faturamentoAtribuido,
    required this.campanhasAtivas,
    required this.leads,
    required this.clientes,
    required this.ordens,
    required this.alcance,
    required this.cliques,
    required this.publicacoesPlanejadas,
  });

  final double investimento;
  final double faturamentoAtribuido;
  final int campanhasAtivas;
  final int leads;
  final int clientes;
  final int ordens;
  final int alcance;
  final int cliques;
  final int publicacoesPlanejadas;

  double get roas =>
      investimento <= 0 ? 0 : faturamentoAtribuido / investimento;
}

class GrowthMarketingCampanhaDesempenho {
  const GrowthMarketingCampanhaDesempenho({
    required this.campanhaId,
    required this.investimento,
    required this.faturamentoAtribuido,
    required this.leads,
    required this.clientes,
    required this.ordens,
  });

  final String campanhaId;
  final double investimento;
  final double faturamentoAtribuido;
  final int leads;
  final int clientes;
  final int ordens;

  double get roas =>
      investimento <= 0 ? 0 : faturamentoAtribuido / investimento;
}

class ComercialGrowthCloudService {
  ComercialGrowthCloudService._();

  static final ComercialGrowthCloudService instance =
      ComercialGrowthCloudService._();

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
      throw StateError('Selecione uma empresa antes de abrir este módulo.');
    }
    return empresa;
  }

  Future<Map<String, dynamic>> _snapshotGrowth() async {
    final empresaId = await _empresaId();
    final raw = await _client.rpc(
      'imperium_growth_snapshot',
      params: <String, dynamic>{'p_empresa_id': empresaId},
    );
    if (raw is! Map) {
      throw StateError('Snapshot comercial inválido.');
    }
    return Map<String, dynamic>.from(raw);
  }

  List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<GrowthPosVendaConfig> carregarConfigPosVenda() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_pos_venda_config')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    return GrowthPosVendaConfig.fromMap(
      raw == null ? null : Map<String, dynamic>.from(raw),
    );
  }

  Future<void> salvarConfigPosVenda({
    required int diasRetorno,
    required int diasReativacao,
    bool ativo = true,
  }) async {
    if (diasRetorno < 1) {
      throw ArgumentError('O prazo de retorno deve ser maior que zero.');
    }
    if (diasReativacao <= diasRetorno) {
      throw ArgumentError(
        'O prazo de reativação deve ser maior que o prazo de retorno.',
      );
    }

    final empresaId = await _empresaId();
    await _client.from('imperium_pos_venda_config').upsert(<String, dynamic>{
      'empresa_id': empresaId,
      'ativo': ativo,
      'dias_retorno': diasRetorno,
      'dias_reativacao': diasReativacao,
    }, onConflict: 'empresa_id');
  }

  Future<GrowthPosVendaPainel> carregarPosVenda() async {
    final resultados = await Future.wait<dynamic>([
      carregarConfigPosVenda(),
      _snapshotGrowth(),
      listarInteracoesPosVenda(),
    ]);

    final config = resultados[0] as GrowthPosVendaConfig;
    final snapshot = resultados[1] as Map<String, dynamic>;
    final interacoes = resultados[2] as List<Map<String, dynamic>>;

    final clientes = _lista(snapshot['clientes']);
    final ordens = _lista(snapshot['ordens']);
    final agendamentos = _lista(snapshot['agendamentos']);

    final ordensPorCliente = <String, List<Map<String, dynamic>>>{};
    for (final ordem in ordens) {
      final clienteId = (ordem['cliente_id'] ?? '').toString();
      if (clienteId.isEmpty) continue;
      ordensPorCliente.putIfAbsent(clienteId, () => []).add(ordem);
    }

    final agendaPorCliente = <String, List<Map<String, dynamic>>>{};
    for (final agenda in agendamentos) {
      final clienteId = (agenda['cliente_id'] ?? '').toString();
      if (clienteId.isEmpty) continue;
      agendaPorCliente.putIfAbsent(clienteId, () => []).add(agenda);
    }

    final interacaoPorCliente = <String, Map<String, dynamic>>{};
    for (final interacao in interacoes) {
      final clienteId = (interacao['cliente_id'] ?? '').toString();
      if (clienteId.isEmpty) continue;
      final atual = interacaoPorCliente[clienteId];
      final data = _parseData(interacao['data_interacao']);
      final dataAtual = _parseData(atual?['data_interacao']);
      if (atual == null ||
          (data != null && (dataAtual == null || data.isAfter(dataAtual)))) {
        interacaoPorCliente[clienteId] = interacao;
      }
    }

    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    final resultado = <GrowthPosVendaCliente>[];

    for (final cliente in clientes) {
      final id = (cliente['id'] ?? '').toString();
      final historico = ordensPorCliente[id] ?? const [];
      if (historico.isEmpty) continue;

      final ordenadas = [...historico]
        ..sort((a, b) {
          final da =
              _parseData(a['data_finalizacao']) ??
              _parseData(a['data_abertura']) ??
              DateTime(1900);
          final db =
              _parseData(b['data_finalizacao']) ??
              _parseData(b['data_abertura']) ??
              DateTime(1900);
          return db.compareTo(da);
        });

      final ultima = ordenadas.first;
      final ultimaVisita =
          _parseData(ultima['data_finalizacao']) ??
          _parseData(ultima['data_abertura']);
      final ultimaDia = ultimaVisita == null
          ? null
          : DateTime(ultimaVisita.year, ultimaVisita.month, ultimaVisita.day);
      final dias = ultimaDia == null
          ? 0
          : max(0, hojeDia.difference(ultimaDia).inDays).toInt();

      DateTime? proximoAgendamento;
      for (final agenda in agendaPorCliente[id] ?? const []) {
        final data = _parseData(agenda['data']);
        if (data == null) continue;
        final dia = DateTime(data.year, data.month, data.day);
        if (dia.isBefore(hojeDia)) continue;
        if (proximoAgendamento == null || dia.isBefore(proximoAgendamento)) {
          proximoAgendamento = dia;
        }
      }

      final status = proximoAgendamento != null
          ? 'Agendado'
          : dias >= config.diasReativacao
          ? 'Reativação'
          : dias >= config.diasRetorno
          ? 'Hora do retorno'
          : 'Em dia';

      final interacao = interacaoPorCliente[id];
      final valorTotal = ordenadas.fold<double>(
        0,
        (total, ordem) => total + _valorNegociado(ordem),
      );

      resultado.add(
        GrowthPosVendaCliente(
          id: id,
          nome: (cliente['nome'] ?? 'Cliente').toString(),
          telefone: (cliente['telefone'] ?? '').toString(),
          email: (cliente['email'] ?? '').toString(),
          status: status,
          ultimaOsId: (ultima['id'] ?? '').toString(),
          ultimaOsNumero: (ultima['numero'] ?? '').toString(),
          ultimaVisita: ultimaVisita,
          diasSemRetorno: dias,
          quantidadeOs: ordenadas.length,
          valorTotal: valorTotal,
          temAgendamento: proximoAgendamento != null,
          proximoAgendamento: proximoAgendamento,
          ultimoContato: _parseData(interacao?['data_interacao']),
          proximoContato: _parseData(interacao?['proximo_contato']),
        ),
      );
    }

    const prioridade = <String, int>{
      'Reativação': 0,
      'Hora do retorno': 1,
      'Em dia': 2,
      'Agendado': 3,
    };

    resultado.sort((a, b) {
      final pa = prioridade[a.status] ?? 9;
      final pb = prioridade[b.status] ?? 9;
      if (pa != pb) return pa.compareTo(pb);
      return b.diasSemRetorno.compareTo(a.diasSemRetorno);
    });

    return GrowthPosVendaPainel(config: config, clientes: resultado);
  }

  Future<List<Map<String, dynamic>>> listarInteracoesPosVenda({
    String? clienteId,
  }) async {
    final empresaId = await _empresaId();
    dynamic query = _client
        .from('imperium_pos_venda_interacoes')
        .select()
        .eq('empresa_id', empresaId);

    if ((clienteId ?? '').trim().isNotEmpty) {
      query = query.eq('cliente_id', clienteId!.trim());
    }

    final raw = await query.order('data_interacao', ascending: false);
    return _lista(raw).where((e) => e['excluido_em'] == null).toList();
  }

  Future<void> registrarInteracaoPosVenda({
    required String clienteId,
    String? ordemServicoId,
    required String tipo,
    required String descricao,
    required String resultado,
    DateTime? proximoContato,
  }) async {
    if (descricao.trim().isEmpty) {
      throw ArgumentError('Descreva o contato realizado.');
    }

    final empresaId = await _empresaId();
    await _client
        .from('imperium_pos_venda_interacoes')
        .insert(<String, dynamic>{
          'empresa_id': empresaId,
          'cliente_id': clienteId,
          'ordem_servico_id': _textoNulo(ordemServicoId),
          'tipo': tipo.trim().isEmpty ? 'Contato' : tipo.trim(),
          'descricao': descricao.trim(),
          'resultado': resultado.trim(),
          'proximo_contato': proximoContato == null
              ? null
              : _dataIso(proximoContato),
        });
  }

  Future<List<Map<String, dynamic>>> listarCampanhasMarketing() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_marketing_campanhas')
        .select()
        .eq('empresa_id', empresaId)
        .order('atualizado_em', ascending: false);

    return _lista(raw).where((e) => e['excluido_em'] == null).toList();
  }

  Future<Map<String, dynamic>> salvarCampanhaMarketing({
    String? id,
    required String nome,
    required String plataforma,
    required String tipo,
    required String objetivo,
    required String status,
    required double investimento,
    DateTime? dataInicio,
    DateTime? dataFim,
    required String utmSource,
    required String utmMedium,
    required String utmCampaign,
    int alcance = 0,
    int impressoes = 0,
    int cliques = 0,
    int leads = 0,
    String observacoes = '',
  }) async {
    if (nome.trim().isEmpty) {
      throw ArgumentError('Informe o nome da campanha.');
    }

    final empresaId = await _empresaId();
    final payload = <String, dynamic>{
      'nome': nome.trim(),
      'plataforma': plataforma.trim().isEmpty ? 'Outro' : plataforma.trim(),
      'tipo': tipo.trim().isEmpty ? 'Orgânico' : tipo.trim(),
      'objetivo': objetivo.trim(),
      'status': status.trim().isEmpty ? 'Rascunho' : status.trim(),
      'investimento': max(0.0, investimento).toDouble(),
      'data_inicio': dataInicio == null ? null : _dataIso(dataInicio),
      'data_fim': dataFim == null ? null : _dataIso(dataFim),
      'utm_source': utmSource.trim(),
      'utm_medium': utmMedium.trim(),
      'utm_campaign': utmCampaign.trim(),
      'alcance': max(0, alcance).toInt(),
      'impressoes': max(0, impressoes).toInt(),
      'cliques': max(0, cliques).toInt(),
      'leads': max(0, leads).toInt(),
      'observacoes': observacoes.trim(),
      'excluido_em': null,
    };

    if ((id ?? '').trim().isEmpty) {
      final raw = await _client
          .from('imperium_marketing_campanhas')
          .insert(<String, dynamic>{'empresa_id': empresaId, ...payload})
          .select()
          .single();
      return Map<String, dynamic>.from(raw);
    }

    final raw = await _client
        .from('imperium_marketing_campanhas')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', id!)
        .select()
        .single();
    return Map<String, dynamic>.from(raw);
  }

  Future<List<Map<String, dynamic>>> listarPublicacoesMarketing() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_marketing_publicacoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('atualizado_em', ascending: false);

    return _lista(raw).where((e) => e['excluido_em'] == null).toList();
  }

  Future<Map<String, dynamic>> salvarPublicacaoMarketing({
    String? id,
    String? campanhaId,
    required String plataforma,
    required String tipoConteudo,
    required String titulo,
    required String legenda,
    required String status,
    DateTime? agendadoPara,
  }) async {
    final empresaId = await _empresaId();
    final payload = <String, dynamic>{
      'campanha_id': _textoNulo(campanhaId),
      'plataforma': plataforma.trim().isEmpty ? 'Instagram' : plataforma.trim(),
      'tipo_conteudo': tipoConteudo.trim().isEmpty
          ? 'Post'
          : tipoConteudo.trim(),
      'titulo': titulo.trim(),
      'legenda': legenda.trim(),
      'status': status.trim().isEmpty ? 'Rascunho' : status.trim(),
      'agendado_para': agendadoPara?.toUtc().toIso8601String(),
      'excluido_em': null,
    };

    if ((id ?? '').trim().isEmpty) {
      final raw = await _client
          .from('imperium_marketing_publicacoes')
          .insert(<String, dynamic>{'empresa_id': empresaId, ...payload})
          .select()
          .single();
      return Map<String, dynamic>.from(raw);
    }

    final raw = await _client
        .from('imperium_marketing_publicacoes')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', id!)
        .select()
        .single();
    return Map<String, dynamic>.from(raw);
  }

  Future<List<Map<String, dynamic>>> listarAtribuicoesMarketing() async {
    final empresaId = await _empresaId();
    final raw = await _client
        .from('imperium_marketing_atribuicoes')
        .select()
        .eq('empresa_id', empresaId)
        .order('criado_em', ascending: false);
    return _lista(raw);
  }

  Future<void> registrarAtribuicaoMarketing({
    required String campanhaId,
    String? leadId,
    String? clienteId,
    String? ordemServicoId,
    String origem = 'Manual',
    String modelo = 'Último toque',
    String observacoes = '',
  }) async {
    if ((leadId ?? '').trim().isEmpty &&
        (clienteId ?? '').trim().isEmpty &&
        (ordemServicoId ?? '').trim().isEmpty) {
      throw ArgumentError('Selecione pelo menos um resultado da campanha.');
    }

    final empresaId = await _empresaId();

    if ((ordemServicoId ?? '').trim().isNotEmpty) {
      final existente = await _client
          .from('imperium_marketing_atribuicoes')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('campanha_id', campanhaId)
          .eq('ordem_servico_id', ordemServicoId!.trim())
          .maybeSingle();
      if (existente != null) return;
    }

    await _client
        .from('imperium_marketing_atribuicoes')
        .insert(<String, dynamic>{
          'empresa_id': empresaId,
          'campanha_id': campanhaId,
          'lead_id': _textoNulo(leadId),
          'cliente_id': _textoNulo(clienteId),
          'ordem_servico_id': _textoNulo(ordemServicoId),
          'origem': origem,
          'modelo': modelo,
          'observacoes': observacoes.trim(),
        });
  }

  Future<GrowthMarketingResumo> carregarResumoMarketing() async {
    final resultados = await Future.wait<dynamic>([
      listarCampanhasMarketing(),
      listarPublicacoesMarketing(),
      listarAtribuicoesMarketing(),
      _snapshotGrowth(),
    ]);

    final campanhas = resultados[0] as List<Map<String, dynamic>>;
    final publicacoes = resultados[1] as List<Map<String, dynamic>>;
    final atribuicoes = resultados[2] as List<Map<String, dynamic>>;
    final snapshot = resultados[3] as Map<String, dynamic>;
    final ordens = _lista(snapshot['ordens']);

    final ordensPorId = <String, Map<String, dynamic>>{
      for (final ordem in ordens) (ordem['id'] ?? '').toString(): ordem,
    };

    final idsOrdens = <String>{};
    final idsLeads = <String>{};
    final idsClientes = <String>{};

    for (final atribuicao in atribuicoes) {
      final ordem = (atribuicao['ordem_servico_id'] ?? '').toString();
      final lead = (atribuicao['lead_id'] ?? '').toString();
      final cliente = (atribuicao['cliente_id'] ?? '').toString();
      if (ordem.isNotEmpty) idsOrdens.add(ordem);
      if (lead.isNotEmpty) idsLeads.add(lead);
      if (cliente.isNotEmpty) idsClientes.add(cliente);
    }

    var faturamento = 0.0;
    for (final id in idsOrdens) {
      final ordem = ordensPorId[id];
      if (ordem != null) faturamento += _valorNegociado(ordem);
    }

    final investimento = campanhas.fold<double>(
      0,
      (total, item) => total + _double(item['investimento']),
    );
    final alcance = campanhas.fold<int>(
      0,
      (total, item) => total + _int(item['alcance']),
    );
    final cliques = campanhas.fold<int>(
      0,
      (total, item) => total + _int(item['cliques']),
    );
    final leadsInformados = campanhas.fold<int>(
      0,
      (total, item) => total + _int(item['leads']),
    );

    return GrowthMarketingResumo(
      investimento: investimento,
      faturamentoAtribuido: faturamento,
      campanhasAtivas: campanhas
          .where((e) => (e['status'] ?? '').toString() == 'Ativa')
          .length,
      leads: max(leadsInformados, idsLeads.length).toInt(),
      clientes: idsClientes.length,
      ordens: idsOrdens.length,
      alcance: alcance,
      cliques: cliques,
      publicacoesPlanejadas: publicacoes
          .where((e) => (e['status'] ?? '').toString() != 'Publicado')
          .length,
    );
  }

  Future<List<GrowthMarketingCampanhaDesempenho>>
  carregarDesempenhoCampanhas() async {
    final resultados = await Future.wait<dynamic>([
      listarCampanhasMarketing(),
      listarAtribuicoesMarketing(),
      _snapshotGrowth(),
    ]);

    final campanhas = resultados[0] as List<Map<String, dynamic>>;
    final atribuicoes = resultados[1] as List<Map<String, dynamic>>;
    final snapshot = resultados[2] as Map<String, dynamic>;
    final ordens = _lista(snapshot['ordens']);

    final ordensPorId = <String, Map<String, dynamic>>{
      for (final ordem in ordens) (ordem['id'] ?? '').toString(): ordem,
    };

    final atribuicoesPorCampanha =
        <String, List<Map<String, dynamic>>>{};
    for (final atribuicao in atribuicoes) {
      final campanhaId = (atribuicao['campanha_id'] ?? '').toString();
      if (campanhaId.isEmpty) continue;
      atribuicoesPorCampanha
          .putIfAbsent(campanhaId, () => <Map<String, dynamic>>[])
          .add(atribuicao);
    }

    final resultado = <GrowthMarketingCampanhaDesempenho>[];

    for (final campanha in campanhas) {
      final campanhaId = (campanha['id'] ?? '').toString();
      if (campanhaId.isEmpty) continue;

      final itens = atribuicoesPorCampanha[campanhaId] ?? const [];
      final idsOrdens = <String>{};
      final idsClientes = <String>{};
      final idsLeads = <String>{};

      for (final item in itens) {
        final ordemId = (item['ordem_servico_id'] ?? '').toString();
        final clienteId = (item['cliente_id'] ?? '').toString();
        final leadId = (item['lead_id'] ?? '').toString();

        if (ordemId.isNotEmpty) idsOrdens.add(ordemId);
        if (clienteId.isNotEmpty) idsClientes.add(clienteId);
        if (leadId.isNotEmpty) idsLeads.add(leadId);
      }

      var faturamento = 0.0;
      for (final ordemId in idsOrdens) {
        final ordem = ordensPorId[ordemId];
        if (ordem != null) {
          faturamento += _valorNegociado(ordem);
        }
      }

      final leadsInformados = _int(campanha['leads']);

      resultado.add(
        GrowthMarketingCampanhaDesempenho(
          campanhaId: campanhaId,
          investimento: _double(campanha['investimento']),
          faturamentoAtribuido: faturamento,
          leads: max(leadsInformados, idsLeads.length).toInt(),
          clientes: idsClientes.length,
          ordens: idsOrdens.length,
        ),
      );
    }

    return resultado;
  }

  Future<Map<String, dynamic>> carregarSnapshotParaAtribuicao() {
    return _snapshotGrowth();
  }

  static DateTime? _parseData(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.toLocal();

    final partes = text.split('/');
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }

  static String _dataIso(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final mes = local.month.toString().padLeft(2, '0');
    final dia = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mes-$dia';
  }

  static String? _textoNulo(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static double _valorNegociado(Map<String, dynamic> ordem) {
    return max(
      0.0,
      _double(ordem['valor_total']) -
          _double(ordem['desconto']) -
          _double(ordem['desconto_negociacao']) +
          _double(ordem['acrescimo_negociacao']) +
          _double(ordem['juros_parcelamento']),
    ).toDouble();
  }
}
