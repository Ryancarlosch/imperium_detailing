import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../services/web_estoque_cloud_service.dart';

class WebEstoqueMovimentacoesPage extends StatefulWidget {
  const WebEstoqueMovimentacoesPage({super.key});

  @override
  State<WebEstoqueMovimentacoesPage> createState() =>
      _WebEstoqueMovimentacoesPageState();
}

class _WebEstoqueMovimentacoesPageState
    extends State<WebEstoqueMovimentacoesPage> {
  final _service = WebEstoqueCloudService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _data = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  late Future<_EstoqueDados> _future;

  @override
  void initState() {
    super.initState();
    _future = _buscarDados();
  }

  Future<_EstoqueDados> _buscarDados() async {
    final resultados = await Future.wait<dynamic>([
      _service.listarItens(),
      _service.listarMovimentacoes(),
      _service.listarAlertas(),
      _service.listarReservasAtivas(),
    ]);

    final reservas = resultados[3] as List<Map<String, dynamic>>;
    return _EstoqueDados(
      itens: resultados[0] as List<Map<String, dynamic>>,
      movimentacoes: resultados[1] as List<Map<String, dynamic>>,
      alertas: resultados[2] as List<Map<String, dynamic>>,
      reservasPorItem: WebEstoqueCloudService.reservasPorItem(reservas),
    );
  }

  void _recarregar() {
    setState(() => _future = _buscarDados());
  }

  Future<void> _abrirMovimentacao(_EstoqueDados dados) async {
    if (dados.itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre um produto antes de movimentar.'),
        ),
      );
      return;
    }

    final quantidade = TextEditingController();
    final valorPago = TextEditingController();
    final fornecedor = TextEditingController();
    final observacoes = TextEditingController();
    final motivo = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var itemId = dados.itens.first['id'].toString();
    var tipo = 'ENTRADA';
    var unidadeEntrada = _unidadesCompativeis(dados.itens.first).first;
    var salvando = false;
    String? erro;

    Map<String, dynamic> itemAtual() {
      return dados.itens.firstWhere(
        (item) => item['id'].toString() == itemId,
        orElse: () => dados.itens.first,
      );
    }

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final item = itemAtual();
            final saldo = _double(item['quantidade']);
            final reservado = dados.reservasPorItem[itemId] ?? 0;
            final disponivel = (saldo - reservado).clamp(0, double.infinity);
            final unidades = _unidadesCompativeis(item);
            if (!unidades.contains(unidadeEntrada)) {
              unidadeEntrada = unidades.first;
            }

            Future<void> salvar() async {
              if (salvando || !(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final quantidadeNumero = _double(quantidade.text);
              final valorNumero = _double(valorPago.text);

              if (tipo == 'SAIDA' && quantidadeNumero > disponivel + 0.000001) {
                setModalState(() {
                  erro =
                      'Disponível para saída: ${_numero(disponivel)} '
                      '${item['unidade'] ?? ''}. O restante está reservado para OS.';
                });
                return;
              }

              if (tipo == 'AJUSTE' && quantidadeNumero + 0.000001 < reservado) {
                setModalState(() {
                  erro =
                      'O ajuste não pode deixar o saldo abaixo de '
                      '${_numero(reservado)} reservado para Ordens de Serviço.';
                });
                return;
              }

              setModalState(() {
                salvando = true;
                erro = null;
              });

              try {
                await _service.movimentar(
                  item: item,
                  tipo: tipo,
                  quantidade: quantidadeNumero,
                  unidadeOriginal: unidadeEntrada,
                  valorTotalPago: tipo == 'ENTRADA' ? valorNumero : null,
                  fornecedor: fornecedor.text,
                  observacoes: observacoes.text,
                  motivo: motivo.text,
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  salvando = false;
                  erro = _textoErro(e);
                });
              }
            }

            return AlertDialog(
              title: const Text('Nova movimentação de estoque'),
              content: SizedBox(
                width: 660,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'A alteração é feita diretamente no estoque Cloud. '
                          'Saídas respeitam reservas e consomem os lotes por FIFO.',
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: itemId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Produto',
                          ),
                          items: dados.itens
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item['id'].toString(),
                                  child: Text(
                                    (item['nome'] ?? 'Produto').toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: salvando
                              ? null
                              : (valor) {
                                  if (valor == null) return;
                                  setModalState(() {
                                    itemId = valor;
                                    unidadeEntrada = _unidadesCompativeis(
                                      itemAtual(),
                                    ).first;
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _InfoChip(
                              rotulo: 'Saldo',
                              valor:
                                  '${_numero(saldo)} ${item['unidade'] ?? ''}',
                            ),
                            _InfoChip(
                              rotulo: 'Reservado OS',
                              valor:
                                  '${_numero(reservado)} ${item['unidade'] ?? ''}',
                            ),
                            _InfoChip(
                              rotulo: 'Disponível',
                              valor:
                                  '${_numero(disponivel)} ${item['unidade'] ?? ''}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: tipo,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de movimentação',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'ENTRADA',
                              child: Text('Entrada'),
                            ),
                            DropdownMenuItem(
                              value: 'SAIDA',
                              child: Text('Saída'),
                            ),
                            DropdownMenuItem(
                              value: 'AJUSTE',
                              child: Text('Ajustar quantidade total'),
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
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: quantidade,
                          enabled: !salvando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: tipo == 'AJUSTE'
                                ? 'Nova quantidade total *'
                                : tipo == 'ENTRADA'
                                ? 'Quantidade da embalagem *'
                                : 'Quantidade *',
                            suffixText: tipo == 'ENTRADA'
                                ? unidadeEntrada
                                : (item['unidade'] ?? '').toString(),
                          ),
                          validator: (texto) {
                            final numero = _double(texto);
                            if (tipo == 'AJUSTE') {
                              if ((texto ?? '').trim().isEmpty || numero < 0) {
                                return 'Informe uma quantidade final válida.';
                              }
                              return null;
                            }
                            if (numero <= 0) {
                              return 'Informe uma quantidade maior que zero.';
                            }
                            return null;
                          },
                        ),
                        if (tipo == 'ENTRADA') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: unidadeEntrada,
                            decoration: const InputDecoration(
                              labelText: 'Unidade da embalagem',
                            ),
                            items: unidades
                                .map(
                                  (unidade) => DropdownMenuItem<String>(
                                    value: unidade,
                                    child: Text(_rotuloUnidade(unidade)),
                                  ),
                                )
                                .toList(),
                            onChanged: salvando
                                ? null
                                : (valor) {
                                    if (valor != null) {
                                      setModalState(
                                        () => unidadeEntrada = valor,
                                      );
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: valorPago,
                            enabled: !salvando,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Valor total pago *',
                              prefixText: 'R\$ ',
                            ),
                            validator: (texto) {
                              if (tipo == 'ENTRADA' && _double(texto) <= 0) {
                                return 'Informe o valor total pago.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: fornecedor,
                            enabled: !salvando,
                            decoration: const InputDecoration(
                              labelText: 'Fornecedor',
                            ),
                          ),
                        ],
                        if (tipo == 'AJUSTE') ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: motivo,
                            enabled: !salvando,
                            decoration: const InputDecoration(
                              labelText: 'Motivo do ajuste *',
                            ),
                            validator: (texto) {
                              if (tipo == 'AJUSTE' &&
                                  (texto ?? '').trim().isEmpty) {
                                return 'Informe o motivo do ajuste.';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: observacoes,
                          enabled: !salvando,
                          minLines: 2,
                          maxLines: 4,
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
                  label: Text(salvando ? 'Salvando...' : 'Registrar'),
                ),
              ],
            );
          },
        );
      },
    );

    quantidade.dispose();
    valorPago.dispose();
    fornecedor.dispose();
    observacoes.dispose();
    motivo.dispose();

    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimentação salva e sincronizável com o aplicativo.'),
        ),
      );
      _recarregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EstoqueDados>(
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
                _textoErro(snapshot.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final dados = snapshot.data!;
        final valorEstoque = dados.itens.fold<double>(0, (total, item) {
          final custo = _double(item['custo_unitario_calculado']) > 0
              ? _double(item['custo_unitario_calculado'])
              : _double(item['custo_unitario']);
          return total + (_double(item['quantidade']) * custo);
        });
        final reservadoTotal = dados.reservasPorItem.values.fold<double>(
          0,
          (total, valor) => total + valor,
        );

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
                        'Estoque',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Saldo Cloud compartilhado com o aplicativo e protegido por FIFO e reservas.',
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => _abrirMovimentacao(dados),
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: const Text('Nova movimentação'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ResumoEstoqueCard(
                    titulo: 'Produtos ativos',
                    valor: dados.itens.length.toString(),
                  ),
                  _ResumoEstoqueCard(
                    titulo: 'Alertas ativos',
                    valor: dados.alertas.length.toString(),
                  ),
                  _ResumoEstoqueCard(
                    titulo: 'Valor em estoque',
                    valor: _moeda.format(valorEstoque),
                  ),
                  _ResumoEstoqueCard(
                    titulo: 'Quantidade reservada',
                    valor: _numero(reservadoTotal),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Produtos',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (dados.itens.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhum produto ativo no estoque.'),
                  ),
                )
              else
                ...dados.itens.map((item) {
                  final id = item['id'].toString();
                  final saldo = _double(item['quantidade']);
                  final reservado = dados.reservasPorItem[id] ?? 0;
                  final disponivel = (saldo - reservado).clamp(
                    0,
                    double.infinity,
                  );
                  final minimo = _double(item['quantidade_minima']);
                  final baixo = minimo > 0 && saldo <= minimo;
                  final unidade = (item['unidade'] ?? '').toString();

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        baixo
                            ? Icons.warning_amber_rounded
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text((item['nome'] ?? 'Produto').toString()),
                      subtitle: Text(
                        [
                          (item['categoria'] ?? '').toString(),
                          'Reservado: ${_numero(reservado)} $unidade',
                          'Disponível: ${_numero(disponivel)} $unidade',
                        ].where((texto) => texto.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        '${_numero(saldo)} $unidade',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 20),
              const Text(
                'Movimentações recentes',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (dados.movimentacoes.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nenhuma movimentação registrada.'),
                  ),
                )
              else
                ...dados.movimentacoes.take(50).map((movimento) {
                  final tipo = (movimento['tipo'] ?? '').toString();
                  final item = _itemPorId(
                    dados.itens,
                    movimento['item_estoque_id']?.toString(),
                  );
                  final unidade = (item?['unidade'] ?? '').toString();
                  final entrada = tipo.toUpperCase() == 'ENTRADA';

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        entrada
                            ? Icons.south_west_rounded
                            : tipo.toUpperCase() == 'SAIDA'
                            ? Icons.north_east_rounded
                            : Icons.tune_rounded,
                      ),
                      title: Text(
                        '${item?['nome'] ?? 'Produto'} · ${_rotuloTipo(tipo)}',
                      ),
                      subtitle: Text(
                        [
                          _formatarData(movimento['data']?.toString()),
                          (movimento['origem'] ?? '').toString(),
                          (movimento['motivo'] ?? '').toString(),
                        ].where((texto) => texto.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: Text(
                        '${entrada
                            ? '+'
                            : tipo.toUpperCase() == 'SAIDA'
                            ? '-'
                            : ''}'
                        '${_numero(_double(movimento['quantidade']))} $unidade',
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
    if (data == null) return valor ?? '';
    return _data.format(data.toLocal());
  }
}

class _EstoqueDados {
  const _EstoqueDados({
    required this.itens,
    required this.movimentacoes,
    required this.alertas,
    required this.reservasPorItem,
  });

  final List<Map<String, dynamic>> itens;
  final List<Map<String, dynamic>> movimentacoes;
  final List<Map<String, dynamic>> alertas;
  final Map<String, double> reservasPorItem;
}

class _ResumoEstoqueCard extends StatelessWidget {
  const _ResumoEstoqueCard({required this.titulo, required this.valor});

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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$rotulo: $valor'));
  }
}

List<String> _unidadesCompativeis(Map<String, dynamic> item) {
  final base = ItemEstoque.unidadeNormalizadaParaBase(
    (item['unidade'] ?? 'unidade').toString(),
  );
  switch (base) {
    case 'ml':
      return const ['ml', 'l'];
    case 'g':
      return const ['g', 'kg'];
    case 'metro':
      return const ['metro'];
    default:
      return const ['unidade'];
  }
}

String _rotuloUnidade(String unidade) {
  switch (unidade) {
    case 'l':
      return 'Litro (L)';
    case 'ml':
      return 'Mililitro (ml)';
    case 'kg':
      return 'Quilograma (kg)';
    case 'g':
      return 'Grama (g)';
    case 'metro':
      return 'Metro';
    default:
      return 'Unidade';
  }
}

String _rotuloTipo(String tipo) {
  switch (tipo.trim().toUpperCase()) {
    case 'ENTRADA':
      return 'Entrada';
    case 'SAIDA':
      return 'Saída';
    case 'AJUSTE':
      return 'Ajuste';
    default:
      return tipo;
  }
}

Map<String, dynamic>? _itemPorId(List<Map<String, dynamic>> itens, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final item in itens) {
    if (item['id']?.toString() == id) return item;
  }
  return null;
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  final texto = valor?.toString().trim().replaceAll(',', '.') ?? '';
  return double.tryParse(texto) ?? 0;
}

String _numero(double valor) {
  if ((valor - valor.roundToDouble()).abs() < 0.000001) {
    return valor.toInt().toString();
  }
  return valor.toStringAsFixed(3).replaceAll('.', ',');
}

String _textoErro(Object erro) {
  return erro
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
