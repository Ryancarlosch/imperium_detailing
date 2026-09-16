import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App cliente nao versiona chaves privilegiadas do Supabase', () {
    final arquivos = <File>[];

    for (final raiz in <String>['lib', 'android', 'web']) {
      final dir = Directory(raiz);
      if (!dir.existsSync()) continue;
      arquivos.addAll(
        dir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((arquivo) {
              final nome = arquivo.path.toLowerCase();
              return nome.endsWith('.dart') ||
                  nome.endsWith('.xml') ||
                  nome.endsWith('.gradle') ||
                  nome.endsWith('.kts') ||
                  nome.endsWith('.html') ||
                  nome.endsWith('.js') ||
                  nome.endsWith('.json');
            }),
      );
    }

    final proibidos = <String>[
      'SUPABASE_SERVICE_ROLE_KEY',
      'service_role=',
      '"service_role"',
      "'service_role'",
      'BEGIN PRIVATE KEY',
      'BEGIN RSA PRIVATE KEY',
    ];

    for (final arquivo in arquivos) {
      final source = arquivo.readAsStringSync();
      for (final proibido in proibidos) {
        expect(
          source,
          isNot(contains(proibido)),
          reason: '${arquivo.path} contem marcador privilegiado: $proibido',
        );
      }
    }

    final supabase = File('lib/config/supabase_config.dart').readAsStringSync();
    expect(supabase, contains('sb_publishable_'));
    expect(supabase, isNot(contains('sb_secret_')));
  });
}
