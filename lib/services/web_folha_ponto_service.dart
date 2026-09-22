import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

/// Calcula a folha Web usando a mesma regra de ponto do aplicativo Android.
///
/// Os dados operacionais vêm das tabelas Cloud do Ponto. Pagamentos e custos
/// de colaboradores continuam vindo do Financeiro/Precificação e são ligados
/// pelo colaborador sincronizado, evitando uma segunda fonte de verdade.
class WebFolhaPontoService {
  WebFolhaPontoService._();

  static final WebFolhaPontoService instance = WebFolhaPontoService._();

  dynamic get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de calcular a folha.');
    }
    return empresaId;
  }

  Future<Map<String, Map<String, dynamic>>> obterResumos({
    required DateTime mes,
    required List<Map<String, dynamic>> colaboradores,
    required List<Map<String, dynamic>> pagamentos,
  }) async {
    final empresaId = await _empresaId();
    final inicio = DateTime(mes.year, mes.month, 1);
    final fim = DateTime(mes.year, mes.month + 1, 0);

    final dados = await Future.wait<dynamic>([
      _client
          .from('ponto_colaboradores')
          .select('id,nome,funcao,ativo,origem_local_id')
          .eq('empresa_id', empresaId),
      _client
          .from('ponto_jornada')
          .select(
            'dia_semana,ativo,entrada,intervalo_inicio,intervalo_fim,saida',
          )
          .eq('empresa_id', empresaId)
          .order('dia_semana'),
      _client
          .from('ponto_config')
          .select('adicional_hora_extra')
          .eq('empresa_id', empresaId)
          .maybeSingle(),
      _client
          .from('ponto_registros')
          .select(
            'id,colaborador_id,data,situacao,entrada,intervalo_inicio,'
            'intervalo_fim,saida,observacoes',
          )
          .eq('empresa_id', empresaId)
          .gte('data', _data(inicio))
          .lte('data', _data(fim))
          .order('data'),
      _client
          .from('ponto_fechamentos')
          .select(
            'colaborador_id,competencia,status,snapshot_json,fechado_em,'
            'reaberto_em,motivo_reabertura',
          )
          .eq('empresa_id', empresaId)
          .eq('competencia', _data(inicio)),
    ]);

    final pontoColaboradores = _mapas(dados[0]);
    final jornada = _mapas(dados[1]);
    final config = dados[2] is Map
        ? Map<String, dynamic>.from(dados[2] as Map)
        : const <String, dynamic>{};
    final registros = _mapas(dados[3]);
    final fechamentos = _mapas(dados[4]);

    final pontoPorOrigem = <int, Map<String, dynamic>>{};
    final pontoPorNome = <String, List<Map<String, dynamic>>>{};
    for (final item in pontoColaboradores) {
      final origem = _int(item['origem_local_id']);
      if (origem > 0) pontoPorOrigem[origem] = item;

      final nome = _normalizarNome(item['nome']);
      if (nome.isNotEmpty) {
        pontoPorNome.putIfAbsent(nome, () => <Map<String, dynamic>>[]).add(item);
      }
    }

    final jornadaPorDia = <int, Map<String, dynamic>>{
      for (final item in jornada) _int(item['dia_semana']): item,
    };

    final registrosPorColaborador = <String, Map<String, Map<String, dynamic>>>{};
    for (final item in registros) {
      final colaboradorId = (item['colaborador_id'] ?? '').toString();
      final data = (item['data'] ?? '').toString();
      if (colaboradorId.isEmpty || data.isEmpty) continue;
      registrosPorColaborador
          .putIfAbsent(
            colaboradorId,
            () => <String, Map<String, dynamic>>{},
          )[data] = item;
    }

    final fechamentoPorColaborador = <String, Map<String, dynamic>>{
      for (final item in fechamentos)
        if ((item['colaborador_id'] ?? '').toString().isNotEmpty)
          item['colaborador_id'].toString(): item,
    };

    final adicionalPercentual = _double(
      config['adicional_hora_extra'],
      padrao: 50,
    ).clamp(0.0, 500.0).toDouble();

    final resultado = <String, Map<String, dynamic>>{};

    for (final colaborador in colaboradores) {
      final id = (colaborador['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      Map<String, dynamic>? ponto;
      final origemLocal = _int(colaborador['origem_local_id']);
      if (origemLocal > 0) {
        ponto = pontoPorOrigem[origemLocal];
      }
      if (ponto == null) {
        final candidatos = pontoPorNome[_normalizarNome(colaborador['nome'])];
        if (candidatos != null && candidatos.length == 1) {
          ponto = candidatos.single;
        }
      }

      final pontoId = (ponto?['id'] ?? '').toString();
      final registrosDoColaborador =
          registrosPorColaborador[pontoId] ??
          const <String, Map<String, dynamic>>{};

      final espelho = _calcularEspelho(
        inicio: inicio,
        fim: fim,
        jornadaPorDia: jornadaPorDia,
        registrosPorData: registrosDoColaborador,
      );

      final salarioBase = _double(colaborador['remuneracao_mensal']);
      const horasBaseMensal = ImperiumRegrasNegocio.horasMensaisPadrao;
      final valorHora = horasBaseMensal <= 0
          ? 0.0
          : salarioBase / horasBaseMensal;

      final minutosExtras = _int(espelho['minutos_extras']);
      final minutosFaltantes = _int(espelho['minutos_faltantes']);
      final valorExtras =
          (minutosExtras / 60.0) *
          valorHora *
          (1 + adicionalPercentual / 100.0);
      final descontoHorasFaltantes =
          (minutosFaltantes / 60.0) * valorHora;
      final valorEstimado =
          (salarioBase - descontoHorasFaltantes + valorExtras)
              .clamp(0.0, double.infinity)
              .toDouble();

      var jaPago = 0.0;
      for (final pagamento in pagamentos) {
        if ((pagamento['colaborador_id'] ?? '').toString() != id) continue;
        final data = DateTime.tryParse(
          (pagamento['data_pagamento'] ?? '').toString(),
        );
        if (data == null || data.isBefore(inicio) || data.isAfter(fim)) {
          continue;
        }
        jaPago += _double(pagamento['valor']);
      }

      var base = <String, dynamic>{
        ...espelho,
        'colaborador_id': id,
        'ponto_colaborador_id': pontoId.isEmpty ? null : pontoId,
        'ponto_vinculado': pontoId.isNotEmpty,
        'nome': (colaborador['nome'] ?? '').toString(),
        'funcao': (colaborador['funcao'] ?? '').toString(),
        'salario_base': salarioBase,
        'horas_base_mensal': horasBaseMensal,
        'valor_hora': valorHora,
        'adicional_hora_extra_percentual': adicionalPercentual,
        'valor_horas_extras': valorExtras,
        'desconto_horas_faltantes': descontoHorasFaltantes,
        'valor_estimado_pagar': valorEstimado,
        'fechamento_status': 'Aberto',
        'fechado_em': null,
      };

      final fechamento = fechamentoPorColaborador[pontoId];
      if (fechamento != null &&
          (fechamento['status'] ?? '').toString() == 'Fechado') {
        final snapshotRaw = fechamento['snapshot_json'];
        if (snapshotRaw is Map && snapshotRaw.isNotEmpty) {
          final snapshot = Map<String, dynamic>.from(snapshotRaw);
          base = <String, dynamic>{
            ...base,
            ...snapshot,
            'colaborador_id': id,
            'ponto_colaborador_id': pontoId,
            'ponto_vinculado': true,
            'nome': (colaborador['nome'] ?? '').toString(),
            'funcao': (colaborador['funcao'] ?? '').toString(),
          };
        }
        base['fechamento_status'] = 'Fechado';
        base['fechado_em'] = fechamento['fechado_em'];
      }

      final estimadoFinal = _double(
        base['valor_estimado_pagar'],
        padrao: valorEstimado,
      );
      base['valor_estimado_pagar'] = estimadoFinal;
      base['ja_pago_mes'] = jaPago;
      base['restante_estimado'] = (estimadoFinal - jaPago)
          .clamp(0.0, double.infinity)
          .toDouble();
      base['pago_acima_estimado'] = (jaPago - estimadoFinal)
          .clamp(0.0, double.infinity)
          .toDouble();

      resultado[id] = base;
    }

    return resultado;
  }

  Map<String, dynamic> _calcularEspelho({
    required DateTime inicio,
    required DateTime fim,
    required Map<int, Map<String, dynamic>> jornadaPorDia,
    required Map<String, Map<String, dynamic>> registrosPorData,
  }) {
    var previstosMes = 0;
    var trabalhados = 0;
    var extras = 0;
    var faltantes = 0;
    var atrasos = 0;
    var faltas = 0;
    var atestados = 0;
    var folgas = 0;
    var pendencias = 0;
    var incompletos = 0;

    final dias = <Map<String, dynamic>>[];
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    var cursor = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day);

    while (!cursor.isAfter(fimDia)) {
      final jornadaDia =
          jornadaPorDia[cursor.weekday] ?? <String, dynamic>{'ativo': false};
      final ativo = _bool(jornadaDia['ativo']);
      final previsto = ativo ? _minutosPeriodo(jornadaDia) : 0;
      previstosMes += previsto;

      final dataBanco = _data(cursor);
      final registro = registrosPorData[dataBanco];
      final situacao = (registro?['situacao'] ?? '').toString();
      final passado = cursor.isBefore(hoje);
      final hojeMesmo =
          cursor.year == hoje.year &&
          cursor.month == hoje.month &&
          cursor.day == hoje.day;

      var trabalhadoDia = 0;
      var extraDia = 0;
      var faltanteDia = 0;
      var atrasoDia = 0;
      var statusExibido = situacao;

      if (registro != null) {
        if (situacao == 'Trabalhado') {
          final entrada = _horaNula(registro['entrada']);
          final saida = _horaNula(registro['saida']);
          final intervaloInicio = _horaNula(registro['intervalo_inicio']);
          final intervaloFim = _horaNula(registro['intervalo_fim']);
          final jornadaTemIntervalo =
              _horaNula(jornadaDia['intervalo_inicio']) != null &&
              _horaNula(jornadaDia['intervalo_fim']) != null;

          final incompleto =
              entrada == null ||
              saida == null ||
              (jornadaTemIntervalo &&
                  (intervaloInicio == null || intervaloFim == null));

          if (incompleto) {
            if (passado) {
              incompletos++;
              statusExibido = 'Incompleto';
            } else if (hojeMesmo) {
              statusExibido = 'Em andamento';
            }
          }

          trabalhadoDia = _minutosPeriodo(registro);
          extraDia = ativo && trabalhadoDia > previsto
              ? trabalhadoDia - previsto
              : 0;
          faltanteDia = ativo && trabalhadoDia < previsto
              ? previsto - trabalhadoDia
              : 0;
          atrasoDia = ativo
              ? _atrasoMinutos(jornadaDia['entrada'], registro['entrada'])
              : 0;
        } else if (situacao == 'Falta') {
          faltas++;
          faltanteDia = ativo ? previsto : 0;
        } else if (situacao == 'Atestado') {
          atestados++;
        } else if (situacao == 'Folga') {
          folgas++;
        }
      } else if (ativo && passado) {
        statusExibido = 'Pendente';
        pendencias++;
      } else if (ativo && hojeMesmo) {
        statusExibido = 'Hoje';
      } else if (ativo) {
        statusExibido = 'Previsto';
      } else {
        statusExibido = 'Sem jornada';
      }

      trabalhados += trabalhadoDia;
      extras += extraDia;
      faltantes += faltanteDia;
      atrasos += atrasoDia;

      dias.add(<String, dynamic>{
        'data': dataBanco,
        'dia_semana': cursor.weekday,
        'jornada_ativa': ativo ? 1 : 0,
        'jornada_entrada': jornadaDia['entrada'],
        'jornada_intervalo_inicio': jornadaDia['intervalo_inicio'],
        'jornada_intervalo_fim': jornadaDia['intervalo_fim'],
        'jornada_saida': jornadaDia['saida'],
        'minutos_previstos': previsto,
        'minutos_trabalhados': trabalhadoDia,
        'minutos_extras': extraDia,
        'minutos_faltantes': faltanteDia,
        'minutos_atraso': atrasoDia,
        'status_exibido': statusExibido,
        'registro': registro,
      });

      cursor = cursor.add(const Duration(days: 1));
    }

    return <String, dynamic>{
      'minutos_previstos_mes': previstosMes,
      'minutos_trabalhados': trabalhados,
      'minutos_extras': extras,
      'minutos_faltantes': faltantes,
      'minutos_atraso': atrasos,
      'faltas': faltas,
      'atestados': atestados,
      'folgas': folgas,
      'pendencias': pendencias,
      'incompletos': incompletos,
      'dias': dias,
    };
  }

  static int _minutosPeriodo(Map<String, dynamic> item) {
    final entrada = _minutosHora(item['entrada']);
    final saida = _minutosHora(item['saida']);
    if (entrada == null || saida == null || saida <= entrada) return 0;

    var total = saida - entrada;
    final inicioIntervalo = _minutosHora(item['intervalo_inicio']);
    final fimIntervalo = _minutosHora(item['intervalo_fim']);
    if (inicioIntervalo != null &&
        fimIntervalo != null &&
        fimIntervalo > inicioIntervalo) {
      total -= fimIntervalo - inicioIntervalo;
    }
    return total < 0 ? 0 : total;
  }

  static int _atrasoMinutos(dynamic esperado, dynamic realizado) {
    final a = _minutosHora(esperado);
    final b = _minutosHora(realizado);
    if (a == null || b == null || b <= a) return 0;
    return b - a;
  }

  static int? _minutosHora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    final partes = texto.split(':');
    if (partes.length < 2) return null;
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    if (hora == null ||
        minuto == null ||
        hora < 0 ||
        hora > 23 ||
        minuto < 0 ||
        minuto > 59) {
      return null;
    }
    return hora * 60 + minuto;
  }

  static String? _horaNula(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final texto = valor?.toString().toLowerCase() ?? '';
    return texto == 'true' || texto == '1';
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor, {double padrao = 0}) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ??
        padrao;
  }

  static List<Map<String, dynamic>> _mapas(dynamic dados) {
    if (dados is! List) return const [];
    return dados
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _normalizarNome(dynamic valor) {
    return valor?.toString().trim().toLowerCase().replaceAll(
              RegExp(r'\s+'),
              ' ',
            ) ??
        '';
  }

  static String _data(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }
}
