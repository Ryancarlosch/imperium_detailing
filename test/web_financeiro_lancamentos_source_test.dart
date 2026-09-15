import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Financeiro Web cria movimento com origem idempotente', () {
    final source = File(
      'lib/services/web_cloud_gestao_service.dart',
    ).readAsStringSync();

    expect(source, contains('criarMovimentoFinanceiro'));
    expect(source, contains('WebOrigemService.instance.proxima()'));
    expect(source, contains("'origem_dispositivo': origem.dispositivoId"));
    expect(source, contains("'origem_local_id': origem.localId"));
    expect(source, contains("from('imperium_financeiro_movimentos')"));
    expect(source, contains("'empresa_id': empresaId"));
    expect(source, contains("'origem': 'Manual'"));
  });

  test('Financeiro Web preserva competencia caixa e DRE', () {
    final source = File(
      'lib/services/web_cloud_gestao_service.dart',
    ).readAsStringSync();

    expect(source, contains("'data_competencia': competenciaIso"));
    expect(source, contains("'data_vencimento': dataVencimento"));
    expect(source, contains("'data_pagamento': dataPagamento"));
    expect(source, contains("'impacta_dre': impactaDre"));
    expect(source, contains('statusNormalizado == \'Realizado\''));
    expect(source, contains('Selecione a conta/caixa'));
  });

  test('Pagina de fluxo de caixa oferece novo lancamento', () {
    final source = File(
      'lib/web/web_financeiro_lancamentos_page.dart',
    ).readAsStringSync();

    expect(source, contains('class WebFinanceiroLancamentosPage'));
    expect(source, contains('Novo lançamento'));
    expect(source, contains('Categoria financeira'));
    expect(source, contains('Conta / caixa *'));
    expect(source, contains('Lançamentos Web e aplicativo'));
  });
}
