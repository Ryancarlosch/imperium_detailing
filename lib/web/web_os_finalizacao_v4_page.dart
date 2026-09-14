import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';
import '../services/web_cloud_operacional_service.dart';
import '../services/web_os_finalizacao_v4_service.dart';

class WebOsFinalizacaoV4Page extends StatefulWidget {
  const WebOsFinalizacaoV4Page({super.key});

  @override
  State<WebOsFinalizacaoV4Page> createState() => _WebOsFinalizacaoV4PageState();
}

class _WebOsFinalizacaoV4PageState extends State<WebOsFinalizacaoV4Page> {
  final _operacional = WebCloudOperacionalService.instance;
  final _service = WebOsFinalizacaoV4Service.instance;
  final _busca = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _ordens = const [];
  List<Map<String, dynamic>> _clientes = const [];
  List<Map<String, dynamic>> _veiculos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final dados = await Future.wait([
        _operacional.listarOrdens(),
        _operacional.listarClientes(),
        _operacional.listarVeiculos(),
      ]);

      if (!mounted) return;

      setState(() {
        _ordens = dados[0];
        _clientes = dados[1];
        _veiculos = dados[2];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _produtos(Map<String, dynamic> ordem) async {
    try {
      final contexto = await _service.carregarContexto(ordem['id'].toString());

      if (!mounted) return;

      final draft = await showDialog<List<Map<String, Object?>>>(
        context: context,
        builder: (context) => _ProdutosOsDialog(contexto: contexto),
      );

      if (draft == null) return;

      final resposta = await _service.salvarProdutos(
        contexto: contexto,
        produtos: draft,
      );

      if (!mounted) return;

      final estado = Map<String, dynamic>.from(resposta['estado'] as Map);

      _mensagem(
        estado['pronto'] == true
            ? 'Contrato de produtos pronto para finalização.'
            : 'Contrato de produtos salvo.',
      );
    } catch (e) {
      _mensagem(e.toString(), erro: true);
    }
  }

  Future<void> _finalizar(Map<String, dynamic> ordem) async {
    try {
      var contexto = await _service.carregarContexto(ordem['id'].toString());

      if (!mounted) return;

      if (contexto['estado'] == null ||
          Map<String, dynamic>.from(contexto['estado'] as Map)['pronto'] !=
              true) {
        final preparar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Produtos ainda não preparados'),
            content: const Text(
              'Antes de finalizar, confirme quais produtos esta OS consome. '
              'Mesmo uma OS sem produtos precisa ter um contrato vazio '
              'confirmado para evitar baixa de estoque incorreta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Preparar produtos'),
              ),
            ],
          ),
        );

        if (preparar != true) return;

        await _produtos(ordem);
        contexto = await _service.carregarContexto(ordem['id'].toString());

        final estadoRaw = contexto['estado'];
        if (estadoRaw == null ||
            Map<String, dynamic>.from(estadoRaw as Map)['pronto'] != true) {
          return;
        }
      }

      if (!mounted) return;

      final draft = await showDialog<_FinalizacaoDraft>(
        context: context,
        builder: (context) => _FinalizarOsDialog(contexto: contexto),
      );

      if (draft == null) return;
      if (!mounted) return;

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finalizar OS?'),
          content: const Text(
            'Esta operação é transacional e irreversível pelo Web neste '
            'momento. Estoque FIFO, mão de obra e financeiro serão gravados '
            'juntos. Se qualquer etapa falhar, nada será finalizado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finalizar'),
            ),
          ],
        ),
      );

      if (confirmar != true) return;

      final resultado = await _service.finalizar(
        contexto: contexto,
        dataEntrada: draft.dataEntrada,
        horaEntrada: draft.horaEntrada,
        dataSaida: draft.dataSaida,
        horaSaida: draft.horaSaida,
        formaPagamento: draft.formaPagamento,
        valorPagamento: draft.valorPagamento,
        dataPagamento: draft.dataPagamento,
        horaPagamento: draft.horaPagamento,
        vencimentoPagamento: draft.vencimentoPagamento,
        contaId: draft.contaId,
        parcelasTaxa: draft.parcelasTaxa,
      );

      if (!mounted) return;

      _mensagem(
        'OS finalizada. Recebido: '
        '${_moeda.format(_double(resultado['valor_recebido']))} · '
        'Taxa: ${_moeda.format(_double(resultado['taxa_operacao']))}.',
      );

      await _carregar();
    } catch (e) {
      _mensagem(e.toString(), erro: true);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _erro!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final clientes = <String, String>{
      for (final item in _clientes)
        item['id'].toString(): (item['nome'] ?? 'Cliente').toString(),
    };

    final veiculos = <String, String>{
      for (final item in _veiculos)
        item['id'].toString():
            '${item['marca'] ?? ''} ${item['modelo'] ?? ''} '
                    '${item['placa'] ?? ''}'
                .trim(),
    };

    final termo = _busca.text.trim().toLowerCase();

    final ordens = _ordens.where((os) {
      if ((os['status'] ?? '').toString() != 'Em andamento') return false;
      if (termo.isEmpty) return true;

      return <dynamic>[
        os['numero'],
        clientes[os['cliente_id']?.toString()],
        veiculos[os['veiculo_id']?.toString()],
        os['funcionario_responsavel'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Finalizar OS',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Finalização transacional: produtos/FIFO, mão de obra, pagamento, '
          'taxa da maquininha e movimentos financeiros no mesmo commit.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar OS, cliente, veículo ou responsável',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (ordens.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhuma OS Em andamento disponível.'),
            ),
          ),
        ...ordens.map((os) {
          final valor = OrdemServicoValor.valorNegociado(
            valorTotal: _double(os['valor_total']),
            desconto: _double(os['desconto']),
            descontoNegociacao: _double(os['desconto_negociacao']),
            acrescimoNegociacao: _double(os['acrescimo_negociacao']),
            jurosParcelamento: _double(os['juros_parcelamento']),
          );

          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.fact_check_outlined),
              ),
              title: Text(
                'OS ${os['numero'] ?? ''} · '
                '${clientes[os['cliente_id']?.toString()] ?? 'Cliente'}',
              ),
              subtitle: Text(
                [
                  veiculos[os['veiculo_id']?.toString()] ?? '',
                  (os['funcionario_responsavel'] ?? '').toString(),
                  'Negociado ${_moeda.format(valor)}',
                ].where((e) => e.trim().isNotEmpty).join(' · '),
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _produtos(os),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Produtos'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _finalizar(os),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Finalizar'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ProdutosOsDialog extends StatefulWidget {
  const _ProdutosOsDialog({required this.contexto});

  final Map<String, dynamic> contexto;

  @override
  State<_ProdutosOsDialog> createState() => _ProdutosOsDialogState();
}

class _ProdutosOsDialogState extends State<_ProdutosOsDialog> {
  late final List<Map<String, Object?>> _itens;
  late final List<Map<String, dynamic>> _estoque;

  @override
  void initState() {
    super.initState();

    _estoque = (widget.contexto['estoque'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final atuais = (widget.contexto['produtos'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    _itens = atuais
        .map(
          (e) => <String, Object?>{
            'id': e['id'],
            'origem_local_id': e['origem_local_id'],
            'item_estoque_id': e['item_estoque_id'],
            'produto_nome': e['produto_nome'],
            'quantidade': _double(e['quantidade']),
            'unidade': e['unidade'],
            'custo_unitario': _double(e['custo_unitario']),
          },
        )
        .toList();
  }

  void _adicionar() {
    if (_estoque.isEmpty) return;

    final item = _estoque.first;

    setState(() {
      _itens.add(<String, Object?>{
        'item_estoque_id': item['id'].toString(),
        'produto_nome': item['nome'].toString(),
        'quantidade': 1.0,
        'unidade': (item['unidade'] ?? '').toString(),
        'custo_unitario': _double(
          item['custo_unitario_calculado'] ?? item['custo_unitario'],
        ),
      });
    });
  }

  void _trocarProduto(int index, String itemId) {
    final estoque = _estoque.firstWhere((e) => e['id'].toString() == itemId);

    setState(() {
      _itens[index]['item_estoque_id'] = itemId;
      _itens[index]['produto_nome'] = estoque['nome'].toString();
      _itens[index]['unidade'] = (estoque['unidade'] ?? '').toString();
      _itens[index]['custo_unitario'] = _double(
        estoque['custo_unitario_calculado'] ?? estoque['custo_unitario'],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Produtos consumidos pela OS'),
      content: SizedBox(
        width: 780,
        height: 560,
        child: ListView(
          children: [
            const Text(
              'Confirme as quantidades antes de finalizar. O custo real será '
              'recalculado por FIFO no servidor no momento da baixa.',
            ),
            const SizedBox(height: 12),
            if (_itens.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Nenhum produto. Salvar assim confirma que esta OS não '
                    'consome estoque.',
                  ),
                ),
              ),
            ...List.generate(_itens.length, (index) {
              final atual = _itens[index];
              final selecionado = (atual['item_estoque_id'] ?? '').toString();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _estoque.any(
                                (e) => e['id'].toString() == selecionado,
                              )
                              ? selecionado
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Produto',
                          ),
                          items: _estoque
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e['id'].toString(),
                                  child: Text(
                                    '${e['nome']} · saldo '
                                    '${_double(e['quantidade']).toStringAsFixed(2)} '
                                    '${e['unidade'] ?? ''}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) _trocarProduto(index, v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: _double(
                            atual['quantidade'],
                          ).toStringAsFixed(2),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Quantidade ${(atual['unidade'] ?? '').toString()}',
                          ),
                          onChanged: (v) => atual['quantidade'] = _double(v),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: () => setState(() => _itens.removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _estoque.isEmpty ? null : _adicionar,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _itens.map((e) => Map<String, Object?>.from(e)).toList(),
          ),
          child: const Text('Salvar contrato'),
        ),
      ],
    );
  }
}

class _FinalizarOsDialog extends StatefulWidget {
  const _FinalizarOsDialog({required this.contexto});

  final Map<String, dynamic> contexto;

  @override
  State<_FinalizarOsDialog> createState() => _FinalizarOsDialogState();
}

class _FinalizarOsDialogState extends State<_FinalizarOsDialog> {
  late final TextEditingController _dataEntrada;
  late final TextEditingController _horaEntrada;
  late final TextEditingController _dataSaida;
  late final TextEditingController _horaSaida;
  late final TextEditingController _valor;
  late final TextEditingController _dataPagamento;
  late final TextEditingController _horaPagamento;
  late final TextEditingController _vencimento;

  String _forma = '';
  String? _contaId;
  int _parcelas = 1;

  late final List<Map<String, dynamic>> _contas;

  @override
  void initState() {
    super.initState();

    final ordem = Map<String, dynamic>.from(widget.contexto['ordem'] as Map);
    _contas = (widget.contexto['contas'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final agora = DateTime.now();
    final dataHoje = _dataIso(agora);
    final horaAgora = _hora(agora);

    _dataEntrada = TextEditingController(
      text: _normalizarData(ordem['data_inicio']) ?? dataHoje,
    );
    _horaEntrada = TextEditingController(
      text: _normalizarHora(ordem['hora_entrada']) ?? horaAgora,
    );
    _dataSaida = TextEditingController(text: dataHoje);
    _horaSaida = TextEditingController(text: horaAgora);

    final negociado = OrdemServicoValor.valorNegociado(
      valorTotal: _double(ordem['valor_total']),
      desconto: _double(ordem['desconto']),
      descontoNegociacao: _double(ordem['desconto_negociacao']),
      acrescimoNegociacao: _double(ordem['acrescimo_negociacao']),
      jurosParcelamento: _double(ordem['juros_parcelamento']),
    );

    _valor = TextEditingController(text: negociado.toStringAsFixed(2));
    _dataPagamento = TextEditingController(text: dataHoje);
    _horaPagamento = TextEditingController(text: horaAgora);
    _vencimento = TextEditingController();
  }

  @override
  void dispose() {
    _dataEntrada.dispose();
    _horaEntrada.dispose();
    _dataSaida.dispose();
    _horaSaida.dispose();
    _valor.dispose();
    _dataPagamento.dispose();
    _horaPagamento.dispose();
    _vencimento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recebeAgora = _forma.isNotEmpty;
    final cartao =
        _forma == 'Cartão de crédito' || _forma == 'Cartão de débito';

    return AlertDialog(
      title: const Text('Finalização transacional'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dataEntrada,
                      decoration: const InputDecoration(
                        labelText: 'Data entrada AAAA-MM-DD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _horaEntrada,
                      decoration: const InputDecoration(
                        labelText: 'Hora entrada HH:mm',
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dataSaida,
                      decoration: const InputDecoration(
                        labelText: 'Data saída AAAA-MM-DD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _horaSaida,
                      decoration: const InputDecoration(
                        labelText: 'Hora saída HH:mm',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _forma,
                decoration: const InputDecoration(
                  labelText: 'Recebimento na finalização',
                ),
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Sem recebimento agora'),
                  ),
                  DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(
                    value: 'Cartão de crédito',
                    child: Text('Cartão de crédito'),
                  ),
                  DropdownMenuItem(
                    value: 'Cartão de débito',
                    child: Text('Cartão de débito'),
                  ),
                  DropdownMenuItem(
                    value: 'Transferência bancária',
                    child: Text('Transferência bancária'),
                  ),
                  DropdownMenuItem(value: 'Boleto', child: Text('Boleto')),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: (v) => setState(() => _forma = v ?? ''),
              ),
              if (recebeAgora) ...[
                TextField(
                  controller: _valor,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor recebido base',
                    helperText:
                        'Se houver repasse de taxa, o servidor recalcula '
                        'automaticamente o valor cobrado.',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _contaId,
                  decoration: const InputDecoration(
                    labelText: 'Conta financeira',
                  ),
                  items: _contas
                      .map(
                        (e) => DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text((e['nome'] ?? 'Conta').toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _contaId = v),
                ),
                if (cartao)
                  DropdownButtonFormField<int>(
                    initialValue: _parcelas,
                    decoration: const InputDecoration(
                      labelText: 'Parcelas para regra de taxa',
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}x'),
                      ),
                    ),
                    onChanged: (v) => setState(() => _parcelas = v ?? 1),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dataPagamento,
                        decoration: const InputDecoration(
                          labelText: 'Data pagamento',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _horaPagamento,
                        decoration: const InputDecoration(
                          labelText: 'Hora pagamento',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              TextField(
                controller: _vencimento,
                decoration: const InputDecoration(
                  labelText: 'Vencimento do saldo restante',
                  hintText: 'Opcional',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _FinalizacaoDraft(
              dataEntrada: _dataEntrada.text.trim(),
              horaEntrada: _horaEntrada.text.trim(),
              dataSaida: _dataSaida.text.trim(),
              horaSaida: _horaSaida.text.trim(),
              formaPagamento: _forma.isEmpty ? null : _forma,
              valorPagamento: _forma.isEmpty ? 0 : _double(_valor.text),
              dataPagamento: _forma.isEmpty ? null : _dataPagamento.text.trim(),
              horaPagamento: _forma.isEmpty ? null : _horaPagamento.text.trim(),
              vencimentoPagamento: _vencimento.text.trim(),
              contaId: _forma.isEmpty ? null : _contaId,
              parcelasTaxa: _parcelas,
            ),
          ),
          child: const Text('Continuar'),
        ),
      ],
    );
  }

  static String _dataIso(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  static String _hora(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String? _normalizarData(dynamic raw) {
    final texto = raw?.toString().trim() ?? '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(texto)) return texto;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return _dataIso(iso);

    final br = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(texto);
    if (br != null) return '${br.group(3)}-${br.group(2)}-${br.group(1)}';

    return null;
  }

  static String? _normalizarHora(dynamic raw) {
    final texto = raw?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(texto);
    return match == null ? null : '${match.group(1)}:${match.group(2)}';
  }
}

class _FinalizacaoDraft {
  const _FinalizacaoDraft({
    required this.dataEntrada,
    required this.horaEntrada,
    required this.dataSaida,
    required this.horaSaida,
    required this.formaPagamento,
    required this.valorPagamento,
    required this.dataPagamento,
    required this.horaPagamento,
    required this.vencimentoPagamento,
    required this.contaId,
    required this.parcelasTaxa,
  });

  final String dataEntrada;
  final String horaEntrada;
  final String dataSaida;
  final String horaSaida;
  final String? formaPagamento;
  final double valorPagamento;
  final String? dataPagamento;
  final String? horaPagamento;
  final String vencimentoPagamento;
  final String? contaId;
  final int parcelasTaxa;
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
