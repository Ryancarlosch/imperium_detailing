import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'regras financeiras centrais continuam separando competencia, caixa e previsao',
    () {
      final dre = File(
        'lib/repositories/dre_repository.dart',
      ).readAsStringSync();
      final fluxo = File(
        'lib/repositories/fluxo_caixa_repository.dart',
      ).readAsStringSync();
      final conciliacao = File(
        'lib/repositories/conta_financeira_repository.dart',
      ).readAsStringSync();

      // financeiro-regra-datas-source-v4
      //
      // DRE:
      // - caixa usa a data em que o dinheiro entrou/saiu;
      // - competencia usa a data economica do fato.
      expect(dre, contains('COALESCE(m.data_pagamento, m.data)'));
      expect(dre, contains('COALESCE(m.data_competencia, m.data)'));
      expect(dre, contains('listarOrigens'));

      // Fluxo:
      // - realizado deve depender de data_pagamento;
      // - previsto deve possuir vencimento e competencia como fallback;
      // - transferencias nao entram como entrada/saida operacional.
      final realizadoUsaPagamento = RegExp(
        r"WHEN\s+m\.status\s*=\s*'Realizado'[\s\S]{0,180}"
        r"COALESCE\(m\.data_pagamento,\s*m\.data\)",
        multiLine: true,
      );

      final previstoUsaVencimentoCompetencia = RegExp(
        r"ELSE\s+COALESCE\([\s\S]{0,180}"
        r"m\.data_vencimento[\s\S]{0,180}"
        r"m\.data_competencia[\s\S]{0,180}"
        r"m\.data",
        multiLine: true,
      );

      expect(
        realizadoUsaPagamento.hasMatch(fluxo),
        isTrue,
        reason:
            'Fluxo realizado deve continuar usando data_pagamento como referencia.',
      );

      expect(
        previstoUsaVencimentoCompetencia.hasMatch(fluxo),
        isTrue,
        reason:
            'Fluxo previsto deve usar vencimento e competencia como referencias.',
      );

      expect(fluxo, contains('m.transferencia_id IS NULL'));

      // Conciliacao altera saldo de conta, mas nao o resultado economico.
      expect(conciliacao, contains("'origem': 'Conciliação de conta'"));
      expect(conciliacao, contains("'impacta_dre': 0"));
      expect(conciliacao, contains('conciliacao-remocao-segura-v1'));
    },
  );

  test('DRE possui PDF detalhado e acoes de visualizar e compartilhar', () {
    final service = File(
      'lib/services/dre_pdf_service.dart',
    ).readAsStringSync();
    final page = File('lib/screens/dre_page.dart').readAsStringSync();

    expect(service, contains('dre-pdf-detalhado-v1'));
    expect(service, contains('Printing.layoutPdf'));
    expect(service, contains('Printing.sharePdf'));
    expect(service, contains('listarOrigens('));
    expect(service, contains('DRE POR CATEGORIA / CONTA'));
    expect(service, contains('DETALHAMENTO DOS LANÇAMENTOS'));

    expect(page, contains('dre-pdf-ui-v1'));
    expect(page, contains('dre-pdf-acao-v1'));
    expect(page, contains('dre-pdf-appbar-v1'));
    expect(page, contains('Visualizar DRE em PDF'));
    expect(page, contains('Compartilhar DRE em PDF'));
  });
}
