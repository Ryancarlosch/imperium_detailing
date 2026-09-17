import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_gestao_service.dart';
import '../widgets/web_financeiro_pagamentos_card.dart';

class WebFinanceiroLancamentosPage extends StatefulWidget {
  const WebFinanceiroLancamentosPage({super.key});

  @override
  State<WebFinanceiroLancamentosPage> createState() =>
      _WebFinanceiroLancamentosPageState();
}

class _WebFinanceiroLancamentosPageState
    extends State<WebFinanceiroLancamentosPage> {
  final _service = WebCloudGestaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  late Future<_FinanceiroDados> _future;

  @override
  void initState() {
    super.initState();
    _future = _buscarDados();
  }

  Future<_FinanceiroDados> _buscarDados() async {
    final resultados = await Future.wait<dynamic>([
      _service.resumoFinanceiro(),
      _service.listarContasFinanceiras(),
      _service.listarPlanoContasFinanceiro(),
      _service.listarMovimentosFinanceiros(),
    ]);

    return _FinanceiroDados(
      resumo: resultados[0] as Map<String, Object?>,
      contas: (resultados[1] as List<Map<String, dynamic>>)
          .where((item) => item['ativo'] != false)
          .toList(),
      planos: (resultados[2] as List<Map<String, dynamic>>)
          .where((item) => item['ativo'] != false)
          .toList(),
      movimentos: resultados[3] as List<Map<String, dynamic>>,
    );
  }

  void _recarregar() {
    setState(() => _future = _buscarDados());
  }

  Future<void> _abrirNovoLancamento(_FinanceiroDados dados) async {
    final descricao = TextEditingController();
    final valor = TextEditingController();
    final formaPagamento = TextEditingController(text: 'Pix');
    final numeroDocumento = TextEditingController();
    final observacoes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var tipo = 'Saída';
    var status = 'Realizado';
    var contaId = dados.contas.isEmpty
        ? ''
        : dados.contas.first['id'].toString();
    var planoId = '';
    var competencia = DateTime.now();
    DateTime? vencimento;
    var salvando = false;
    String? erro;

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: !salvando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> escolherCompetencia() async {
              final selecionada = await showDatePicker(
                context: context,
                initialDate: competencia,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('pt', 'BR'),
              );
              if (selecionada != null) {
                setModalState(() => competencia = selecionada);
              }
            }

            Future<void> escolherVencimento() async {
              final selecionada = await showDatePicker(
                context: context,
                initialDate: vencimento ?? competencia,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('pt', 'BR'),
              );
              if (selecionada != null) {
                setModalState(() => vencimento = selecionada);
              }
            }

            Future<void> salvar() async {
              if (salvando || !(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final valorNumero = _double(valor.text);
              if (status == 'Realizado' && contaId.isEmpty) {
                setModalState(() {
                  erro =
                      'Cadastre ou selecione uma conta/caixa para receber o lançamento.';
                });
                return;
              }

              setModalState(() {
                salvando = true;
                erro = null;
              });

              try {
                await _service.criarMovimentoFinanceiro(
                  tipo: tipo,
                  descricao: descricao.text,
                  valor: valorNumero,
                  status: status,
                  competencia: competencia,
                  vencimento: status == 'Previsto'
                      ? vencimento ?? competencia
                      : null,
                  contaId: status == 'Realizado' ? contaId : null,
                  planoContaId: planoId.isEmpty ? null : planoId,
                  formaPagamento: formaPagamento.text,
                  numeroDocumento: numeroDocumento.text,
                  observacoes: observacoes.text,
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  salvando = false;
                  erro = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Text('Novo lançamento financeiro'),
              content: SizedBox(
                width: 640,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'O lançamento é salvo diretamente na nuvem e entra no mesmo fluxo de sincronização do aplicativo.',
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                initialValue: tipo,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Entrada',
                                    child: Text('Entrada'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Saída',
                                    child: Text('Saída'),
                                  ),
                                ],
                                onChanged: salvando
                                    ? null
                                    : (valor) {
                                        if (valor != null) {
                                          setModalState(() => tipo = valor);
                                        }
                                      },
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                initialValue: status,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Realizado',
                                    child: Text('Realizado'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Previsto',
                                    child: Text('Previsto'),
                                  ),
                                ],
                                onChanged: salvando
                                    ? null
                                    : (valor) {
                                        if (valor != null) {
                                          setModalState(() {
                                            status = valor;
                                            if (status == 'Previsto') {
                                              vencimento ??= competencia;
                                            }
                                          });
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descricao,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Descrição *',
                          ),
                          validator: (texto) {
                            if ((texto ?? '').trim().length < 3) {
                              return 'Informe uma descrição com pelo menos 3 caracteres.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: valor,
                          enabled: !salvando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor *',
                            prefixText: 'R\$ ',
                          ),
                          validator: (texto) {
                            if (_double(texto) <= 0) {
                              return 'Informe um valor maior que zero.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: planoId,
                          decoration: const InputDecoration(
                            labelText: 'Categoria financeira',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Categoria padrão automática'),
                            ),
                            ...dados.planos.map(
                              (plano) => DropdownMenuItem<String>(
                                value: plano['id'].toString(),
                                child: Text(
                                  '${plano['codigo'] ?? ''} · ${plano['nome'] ?? 'Categoria'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: salvando
                              ? null
                              : (valor) {
                                  setModalState(() => planoId = valor ?? '');
                                },
                        ),
                        if (status == 'Realizado') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: contaId.isEmpty ? null : contaId,
                            decoration: const InputDecoration(
                              labelText: 'Conta / caixa *',
                            ),
                            items: dados.contas
                                .map(
                                  (conta) => DropdownMenuItem<String>(
                                    value: conta['id'].toString(),
                                    child: Text(
                                      (conta['nome'] ?? 'Conta').toString(),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: salvando
                                ? null
                                : (valor) {
                                    setModalState(() => contaId = valor ?? '');
                                  },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: formaPagamento,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Forma de pagamento',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: salvando ? null : escolherCompetencia,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                'Competência: ${_data.format(competencia)}',
                              ),
                            ),
                            if (status == 'Previsto')
                              OutlinedButton.icon(
                                onPressed: salvando ? null : escolherVencimento,
                                icon: const Icon(Icons.schedule_outlined),
                                label: Text(
                                  'Vencimento: ${_data.format(vencimento ?? competencia)}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: numeroDocumento,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Número do documento',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: observacoes,
                          enabled: !salvando,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                          ),
                        ),
                        if (erro != null) ...[
                          const SizedBox(height: 12),
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
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: salvando ? null : salvar,
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar lançamento'),
                ),
              ],
            );
          },
        );
      },
    );

    descricao.dispose();
    valor.dispose();
    formaPagamento.dispose();
    numeroDocumento.dispose();
    observacoes.dispose();

    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lançamento salvo na nuvem e disponível para sincronização.',
          ),
        ),
      );
      _recarregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FinanceiroDados>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final dados = snapshot.data!;
        final saldos =
            dados.resumo['saldos'] as Map<String, double>? ?? const {};

        return RefreshIndicator(
          onRefresh: () async {
            _recarregar();
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fluxo de caixa',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Lançamentos Web e aplicativo compartilham o mesmo financeiro Cloud.',
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => _abrirNovoLancamento(dados),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novo lançamento'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ResumoFinanceiroCard(
                    titulo: 'Saldo total',
                    valor: _moeda.format(_double(dados.resumo['saldo_total'])),
                  ),
                  _ResumoFinanceiroCard(
                    titulo: 'Entradas do mês',
                    valor: _moeda.format(_double(dados.resumo['entradas_mes'])),
                  ),
                  _ResumoFinanceiroCard(
                    titulo: 'Saídas do mês',
                    valor: _moeda.format(_double(dados.resumo['saidas_mes'])),
                  ),
                  _ResumoFinanceiroCard(
                    titulo: 'Resultado de caixa',
                    valor: _moeda.format(
                      _double(dados.resumo['resultado_caixa_mes']),
                    ),
                  ),
                  _ResumoFinanceiroCard(
                    titulo: 'A receber',
                    valor: _moeda.format(_double(dados.resumo['a_receber'])),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Contas',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...dados.contas.map(
                (conta) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text((conta['nome'] ?? 'Conta').toString()),
                    subtitle: Text(
                      [
                        (conta['tipo'] ?? '').toString(),
                        (conta['instituicao'] ?? '').toString(),
                      ].where((e) => e.trim().isNotEmpty).join(' · '),
                    ),
                    trailing: Text(
                      _moeda.format(
                        saldos[conta['id'].toString()] ??
                            _double(conta['saldo_inicial']),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              WebFinanceiroPagamentosCard(onChanged: _recarregar),
              const SizedBox(height: 20),
              const Text(
                'Movimentos recentes',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (dados.movimentos.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhum movimento financeiro registrado.'),
                  ),
                )
              else
                ...dados.movimentos.take(50).map((movimento) {
                  final entrada = _entrada(movimento['tipo']);
                  final status = (movimento['status'] ?? '').toString();
                  final contaNome = _nomeConta(
                    dados.contas,
                    movimento['conta_id']?.toString(),
                  );

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        entrada
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                      ),
                      title: Text(
                        (movimento['descricao'] ?? 'Movimento').toString(),
                      ),
                      subtitle: Text(
                        [
                          _formatarData(movimento['data']?.toString()),
                          status,
                          contaNome,
                          (movimento['forma_pagamento'] ?? '').toString(),
                        ].where((e) => e.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        '${entrada ? '+' : '-'} ${_moeda.format(_double(movimento['valor']))}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  String _formatarData(String? valor) {
    final data = DateTime.tryParse(valor ?? '');
    return data == null ? (valor ?? '') : _data.format(data);
  }
}

class _FinanceiroDados {
  const _FinanceiroDados({
    required this.resumo,
    required this.contas,
    required this.planos,
    required this.movimentos,
  });

  final Map<String, Object?> resumo;
  final List<Map<String, dynamic>> contas;
  final List<Map<String, dynamic>> planos;
  final List<Map<String, dynamic>> movimentos;
}

class _ResumoFinanceiroCard extends StatelessWidget {
  const _ResumoFinanceiroCard({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo),
              const SizedBox(height: 6),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _nomeConta(List<Map<String, dynamic>> contas, String? contaId) {
  if (contaId == null || contaId.isEmpty) return '';
  for (final conta in contas) {
    if (conta['id']?.toString() == contaId) {
      return (conta['nome'] ?? '').toString();
    }
  }
  return '';
}

bool _entrada(dynamic tipo) {
  final texto = tipo?.toString().toLowerCase() ?? '';
  return texto.contains('entrada') || texto.contains('receita');
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(
        valor?.toString().trim().replaceAll('.', '').replaceAll(',', '.') ?? '',
      ) ??
      0;
}
