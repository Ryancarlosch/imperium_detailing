import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resumo da folha não mistura custos gerais da empresa', () {
    final resumo = File(
      'lib/screens/funcionarios_resumo_page.dart',
    ).readAsStringSync();

    expect(resumo, contains('Estimado a pagar'));
    expect(resumo, contains('Já pago'));
    expect(resumo, contains('Falta pagar'));
    expect(
      resumo,
      contains('Custos fixos e demais despesas da empresa não entram aqui.'),
    );
    expect(resumo, isNot(contains('obterResumoEstruturaCustos')));
    expect(resumo, isNot(contains('financeiro_custos_fixos')));
  });

  test('Central de Funcionários reúne cadastro folha pagamentos e ponto', () {
    final central = File(
      'lib/screens/funcionarios_central_page.dart',
    ).readAsStringSync();

    expect(central, contains('Estimado a pagar'));
    expect(central, contains('Já pago'));
    expect(central, contains('Falta pagar'));
    expect(central, contains('Cadastro e salários'));
    expect(central, contains('Pagamentos'));
    expect(central, contains('Ponto'));
    expect(central, contains('Reajuste salarial'));
    expect(central, contains('Inativar'));
    expect(central, contains('Histórico salarial e de situação'));
  });

  test('Dashboard e login com permissão de funcionários abrem a Central', () {
    final dashboard = File(
      'lib/screens/dashboard_page.dart',
    ).readAsStringSync();
    final inicio = File(
      'lib/screens/usuario_inicio_page.dart',
    ).readAsStringSync();

    expect(dashboard, contains('const FuncionariosCentralPage()'));
    expect(dashboard, contains("'Funcionários'"));
    expect(inicio, contains('const FuncionariosCentralPage()'));
  });

  test('cálculos de mão de obra continuam filtrando somente ativos', () {
    final custos = File(
      'lib/repositories/custos_repository.dart',
    ).readAsStringSync();
    final precificacao = File(
      'lib/repositories/precificacao_repository.dart',
    ).readAsStringSync();
    final dre = File('lib/repositories/dre_repository.dart').readAsStringSync();

    expect(
      RegExp(
        r'FROM financeiro_colaboradores_custo\s+WHERE ativo = 1',
      ).allMatches(custos).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      RegExp(
        r'FROM financeiro_colaboradores_custo\s+WHERE ativo = 1',
      ).allMatches(precificacao).length,
      greaterThanOrEqualTo(1),
    );
    expect(
      RegExp(
        r'FROM financeiro_colaboradores_custo\s+WHERE ativo = 1',
      ).allMatches(dre).length,
      greaterThanOrEqualTo(1),
    );
  });
}
