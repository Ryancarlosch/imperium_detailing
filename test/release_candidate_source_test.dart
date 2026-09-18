import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gate de release candidate valida Android e Web release', () {
    final script = File('VALIDAR_RC.ps1').readAsStringSync();
    final vercel = File('scripts/vercel_build.sh').readAsStringSync();
    final iosDoc = File('IOS-PREPARACAO-E-HOMOLOGACAO.md').readAsStringSync();
    final prepararIos = File(
      'scripts/preparar_ios_macos.sh',
    ).readAsStringSync();
    final validarIos = File(
      'scripts/validar_ios_macos.sh',
    ).readAsStringSync();
    final configurarIos = File(
      'scripts/configurar_ios_imperium.py',
    ).readAsStringSync();

    expect(script, contains('flutter pub get'));
    expect(
      script,
      contains('dart format --output=none --set-exit-if-changed lib test'),
    );
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
    expect(script, contains('RELEASE CANDIDATE ANDROID/WEB APROVADO.'));

    expect(
      vercel,
      contains(
        'flutter build web --target lib/main_web_bootstrap.dart --release',
      ),
    );

    expect(iosDoc, contains('scripts/preparar_ios_macos.sh'));
    expect(iosDoc, contains('flutter build ios --release --no-codesign'));
    expect(iosDoc, contains('imperiumdetailing://login-callback/'));
    expect(iosDoc, contains('NSCameraUsageDescription'));
    expect(iosDoc, contains('NSPhotoLibraryUsageDescription'));
    expect(iosDoc, contains('TestFlight'));

    expect(prepararIos, contains('flutter create . --platforms ios'));
    expect(prepararIos, contains('arvore Git limpa'));
    expect(prepararIos, contains('configurar_ios_imperium.py'));
    expect(prepararIos, contains('BUNDLE_ID'));
    expect(validarIos, contains('NSCameraUsageDescription'));
    expect(validarIos, contains('NSPhotoLibraryUsageDescription'));
    expect(validarIos, contains('imperiumdetailing'));
    expect(validarIos, contains('flutter build ios --release --no-codesign'));
    expect(validarIos, contains('VALIDACAO IOS SEM ASSINATURA APROVADA.'));

    expect(configurarIos, contains('CFBundleDisplayName'));
    expect(configurarIos, contains('Imperium Manager'));
    expect(configurarIos, contains('NSCameraUsageDescription'));
    expect(configurarIos, contains('NSPhotoLibraryUsageDescription'));
    expect(configurarIos, contains('NSPhotoLibraryAddUsageDescription'));
    expect(configurarIos, contains('CFBundleURLTypes'));
    expect(configurarIos, contains('imperiumdetailing'));
    expect(configurarIos, contains('PRODUCT_BUNDLE_IDENTIFIER'));
    expect(
      configurarIos,
      isNot(contains('br.com.imperiumdetailing.imperium_detailing')),
    );
  });
}
