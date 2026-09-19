import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_fiscal_service.dart';

class WebFiscalPage extends StatefulWidget {
  const WebFiscalPage({super.key});

  @override
  State<WebFiscalPage> createState() => _WebFiscalPageState();
}

class _WebFiscalPageState extends State<WebFiscalPage> {
  final _service = WebFiscalService.instance;
  final _busca = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  String? _erro;
  WebFiscalPacote? _pacote;

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
      final pacote = await _service.carregar();
      if (!mounted) return;
      setState(() => _pacote = pacote);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _importarXml() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: true,
    );
    if (resultado == null) return;

    final bytes = resultado.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      _snack('Não foi possível ler o XML selecionado.', erro: true);
      return;
    }

    try {
      await _service.importarXml(utf8.decode(bytes));
      await _carregar();
      _snack('XML fiscal validado e importado no Cloud.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  List<Map<String, dynamic>> _itensNota(String notaId) {
    final pacote = _pacote;
    if (pacote == null) return const [];
    return pacote.itens
        .where((e) => e['nota_fiscal_id'].toString() == notaId)
        .toList();
  }

  Future<void> _abrirNota(Map<String, dynamic> nota) async {
    final pacote = _pacote!;
    var itens = _itensNota(nota['id'].toString());

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            'NF ' +
                (nota['numero'] ?? '—').toString() +
                ' · ' +
                (nota['emitente_nome'] ?? 'Emitente').toString(),
          ),
          content: SizedBox(
            width: 900,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Série: ' + (nota['serie'] ?? '—').toString()),
                    Text(
                      'Total: ' + _moeda.format(_double(nota['valor_total'])),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Situação: ' +
                          (nota['situacao_fiscal'] ?? '—').toString(),
                    ),
                    Text(
                      'Status: ' +
                          (nota['status_importacao'] ?? '—').toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  (nota['chave_acesso'] ?? '').toString(),
                  style: const TextStyle(
                    color: Color(0xFF89939E),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Itens fiscais e vínculo com estoque',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: itens.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = itens[index];
                      final estoqueId = (item['estoque_item_id'] ?? '')
                          .toString();
                      final itemId = item['id'].toString();

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                '#' + (item['numero_item'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['descricao'] ?? 'Item').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _double(item['quantidade']).toString() +
                                        ' ' +
                                        (item['unidade'] ?? '').toString() +
                                        ' · ' +
                                        _moeda.format(
                                          _double(item['valor_total']),
                                        ),
                                    style: const TextStyle(
                                      color: Color(0xFF89939E),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 310,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'fiscal-' + itemId + '-' + estoqueId,
                                ),
                                initialValue: estoqueId.isEmpty
                                    ? null
                                    : estoqueId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Produto no estoque',
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Não vinculado'),
                                  ),
                                  ...pacote.estoque.map(
                                    (produto) => DropdownMenuItem(
                                      value: produto['id'].toString(),
                                      child: Text(
                                        (produto['nome'] ?? 'Produto')
                                            .toString(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (valor) async {
                                  try {
                                    await _service.vincularItemEstoque(
                                      itemFiscalId: itemId,
                                      estoqueItemId: valor,
                                    );
                                    final novo = Map<String, dynamic>.from(item)
                                      ..['estoque_item_id'] =
                                          (valor ?? '').isEmpty ? null : valor;
                                    setLocal(() {
                                      itens = [...itens];
                                      itens[index] = novo;
                                    });
                                  } catch (e) {
                                    _snack(_textoErro(e), erro: true);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await _service.confirmarEntradaEstoque(nota['id'].toString());
                  _snack('Entrada de estoque confirmada.');
                } catch (e) {
                  _snack(_textoErro(e), erro: true);
                }
              },
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Confirmar estoque'),
            ),
            OutlinedButton.icon(
              onPressed: () => _lancarFinanceiro(nota),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Lançar financeiro'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lancarFinanceiro(Map<String, dynamic> nota) async {
    final pacote = _pacote!;
    var status = 'Previsto';
    var contaId = '';
    var planoId = '';
    var forma = 'Pix';
    var competencia = DateTime.now();
    var vencimento = DateTime.now();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Financeiro da nota'),
          content: SizedBox(
            width: 580,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Previsto',
                      child: Text('Previsto / a pagar'),
                    ),
                    DropdownMenuItem(
                      value: 'Realizado',
                      child: Text('Pago / realizado'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => status = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: contaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Conta financeira',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Selecionar conta'),
                    ),
                    ...pacote.contas.map(
                      (e) => DropdownMenuItem(
                        value: e['id'].toString(),
                        child: Text((e['nome'] ?? 'Conta').toString()),
                      ),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => contaId = v ?? ''),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: planoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoria financeira',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sem categoria específica'),
                    ),
                    ...pacote.planoContas.map(
                      (e) => DropdownMenuItem(
                        value: e['id'].toString(),
                        child: Text(
                          (e['codigo'] ?? '').toString() +
                              ' · ' +
                              (e['nome'] ?? '').toString(),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => planoId = v ?? ''),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: forma,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                  ),
                  items:
                      const [
                            'Pix',
                            'Dinheiro',
                            'Boleto',
                            'Débito',
                            'Crédito',
                            'Transferência',
                            'Outro',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => forma = v);
                  },
                ),
                const SizedBox(height: 10),
                _FiscalData(
                  label: 'Competência',
                  data: competencia,
                  onChanged: (v) => setLocal(() => competencia = v),
                ),
                const SizedBox(height: 10),
                _FiscalData(
                  label: 'Vencimento',
                  data: vencimento,
                  onChanged: (v) => setLocal(() => vencimento = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                status != 'Realizado' || contaId.isNotEmpty,
              ),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true) return;

    try {
      await _service.registrarFinanceiro(
        notaId: nota['id'].toString(),
        status: status,
        competencia: competencia,
        vencimento: vencimento,
        contaId: contaId,
        planoContaId: planoId,
        formaPagamento: forma,
      );
      await _carregar();
      _snack('Lançamento financeiro registrado.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pacote = _pacote;
    if (_carregando && pacote == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && pacote == null) {
      return Center(child: Text(_erro!));
    }

    final dados = pacote!;
    final termo = _busca.text.trim().toLowerCase();
    final notas = dados.notas.where((nota) {
      if (termo.isEmpty) return true;
      return [
        nota['numero'],
        nota['chave_acesso'],
        nota['emitente_nome'],
        nota['emitente_cnpj_cpf'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    final autorizadas = dados.notas
        .where((e) => e['situacao_fiscal'] == 'autorizada')
        .length;
    final total = dados.notas.fold<double>(
      0,
      (s, e) => s + _double(e['valor_total']),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 980;
        final conteudo = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1050
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final cardWidth = (conteudo - 12 * (colunas - 1)) / colunas;

        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
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
                          'Notas fiscais',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'XML, estoque e financeiro usando a mesma validação fiscal do Android.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _importarXml,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(compacto ? 'XML' : 'Importar XML'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FiscalResumo(
                    width: cardWidth,
                    titulo: 'Notas importadas',
                    valor: dados.notas.length.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                  _FiscalResumo(
                    width: cardWidth,
                    titulo: 'Autorizadas',
                    valor: autorizadas.toString(),
                    icon: Icons.verified_outlined,
                  ),
                  _FiscalResumo(
                    width: cardWidth,
                    titulo: 'Valor total',
                    valor: _moeda.format(total),
                    icon: Icons.payments_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _busca,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar número, chave ou emitente',
                      suffixIcon: _busca.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _busca.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (notas.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 42),
                    child: Center(
                      child: Text('Nenhuma nota fiscal encontrada.'),
                    ),
                  ),
                )
              else if (tabela)
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('NF')),
                        DataColumn(label: Text('EMITENTE')),
                        DataColumn(label: Text('EMISSÃO')),
                        DataColumn(label: Text('SITUAÇÃO')),
                        DataColumn(label: Text('ITENS')),
                        DataColumn(label: Text('VALOR')),
                        DataColumn(label: Text('AÇÃO')),
                      ],
                      rows: notas.map((nota) {
                        final qtd = _itensNota(nota['id'].toString()).length;
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                (nota['numero'] ?? '—').toString() +
                                    ' / ' +
                                    (nota['serie'] ?? '—').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 260,
                                child: Text(
                                  (nota['emitente_nome'] ?? '—').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text((nota['data_emissao'] ?? '—').toString()),
                            ),
                            DataCell(
                              Chip(
                                label: Text(
                                  (nota['situacao_fiscal'] ?? '—').toString(),
                                ),
                              ),
                            ),
                            DataCell(Text(qtd.toString())),
                            DataCell(
                              Text(
                                _moeda.format(_double(nota['valor_total'])),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Detalhes',
                                onPressed: () => _abrirNota(nota),
                                icon: const Icon(Icons.visibility_outlined),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                ...notas.map(
                  (nota) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long_outlined),
                        ),
                        title: Text(
                          'NF ' +
                              (nota['numero'] ?? '—').toString() +
                              ' · ' +
                              (nota['emitente_nome'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          (nota['situacao_fiscal'] ?? '').toString() +
                              ' · ' +
                              _moeda.format(_double(nota['valor_total'])),
                        ),
                        onTap: () => _abrirNota(nota),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _snack(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}

class _FiscalData extends StatelessWidget {
  const _FiscalData({
    required this.label,
    required this.data,
    required this.onChanged,
  });

  final String label;
  final DateTime data;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd/MM/yyyy', 'pt_BR');
    return InkWell(
      onTap: () async {
        final escolhida = await showDatePicker(
          context: context,
          initialDate: data,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (escolhida != null) onChanged(escolhida);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
        ),
        child: Text(format.format(data)),
      ),
    );
  }
}

class _FiscalResumo extends StatelessWidget {
  const _FiscalResumo({
    required this.width,
    required this.titulo,
    required this.valor,
    required this.icon,
  });

  final double width;
  final String titulo;
  final String valor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
