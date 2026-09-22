import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Configurações Web expõem identidade visual do Android', () {
    final page = File(
      'lib/web/web_configuracoes_empresa_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/web_configuracao_empresa_service.dart',
    ).readAsStringSync();

    for (final marker in [
      'Identidade visual',
      'Nome do aplicativo',
      'Tema escuro',
      'Tema claro',
      'Cor principal',
      'Cor secundária',
      'Dourado Imperium',
    ]) {
      expect(page, contains(marker));
    }

    for (final campo in [
      'nome_aplicativo',
      'tema',
      'cor_principal',
      'cor_secundaria',
    ]) {
      expect(page, contains(campo));
      expect(service, contains(campo));
    }

    expect(
      page,
      contains(
        'A interface Web mantém o tema administrativo próprio por enquanto.',
      ),
    );
  });

  test('Branding Web preserva defaults do mobile', () {
    final service = File(
      'lib/services/web_configuracao_empresa_service.dart',
    ).readAsStringSync();

    expect(service, contains("'Imperium Detailing'"));
    expect(service, contains('0xFFD6A84B'));
    expect(service, contains('0xFF1A1A1A'));
    expect(service, contains("'escuro'"));
    expect(service, contains("tema == 'claro' ? 'claro' : 'escuro'"));
  });
}
