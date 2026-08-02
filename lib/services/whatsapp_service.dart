import 'package:url_launcher/url_launcher.dart';

import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';

class WhatsAppException implements Exception {
  const WhatsAppException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class WhatsAppService {
  WhatsAppService._();

  static final ConfiguracaoRepository _configRepository =
      ConfiguracaoRepository();

  static const String _assinaturaPadrao = 'Imperium Detailing';

  static String _somenteNumeros(String telefone) {
    return telefone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String _primeiroNome(String nome) {
    final nomeLimpo = nome.trim();

    if (nomeLimpo.isEmpty) {
      return 'cliente';
    }

    return nomeLimpo.split(RegExp(r'\s+')).first;
  }

  static String _assinaturaEmpresa(Configuracao? config) {
    final fantasia = config?.nomeFantasia.trim() ?? '';
    if (fantasia.isNotEmpty) {
      return fantasia;
    }

    final razao = config?.razaoSocial.trim() ?? '';
    if (razao.isNotEmpty) {
      return razao;
    }

    return _assinaturaPadrao;
  }

  static String _formatarVeiculo({
    required String veiculo,
    required String placa,
  }) {
    final veiculoLimpo = veiculo.trim();
    final placaLimpa = placa.trim().toUpperCase();

    if (veiculoLimpo.isEmpty && placaLimpa.isEmpty) {
      return 'Não informado';
    }

    if (placaLimpa.isEmpty) {
      return veiculoLimpo;
    }

    if (veiculoLimpo.isEmpty) {
      return placaLimpa;
    }

    return '$veiculoLimpo • $placaLimpa';
  }

  static Future<Configuracao?> _carregarConfiguracao() async {
    try {
      return await _configRepository.obterConfiguracao();
    } catch (_) {
      return null;
    }
  }

  static String _normalizarTelefone(String telefone) {
    var numero = _somenteNumeros(telefone);

    while (numero.startsWith('0')) {
      numero = numero.substring(1);
    }

    if (numero.startsWith('00')) {
      numero = numero.substring(2);
    }

    if (numero.isEmpty) {
      throw const WhatsAppException(
        'Informe um telefone para enviar a mensagem no WhatsApp.',
      );
    }

    if (numero.startsWith('55')) {
      if (numero.length < 12 || numero.length > 13) {
        throw WhatsAppException(
          'Telefone inválido: $telefone. Verifique DDD e número.',
        );
      }

      return numero;
    }

    if (numero.length == 10 || numero.length == 11) {
      return '55$numero';
    }

    if (numero.length == 8 || numero.length == 9) {
      throw WhatsAppException(
        'Telefone sem DDD: $telefone. Inclua o DDD para continuar.',
      );
    }

    throw WhatsAppException(
      'Telefone inválido: $telefone. Corrija o número e tente novamente.',
    );
  }

  static Future<void> enviarMensagem({
    required String telefone,
    required String mensagem,
  }) async {
    final numero = _normalizarTelefone(telefone);

    final texto = mensagem.trim();

    if (texto.isEmpty) {
      throw const WhatsAppException(
        'A mensagem está vazia. Escreva um texto antes de enviar.',
      );
    }

    final uri = Uri.https('wa.me', '/$numero', {'text': texto});

    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!abriu) {
      throw const WhatsAppException(
        'Não foi possível abrir o WhatsApp neste dispositivo.',
      );
    }
  }

  static Future<void> enviarMensagemPersonalizada({
    required String telefone,
    required String mensagem,
  }) async {
    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> confirmarAgendamento({
    required String telefone,
    required String cliente,
    required String data,
    required String horario,
    required String veiculo,
    String placa = '',
    required String servico,
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final primeiroNome = _primeiroNome(cliente);

    final mensagemConfig = config?.mensagemConfirmacao.trim() ?? '';

    final textoPersonalizado = mensagemPersonalizada.trim();

    final assinatura = _assinaturaEmpresa(config);

    final veiculoComPlaca = _formatarVeiculo(veiculo: veiculo, placa: placa);

    final mensagem =
        '''
Olá, $primeiroNome! 👋

Gostaríamos de confirmar seu agendamento:

📅 Data: $data
⏰ Horário: $horario
🚗 Veículo: $veiculoComPlaca
🧽 Serviço: $servico

${mensagemConfig.isEmpty ? 'Por favor, confirme o recebimento desta mensagem.' : mensagemConfig}

${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}

*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarLembreteAgendamento({
    required String telefone,
    required String cliente,
    required String data,
    required String horario,
    required String veiculo,
    String placa = '',
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final primeiroNome = _primeiroNome(cliente);

    final textoPersonalizado = mensagemPersonalizada.trim();

    final assinatura = _assinaturaEmpresa(config);

    final veiculoComPlaca = _formatarVeiculo(veiculo: veiculo, placa: placa);

    final mensagem =
        '''
Olá, $primeiroNome! 👋

Passando para lembrar do seu agendamento:

📅 Data: $data
⏰ Horário: $horario
🚗 Veículo: $veiculoComPlaca

${textoPersonalizado.isEmpty ? 'Aguardamos você!' : textoPersonalizado}

*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarOrcamento({
    required String telefone,
    required String cliente,
    required String numeroOrcamento,
    required String valorTotal,
    String observacoes = '',
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final mensagemConfig = config?.mensagemOrcamento.trim() ?? '';

    final observacoesLimpa = observacoes.trim();
    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! 👋

Segue seu orçamento:

📄 Número: $numeroOrcamento
💰 Valor total: $valorTotal
${observacoesLimpa.isEmpty ? '' : '📝 Observações: $observacoesLimpa\n'}
${mensagemConfig.isEmpty ? '' : '$mensagemConfig\n'}
${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}
*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarAprovacaoOrcamento({
    required String telefone,
    required String cliente,
    required String numeroOrcamento,
    required String valorTotal,
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! ✅

Seu orçamento foi aprovado para continuidade do atendimento.

📄 Número: $numeroOrcamento
💰 Valor: $valorTotal

${textoPersonalizado.isEmpty ? 'Seguimos à disposição para qualquer dúvida.' : textoPersonalizado}

*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarAtualizacaoOrdemServico({
    required String telefone,
    required String cliente,
    required String numeroOrdem,
    required String status,
    required String valor,
    String previsao = '',
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final previsaoLimpa = previsao.trim();
    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! 👋

Atualização da sua Ordem de Serviço:

📋 Número: $numeroOrdem
📌 Status: $status
💰 Valor: $valor
${previsaoLimpa.isEmpty ? '' : '🗓️ Previsão: $previsaoLimpa\n'}
${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}
*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarVeiculoPronto({
    required String telefone,
    required String cliente,
    required String numeroOrdem,
    required String valor,
    String previsao = '',
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final mensagemConfig = config?.mensagemEntrega.trim() ?? '';

    final previsaoLimpa = previsao.trim();
    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! ✅

Seu veículo está pronto para retirada.

📋 Ordem de Serviço: $numeroOrdem
💰 Valor: $valor
${previsaoLimpa.isEmpty ? '' : '🗓️ Previsão/entrega: $previsaoLimpa\n'}
${mensagemConfig.isEmpty ? '' : '$mensagemConfig\n'}
${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}
*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarCobrancaOrdemServico({
    required String telefone,
    required String cliente,
    required String numeroOrdem,
    required String valor,
    String formaPagamento = '',
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final mensagemConfig = config?.mensagemCobranca.trim() ?? '';

    final formaPagamentoLimpa = formaPagamento.trim();
    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! 👋

Segue o valor referente ao serviço realizado:

📋 Ordem de Serviço: $numeroOrdem
💰 Valor: *$valor*
${formaPagamentoLimpa.isEmpty ? '' : '💳 Forma de pagamento: $formaPagamentoLimpa\n'}
${mensagemConfig.isEmpty ? '' : '$mensagemConfig\n'}
${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}
*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }

  static Future<void> enviarAgradecimentoPosServico({
    required String telefone,
    required String cliente,
    String mensagemPersonalizada = '',
  }) async {
    final config = await _carregarConfiguracao();

    final assinatura = _assinaturaEmpresa(config);

    final mensagemConfig = config?.mensagemAgradecimento.trim() ?? '';
    final textoPersonalizado = mensagemPersonalizada.trim();

    final mensagem =
        '''
Olá, ${_primeiroNome(cliente)}! 🙌

Muito obrigado por confiar no nosso serviço.

${mensagemConfig.isEmpty ? '' : '$mensagemConfig\n'}
${textoPersonalizado.isEmpty ? '' : '$textoPersonalizado\n'}
*$assinatura*
''';

    await enviarMensagem(telefone: telefone, mensagem: mensagem);
  }
}
