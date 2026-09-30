import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repositório não versiona segredos de servidor', () {
    const extensoesTexto = <String>{
      '.dart',
      '.yaml',
      '.yml',
      '.json',
      '.sql',
      '.md',
      '.properties',
      '.gradle',
      '.kts',
      '.xml',
      '.plist',
      '.xcconfig',
    };

    final ignorados = <String>{
      'test/repositorio_segredos_source_test.dart',
    };

    final arquivos = Directory('.')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((arquivo) {
          final caminho = arquivo.path.replaceAll('\\\\', '/');
          if (caminho.contains('/.git/') ||
              caminho.contains('/build/') ||
              caminho.contains('/.dart_tool/')) {
            return false;
          }
          if (ignorados.contains(caminho)) return false;
          return extensoesTexto.any(caminho.endsWith);
        });

    final proibidos = <RegExp>[
      RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
      RegExp(r'\\bsb_secret_[A-Za-z0-9._-]{12,}'),
      RegExp(
        r'(?:SUPABASE_)?SERVICE_ROLE(?:_KEY)?\\s*[:=]\\s*["\\x27]?[A-Za-z0-9._-]{20,}',
        caseSensitive: false,
      ),
      RegExp(
        r'postgres(?:ql)?://[^\\s:@/]+:[^\\s@/]+@',
        caseSensitive: false,
      ),
    ];

    for (final arquivo in arquivos) {
      final fonte = arquivo.readAsStringSync();
      for (final padrao in proibidos) {
        expect(
          padrao.hasMatch(fonte),
          isFalse,
          reason: 'Possível segredo versionado em ${arquivo.path}: $padrao',
        );
      }
    }
  });
}
