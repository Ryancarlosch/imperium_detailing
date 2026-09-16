import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile usa login email/senha compartilhado e sincroniza a sessao', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains('LoginEmailSenhaPage'));
    expect(main, isNot(contains('LoginPage(')));
    expect(main, contains('AuthChangeEvent.passwordRecovery'));
    expect(main, contains('WidgetsBindingObserver'));
    expect(main, contains("'mobile_login'"));
    expect(main, contains("'mobile_startup'"));
    expect(main, contains("'mobile_resume'"));
    expect(main, contains('OperacionalSyncService.instance.sincronizarTudo'));
    expect(main, contains('NovaSenhaPage'));
  });

  test('login e cadastro direcionam confirmacao e recuperacao ao app', () {
    final login = File(
      'lib/screens/login_email_senha_page.dart',
    ).readAsStringSync();
    final cadastro = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();
    final auth = File(
      'lib/services/imperium_auth_service.dart',
    ).readAsStringSync();

    expect(login, contains('imperiumdetailing://login-callback/'));
    expect(login, contains('Começar 30 dias grátis'));
    expect(cadastro, contains('imperiumdetailing://login-callback/'));
    expect(cadastro, contains('redirectTo: _redirectConfirmacao'));
    expect(auth, contains('emailRedirectTo: redirectTo'));
  });

  test('checkout mobile volta ao aplicativo com allowlist dedicada', () {
    final checkout = File(
      'lib/services/assinatura_checkout_service.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final edgeCheckout = File(
      'supabase/functions/imperium-infinitepay-checkout/index.ts',
    ).readAsStringSync();
    final edgeRetorno = File(
      'supabase/functions/imperium-infinitepay-retorno/index.ts',
    ).readAsStringSync();

    expect(checkout, contains('imperiumdetailing://payment-return/'));
    expect(checkout, contains("'return_url': _returnUrl()"));
    expect(manifest, contains('android:host="login-callback"'));
    expect(manifest, contains('android:host="payment-return"'));
    expect(edgeCheckout, contains('MOBILE_RETURN_URL'));
    expect(edgeCheckout, contains('body.return_url'));
    expect(edgeRetorno, contains('MOBILE_RETURN_URL'));
    expect(edgeRetorno, contains('redirectToApp'));
  });
}
