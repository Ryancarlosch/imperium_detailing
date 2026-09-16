import 'dart:convert';

import 'supabase_bootstrap.dart';

class ImperiumPlanoAdmin {
  const ImperiumPlanoAdmin({
    required this.codigo,
    required this.nome,
    required this.meses,
    required this.valorCentavos,
    required this.moeda,
    required this.ativo,
    required this.ordem,
  });

  final String codigo;
  final String nome;
  final int meses;
  final int valorCentavos;
  final String moeda;
  final bool ativo;
  final int ordem;

  double get valor => valorCentavos / 100;

  factory ImperiumPlanoAdmin.fromMap(Map<String, dynamic> map) {
    return ImperiumPlanoAdmin(
      codigo: (map['codigo'] ?? '').toString().trim(),
      nome: (map['nome'] ?? '').toString().trim(),
      meses: _int(map['meses']),
      valorCentavos: _int(map['valor_centavos']),
      moeda: (map['moeda'] ?? 'BRL').toString().trim(),
      ativo: map['ativo'] == true,
      ordem: _int(map['ordem']),
    );
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ImperiumPlanosAdminService {
  const ImperiumPlanosAdminService();

  Future<List<ImperiumPlanoAdmin>> listar() async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta administrativa do Imperium.');
    }

    final response = await client.functions.invoke(
      'imperium-admin-planos',
      body: const <String, dynamic>{'action': 'list'},
    );

    final map = _mapResponse(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _mensagemErro(map, 'Não foi possível carregar os planos.'),
      );
    }

    final raw = map['planos'];
    if (raw is! List) {
      throw StateError('O servidor retornou uma lista de planos inválida.');
    }

    return raw
        .whereType<Map>()
        .map(
          (item) => ImperiumPlanoAdmin.fromMap(Map<String, dynamic>.from(item)),
        )
        .where((plano) => plano.codigo.isNotEmpty && plano.nome.isNotEmpty)
        .toList(growable: false);
  }

  Future<ImperiumPlanoAdmin> salvar({
    String? codigo,
    required String nome,
    required int meses,
    required int valorCentavos,
    required bool ativo,
    required int ordem,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta administrativa do Imperium.');
    }

    final response = await client.functions.invoke(
      'imperium-admin-planos',
      body: <String, dynamic>{
        'action': 'save',
        if ((codigo ?? '').trim().isNotEmpty) 'codigo': codigo!.trim(),
        'nome': nome.trim(),
        'meses': meses,
        'valor_centavos': valorCentavos,
        'ativo': ativo,
        'ordem': ordem,
      },
    );

    final map = _mapResponse(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_mensagemErro(map, 'Não foi possível salvar o plano.'));
    }

    final raw = map['plano'];
    if (raw is! Map) {
      throw StateError('O servidor não retornou o plano salvo.');
    }

    return ImperiumPlanoAdmin.fromMap(Map<String, dynamic>.from(raw));
  }

  Map<String, dynamic> _mapResponse(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        throw StateError('O servidor retornou uma resposta inválida.');
      }
    }

    if (value is! Map) {
      throw StateError('O servidor retornou uma resposta inválida.');
    }

    return Map<String, dynamic>.from(value);
  }

  String _mensagemErro(Map<String, dynamic> map, String fallback) {
    final text = (map['error'] ?? map['message'] ?? fallback).toString().trim();
    return text.isEmpty ? fallback : text;
  }
}
