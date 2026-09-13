import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class WebOrigem {
  const WebOrigem({required this.dispositivoId, required this.localId});

  final String dispositivoId;
  final int localId;
}

class WebOrigemService {
  WebOrigemService._();

  static final WebOrigemService instance = WebOrigemService._();

  static const _chaveDispositivo = 'imperium_web_origem_dispositivo_v1';
  static const _chaveSequencia = 'imperium_web_origem_local_id_v1';

  Future<String> dispositivoId() async {
    final prefs = await SharedPreferences.getInstance();
    final atual = prefs.getString(_chaveDispositivo)?.trim() ?? '';

    if (atual.isNotEmpty) return atual;

    final random = Random.secure();
    final sufixo = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

    final novo =
        'web-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$sufixo';

    await prefs.setString(_chaveDispositivo, novo);
    return novo;
  }

  Future<int> proximoLocalId() async {
    final prefs = await SharedPreferences.getInstance();
    final ultimo = prefs.getInt(_chaveSequencia) ?? 0;
    final agora = DateTime.now().microsecondsSinceEpoch;
    final proximo = max(ultimo + 1, agora);

    await prefs.setInt(_chaveSequencia, proximo);
    return proximo;
  }

  Future<WebOrigem> proxima() async {
    return WebOrigem(
      dispositivoId: await dispositivoId(),
      localId: await proximoLocalId(),
    );
  }
}
