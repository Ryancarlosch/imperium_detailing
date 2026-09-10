import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fiscal V33 mantém integração condicionada à autorização fiscal', () {
    final estoque = File(
      'lib/services/nota_fiscal_entrada_integracao_service.dart',
    ).readAsStringSync();
    final financeiro = File(
      'lib/services/nota_fiscal_financeiro_service.dart',
    ).readAsStringSync();

    expect(estoque, contains("nota.situacaoFiscal != 'autorizada'"));
    expect(financeiro, contains("situacaoFiscal != 'autorizada'"));
  });

  test('Fiscal V33 possui rastreio, reprocessamento e saúde fiscal', () {
    final banco = File('lib/database/app_database.dart').readAsStringSync();
    final importacao = File(
      'lib/services/nota_fiscal_importacao_service.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/importar_nota_fiscal_page.dart',
    ).readAsStringSync();

    expect(banco, contains('static const int schemaVersion = 33;'));
    expect(banco, contains('nota_fiscal_importacao_tentativas'));
    expect(banco, contains('tentativas_importacao'));
    expect(
      importacao,
      contains('Future<NotaFiscalImportacaoResultado> reprocessar'),
    );
    expect(tela, contains('Saúde Fiscal'));
  });

  test(
    'backend não aceita CNPJ injetado pelo APK nem manifesta automaticamente',
    () {
      final backend = File(
        'supabase/functions/imperium-fiscal-dfe/index.ts',
      ).readAsStringSync();

      expect(backend, contains('FOCUS_NFE_CNPJ'));
      expect(backend, isNot(contains('body.cnpj')));
      expect(backend, contains('auto_manifestacao: false'));
      expect(backend, contains('client.auth.getUser()'));
    },
  );

  test(
    'portal assistido tenta DOM renderizado, frames e Shadow DOM sem contornar CAPTCHA',
    () {
      final portal = File(
        'lib/screens/nota_fiscal_portal_assistido_page.dart',
      ).readAsStringSync();

      expect(portal, contains('shadowRoot'));
      expect(portal, contains('iframe,frame,object,embed'));
      expect(portal, contains('Copiar diagnóstico fiscal'));
      expect(portal, contains('Frame cross-origin'));
    },
  );
}
