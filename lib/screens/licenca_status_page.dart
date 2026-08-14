import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/licenca_service.dart';

class LicencaStatusPage extends StatefulWidget {
  const LicencaStatusPage({super.key});

  @override
  State<LicencaStatusPage> createState() => _LicencaStatusPageState();
}

class _LicencaStatusPageState extends State<LicencaStatusPage> {
  final LicencaService _service = const LicencaService();
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
      final status = await _service.consultar();

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
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto;
  }

  String _tituloStatus(LicencaStatus status) {
    switch (status.statusEfetivo) {
      case 'vitalicia':
        return 'Licença vitalícia';
      case 'cortesia':
        return 'Licença interna';
      case 'teste':
        return 'Período de teste';
      case 'ativa':
        return 'Mensalidade ativa';
      case 'tolerancia':
        return 'Período de tolerância';
      case 'suspensa':
        return 'Licença suspensa';
      case 'cancelada':
        return 'Licença cancelada';
      case 'vencida':
        return 'Mensalidade vencida';
      default:
        return 'Licença não cadastrada';
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
        title: const Text('Licença do Imperium'),
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
          ? const Center(child: Text('Licença não encontrada.'))
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
                                : 'Acesso bloqueado',
                            style: TextStyle(
                              color: _corStatus(context, status),
                              fontWeight: FontWeight.w600,
                            ),
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
                  const SizedBox(height: 16),
                  const Text(
                    'Nesta primeira etapa a tela apenas consulta a '
                    'licença no servidor. O bloqueio automático do '
                    'aplicativo será ativado na próxima etapa, depois '
                    'que esta consulta estiver validada no APK.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
