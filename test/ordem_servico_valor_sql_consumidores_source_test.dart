import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumidores SQL criticos usam OrdemServicoValor', () {
    const arquivos = <String>[
      'lib/repositories/pagamento_repository.dart',
      'lib/repositories/dashboard_repository.dart',
      'lib/repositories/financeiro_dashboard_repository.dart',
      'lib/repositories/ordem_servico_repository.dart',
      'lib/repositories/dre_repository.dart',
    ];

    for (final caminho in arquivos) {
      final arquivo = File(caminho);
      expect(arquivo.existsSync(), isTrue, reason: caminho);

      final conteudo = arquivo.readAsStringSync();

      expect(
        conteudo.contains('OrdemServicoValor.sqlValorNegociado'),
        isTrue,
        reason: '$caminho deve usar o contrato SQL oficial da OS.',
      );

      if (caminho.endsWith('pagamento_repository.dart')) {
        expect(
          conteudo.contains(
            r"${OrdemServicoValor.sqlValorNegociado(alias: 'os')} AS total",
          ),
          isTrue,
          reason:
              'O resumo geral do PagamentoRepository deve usar o contrato SQL.',
        );
      }
    }
  });

  test(
    'formula monetaria manual antiga nao existe nos consumidores migrados',
    () {
      final regex = RegExp(
        r'COALESCE\((?:os\.)?valor_total,\s*0\)\s*'
        r'-\s*COALESCE\((?:os\.)?desconto,\s*0\)\s*'
        r'-\s*COALESCE\((?:os\.)?desconto_negociacao,\s*0\)',
        multiLine: true,
      );

      const arquivos = <String>[
        'lib/repositories/pagamento_repository.dart',
        'lib/repositories/dashboard_repository.dart',
        'lib/repositories/financeiro_dashboard_repository.dart',
        'lib/repositories/ordem_servico_repository.dart',
      ];

      for (final caminho in arquivos) {
        final conteudo = File(caminho).readAsStringSync();

        expect(
          regex.hasMatch(conteudo),
          isFalse,
          reason: '$caminho ainda contem formula monetaria duplicada.',
        );
      }
    },
  );
}
