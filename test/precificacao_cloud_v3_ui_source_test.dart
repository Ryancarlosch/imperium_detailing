import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Central V3 expoe visao geral simulacoes e conflitos', () {
    final source = File(
      'lib/screens/precificacao_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains("text: 'Visão geral'"));
    expect(source, contains("text: 'Simulações'"));
    expect(source, contains("text: 'Conflitos'"));
    expect(source, contains('listarConflitosPendentes'));
    expect(source, contains('listarSimulacoes'));
    expect(source, contains('simularESalvar'));
  });

  test('Central V3 mostra margem critica e ponto de equilibrio', () {
    final source = File(
      'lib/screens/precificacao_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('margemAtual < painel.config.margemMinima'));
    expect(source, contains('precoAtual < item.precoEquilibrio'));
    expect(source, contains("'Prejuízo'"));
    expect(source, contains("'Margem baixa'"));
  });

  test('Aplicacao de preco e individual e confirmada', () {
    final source = File(
      'lib/screens/precificacao_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('Aplicar preço sugerido?'));
    expect(source, contains('_repository.aplicarPrecoPadrao'));
    expect(source, contains('servicoId: servico.id'));
    expect(source, contains('preco: servico.precoSugerido'));
  });

  test('Conflitos permitem usar local ou nuvem', () {
    final source = File(
      'lib/screens/precificacao_cloud_central_page.dart',
    ).readAsStringSync();

    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
    expect(source, contains("'Usar nuvem'"));
    expect(source, contains("'Usar local'"));
  });

  test('Tela principal abre a Central Cloud', () {
    final source = File(
      'lib/screens/custo_servicos_page.dart',
    ).readAsStringSync();

    expect(source, contains('precificacao_cloud_central_page.dart'));
    expect(source, contains('PrecificacaoCloudCentralPage'));
    expect(source, contains("'Central Cloud'"));
  });

  test('220h e SQLite v33 continuam preservados', () {
    expect(
      File('lib/config/imperium_regras_negocio.dart').readAsStringSync(),
      contains('horasMensaisPadrao = 220.0'),
    );
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
