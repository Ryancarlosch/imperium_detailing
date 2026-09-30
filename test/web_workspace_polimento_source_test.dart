import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('superficies operacionais Web usam o design system compartilhado', () {
    final arquivos = <String>[
      'lib/web/web_estoque_config_page.dart',
      'lib/web/web_estoque_movimentacoes_page.dart',
      'lib/web/web_estoque_produtos_page.dart',
      'lib/web/web_os_arquivos_page.dart',
      'lib/web/web_os_finalizacao_v4_page.dart',
      'lib/web/web_financeiro_administracao_page.dart',
    ];

    for (final caminho in arquivos) {
      final fonte = File(caminho).readAsStringSync();
      expect(fonte, contains('ImperiumWebTheme'), reason: caminho);
      expect(fonte, isNot(contains('Color(0xFFAAB3BD)')), reason: caminho);
      expect(fonte, isNot(contains('Color(0xFF89939E)')), reason: caminho);
    }

    for (final caminho in arquivos.take(5)) {
      final fonte = File(caminho).readAsStringSync();
      expect(
        fonte,
        contains('ImperiumWebTheme.contentMaxWidth'),
        reason: caminho,
      );
    }
  });
}
