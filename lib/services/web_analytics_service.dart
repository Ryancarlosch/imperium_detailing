import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Telemetria do Imperium Web com coleta mínima e sem dados de clientes.
///
/// O identificador de usuário enviado ao PostHog é somente o UUID do Supabase.
/// E-mail, telefone, placa, valores e demais dados operacionais são removidos
/// por uma segunda camada de proteção antes do envio.
class WebAnalyticsService {
  WebAnalyticsService._();

  static final WebAnalyticsService instance = WebAnalyticsService._();

  static const String _projectToken =
      'phc_mWBx4yuoMBizVA37PsDa7fNxLWSkGEiGp6K4i3QEBVFy';

  static const Set<String> _blockedKeyFragments = {
    'email',
    'mail',
    'nome',
    'name',
    'telefone',
    'phone',
    'cpf',
    'cnpj',
    'placa',
    'plate',
    'endereco',
    'address',
    'senha',
    'password',
    'token',
    'secret',
    'observ',
    'descricao',
    'description',
    'valor',
    'value',
    'amount',
  };

  bool _inicializado = false;

  bool get inicializado => _inicializado;

  Future<void> inicializar() async {
    if (_inicializado) return;

    try {
      final config = PostHogConfig(_projectToken, beforeSend: [_redactEvent])
        ..host = 'https://us.i.posthog.com'
        ..captureApplicationLifecycleEvents = false
        ..sendFeatureFlagEvents = false
        ..preloadFeatureFlags = false
        ..sessionReplay = false
        ..surveys = false
        ..personProfiles = PostHogPersonProfiles.identifiedOnly
        ..capturePushNotificationSubscriptions = false
        ..capturePushNotificationOpened = false;

      // Exceções são registradas manualmente após sanitização. Não ativar o
      // autocapture aqui para evitar que mensagens com dados operacionais sejam
      // enviadas antes da limpeza.
      config.errorTrackingConfig.captureFlutterErrors = false;
      config.errorTrackingConfig.capturePlatformDispatcherErrors = false;
      config.errorTrackingConfig.captureIsolateErrors = false;
      config.errorTrackingConfig.captureNativeExceptions = false;

      await Posthog().setup(config);
      _inicializado = true;
      await evento('web_app_opened');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PostHog indisponível: ${e.runtimeType}');
      }
    }
  }

  Future<void> identificar(String userId) async {
    if (!_inicializado || userId.trim().isEmpty) return;

    await _safe(() async {
      await Posthog().identify(
        userId: userId,
        userProperties: const {'platform': 'web'},
      );
    });
  }

  Future<void> evento(String nome, {Map<String, Object>? propriedades}) async {
    if (!_inicializado || nome.trim().isEmpty) return;

    await _safe(() async {
      await Posthog().capture(
        eventName: nome,
        properties: _sanitizeMap(propriedades),
      );
    });
  }

  /// Registra uma exceção sem enviar a mensagem original do erro.
  ///
  /// O stack trace original é mantido para diagnóstico, enquanto o objeto do
  /// erro é substituído por uma versão que contém somente área e tipo.
  Future<void> registrarErro({
    required String area,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    if (!_inicializado) return;

    final tipo = error.runtimeType.toString();
    final erroSeguro = _ImperiumWebException(area: area, tipo: tipo);

    await _safe(() async {
      await Posthog().captureException(
        error: erroSeguro,
        stackTrace: stackTrace ?? StackTrace.current,
        properties: {'area': area, 'runtime_type': tipo, 'platform': 'web'},
      );
    });
  }

  Future<void> limparIdentidade() async {
    if (!_inicializado) return;
    await _safe(Posthog().reset);
  }

  Future<void> _safe(Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Falha de telemetria ignorada: ${e.runtimeType}');
      }
    }
  }

  static PostHogEvent? _redactEvent(PostHogEvent event) {
    event.properties = _sanitizeMap(event.properties);
    event.userProperties = _sanitizeMap(event.userProperties);
    event.userPropertiesSetOnce = _sanitizeMap(event.userPropertiesSetOnce);
    return event;
  }

  static Map<String, Object>? _sanitizeMap(Map<String, Object>? source) {
    if (source == null || source.isEmpty) return null;

    final safe = <String, Object>{};

    for (final entry in source.entries) {
      final key = entry.key.trim();
      final normalized = key.toLowerCase();
      if (key.isEmpty || _isBlockedKey(normalized)) continue;

      final value = entry.value;
      if (value is bool || value is num) {
        safe[key] = value;
      } else if (value is String) {
        safe[key] = value.length <= 120 ? value : value.substring(0, 120);
      }
    }

    return safe.isEmpty ? null : safe;
  }

  static bool _isBlockedKey(String key) {
    for (final fragment in _blockedKeyFragments) {
      if (key.contains(fragment)) return true;
    }
    return false;
  }
}

final class _ImperiumWebException implements Exception {
  const _ImperiumWebException({required this.area, required this.tipo});

  final String area;
  final String tipo;

  @override
  String toString() => 'ImperiumWebException(area=$area,type=$tipo)';
}
