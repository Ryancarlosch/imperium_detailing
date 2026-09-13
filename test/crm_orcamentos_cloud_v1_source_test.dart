import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRM e Orcamentos V1 possuem seis entidades cloud', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('crm-orcamentos-cloud-v1'));
    expect(source, contains('imperium_orcamentos'));
    expect(source, contains('imperium_orcamento_itens'));
    expect(source, contains('imperium_crm_leads'));
    expect(source, contains('imperium_crm_interacoes'));
    expect(source, contains('imperium_crm_campanhas'));
    expect(source, contains('imperium_crm_cupons'));
    expect(source, contains('sincronizarDownloadNovos'));
  });

  test('V1 usa soft delete e download somente de novos', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('_marcarAusentesComoExcluidos'));
    expect(source, contains("'excluido_em'"));
    expect(source, contains('_jaMapeadoRemoto'));
    expect(source, contains('_reconstruirOrigem'));
    expect(source, isNot(contains('.delete().eq(')));
  });

  test('Orcamentos preservam perfil e catalogo quando disponivel', () {
    final source = File(
      'lib/services/crm_orcamentos_cloud_service.dart',
    ).readAsStringSync();

    expect(source, contains('financeiro_preco_documentos'));
    expect(source, contains('financeiro_orcamento_item_catalogo'));
    expect(source, contains("'perfil_preco'"));
    expect(source, contains("'servico_catalogo_id'"));
  });

  test('CRM e Orcamentos ficam liberados apenas apos integracao', () {
    final acesso = File(
      'lib/services/funcionario_acesso_service.dart',
    ).readAsStringSync();

    final bloco =
        RegExp(
          r'modulosRemotosProntos\s*=\s*<String>\{([^}]*)\}',
          dotAll: true,
        ).firstMatch(acesso)?.group(1) ??
        '';

    expect(bloco, contains("'crm'"));
    expect(bloco, contains("'orcamentos'"));
  });

  test('Sync operacional publica e baixa CRM Orcamentos', () {
    final source = File(
      'lib/services/operacional_sync_service.dart',
    ).readAsStringSync();
    final compact = source.replaceAll(RegExp(r'\s+'), '');

    final osUpload =
        RegExp(
          r'awaitOsCloudUploadService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final crmUpload =
        RegExp(
          r'awaitCrmOrcamentosCloudService\.instance\.'
          r'sincronizarUpload\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final osDownload =
        RegExp(
          r'awaitOsCloudDownloadService\.instance\.'
          r'sincronizarDownloadNovos\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    final crmDownload =
        RegExp(
          r'awaitCrmOrcamentosCloudService\.instance\.'
          r'sincronizarDownloadNovos\(empresaId,?\);',
        ).firstMatch(compact)?.start ??
        -1;

    expect(osUpload, greaterThanOrEqualTo(0));
    expect(crmUpload, greaterThan(osUpload));
    expect(osDownload, greaterThan(crmUpload));
    expect(crmDownload, greaterThan(osDownload));
  });

  test('Migration RLS separa CRM de Orcamentos', () {
    final sql = File(
      'supabase/migrations/20260913023051_crm_orcamentos_cloud_v1.sql',
    ).readAsStringSync();

    expect(sql, contains("private.imperium_pode_modulo(empresa_id, 'crm')"));
    expect(
      sql,
      contains("private.imperium_pode_modulo(empresa_id, 'orcamentos')"),
    );
    expect(sql, contains('enable row level security'));
  });

  test('SQLite de dominio continua v33', () {
    expect(
      File('lib/database/app_database.dart').readAsStringSync(),
      contains('static const int schemaVersion = 33;'),
    );
  });
}
