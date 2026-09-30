import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('superficies operacionais Web usam o design system compartilhado', () {
    final arquivosComCanvas = <String>[
      'lib/web/web_estoque_config_page.dart',
      'lib/web/web_estoque_movimentacoes_page.dart',
      'lib/web/web_estoque_produtos_page.dart',
      'lib/web/web_os_arquivos_page.dart',
      'lib/web/web_os_finalizacao_v4_page.dart',
    ];

    final arquivosWeb = Directory('lib/web')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (arquivo) =>
              arquivo.path.endsWith('.dart') &&
              !arquivo.path.endsWith('imperium_web_theme.dart'),
        );

    for (final arquivo in arquivosWeb) {
      final fonte = arquivo.readAsStringSync();
      expect(fonte, isNot(contains('Color(0xFFAAB3BD)')), reason: arquivo.path);
      expect(fonte, isNot(contains('Color(0xFF89939E)')), reason: arquivo.path);
    }

    for (final caminho in arquivosComCanvas) {
      final fonte = File(caminho).readAsStringSync();
      expect(fonte, contains('ImperiumWebTheme'), reason: caminho);
      expect(
        fonte,
        contains('ImperiumWebTheme.contentMaxWidth'),
        reason: caminho,
      );
    }
  });
}
