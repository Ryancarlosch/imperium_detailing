import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumidores Dart criticos usam o contrato monetario da OS', () {
    const arquivos = <String>[
      'lib/models/ordem_servico.dart',
      'lib/repositories/pagamento_repository.dart',
      'lib/repositories/custos_repository.dart',
      'lib/repositories/ordem_servico_repository.dart',
    ];

    for (final caminho in arquivos) {
      final arquivo = File(caminho);
      expect(arquivo.existsSync(), isTrue, reason: caminho);

      final conteudo = arquivo.readAsStringSync();
      expect(
        conteudo.contains('OrdemServicoValor'),
        isTrue,
        reason: '$caminho deve usar OrdemServicoValor.',
      );
    }
  });

  test('documentacao reflete v33 e Sprint 1A', () {
    final arquitetura = File('ARQUITETURA_PROJETO.md').readAsStringSync();
    final pendencias = File('PENDENCIAS_TECNICAS.md').readAsStringSync();

    expect(arquitetura.contains('v33'), isTrue);
    expect(arquitetura.contains('Contrato monetario da OS'), isTrue);
    expect(pendencias.contains('Sprint 1A'), isTrue);
    expect(pendencias.contains('Parte B'), isTrue);
    expect(pendencias.contains('SQL'), isTrue);
  });
}
