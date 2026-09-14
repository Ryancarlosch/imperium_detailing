import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

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

    final movimentos = (movimentosRaw as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final contas = <WebContaFinanceiraResumo>[];
    for (final raw in contasRaw as List) {
      final conta = Map<String, dynamic>.from(raw as Map);
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

    final todosMovimentos = (movimentosRaw as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
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

    final movimentos = todosMovimentos.where((movimento) {
      final dataMovimento = _dataMovimento(movimento)!;
      return !dataMovimento.isBefore(inicioMovimentos) &&
          dataMovimento.isBefore(fimExclusivo);
    }).toList()
      ..sort((a, b) {
        final dataA = _dataMovimento(a)!;
        final dataB = _dataMovimento(b)!;
        final porData = dataA.compareTo(dataB);
        if (porData != 0) return porData;
        return (a['criado_em'] ?? '')
            .toString()
            .compareTo((b['criado_em'] ?? '').toString());
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

    return (raw as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final data = _parseData(item['data_conciliacao']);
          return data != null &&
              !data.isBefore(inicio) &&
              data.isBefore(fimExclusivo);
        })
        .toList();
  }

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir o financeiro.');
    }
    return empresaId;
  }

  dynamic _client() {
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
