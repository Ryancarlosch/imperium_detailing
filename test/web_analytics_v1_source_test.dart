import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web Analytics V1', () {
    test('PostHog Web nasce com coleta automática sensível desligada', () {
      final html = File('web/index.html').readAsStringSync();

      expect(html, contains("api_host: 'https://us.i.posthog.com'"));
      expect(html, contains('autocapture: false'));
      expect(html, contains('disable_session_recording: true'));
      expect(html, contains('disable_surveys: true'));
      expect(html, contains('capture_pageview: false'));
      expect(html, contains('capture_pageleave: false'));
      expect(html, contains('capture_exceptions: false'));
      expect(
        html,
        contains('advanced_disable_feature_flags_on_first_load: true'),
      );
    });

    test('serviço sanitiza eventos e erros antes do envio', () {
      final source = File(
        'lib/services/web_analytics_service.dart',
      ).readAsStringSync();

      expect(source, contains('beforeSend: [_redactEvent]'));
      expect(source, contains('PostHogPersonProfiles.identifiedOnly'));
      expect(source, contains('captureFlutterErrors = false'));
      expect(source, contains('capturePlatformDispatcherErrors = false'));
      expect(source, contains("evento('web_app_opened')"));
      expect(source, contains('Posthog().captureException'));
      expect(source, contains('_ImperiumWebException'));
      expect(source, contains("'senha'"));
      expect(source, contains("'placa'"));
      expect(source, contains("'valor'"));
    });

    test('login Web envia somente eventos operacionais sem e-mail', () {
      final source = File('lib/main_web.dart').readAsStringSync();

      expect(source, contains('WebAnalyticsService.instance'));
      expect(source, contains("'auth_magic_link_requested'"));
      expect(source, contains("'auth_context_ready'"));
      expect(source, contains("'company_switched'"));
      expect(source, contains("'auth_signed_out'"));
      expect(source, contains('analytics.identificar(user.id)'));
      expect(source, isNot(contains("propriedades: {'email'")));
    });

    test('CI compila e valida o bundle Web', () {
      final workflow = File(
        '.github/workflows/flutter_quality.yml',
      ).readAsStringSync();

      expect(
        workflow,
        contains('flutter build web -t lib/main_web.dart --release'),
      );
      expect(workflow, contains('test -f build/web/sqlite3.wasm'));
      expect(workflow, contains('actions/upload-artifact@v4'));
    });
  });
}
