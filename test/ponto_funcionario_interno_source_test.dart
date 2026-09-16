import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rota antiga do Ponto aponta para o fluxo interno V2', () {
    final source = File(
      'lib/screens/ponto_nuvem_importacao_page.dart',
    ).readAsStringSync();

    expect(source, contains("export 'ponto_nuvem_importacao_v2_page.dart';"));
  });

  test('Ponto gerencia funcionarios dentro do Imperium', () {
    final source = File(
      'lib/screens/ponto_nuvem_importacao_v2_page.dart',
    ).readAsStringSync();

    expect(source, contains('Funcionários sincronizados'));
    expect(source, contains('Gerenciar funcionários e permissões'));
    expect(source, contains('Nenhuma configuração manual '));
    expect(source, contains('no Supabase é necessária.'));
    expect(source, contains('Cadastro operacional vinculado à empresa'));

    expect(source, isNot(contains('vincularUsuario')));
    expect(source, isNot(contains('E-mail confirmado no Supabase')));
    expect(source, isNot(contains('Conta Supabase ainda não vinculada')));
    expect(source, isNot(contains('Primeiro envie o convite em Supabase')));
    expect(source, isNot(contains('auth_user_id')));
  });
}
