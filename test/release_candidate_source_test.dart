import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gate de release candidate valida Android e Web release', () {
    final script = File('VALIDAR_RC.ps1').readAsStringSync();
    final vercel = File('scripts/vercel_build.sh').readAsStringSync();
    final iosDoc = File(
      'IOS-PREPARACAO-E-HOMOLOGACAO.md',
    ).readAsStringSync();

    expect(script, contains('flutter pub get'));
    expect(script, contains('dart format --output=none --set-exit-if-changed lib test'));
    expect(script, contains('flutter analyze'));
    expect(script, contains('flutter test'));
    expect(script, contains('flutter build apk --release'));
    expect(
      script,
      contains(
        'flutter build web --target lib/main_web_bootstrap.dart --release',
      ),
    );
    expect(script, contains('git diff --check'));
    expect(
      script,
      contains('RELEASE CANDIDATE ANDROID/WEB APROVADO.'),
    );

    expect(
      vercel,
      contains(
        'flutter build web --target lib/main_web_bootstrap.dart --release',
      ),
    );

    expect(iosDoc, contains('flutter create . --platforms ios'));
    expect(iosDoc, contains('flutter build ios --release --no-codesign'));
    expect(iosDoc, contains('imperiumdetailing://login-callback/'));
    expect(iosDoc, contains('NSCameraUsageDescription'));
    expect(iosDoc, contains('NSPhotoLibraryUsageDescription'));
    expect(iosDoc, contains('TestFlight'));
  });
}
