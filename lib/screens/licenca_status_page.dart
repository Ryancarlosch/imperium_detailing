import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/licenca_empresa_cloud_service.dart';
import '../services/licenca_service.dart';

class LicencaStatusPage extends StatefulWidget {
  const LicencaStatusPage({super.key, this.empresaId});

  final String? empresaId;

  @override
  State<LicencaStatusPage> createState() => _LicencaStatusPageState();
}

class _LicencaStatusPageState extends State<LicencaStatusPage> {
  final LicencaService _service = const LicencaService();
  final LicencaEmpresaCloudService _empresaService =
      const LicencaEmpresaCloudService();
  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String? _erro;
  LicencaStatus? _status;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final empresaId = widget.empresaId?.trim() ?? '';
      final status = empresaId.isEmpty
          ? await _service.consultar()
          : await _empresaService.consultar(empresaId);

      if (!mounted) return;

      setState(() {
        _status = status;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _status = null;
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'PostgrestException: ',
      'AuthException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Não foi possível consultar seu plano.' : texto;
  }

  String _tituloStatus(LicencaStatus status) {
    switch (status.statusEfetivo) {
      case 'vitalicia':
        return 'Plano vitalício';
      case 'cortesia':
        return 'Plano interno';
      case 'teste':
        return 'Teste grátis';
      case 'ativa':
        return 'Plano ativo';
      case 'tolerancia':
        return 'Pagamento em tolerância';
      case 'suspensa':
        return 'Plano suspenso';
      case 'cancelada':
        return 'Plano cancelado';
      case 'vencida':
        return 'Plano vencido';
      default:
        return 'Plano não cadastrado';
    }
  }

  IconData _iconeStatus(LicencaStatus status) {
    if (status.acessoLiberado) {
      return Icons.verified_user_outlined;
    }

    return Icons.lock_outline_rounded;
  }

  Color _corStatus(BuildContext context, LicencaStatus status) {
    if (status.statusEfetivo == 'tolerancia') {
      return Colors.orange;
    }

    if (status.acessoLiberado) {
      return Colors.green;
    }

    return Theme.of(context).colorScheme.error;
  }

  String _textoPlano(LicencaStatus status) {
    if (status.statusEfetivo == 'teste') {
      final dias = status.diasRestantes;
      if (dias != null && dias >= 0) {
        return 'Você está nos 30 dias grátis. Restam $dias dia(s). '
            'Você pode assinar antes do fim do teste para continuar sem interrupção.';
      }
      return 'Você está usando o período grátis do Imperium. '
          'Pode assinar antes do vencimento para continuar sem interrupção.';
    }

    if (!status.acessoLiberado) {
      return 'O acesso ao sistema está bloqueado, mas esta área de Plano '
          'continua disponível para você renovar e liberar novamente a empresa.';
    }

    return 'Acompanhe aqui o seu plano, vencimento e futuras cobranças do Imperium.';
  }

  String _textoBotaoPagamento(LicencaStatus status) {
    if (status.statusEfetivo == 'teste') return 'Assinar antes do vencimento';
    if (!status.acessoLiberado) return 'Renovar e liberar acesso';
    return 'Gerenciar pagamento';
  }

  Future<void> _abrirPagamento() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pagamento do plano'),
          content: const Text(
            'A área de Plano já está preparada para receber o checkout. '
            'A integração com a InfinitePay será conectada na próxima etapa. '
            'Nenhuma cobrança foi realizada agora.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plano do Imperium'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 46),
                    const SizedBox(height: 14),
                    Text(_erro!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _carregar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : status == null
          ? const Center(child: Text('Plano não encontrado.'))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Icon(
                            _iconeStatus(status),
                            size: 48,
                            color: _corStatus(context, status),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _tituloStatus(status),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            status.acessoLiberado
                                ? 'Acesso liberado'
                                : 'Acesso ao sistema bloqueado',
                            style: TextStyle(
                              color: _corStatus(context, status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _textoPlano(status),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _linha('Empresa', status.empresaNome),
                          _linha('Plano', status.plano),
                          _linha('Papel', status.papel),
                          _linha(
                            'Data servidor',
                            status.hoje == null
                                ? '—'
                                : _data.format(status.hoje!),
                          ),
                          _linha(
                            'Válido até',
                            status.validoAte == null
                                ? (status.statusEfetivo == 'cortesia' ||
                                          status.statusEfetivo == 'vitalicia')
                                      ? 'Sem vencimento'
                                      : '—'
                                : _data.format(status.validoAte!),
                          ),
                          _linha(
                            'Dias restantes',
                            status.diasRestantes == null
                                ? '—'
                                : '${status.diasRestantes}',
                          ),
                          if (status.valorMensal != null)
                            _linha(
                              'Mensalidade',
                              _moeda.format(status.valorMensal),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (status.motivo.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded),
                            const SizedBox(width: 10),
                            Expanded(child: Text(status.motivo)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _abrirPagamento,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(_textoBotaoPagamento(status)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'O checkout será conectado à InfinitePay na próxima etapa. '
                    'Até lá, este botão não realiza nenhuma cobrança.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
