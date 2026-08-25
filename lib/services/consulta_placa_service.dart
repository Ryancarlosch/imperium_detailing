import 'dart:convert';

import 'supabase_bootstrap.dart';

class ConsultaPlacaResultado {
  const ConsultaPlacaResultado({
    required this.placa,
    required this.marca,
    required this.modelo,
    required this.cor,
    required this.anoFabricacao,
    required this.anoModelo,
  });

  final String placa;
  final String marca;
  final String modelo;
  final String cor;
  final int anoFabricacao;
  final int anoModelo;

  String get anoPreferencial {
    if (anoModelo > 0) return anoModelo.toString();
    if (anoFabricacao > 0) return anoFabricacao.toString();
    return '';
  }

  factory ConsultaPlacaResultado.fromMap(Map<String, dynamic> map) {
    return ConsultaPlacaResultado(
      placa: (map['placa'] ?? '').toString().trim().toUpperCase(),
      marca: (map['marca'] ?? '').toString().trim(),
      modelo: (map['modelo'] ?? '').toString().trim(),
      cor: (map['cor'] ?? '').toString().trim(),
      anoFabricacao: _int(map['ano_fabricacao']),
      anoModelo: _int(map['ano_modelo']),
    );
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ConsultaPlacaService {
  final Map<String, ConsultaPlacaResultado> _cache =
      <String, ConsultaPlacaResultado>{};

  final Map<String, Future<ConsultaPlacaResultado>> _emAndamento =
      <String, Future<ConsultaPlacaResultado>>{};

  // consulta-placa-automatica-v1
  Future<ConsultaPlacaResultado> consultar(String placaInformada) async {
    final placa = normalizarPlaca(placaInformada);

    if (!placaValida(placa)) {
      throw ArgumentError(
        'Informe uma placa válida no padrão antigo ou Mercosul.',
      );
    }

    final cache = _cache[placa];
    if (cache != null) return cache;

    final andamento = _emAndamento[placa];
    if (andamento != null) return andamento;

    final operacao = _consultarRemoto(placa);
    _emAndamento[placa] = operacao;

    try {
      final resultado = await operacao;
      _cache[placa] = resultado;
      return resultado;
    } finally {
      if (identical(_emAndamento[placa], operacao)) {
        _emAndamento.remove(placa);
      }
    }
  }

  Future<ConsultaPlacaResultado> _consultarRemoto(String placa) async {
    final client = SupabaseBootstrap.client;
    final usuario = client?.auth.currentUser;

    if (client == null || usuario == null) {
      throw StateError(
        'Entre na conta da empresa para consultar os dados da placa.',
      );
    }

    final response = await client.functions.invoke(
      'consultar-placa',
      body: <String, dynamic>{'placa': placa},
    );

    dynamic raw = response.data;

    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        throw StateError('A consulta da placa retornou uma resposta inválida.');
      }
    }

    if (raw is! Map) {
      throw StateError('A consulta da placa retornou uma resposta inválida.');
    }

    final map = Map<String, dynamic>.from(raw);

    if (response.status < 200 || response.status >= 300) {
      final mensagem =
          (map['error'] ??
                  map['mensagem'] ??
                  'Não foi possível consultar a placa.')
              .toString();
      throw StateError(mensagem);
    }

    final dadosRaw = map['data'];
    final dados = dadosRaw is Map ? Map<String, dynamic>.from(dadosRaw) : map;

    final resultado = ConsultaPlacaResultado.fromMap(dados);

    if (resultado.marca.isEmpty && resultado.modelo.isEmpty) {
      throw StateError(
        'A placa foi consultada, mas o veículo não foi identificado.',
      );
    }

    return resultado;
  }

  static String normalizarPlaca(String placa) {
    return placa.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static bool placaValida(String placa) {
    final normalizada = normalizarPlaca(placa);
    return RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(normalizada);
  }
}
