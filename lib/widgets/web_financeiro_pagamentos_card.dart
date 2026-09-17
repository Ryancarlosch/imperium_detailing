import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_gestao_service.dart';
import '../services/web_financeiro_estorno_service.dart';

class WebFinanceiroPagamentosCard extends StatefulWidget {
  const WebFinanceiroPagamentosCard({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<WebFinanceiroPagamentosCard> createState() =>
      _WebFinanceiroPagamentosCardState();
}

class _WebFinanceiroPagamentosCardState
    extends State<WebFinanceiroPagamentosCard> {
  final _gestao = WebCloudGestaoService.instance;
  final _estorno = WebFinanceiroEstornoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  bool _carregando = true;
  bool _processando = false;
  String? _erro;
  List<Map<String, dynamic>> _pagamentos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final pagamentos = await _gestao.listarPagamentosOs();
      pagamentos.sort((a, b) {
        final aa = (a['atualizado_em'] ?? a['criado_em'] ?? '').toString();
        final bb = (b['atualizado_em'] ?? b['criado_em'] ?? '').toString();
        return bb.compareTo(aa);
      });

      if (!mounted) return;
      setState(() => _pagamentos = pagamentos);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirEstorno(Map<String, dynamic> pagamento) async {
    if (_processando || '${pagamento['status']}' != 'Pago') return;

    final motivo = TextEditingController();
    var modo = WebFinanceiroEstornoModo.correcao;
    var salvando = false;
    String? erro;

    final confirmar = await showDialog<_EstornoDraft>(
      context: context,
      barrierDismissible: !salvando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> concluir() async {
              final motivoLimpo = motivo.text.trim();
              if (motivoLimpo.length < 5 || salvando) {
                setModalState(() {
                  erro = 'Informe um motivo com pelo menos 5 caracteres.';
                });
                return;
              }

              setModalState(() {
                salvando = true;
                erro = null;
              });

              Navigator.of(dialogContext).pop(
                _EstornoDraft(modo: modo, motivo: motivoLimpo),
              );
            }

            return AlertDialog(
              title: const Text('Corrigir ou devolver pagamento'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pagamento de ${_moeda.format(_double(pagamento['valor']))} '
                      '· ${(pagamento['forma_pagamento'] ?? 'Forma não informada')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    RadioGroup<WebFinanceiroEstornoModo>(
                      groupValue: modo,
                      onChanged: salvando
                          ? null
                          : (valor) {
                              if (valor != null) {
                                setModalState(() => modo = valor);
                              }
                            },
                      child: const Column(
                        children: [
                          RadioListTile<WebFinanceiroEstornoModo>(
                            value: WebFinanceiroEstornoModo.correcao,
                            title: Text('Correção de lançamento'),
                            subtitle: Text(
                              'Use quando o recebimento foi lançado por engano. '
                              'O dinheiro não aconteceu: entrada e taxa originais '
                              'são canceladas para auditoria, sem criar saída.',
                            ),
                          ),
                          RadioListTile<WebFinanceiroEstornoModo>(
                            value: WebFinanceiroEstornoModo.devolucao,
                            title: Text('Devolução ao cliente'),
                            subtitle: Text(
                              'Use quando o dinheiro entrou de verdade e será '
                              'devolvido. A entrada histórica é preservada e uma '
                              'saída real de devolução é criada.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: motivo,
                      enabled: !salvando,
                      autofocus: true,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Motivo *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (erro != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        erro!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Voltar'),
                ),
                FilledButton.icon(
                  onPressed: salvando ? null : concluir,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Confirmar operação'),
                ),
              ],
            );
          },
        );
      },
    );

    motivo.dispose();
    if (confirmar == null || !mounted) return;

    setState(() => _processando = true);
    try {
      final resultado = await _estorno.estornar(
        pagamento: pagamento,
        modo: confirmar.modo,
        motivo: confirmar.motivo,
      );

      if (!mounted) return;
      final modoTexto = confirmar.modo == WebFinanceiroEstornoModo.correcao
          ? 'Correção registrada'
          : 'Devolução registrada';
      final statusOs = (resultado['status_pagamento'] ?? '').toString().trim();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              statusOs.isEmpty
                  ? '$modoTexto com segurança.'
                  : '$modoTexto com segurança. OS agora: $statusOs.',
            ),
          ),
        );

      widget.onChanged?.call();
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red.shade700,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pagamentos de OS',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Corrija recebimentos lançados por engano ou registre '
                        'uma devolução real ao cliente com auditoria.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar pagamentos',
                  onPressed: _carregando || _processando ? null : _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_erro != null)
              Text(
                _erro!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_pagamentos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhum pagamento de OS registrado.'),
              )
            else
              ..._pagamentos.take(20).map((pagamento) {
                final status = (pagamento['status'] ?? '').toString();
                final pago = status == 'Pago';
                final parcela = pagamento['parcela_numero'];
                final totalParcelas = pagamento['total_parcelas'];
                final referenciaParcela = parcela == null
                    ? ''
                    : 'Parcela $parcela${totalParcelas == null ? '' : '/$totalParcelas'}';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    pago ? Icons.payments_outlined : Icons.history_outlined,
                  ),
                  title: Text(
                    _moeda.format(_double(pagamento['valor'])),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      status,
                      (pagamento['forma_pagamento'] ?? '').toString(),
                      referenciaParcela,
                      _formatarData(
                        pagamento['data_pagamento']?.toString() ??
                            pagamento['vencimento']?.toString(),
                      ),
                    ].where((item) => item.trim().isNotEmpty).join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: pago
                        ? 'Corrigir ou devolver pagamento'
                        : 'Somente pagamentos confirmados podem ser estornados',
                    onPressed: pago && !_processando
                        ? () => _abrirEstorno(pagamento)
                        : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _formatarData(String? valor) {
    final data = DateTime.tryParse(valor ?? '');
    return data == null ? (valor ?? '') : _data.format(data);
  }
}

class _EstornoDraft {
  const _EstornoDraft({required this.modo, required this.motivo});

  final WebFinanceiroEstornoModo modo;
  final String motivo;
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
