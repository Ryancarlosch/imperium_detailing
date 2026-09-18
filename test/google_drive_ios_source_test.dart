import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('google drive no ios falha de forma controlada sem oauth nativo', () {
    final service = File(
      'lib/services/google_drive_backup_service.dart',
    ).readAsStringSync();
    final configurarIos = File(
      'scripts/configurar_ios_imperium.py',
    ).readAsStringSync();
    final prepararIos = File(
      'scripts/preparar_ios_macos.sh',
    ).readAsStringSync();

    expect(service, contains("import 'package:flutter/foundation.dart';"));
    expect(service, contains('String? _erroInicializacao;'));
    expect(service, contains('TargetPlatform.iOS'));
    expect(
      service,
      contains('Google Drive ainda não está configurado no iPhone.'),
    );
    expect(
      service,
      contains('Configure o OAuth Client ID iOS e o URL scheme reverso.'),
    );
    expect(
      service,
      contains('GoogleDriveOAuthConfig.serverClientId'),
    );

    expect(configurarIos, contains('google_ios_client_id'));
    expect(configurarIos, contains('GIDClientID'));
    expect(configurarIos, contains('GIDServerClientID'));
    expect(configurarIos, contains('com.googleusercontent.apps.'));
    expect(
      configurarIos,
      contains('Google Sign-In iOS configurado.'),
    );

    expect(prepararIos, contains('GOOGLE_IOS_CLIENT_ID'));
    expect(
      prepararIos,
      contains('Google Sign-In iOS: pendente; o app continua compilavel.'),
    );
  });
}
