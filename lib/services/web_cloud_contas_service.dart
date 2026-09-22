import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebContaFinanceiraResumo {
  const WebContaFinanceiraResumo({
    required this.conta,
    required this.saldoAtual,
  });

  final Map<String, dynamic> conta;
  final double saldoAtual;

  String get id => (conta['id'] ?? '').toString();
  String get nome => (conta['nome'] ?? '').toString();
  String get tipo => (conta['tipo'] ?? '').toString();
  String get instituicao => (conta['instituicao'] ?? '').toString();
  bool get ativa => conta['ativo'] != false;
}

class WebExtratoContaResumo {
  const WebExtratoContaResumo({
    required this.conta,
    required this.mes,
    required this.saldoInicialMes,
    required this.entradas,
    required this.saidas,
    required this.saldoFinalMes,
    required this.movimentos,
    required this.conciliacoes,
  });

  final Map<String, dynamic> conta;
  final DateTime mes;
  final double saldoInicialMes;
  final double entradas;
  final double saidas;
  final double saldoFinalMes;
  final List<Map<String, dynamic>> movimentos;
  final List<Map<String, dynamic>> conciliacoes;

  double get movimentoLiquido => entradas - saidas;
}

class WebComparativoContaResumo {
  const WebComparativoContaResumo({
    required this.atual,
    required this.anterior,
  });

  final WebExtratoContaResumo atual;
  final WebExtratoContaResumo anterior;
}

class WebCloudContasService {
  WebCloudContasService._();

  static final WebCloudContasService instance = WebCloudContasService._();

  Future<List<WebContaFinanceiraResumo>> listarContas({
    bool incluirInativas = true,
  }) async {
    final empresaId = await _empresaId();
    final client = _client();

    final contasRaw = await client
        .from('imperium_financeiro_contas')
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order('ativo', ascending: false)
        .order('nome');

    final movimentosRaw = await client
        .from('imperium_financeiro_movimentos')
        .select('conta_id,tipo,valor,status,data,data_pagamento,excluido_em')
        .eq('empresa_id', empresaId)
        .eq('status', 'Realizado')
        .isFilter('excluido_em', null);

    final movimentos = movimentosRaw
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final contas = <WebContaFinanceiraResumo>[];
    for (final raw in contasRaw) {
      final conta = Map<String, dynamic>.from(raw);
      if (!incluirInativas && conta['ativo'] == false) continue;

      final contaId = (conta['id'] ?? '').toString();
      final dataSaldo = _parseData(conta['data_saldo_inicial']);
      var saldo = _double(conta['saldo_inicial']);

      for (final movimento in movimentos) {
        if ((movimento['conta_id'] ?? '').toString() != contaId) continue;
        final dataMovimento = _dataMovimento(movimento);
        if (dataMovimento == null) continue;
        if (dataSaldo != null && dataMovimento.isBefore(dataSaldo)) continue;
        saldo += _valorAssinado(movimento);
      }

      contas.add(WebContaFinanceiraResumo(conta: conta, saldoAtual: saldo));
    }

    contas.sort((a, b) {
      if (a.ativa != b.ativa) return a.ativa ? -1 : 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
    return contas;
  }

  Future<WebExtratoContaResumo> obterExtratoMensal({
    required String contaId,
    required DateTime mes,
  }) async {
    final empresaId = await _empresaId();
    final client = _client();
    final inicio = DateTime(mes.year, mes.month, 1);
    final fimExclusivo = DateTime(mes.year, mes.month + 1, 1);

    final contaRaw = await client
        .from('imperium_financeiro_contas')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', contaId)
        .isFilter('excluido_em', null)
        .maybeSingle();

    if (contaRaw == null) {
      throw StateError('Conta financeira não encontrada.');
    }

    final conta = Map<String, dynamic>.from(contaRaw);
    final dataSaldo = _parseData(conta['data_saldo_inicial']);
    final snapshotDepoisDoPeriodo =
        dataSaldo != null && !dataSaldo.isBefore(fimExclusivo);

    if (snapshotDepoisDoPeriodo) {
      return WebExtratoContaResumo(
        conta: conta,
        mes: inicio,
        saldoInicialMes: 0,
        entradas: 0,
        saidas: 0,
        saldoFinalMes: 0,
        movimentos: const [],
        conciliacoes: const [],
      );
    }

    final movimentosRaw = await client
        .from('imperium_financeiro_movimentos')
        .select()
        .eq('empresa_id', empresaId)
        .eq('conta_id', contaId)
        .eq('status', 'Realizado')
        .isFilter('excluido_em', null)
        .order('data', ascending: true);

    final todosMovimentos = movimentosRaw
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _dataMovimento(item) != null)
        .toList();

    var movimentoAnterior = 0.0;
    if (dataSaldo == null || !dataSaldo.isAfter(inicio)) {
      for (final movimento in todosMovimentos) {
        final dataMovimento = _dataMovimento(movimento)!;
        if (!dataMovimento.isBefore(inicio)) continue;
        if (dataSaldo != null && dataMovimento.isBefore(dataSaldo)) continue;
        movimentoAnterior += _valorAssinado(movimento);
      }
    }

    final saldoInicialMes = _double(conta['saldo_inicial']) + movimentoAnterior;
    final inicioMovimentos = dataSaldo != null && dataSaldo.isAfter(inicio)
        ? dataSaldo
        : inicio;

    final movimentos =
        todosMovimentos.where((movimento) {
          final dataMovimento = _dataMovimento(movimento)!;
          return !dataMovimento.isBefore(inicioMovimentos) &&
              dataMovimento.isBefore(fimExclusivo);
        }).toList()..sort((a, b) {
          final dataA = _dataMovimento(a)!;
          final dataB = _dataMovimento(b)!;
          final porData = dataA.compareTo(dataB);
          if (porData != 0) return porData;
          return (a['criado_em'] ?? '').toString().compareTo(
            (b['criado_em'] ?? '').toString(),
          );
        });

    var entradas = 0.0;
    var saidas = 0.0;
    for (final movimento in movimentos) {
      final tipo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();
      final valor = _double(movimento['valor']);
      if (tipo == 'entrada') {
        entradas += valor;
      } else if (tipo == 'saída' || tipo == 'saida') {
        saidas += valor;
      }
    }

    final conciliacoes = await _listarConciliacoesMes(
      empresaId: empresaId,
      contaId: contaId,
      inicio: inicio,
      fimExclusivo: fimExclusivo,
    );

    return WebExtratoContaResumo(
      conta: conta,
      mes: inicio,
      saldoInicialMes: saldoInicialMes,
      entradas: entradas,
      saidas: saidas,
      saldoFinalMes: saldoInicialMes + entradas - saidas,
      movimentos: movimentos,
      conciliacoes: conciliacoes,
    );
  }

  Future<WebComparativoContaResumo> obterComparativo({
    required String contaId,
    required DateTime mes,
  }) async {
    final atualMes = DateTime(mes.year, mes.month, 1);
    final anteriorMes = DateTime(mes.year, mes.month - 1, 1);
    final resultados = await Future.wait([
      obterExtratoMensal(contaId: contaId, mes: atualMes),
      obterExtratoMensal(contaId: contaId, mes: anteriorMes),
    ]);

    return WebComparativoContaResumo(
      atual: resultados[0],
      anterior: resultados[1],
    );
  }

  Future<List<Map<String, dynamic>>> _listarConciliacoesMes({
    required String empresaId,
    required String contaId,
    required DateTime inicio,
    required DateTime fimExclusivo,
  }) async {
    final client = _client();
    final raw = await client
        .from('imperium_financeiro_conciliacoes')
        .select()
        .eq('empresa_id', empresaId)
        .eq('conta_id', contaId)
        .isFilter('excluido_em', null)
        .order('data_conciliacao', ascending: false);

    return raw.map((item) => Map<String, dynamic>.from(item)).where((item) {
      final data = _parseData(item['data_conciliacao']);
      return data != null &&
          !data.isBefore(inicio) &&
          data.isBefore(fimExclusivo);
    }).toList();
  }

  Future<Map<String, dynamic>> salvarConta({
    String? id,
    String? atualizadoEmEsperado,
    required String nome,
    required String tipo,
    required String instituicao,
    required double saldoInicial,
    DateTime? dataSaldoInicial,
    String observacoes = '',
    bool ativo = true,
  }) async {
    final nomeLimpo = nome.trim();
    final tipoLimpo = tipo.trim();
    if (nomeLimpo.length < 2) {
      throw ArgumentError('Informe o nome da conta.');
    }
    if (tipoLimpo.isEmpty) {
      throw ArgumentError('Informe o tipo da conta.');
    }

    final empresaId = await _empresaId();
    final client = _client();
    final agora = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'nome': nomeLimpo,
      'tipo': tipoLimpo,
      'instituicao': instituicao.trim(),
      'saldo_inicial': saldoInicial,
      'data_saldo_inicial': dataSaldoInicial?.toIso8601String(),
      'observacoes': observacoes.trim(),
      'ativo': ativo,
      'origem_atualizado_em': agora,
      'excluido_em': null,
    };

    final idLimpo = id?.trim() ?? '';
    if (idLimpo.isEmpty) {
      final origem = await WebOrigemService.instance.proxima();
      final raw = await client
          .from('imperium_financeiro_contas')
          .insert({
            'empresa_id': empresaId,
            'origem_dispositivo': origem.dispositivoId,
            'origem_local_id': origem.localId,
            ...payload,
            'origem_criado_em': agora,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(raw);
    }

    dynamic query = client
        .from('imperium_financeiro_contas')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('id', idLimpo);

    final esperado = atualizadoEmEsperado?.trim() ?? '';
    if (esperado.isNotEmpty) {
      query = query.eq('atualizado_em', esperado);
    }

    final rows = await query.select();
    if (rows is! List || rows.isEmpty) {
      throw StateError(
        'A conta foi alterada em outro dispositivo. Atualize a tela e tente novamente.',
      );
    }
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<void> definirAtivo({
    required Map<String, dynamic> conta,
    required bool ativo,
  }) async {
    await salvarConta(
      id: conta['id']?.toString(),
      atualizadoEmEsperado: conta['atualizado_em']?.toString(),
      nome: (conta['nome'] ?? '').toString(),
      tipo: (conta['tipo'] ?? 'Conta bancária').toString(),
      instituicao: (conta['instituicao'] ?? '').toString(),
      saldoInicial: _double(conta['saldo_inicial']),
      dataSaldoInicial: _parseData(conta['data_saldo_inicial']),
      observacoes: (conta['observacoes'] ?? '').toString(),
      ativo: ativo,
    );
  }

  Future<Map<String, dynamic>> registrarConciliacao({
    required String contaId,
    required DateTime data,
    required double saldoInformado,
    required bool criarAjuste,
    String observacoes = '',
  }) async {
    final id = contaId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Conta financeira inválida.');
    }

    final empresaId = await _empresaId();
    final conciliacao = await WebOrigemService.instance.proxima();
    final movimento = await WebOrigemService.instance.proxima();

    final raw = await _client().rpc(
      'imperium_financeiro_conciliar_web',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_conta_id': id,
        'p_data': data.toIso8601String(),
        'p_saldo_informado': saldoInformado,
        'p_criar_ajuste': criarAjuste,
        'p_observacoes': observacoes.trim(),
        'p_origem_dispositivo': conciliacao.dispositivoId,
        'p_conciliacao_local_id': conciliacao.localId,
        'p_movimento_local_id': movimento.localId,
      },
    );

    if (raw is! Map) {
      throw StateError('A conciliação não retornou um resultado válido.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir o financeiro.');
    }
    return empresaId;
  }

  SupabaseClient _client() {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  static DateTime? _dataMovimento(Map<String, dynamic> movimento) {
    return _parseData(movimento['data_pagamento']) ??
        _parseData(movimento['data']);
  }

  static double _valorAssinado(Map<String, dynamic> movimento) {
    final tipo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();
    final valor = _double(movimento['valor']);
    if (tipo == 'entrada') return valor;
    if (tipo == 'saída' || tipo == 'saida') return -valor;
    return 0;
  }

  static DateTime? _parseData(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
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

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
