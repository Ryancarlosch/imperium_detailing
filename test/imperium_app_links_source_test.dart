import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deep links nativos usam contrato central e Android equivalente', () {
    final links = File(
      'lib/config/imperium_app_links.dart',
    ).readAsStringSync();
    final primeiroAcesso = File(
      'lib/screens/empresa_primeiro_acesso_page.dart',
    ).readAsStringSync();
    final funcionario = File(
      'lib/services/funcionario_acesso_service.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(links, contains("scheme = 'imperiumdetailing'"));
    expect(links, contains("loginHost = 'login-callback'"));
    expect(links, contains("paymentHost = 'payment-return'"));
    expect(links, contains("loginCallback = '\$scheme://\$loginHost/'"));
    expect(links, contains("paymentReturn = '\$scheme://\$paymentHost/'"));

    expect(
      primeiroAcesso,
      contains('ImperiumAppLinks.loginCallback'),
    );
    expect(
      funcionario,
      contains('ImperiumAppLinks.loginCallback'),
    );

    expect(
      primeiroAcesso,
      isNot(contains('imperiumdetailing://login-callback/')),
    );
    expect(
      funcionario,
      isNot(contains('imperiumdetailing://login-callback/')),
    );

    expect(manifest, contains('android:scheme="imperiumdetailing"'));
    expect(manifest, contains('android:host="login-callback"'));
    expect(manifest, contains('android:host="payment-return"'));
  });
}
