import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nova OS Web permanece integrada ao workspace profissional', () {
    final source = File('lib/web/web_gestao_pages.dart').readAsStringSync();

    for (final marker in [
      'class WebNovaOrdemPage',
      'Nova ordem de serviço',
      'Dados da OS',
      'Resumo da OS',
      'Valor previsto',
      'Criar OS aberta',
      'LayoutBuilder',
      'ImperiumWebTheme',
    ]) {
      expect(source, contains(marker));
    }

    expect(source, contains('criarOrdemAberta'));
  });

  test('Editar OS Web preserva CAS cancelamento e layout desktop', () {
    final source = File('lib/web/web_ordens_v3_page.dart').readAsStringSync();

    for (final marker in [
      'Editar ordens de serviço',
      'Valor editável',
      'Bloqueadas',
      'DataTable',
      'Fotos, avarias e assinatura',
      'Editar com proteção de concorrência',
      'Cancelar OS com transação segura',
      'salvarEdicao',
      '_cancelamento.cancelar',
    ]) {
      expect(source, contains(marker));
    }
  });

  test('Finalizar OS Web preserva fechamento transacional completo', () {
    final source = File(
      'lib/web/web_os_finalizacao_v4_page.dart',
    ).readAsStringSync();

    for (final marker in [
      'Finalizar ordens de serviço',
      'Valor negociado',
      'Sem responsável',
      'Produtos',
      'Finalizar',
      'DataTable',
      'estoque FIFO',
      'salvarProdutos',
      '_service.finalizar',
    ]) {
      expect(source, contains(marker));
    }

    expect(
      source,
      contains(
        'Se houver falha em estoque, pagamento ou financeiro, a OS permanece sem finalizar.',
      ),
    );
  });

  test('Shell mantém Nova Editar e Finalizar OS no mesmo workspace', () {
    final source = File(
      'lib/web/web_operacional_shell.dart',
    ).readAsStringSync();

    expect(source, contains('5 => WebNovaOrdemPage('));
    expect(source, contains('6 => WebOrdensV3Page('));
    expect(source, contains('7 => WebOsFinalizacaoV4Page('));
    expect(source, isNot(contains('_paginaRoteada')));
  });
}
