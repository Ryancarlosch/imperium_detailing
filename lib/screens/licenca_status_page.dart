import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/assinatura_checkout_service.dart';
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
  final AssinaturaCheckoutService _checkoutService =
      const AssinaturaCheckoutService();
  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  bool _preparandoCheckout = false;
  String? _erro;
  LicencaStatus? _status;
  List<AssinaturaPlano> _planos = const <AssinaturaPlano>[];

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

      var planos = _planos;
      try {
        planos = await _checkoutService.listarPlanos();
      } catch (_) {
        // O status da licença continua útil mesmo se os planos falharem.
      }

      if (!mounted) return;

      setState(() {
        _status = status;
        _planos = planos;
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

    return 'Acompanhe aqui o seu plano, vencimento e pagamentos do Imperium.';
  }

  String _textoBotaoPagamento(LicencaStatus status) {
    if (status.statusEfetivo == 'teste') return 'Assinar antes do vencimento';
    if (!status.acessoLiberado) return 'Renovar e liberar acesso';
    return 'Renovar ou estender plano';
  }

  String _periodoPlano(AssinaturaPlano plano) {
    if (plano.meses == 1) return '1 mês';
    if (plano.meses == 12) return '12 meses';
    return '${plano.meses} meses';
  }

  Future<void> _abrirPagamento() async {
    if (_preparandoCheckout || !mounted) return;

    var planos = _planos;
    if (planos.isEmpty) {
      try {
        planos = await _checkoutService.listarPlanos();
        if (!mounted) return;
        setState(() => _planos = planos);
      } catch (erro) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_textoErro(erro))),
        );
        return;
      }
    }

    if (!mounted) return;

    final selecionado = await showDialog<AssinaturaPlano>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Escolha o plano'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final plano in planos)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        plano.nome,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_periodoPlano(plano)),
                      trailing: Text(
                        _moeda.format(plano.valor),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => Navigator.of(dialogContext).pop(plano),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (selecionado != null && mounted) {
      await _prepararCheckout(selecionado);
    }
  }

  Future<void> _prepararCheckout(AssinaturaPlano plano) async {
    final status = _status;
    if (status == null || _preparandoCheckout) return;

    setState(() => _preparandoCheckout = true);

    try {
      final resultado = await _checkoutService.criarCheckout(
        empresaId: status.empresaId,
        planoCodigo: plano.codigo,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Checkout pronto'),
            content: Text(
              '${plano.nome} por ${_moeda.format(plano.valor)}. '
              'O pagamento será finalizado no ambiente seguro da InfinitePay. '
              'Depois da aprovação, a licença é renovada automaticamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Agora não'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final abriu = await launchUrl(
                    Uri.parse(resultado.url),
                    mode: LaunchMode.platformDefault,
                  );
                  if (!abriu && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Não foi possível abrir o checkout.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Ir para pagamento'),
              ),
            ],
          );
        },
      );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_textoErro(erro))),
      );
    } finally {
      if (mounted) {
        setState(() => _preparandoCheckout = false);
      }
    }
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
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

  Widget _cardPlanos() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Opções de assinatura',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pix ou cartão pela InfinitePay. Toque em uma opção para continuar.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 10),
            for (final plano in _planos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(plano.nome),
                subtitle: Text(_periodoPlano(plano)),
                trailing: Text(
                  _moeda.format(plano.valor),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: _preparandoCheckout
                    ? null
                    : () => _prepararCheckout(plano),
              ),
          ],
        ),
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
            onPressed: _carregando || _preparandoCheckout ? null : _carregar,
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
                              'Valor mensal equivalente',
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
                  if (status.statusEfetivo != 'vitalicia' &&
                      status.statusEfetivo != 'cortesia') ...[
                    if (_planos.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _cardPlanos(),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _preparandoCheckout ? null : _abrirPagamento,
                        icon: _preparandoCheckout
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.payments_outlined),
                        label: Text(
                          _preparandoCheckout
                              ? 'Preparando checkout...'
                              : _textoBotaoPagamento(status),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'A InfinitePay processa o pagamento. O Imperium não recebe '
                      'nem armazena os dados do seu cartão. Após a aprovação, a '
                      'licença é atualizada automaticamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
