import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  WhatsAppService._();

  static String limparTelefone(String telefone) {
    return telefone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String prepararTelefoneBrasileiro(String telefone) {
    var numero = limparTelefone(telefone);

    if (numero.isEmpty) {
      throw Exception('Telefone do cliente não informado.');
    }

    if (numero.startsWith('00')) {
      numero = numero.substring(2);
    }

    if (!numero.startsWith('55')) {
      numero = '55$numero';
    }

    return numero;
  }

  static Future<void> abrirConversa({
    required String telefone,
    required String mensagem,
  }) async {
    final numero = prepararTelefoneBrasileiro(telefone);
    final texto = mensagem.trim();

    if (texto.isEmpty) {
      throw Exception('A mensagem do WhatsApp está vazia.');
    }

    final uri = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent(texto)}',
    );

    final abriu = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!abriu) {
      throw Exception(
        'Não foi possível abrir o WhatsApp. '
            'Verifique se ele está instalado no aparelho.',
      );
    }
  }

  static Future<void> enviarMensagemPersonalizada({
    required String telefone,
    required String mensagem,
  }) {
    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> confirmarAgendamento({
    required String telefone,
    required String cliente,
    required String data,
    required String horario,
    required String veiculo,
    String servico = '',
  }) {
    final servicoFormatado = servico.trim().isEmpty
        ? ''
        : '\n🧼 Serviço: ${servico.trim()}';

    final mensagem = '''
Olá, ${cliente.trim()}! 👋

Seu agendamento na *Imperium Detailing* está confirmado.

📅 Data: $data
🕘 Horário: $horario
🚗 Veículo: $veiculo$servicoFormatado

Caso precise alterar o horário, entre em contato conosco.

Agradecemos pela preferência!
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> enviarLembreteAgendamento({
    required String telefone,
    required String cliente,
    required String data,
    required String horario,
    required String veiculo,
  }) {
    final mensagem = '''
Olá, ${cliente.trim()}! 👋

Passando para lembrar do seu agendamento na *Imperium Detailing*.

📅 Data: $data
🕘 Horário: $horario
🚗 Veículo: $veiculo

Estamos aguardando você!
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> avisarServicoIniciado({
    required String telefone,
    required String cliente,
    required String veiculo,
    String numeroOrdem = '',
  }) {
    final ordemFormatada = numeroOrdem.trim().isEmpty
        ? ''
        : '\n📄 Ordem de Serviço: ${numeroOrdem.trim()}';

    final mensagem = '''
Olá, ${cliente.trim()}! 👋

O serviço do seu veículo foi iniciado na *Imperium Detailing*.

🚗 Veículo: $veiculo$ordemFormatada

Manteremos você informado sobre o andamento.
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> avisarServicoFinalizado({
    required String telefone,
    required String cliente,
    required String veiculo,
    String valor = '',
    String formaPagamento = '',
  }) {
    final valorFormatado = valor.trim().isEmpty
        ? ''
        : '\n💰 Valor: ${valor.trim()}';

    final pagamentoFormatado = formaPagamento.trim().isEmpty
        ? ''
        : '\n💳 Forma de pagamento: ${formaPagamento.trim()}';

    final mensagem = '''
Olá, ${cliente.trim()}! ✅

Temos uma ótima notícia: o serviço do seu veículo foi finalizado.

🚗 Veículo: $veiculo$valorFormatado$pagamentoFormatado

Seu veículo está pronto para retirada.

A *Imperium Detailing* agradece pela confiança!
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> enviarCobranca({
    required String telefone,
    required String cliente,
    required String descricao,
    required String valor,
    String chavePix = '',
  }) {
    final pixFormatado = chavePix.trim().isEmpty
        ? ''
        : '\n🔑 Chave Pix: ${chavePix.trim()}';

    final mensagem = '''
Olá, ${cliente.trim()}!

Segue a informação referente ao serviço realizado pela *Imperium Detailing*.

🧾 Serviço: ${descricao.trim()}
💰 Valor: ${valor.trim()}$pixFormatado

Em caso de dúvida, estamos à disposição.
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> enviarOrcamento({
    required String telefone,
    required String cliente,
    required String veiculo,
    required String valor,
    String validade = '',
  }) {
    final validadeFormatada = validade.trim().isEmpty
        ? ''
        : '\n📅 Validade do orçamento: ${validade.trim()}';

    final mensagem = '''
Olá, ${cliente.trim()}! 👋

Preparamos o orçamento solicitado para seu veículo.

🚗 Veículo: $veiculo
💰 Valor total: $valor$validadeFormatada

Qualquer dúvida sobre os serviços, estamos à disposição.

*Imperium Detailing*
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }

  static Future<void> enviarOrdemServico({
    required String telefone,
    required String cliente,
    required String numeroOrdem,
    required String veiculo,
    required String valor,
  }) {
    final mensagem = '''
Olá, ${cliente.trim()}!

Segue a informação da sua Ordem de Serviço na *Imperium Detailing*.

📄 Ordem de Serviço: ${numeroOrdem.trim()}
🚗 Veículo: $veiculo
💰 Valor: $valor

Qualquer dúvida, entre em contato conosco.
''';

    return abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
  }
}