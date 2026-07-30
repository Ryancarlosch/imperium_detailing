import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  WhatsAppService._();

  static String _somenteNumeros(
      String telefone,
      ) {
    return telefone.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
  }

  static String _normalizarTelefone(
      String telefone,
      ) {
    var numero = _somenteNumeros(telefone);

    if (numero.startsWith('00')) {
      numero = numero.substring(2);
    }

    if (numero.isEmpty) {
      throw Exception(
        'Telefone não informado.',
      );
    }

    if (!numero.startsWith('55')) {
      numero = '55$numero';
    }

    return numero;
  }

  static Future<void> enviarMensagem({
    required String telefone,
    required String mensagem,
  }) async {
    final numero = _normalizarTelefone(
      telefone,
    );

    final texto = mensagem.trim();

    if (texto.isEmpty) {
      throw Exception(
        'A mensagem não pode estar vazia.',
      );
    }

    final uri = Uri.parse(
      'https://wa.me/$numero'
          '?text=${Uri.encodeComponent(texto)}',
    );

    final abriu = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!abriu) {
      throw Exception(
        'Não foi possível abrir o WhatsApp.',
      );
    }
  }

  static Future<void> confirmarAgendamento({
    required String telefone,
    required String cliente,
    required String data,
    required String horario,
    required String veiculo,
    required String servico,
  }) async {
    final mensagem = '''
Olá, $cliente! 👋

Gostaríamos de confirmar seu agendamento:

📅 Data: $data
⏰ Horário: $horario
🚗 Veículo: $veiculo
🧽 Serviço: $servico

Por favor, confirme o recebimento desta mensagem.

*Imperium Detailing*
''';

    await enviarMensagem(
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
  }) async {
    final mensagem = '''
Olá, $cliente! 👋

Passando para lembrar do seu agendamento:

📅 Data: $data
⏰ Horário: $horario
🚗 Veículo: $veiculo

Aguardamos você!

*Imperium Detailing*
''';

    await enviarMensagem(
      telefone: telefone,
      mensagem: mensagem,
    );
  }
}
