import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';

void main() {
  test('Fiscal V33 mantém schema esperado e histórico de importação', () {
    expect(AppDatabase.schemaVersion, 33);

    final banco = File('lib/database/app_database.dart').readAsStringSync();
    expect(banco, contains('nota_fiscal_importacao_tentativas'));
    expect(banco, contains('tentativas_importacao'));
    expect(banco, contains('ultimo_erro_codigo'));
    expect(banco, contains('ultimo_erro_mensagem'));
  });

  test('estoque e financeiro exigem documento fiscal autorizado', () {
    final estoque = File(
      'lib/services/nota_fiscal_entrada_integracao_service.dart',
    ).readAsStringSync();
    final financeiro = File(
      'lib/services/nota_fiscal_financeiro_service.dart',
    ).readAsStringSync();

    expect(estoque, contains("nota.situacaoFiscal != 'autorizada'"));
    expect(financeiro, contains("situacaoFiscal != 'autorizada'"));
  });

  test(
    'Flutter não acessa credencial server-side do Focus nem service role',
    () {
      final arquivos = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (arquivo) =>
                arquivo.path.endsWith('.dart') &&
                arquivo.path.toLowerCase().contains('nota_fiscal'),
          );

      for (final arquivo in arquivos) {
        final fonte = arquivo.readAsStringSync();

        expect(
          fonte,
          isNot(contains('SUPABASE_SERVICE_ROLE_KEY')),
          reason: arquivo.path,
        );
        expect(fonte, isNot(contains('service_role')), reason: arquivo.path);
        expect(
          fonte,
          isNot(contains("String.fromEnvironment('FOCUS_NFE_TOKEN')")),
          reason: arquivo.path,
        );
        expect(
          fonte,
          isNot(contains('String.fromEnvironment("FOCUS_NFE_TOKEN")')),
          reason: arquivo.path,
        );
        expect(
          fonte,
          isNot(contains("Platform.environment['FOCUS_NFE_TOKEN']")),
          reason: arquivo.path,
        );
        expect(
          fonte,
          isNot(contains('Platform.environment["FOCUS_NFE_TOKEN"]')),
          reason: arquivo.path,
        );
      }
    },
  );

  test('Edge Function guarda segredo no servidor e revalida autenticação', () {
    final backend = File(
      'supabase/functions/imperium-fiscal-dfe/index.ts',
    ).readAsStringSync();

    expect(backend, contains('Deno.env.get("FOCUS_NFE_TOKEN")'));
    expect(backend, contains('Deno.env.get("FOCUS_NFE_CNPJ")'));
    expect(backend, contains('client.auth.getUser()'));
    expect(backend, isNot(contains('body.cnpj')));
    expect(backend, contains('auto_manifestacao: false'));
  });

  test('portal assistido mantém fallback sem automatizar CAPTCHA', () {
    final portal = File(
      'lib/screens/nota_fiscal_portal_assistido_page.dart',
    ).readAsStringSync();

    expect(portal, contains('shadowRoot'));
    expect(portal, contains('iframe,frame,object,embed'));
    expect(portal, contains('Copiar diagnóstico fiscal'));
    expect(portal, contains('Frame cross-origin'));
  });
}
