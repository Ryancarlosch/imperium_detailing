import 'dart:convert';

import 'supabase_bootstrap.dart';

class AssinaturaPlano {
  const AssinaturaPlano({
    required this.codigo,
    required this.nome,
    required this.meses,
    required this.valorCentavos,
    required this.moeda,
  });

  final String codigo;
  final String nome;
  final int meses;
  final int valorCentavos;
  final String moeda;

  double get valor => valorCentavos / 100;

  factory AssinaturaPlano.fromMap(Map<String, dynamic> map) {
    return AssinaturaPlano(
      codigo: (map['codigo'] ?? '').toString().trim(),
      nome: (map['nome'] ?? '').toString().trim(),
      meses: _int(map['meses']),
      valorCentavos: _int(map['valor_centavos']),
      moeda: (map['moeda'] ?? 'BRL').toString().trim(),
    );
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}

class AssinaturaCheckoutResultado {
  const AssinaturaCheckoutResultado({
    required this.url,
    required this.orderNsu,
    required this.plano,
    required this.valorCentavos,
  });

  final String url;
  final String orderNsu;
  final String plano;
  final int valorCentavos;

  factory AssinaturaCheckoutResultado.fromMap(Map<String, dynamic> map) {
    return AssinaturaCheckoutResultado(
      url: (map['url'] ?? '').toString().trim(),
      orderNsu: (map['order_nsu'] ?? '').toString().trim(),
      plano: (map['plano'] ?? '').toString().trim(),
      valorCentavos: AssinaturaPlano._int(map['valor_centavos']),
    );
  }
}

class AssinaturaCheckoutService {
  const AssinaturaCheckoutService();

  Future<List<AssinaturaPlano>> listarPlanos() async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta da empresa para consultar os planos.');
    }

    final resposta = await client.rpc('imperium_planos_disponiveis');
    if (resposta is! List) {
      throw StateError('Não foi possível carregar os planos do Imperium.');
    }

    return resposta
        .whereType<Map>()
        .map((row) => AssinaturaPlano.fromMap(Map<String, dynamic>.from(row)))
        .where(
          (plano) =>
              plano.codigo.isNotEmpty &&
              plano.nome.isNotEmpty &&
              plano.meses > 0 &&
              plano.valorCentavos > 0,
        )
        .toList(growable: false);
  }

  Future<AssinaturaCheckoutResultado> criarCheckout({
    required String empresaId,
    required String planoCodigo,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta da empresa para assinar o plano.');
    }

    final empresa = empresaId.trim();
    final plano = planoCodigo.trim().toLowerCase();
    if (empresa.isEmpty || plano.isEmpty) {
      throw ArgumentError('Empresa e plano são obrigatórios para o checkout.');
    }

    final response = await client.functions.invoke(
      'imperium-infinitepay-checkout',
      body: <String, dynamic>{
        'empresa_id': empresa,
        'plano_codigo': plano,
      },
    );

    dynamic raw = response.data;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        throw StateError('A InfinitePay retornou uma resposta inválida.');
      }
    }

    if (raw is! Map) {
      throw StateError('A InfinitePay retornou uma resposta inválida.');
    }

    final map = Map<String, dynamic>.from(raw);
    if (response.status < 200 || response.status >= 300) {
      final mensagem = (map['error'] ?? 'Não foi possível criar o checkout.')
          .toString()
          .trim();
      throw StateError(
        mensagem.isEmpty ? 'Não foi possível criar o checkout.' : mensagem,
      );
    }

    final resultado = AssinaturaCheckoutResultado.fromMap(map);
    final uri = Uri.tryParse(resultado.url);
    if (resultado.orderNsu.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        !uri.isScheme('https')) {
      throw StateError('O checkout retornado pela InfinitePay é inválido.');
    }

    return resultado;
  }
}
