import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V2 fecha CAS e conflitos antes do upload V1', () {
    final source = File(
      'lib/services/precificacao_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('precificacao-cloud-v2-cas-conflitos-simulacoes'));
    expect(source, contains('reconciliarAntesDoUpload'));
    expect(source, contains("'alteracao_concorrente'"));
    expect(source, contains("'cas_falhou'"));
    expect(source, contains(".eq('atualizado_em', baseTs)"));
    expect(source, contains('resolverUsandoLocal'));
    expect(source, contains('resolverUsandoNuvem'));
  });

  test('V2 sincroniza exclusoes sem hard delete remoto', () {
    final source = File(
      'lib/services/precificacao_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains("'excluido_em'"));
    expect(source, contains('exclusao_local_e_alteracao_remota'));
    expect(source, contains('cas_falhou_na_exclusao'));
    expect(source, isNot(contains(".delete().eq('empresa_id'")));
  });

  test('V2 cria cenarios com historico imutavel', () {
    final source = File(
      'lib/services/precificacao_cloud_v2_service.dart',
    ).readAsStringSync();

    expect(source, contains('simularESalvar'));
    expect(source, contains('listarSimulacoes'));
    expect(source, contains('sincronizarSimulacoes'));
    expect(source, contains("'meta_faturamento'"));
    expect(source, contains("'preco_sugerido'"));
    expect(source, contains("'preco_revenda_10_mais'"));

    final sql = File(
      'supabase/migrations/'
      '20260913015157_precificacao_cloud_v2_simulacoes.sql',
    ).readAsStringSync();

    expect(sql, contains('imperium_precificacao_simulacoes'));
    expect(sql, contains('grant select, insert'));
    expect(sql, isNot(contains('grant select, insert, update')));
  });

  test('Guard V2 fica antes do upload V1', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();

    final inicio = source.indexOf('Future<void> _syncPrecificacao');
    final fim = source.indexOf('Future<void> registrarExclusaoVeiculo', inicio);

    expect(inicio, greaterThanOrEqualTo(0));
    expect(fim, greaterThan(inicio));

    final bloco = source.substring(inicio, fim);

    // O contrato e sobre ordem semantica dentro da etapa de precificacao.
    // Evita acoplar o teste a quebras de linha/formatacao de chamadas Dart.
    final guard = bloco.indexOf('reconciliarAntesDoUpload');
    final upload = bloco.indexOf('sincronizarUpload');
    final download = bloco.indexOf('sincronizarDownload');
    final depois = bloco.indexOf('sincronizarDepoisDoDownload');

    expect(guard, greaterThanOrEqualTo(0));
    expect(upload, greaterThan(guard));
    expect(download, greaterThan(upload));
    expect(depois, greaterThan(download));

    expect(
      bloco,
      contains('SyncMotorBloqueadoException'),
      reason: 'Conflito pendente deve bloquear o modulo antes do upload.',
    );
  });

  test('SQLite de dominio continua v33 e 220h continua oficial', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
    expect(
      File('lib/config/imperium_regras_negocio.dart').readAsStringSync(),
      contains('horasMensaisPadrao = 220.0'),
    );
  });
}
