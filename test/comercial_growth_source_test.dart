import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Marketing compartilha campanhas publicacoes e atribuicao', () {
    final screen = File('lib/screens/marketing_page.dart').readAsStringSync();
    final service = File(
      'lib/services/comercial_growth_cloud_service.dart',
    ).readAsStringSync();
    final web = File('lib/web/web_operacional_shell.dart').readAsStringSync();
    final mobile = File('lib/screens/dashboard_page.dart').readAsStringSync();

    for (final marker in [
      'Conteúdo e publicações',
      'Nova publicação',
      'Post',
      'Reel',
      'Story',
      'Carrossel',
      'Atribuir venda',
      'ROAS',
    ]) {
      expect(screen, contains(marker));
    }

    expect(service, contains('listarPublicacoesMarketing'));
    expect(service, contains('salvarPublicacaoMarketing'));
    expect(service, contains('registrarAtribuicaoMarketing'));
    expect(service, contains('carregarDesempenhoCampanhas'));
    expect(service, contains('GrowthMarketingCampanhaDesempenho'));
    expect(service, contains('imperium_marketing_publicacoes'));
    expect(service, contains('imperium_marketing_atribuicoes'));

    expect(web, contains("titulo: 'Marketing'"));
    expect(web, contains('MarketingPage'));
    expect(mobile, contains('MarketingPage'));
  });

  test('Pos venda calcula retorno e reativacao usando OS finalizada', () {
    final service = File(
      'lib/services/comercial_growth_cloud_service.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pos_venda_page.dart').readAsStringSync();

    expect(service, contains("'Hora do retorno'"));
    expect(service, contains("'Reativação'"));
    expect(service, contains("'Agendado'"));
    expect(service, contains('diasReativacao'));
    expect(service, contains('diasRetorno'));
    expect(service, contains('registrarInteracaoPosVenda'));
    expect(screen, contains('Regras do pós-venda'));
    expect(screen, contains('Próximo contato'));
    expect(screen, contains('WhatsApp'));
  });
}
