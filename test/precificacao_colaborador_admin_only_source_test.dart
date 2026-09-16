import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Custos financeiros de colaborador ficam restritos ao admin', () {
    final sql = File(
      'supabase/migrations/20260916235500_precificacao_colaborador_admin_only.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_precificacao_colaboradores_custo'));
    expect(sql, contains('private.imperium_eh_admin_empresa(empresa_id)'));
    expect(
      sql,
      isNot(contains("imperium_pode_modulo(empresa_id, 'financeiro')")),
    );
    expect(sql, contains('for select'));
    expect(sql, contains('for insert'));
    expect(sql, contains('for update'));
  });
}
