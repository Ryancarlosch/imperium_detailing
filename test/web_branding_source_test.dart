import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Index Web usa identidade premium durante o carregamento', () {
    final source = File('web/index.html').readAsStringSync();

    for (final marker in [
      '<html lang="pt-BR">',
      '<title>Imperium Manager</title>',
      'content="#090B0E"',
      'id="imperium-loading"',
      'IMPERIUM',
      'MANAGER',
      'Preparando seu ambiente',
      'flutter-first-frame',
      'prefers-reduced-motion',
      'flutter_bootstrap.js',
    ]) {
      expect(source, contains(marker));
    }

    expect(source, isNot(contains('A new Flutter project')));
    expect(source, isNot(contains('<title>imperium_detailing</title>')));
  });

  test('Manifesto PWA preserva identidade Imperium', () {
    final source = File('web/manifest.json').readAsStringSync();

    expect(source, contains('"name": "Imperium Manager"'));
    expect(source, contains('"short_name": "Imperium"'));
    expect(source, contains('"background_color": "#090B0E"'));
    expect(source, contains('"theme_color": "#090B0E"'));
    expect(source, contains('"lang": "pt-BR"'));
    expect(source, isNot(contains('A new Flutter project')));
  });
}
