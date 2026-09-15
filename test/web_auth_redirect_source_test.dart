import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap web libera fragmento da URL para redirects do Supabase', () {
    final source = File('lib/main_web_bootstrap.dart').readAsStringSync();

    expect(source, contains("flutter_web_plugins/url_strategy.dart"));
    expect(source, contains('usePathUrlStrategy();'));
    expect(source, contains("import 'main_web.dart' as imperium_web;"));
    expect(source, contains('await imperium_web.main();'));
  });

  test('pipeline web builda o bootstrap de autenticacao', () {
    final workflow = File(
      '.github/workflows/web_preview_build.yml',
    ).readAsStringSync();
    final vercelBuild = File('scripts/vercel_build.sh').readAsStringSync();

    expect(
      workflow,
      contains('--target lib/main_web_bootstrap.dart --release'),
    );
    expect(
      vercelBuild,
      contains('--target lib/main_web_bootstrap.dart --release'),
    );
  });
}
