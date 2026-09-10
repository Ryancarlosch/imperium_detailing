import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Central de Saúde permanece aditiva e não migra módulos protegidos', () {
    final configuracoes = File(
      'lib/screens/configuracoes_page.dart',
    ).readAsStringSync();
    final pagina = File(
      'lib/screens/saude_sistema_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/repositories/saude_sistema_repository.dart',
    ).readAsStringSync();
    final database = File('lib/database/app_database.dart').readAsStringSync();

    expect(configuracoes, contains("import 'saude_sistema_page.dart';"));
    expect(configuracoes, contains('Saúde e homologação'));
    expect(pagina, contains('Sincronizar agora?'));
    expect(pagina, contains('não migra Financeiro nem Estoque'));
    expect(pagina, contains('A sincronização só é executada quando você toca'));
    expect(repository, contains('PRAGMA quick_check'));
    expect(repository, contains('PRAGMA foreign_key_check'));
    expect(repository, contains('PontoNuvemDiagnosticoService.instance'));
    expect(repository, contains('_operacional.sincronizarTudo()'));
    expect(repository, isNot(contains('service_role')));
    expect(database, contains('static const int schemaVersion = 33;'));
  });
}
