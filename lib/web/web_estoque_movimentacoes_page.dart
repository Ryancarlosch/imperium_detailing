import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_estoque.dart';
import '../services/web_estoque_cloud_service.dart';
import 'imperium_web_theme.dart';

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
  final _busca = TextEditingController();
  String _filtroTipo = 'Todos';

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

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
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

  Widget _resumoCard({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

        final termo = _busca.text.trim().toLowerCase();
        final itensFiltrados =
            dados.itens.where((item) {
              if (termo.isEmpty) return true;
              return [
                item['nome'],
                item['categoria'],
                item['ean'],
                item['fornecedor'],
              ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
            }).toList()..sort(
              (a, b) => (a['nome'] ?? '').toString().toLowerCase().compareTo(
                (b['nome'] ?? '').toString().toLowerCase(),
              ),
            );

        final movimentosFiltrados = dados.movimentacoes.where((movimento) {
          final tipo = (movimento['tipo'] ?? '').toString().toUpperCase();
          if (_filtroTipo != 'Todos' && tipo != _filtroTipo) return false;

          final item = _itemPorId(
            dados.itens,
            movimento['item_estoque_id']?.toString(),
          );
          if (termo.isEmpty) return true;

          return [
            item?['nome'],
            movimento['origem'],
            movimento['motivo'],
            movimento['observacoes'],
            movimento['fornecedor'],
          ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
        }).toList();

        final alertasAtivos = dados.alertas.where((item) {
          final status = (item['status'] ?? 'Ativo').toString().toLowerCase();
          return status == 'ativo' || status == 'aberto';
        }).toList();

        return RefreshIndicator(
          onRefresh: () async {
            _recarregar();
            await _future;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 760;
              final tabela = constraints.maxWidth >= 1000;
              final larguraDisponivel =
                  constraints.maxWidth - (compacto ? 32 : 48);
              final colunas = constraints.maxWidth >= 1160
                  ? 4
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              final larguraCard =
                  (larguraDisponivel - (12 * (colunas - 1))) / colunas;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  compacto ? 16 : 24,
                  compacto ? 18 : 24,
                  compacto ? 16 : 24,
                  40,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo e movimentações',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Controle de saldo, reservas de OS, estoque mínimo e histórico de movimentações.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        tooltip: 'Atualizar',
                        onPressed: _recarregar,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: () => _abrirMovimentacao(dados),
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: Text(
                          compacto ? 'Movimentar' : 'Nova movimentação',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Produtos ativos',
                        valor: '${dados.itens.length}',
                        detalhe: 'Itens disponíveis para a operação',
                        icone: Icons.inventory_2_outlined,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Alertas ativos',
                        valor: '${alertasAtivos.length}',
                        detalhe: 'Produtos que exigem atenção',
                        icone: Icons.warning_amber_rounded,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Valor em estoque',
                        valor: _moeda.format(valorEstoque),
                        detalhe: 'Custo estimado do saldo atual',
                        icone: Icons.payments_outlined,
                      ),
                      _resumoCard(
                        width: larguraCard,
                        titulo: 'Quantidade reservada',
                        valor: _numero(reservadoTotal),
                        detalhe: 'Saldo comprometido com ordens de serviço',
                        icone: Icons.lock_clock_outlined,
                      ),
                    ],
                  ),
                  if (alertasAtivos.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'Alertas de estoque',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: alertasAtivos.take(8).map((alerta) {
                        final item = _itemPorId(
                          dados.itens,
                          alerta['item_estoque_id']?.toString(),
                        );
                        return Chip(
                          avatar: const Icon(
                            Icons.warning_amber_rounded,
                            size: 17,
                          ),
                          label: Text(
                            (alerta['mensagem'] ??
                                    item?['nome'] ??
                                    'Estoque baixo')
                                .toString(),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compacto ? larguraDisponivel - 28 : 430,
                            child: TextField(
                              controller: _busca,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText:
                                    'Buscar produto, categoria, origem ou observação',
                                suffixIcon: _busca.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar busca',
                                        onPressed: () {
                                          _busca.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                              initialValue: _filtroTipo,
                              decoration: const InputDecoration(
                                labelText: 'Movimentação',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos os tipos'),
                                ),
                                DropdownMenuItem(
                                  value: 'ENTRADA',
                                  child: Text('Entradas'),
                                ),
                                DropdownMenuItem(
                                  value: 'SAIDA',
                                  child: Text('Saídas'),
                                ),
                                DropdownMenuItem(
                                  value: 'AJUSTE',
                                  child: Text('Ajustes'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filtroTipo = v ?? 'Todos'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Produtos',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${itensFiltrados.length} resultado(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (itensFiltrados.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nenhum produto encontrado.'),
                      ),
                    )
                  else if (tabela)
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 58,
                          dataRowMaxHeight: 72,
                          columns: const [
                            DataColumn(label: Text('PRODUTO')),
                            DataColumn(label: Text('SALDO')),
                            DataColumn(label: Text('RESERVADO')),
                            DataColumn(label: Text('DISPONÍVEL')),
                            DataColumn(label: Text('MÍNIMO')),
                            DataColumn(label: Text('CUSTO ESTIMADO')),
                          ],
                          rows: itensFiltrados.map((item) {
                            final id = item['id'].toString();
                            final saldo = _double(item['quantidade']);
                            final reservado = dados.reservasPorItem[id] ?? 0;
                            final disponivel = (saldo - reservado).clamp(
                              0,
                              double.infinity,
                            );
                            final minimo = _double(item['quantidade_minima']);
                            final unidade = (item['unidade'] ?? '').toString();
                            final baixo = minimo > 0 && saldo <= minimo;
                            final custo =
                                _double(item['custo_unitario_calculado']) > 0
                                ? _double(item['custo_unitario_calculado'])
                                : _double(item['custo_unitario']);

                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 250,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 17,
                                          child: Icon(
                                            baixo
                                                ? Icons.warning_amber_rounded
                                                : Icons.inventory_2_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            (item['nome'] ?? 'Produto')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${_numero(saldo)} $unidade',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: baixo ? Colors.orangeAccent : null,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text('${_numero(reservado)} $unidade'),
                                ),
                                DataCell(
                                  Text('${_numero(disponivel)} $unidade'),
                                ),
                                DataCell(Text('${_numero(minimo)} $unidade')),
                                DataCell(
                                  Text(
                                    custo > 0
                                        ? _moeda.format(saldo * custo)
                                        : '—',
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  else
                    ...itensFiltrados.map((item) {
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

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                baixo
                                    ? Icons.warning_amber_rounded
                                    : Icons.inventory_2_outlined,
                              ),
                            ),
                            title: Text(
                              (item['nome'] ?? 'Produto').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              'Reservado ${_numero(reservado)} · '
                              'Disponível ${_numero(disponivel)} $unidade',
                            ),
                            trailing: Text(
                              '${_numero(saldo)} $unidade',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Movimentações',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${movimentosFiltrados.length} resultado(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (movimentosFiltrados.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nenhuma movimentação encontrada.'),
                      ),
                    )
                  else if (tabela)
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 58,
                          dataRowMaxHeight: 72,
                          columns: const [
                            DataColumn(label: Text('DATA')),
                            DataColumn(label: Text('PRODUTO')),
                            DataColumn(label: Text('TIPO')),
                            DataColumn(label: Text('ORIGEM')),
                            DataColumn(label: Text('QUANTIDADE')),
                            DataColumn(label: Text('MOTIVO / OBSERVAÇÃO')),
                          ],
                          rows: movimentosFiltrados.map((movimento) {
                            final tipo = (movimento['tipo'] ?? '').toString();
                            final item = _itemPorId(
                              dados.itens,
                              movimento['item_estoque_id']?.toString(),
                            );
                            final unidade = (item?['unidade'] ?? '').toString();
                            final entrada = tipo.toUpperCase() == 'ENTRADA';
                            final saida = tipo.toUpperCase() == 'SAIDA';

                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 135,
                                    child: Text(
                                      _formatarData(
                                        movimento['data']?.toString(),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 230,
                                    child: Text(
                                      (item?['nome'] ?? 'Produto').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        entrada
                                            ? Icons.south_west_rounded
                                            : saida
                                            ? Icons.north_east_rounded
                                            : Icons.tune_rounded,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(_rotuloTipo(tipo)),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      (movimento['origem'] ?? '—').toString(),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${entrada
                                        ? '+'
                                        : saida
                                        ? '-'
                                        : ''}'
                                    '${_numero(_double(movimento['quantidade']))} $unidade',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 260,
                                    child: Text(
                                      () {
                                        final detalhe =
                                            [
                                                  (movimento['motivo'] ?? '')
                                                      .toString(),
                                                  (movimento['observacoes'] ??
                                                          '')
                                                      .toString(),
                                                ]
                                                .where(
                                                  (e) => e.trim().isNotEmpty,
                                                )
                                                .join(' · ');
                                        return detalhe.isEmpty ? '—' : detalhe;
                                      }(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  else
                    ...movimentosFiltrados.map((movimento) {
                      final tipo = (movimento['tipo'] ?? '').toString();
                      final item = _itemPorId(
                        dados.itens,
                        movimento['item_estoque_id']?.toString(),
                      );
                      final unidade = (item?['unidade'] ?? '').toString();
                      final entrada = tipo.toUpperCase() == 'ENTRADA';
                      final saida = tipo.toUpperCase() == 'SAIDA';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                entrada
                                    ? Icons.south_west_rounded
                                    : saida
                                    ? Icons.north_east_rounded
                                    : Icons.tune_rounded,
                              ),
                            ),
                            title: Text(
                              '${item?['nome'] ?? 'Produto'} · '
                              '${_rotuloTipo(tipo)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              [
                                _formatarData(movimento['data']?.toString()),
                                (movimento['origem'] ?? '').toString(),
                                (movimento['motivo'] ?? '').toString(),
                              ].where((e) => e.trim().isNotEmpty).join(' · '),
                            ),
                            trailing: Text(
                              '${entrada
                                  ? '+'
                                  : saida
                                  ? '-'
                                  : ''}'
                              '${_numero(_double(movimento['quantidade']))} $unidade',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
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

String _numero(num valor) {
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
