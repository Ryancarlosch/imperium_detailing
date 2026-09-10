import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ponto V7 mantém solicitação de ajuste versionada e integrada', () {
    const arquivos = <String>[
      'lib/services/ponto_solicitacao_ajuste_service.dart',
      'lib/screens/ponto_solicitacoes_ajuste_page.dart',
      'supabase/migrations/20260910090000_ponto_v7_solicitacoes_ajuste.sql',
      'supabase/migrations/20260910091500_ponto_v7_hardening_decisao.sql',
    ];

    for (final caminho in arquivos) {
      expect(
        File(caminho).existsSync(),
        isTrue,
        reason: 'Arquivo obrigatório do Ponto V7 ausente: $caminho',
      );
    }

    final service = File(
      'lib/services/ponto_solicitacao_ajuste_service.dart',
    ).readAsStringSync();
    final tela = File(
      'lib/screens/ponto_solicitacoes_ajuste_page.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/20260910090000_ponto_v7_solicitacoes_ajuste.sql',
    ).readAsStringSync();
    final hardening = File(
      'supabase/migrations/20260910091500_ponto_v7_hardening_decisao.sql',
    ).readAsStringSync();

    expect(service, contains("'ponto_solicitar_ajuste'"));
    expect(service, contains("'ponto_decidir_solicitacao_ajuste'"));
    expect(service, contains("'ponto_cancelar_solicitacao_ajuste'"));
    expect(tela, contains('Solicitar correção do ponto'));
    expect(tela, contains('Aprovar'));
    expect(tela, contains('Rejeitar'));

    expect(
      sql,
      contains('create table if not exists public.ponto_solicitacoes_ajuste'),
    );
    expect(sql, contains('enable row level security'));
    expect(sql, contains('private.usuario_admin_empresa'));
    expect(sql, contains('pc.auth_user_id = v_auth'));
    expect(sql, contains('ponto_salvar_registro_admin'));
    expect(sql, contains("where status = 'Pendente'"));
    expect(hardening, contains('p_aprovar is null'));
    expect(hardening, contains('private.usuario_admin_empresa'));
    expect(hardening, contains('ponto_salvar_registro_admin'));
  });

  test('Meu Ponto e painel administrativo expõem o fluxo de correção', () {
    final meuPonto = File('lib/screens/meu_ponto_page.dart').readAsStringSync();
    final admin = File(
      'lib/screens/ponto_funcionarios_page.dart',
    ).readAsStringSync();

    expect(meuPonto, contains('Precisa corrigir uma batida?'));
    expect(meuPonto, contains('PontoSolicitarAjustePage'));
    expect(meuPonto, contains('PontoSolicitacoesAjustePage.minhas'));
    expect(admin, contains('PontoSolicitacoesAjustePage.admin'));
    expect(admin, contains('Solicitações de ajuste'));
  });
}
