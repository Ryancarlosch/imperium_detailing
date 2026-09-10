import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/repositories/central_gerencial_repository.dart';

void main() {
  test('normaliza período invertido', () {
    final periodo = CentralGerencialRepository.normalizarPeriodo(
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 1),
    );

    expect(periodo.$1, DateTime(2026, 9, 1));
    expect(periodo.$2, DateTime(2026, 9, 10));
  });

  test('período anterior mantém a mesma quantidade de dias', () {
    final anterior = CentralGerencialRepository.periodoAnterior(
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 10),
    );

    expect(anterior.$1, DateTime(2026, 8, 22));
    expect(anterior.$2, DateTime(2026, 8, 31));
  });

  test('comparativo calcula variação contra base anterior', () {
    const indicador = CentralGerencialComparativo(
      titulo: 'Faturamento',
      atual: 12000,
      anterior: 10000,
    );

    expect(indicador.variacaoPercentual, closeTo(20, 0.0001));
    expect(indicador.evoluiu, isTrue);
  });

  test('comparativo sem base anterior não inventa percentual', () {
    const indicador = CentralGerencialComparativo(
      titulo: 'Ticket médio',
      atual: 500,
      anterior: 0,
    );

    expect(indicador.variacaoPercentual, isNull);
  });

  test('alertas gerenciais cobrem riscos financeiros e operacionais', () {
    final alertas = CentralGerencialRepository.gerarAlertasBase(
      resultado: -100,
      margemAtual: 20,
      margemAnterior: 30,
      vencido: 500,
      itensEstoqueBaixo: 3,
      itensEstoqueZerado: 1,
      conversaoAtual: 20,
      conversaoAnterior: 35,
      servicosAbaixoMinimo: 2,
      horasFaltantes: 10,
      receitaPrevista: 10000,
      receitaRealizada: 5000,
    );

    final titulos = alertas.map((item) => item.titulo).join(' | ');
    expect(titulos, contains('Resultado negativo'));
    expect(titulos, contains('Margem caiu'));
    expect(titulos, contains('valores vencidos'));
    expect(titulos, contains('Estoque exige reposição'));
    expect(titulos, contains('Conversão do CRM caiu'));
    expect(titulos, contains('abaixo do preço mínimo seguro'));
    expect(titulos, contains('Horas faltantes'));
    expect(titulos, contains('Receita realizada abaixo do previsto'));
  });

  test('sem riscos retorna status de oportunidade', () {
    final alertas = CentralGerencialRepository.gerarAlertasBase(
      resultado: 1000,
      margemAtual: 40,
      margemAnterior: 38,
      vencido: 0,
      itensEstoqueBaixo: 0,
      itensEstoqueZerado: 0,
      conversaoAtual: 50,
      conversaoAnterior: 45,
      servicosAbaixoMinimo: 0,
      horasFaltantes: 0,
      receitaPrevista: 10000,
      receitaRealizada: 9000,
    );

    expect(alertas, hasLength(1));
    expect(alertas.single.nivel, CentralGerencialAlertaNivel.oportunidade);
  });
}
