import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_expansao_service.dart';
import 'imperium_web_theme.dart';

class WebServicosCatalogoPage extends StatefulWidget {
  const WebServicosCatalogoPage({super.key});

  @override
  State<WebServicosCatalogoPage> createState() =>
      _WebServicosCatalogoPageState();
}

class _WebServicosCatalogoPageState extends State<WebServicosCatalogoPage> {
  final _service = WebCloudExpansaoService.instance;
  final _busca = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _mostrarInativos = false;
  String _categoria = 'Todas';
  String? _erro;
  List<Map<String, dynamic>> _itens = const [];

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
      final itens = await _service.listarCatalogoServicos();
      if (!mounted) return;
      setState(() => _itens = itens);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: (atual?['nome'] ?? '').toString());
    final categoria = TextEditingController(
      text: (atual?['categoria'] ?? '').toString(),
    );
    final descricao = TextEditingController(
      text: (atual?['descricao'] ?? '').toString(),
    );
    final observacoes = TextEditingController(
      text: (atual?['observacoes_padrao'] ?? '').toString(),
    );
    final preco = TextEditingController(
      text: _double(atual?['preco_padrao']).toStringAsFixed(2),
    );
    final duracao = TextEditingController(
      text: '${_int(atual?['duracao_minutos'])}',
    );
    var ativo = atual?['ativo'] != false;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo serviço' : 'Editar serviço'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    autofocus: atual == null,
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                      prefixIcon: Icon(Icons.design_services_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descricao,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: preco,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Preço padrão',
                            prefixText: r'R$ ',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: duracao,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duração (minutos)',
                            prefixIcon: Icon(Icons.schedule_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: observacoes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observações padrão para OS',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Serviço ativo'),
                    subtitle: const Text(
                      'Serviços inativos permanecem no histórico, mas saem das novas operações.',
                    ),
                    value: ativo,
                    onChanged: (v) => setLocal(() => ativo = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(context, nome.text.trim().isNotEmpty),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar serviço'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    try {
      await _service.salvarServicoCatalogo(
        id: atual?['id']?.toString(),
        atualizadoEmEsperado: atual?['atualizado_em']?.toString(),
        nome: nome.text,
        categoria: categoria.text,
        descricao: descricao.text,
        observacoesPadrao: observacoes.text,
        precoPadrao: _double(preco.text),
        duracaoMinutos: _int(duracao.text),
        ativo: ativo,
      );
      await _carregar();
      _snack(atual == null ? 'Serviço criado.' : 'Serviço atualizado.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _alternarAtivo(Map<String, dynamic> item) async {
    try {
      await _service.alterarAtivoServicoCatalogo(
        id: item['id'].toString(),
        atualizadoEmEsperado: (item['atualizado_em'] ?? '').toString(),
        ativo: item['ativo'] == false,
      );
      await _carregar();
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    final termo = _busca.text.trim().toLowerCase();
    final itens = _itens.where((item) {
      if (!_mostrarInativos && item['ativo'] == false) return false;
      if (_categoria != 'Todas' &&
          (item['categoria'] ?? '').toString() != _categoria) {
        return false;
      }
      if (termo.isEmpty) return true;
      return [
        item['nome'],
        item['categoria'],
        item['descricao'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    itens.sort(
      (a, b) => (a['nome'] ?? '').toString().toLowerCase().compareTo(
        (b['nome'] ?? '').toString().toLowerCase(),
      ),
    );
    return itens;
  }

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icon,
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
                child: Icon(icon, color: ImperiumWebTheme.accentStrong),
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
    if (_carregando && _itens.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && _itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_erro!, textAlign: TextAlign.center),
        ),
      );
    }

    final categorias =
        _itens
            .map((e) => (e['categoria'] ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final ativos = _itens.where((e) => e['ativo'] != false).length;
    final inativos = _itens.length - ativos;
    final precoMedio = ativos == 0
        ? 0.0
        : _itens
                  .where((e) => e['ativo'] != false)
                  .fold<double>(
                    0,
                    (total, e) => total + _double(e['preco_padrao']),
                  ) /
              ativos;
    final itens = _filtrados;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 900;
        final conteudo = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final cardWidth = (conteudo - (12 * (colunas - 1))) / colunas;

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
                          'Catálogo de serviços',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Serviços usados em agenda, orçamentos, OS e precificação.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _editar(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(compacto ? 'Novo' : 'Novo serviço'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumo(
                    width: cardWidth,
                    titulo: 'Ativos',
                    valor: '$ativos',
                    detalhe: 'Disponíveis para novas operações',
                    icon: Icons.design_services_outlined,
                  ),
                  _resumo(
                    width: cardWidth,
                    titulo: 'Categorias',
                    valor: '${categorias.length}',
                    detalhe: 'Grupos do catálogo atual',
                    icon: Icons.category_outlined,
                  ),
                  _resumo(
                    width: cardWidth,
                    titulo: 'Preço médio',
                    valor: _moeda.format(precoMedio),
                    detalhe: '$inativos serviço(s) inativo(s)',
                    icon: Icons.price_check_outlined,
                  ),
                ],
              ),
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
                        width: compacto ? conteudo - 28 : 400,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Buscar serviço, categoria ou descrição',
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
                      SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<String>(
                          initialValue: _categoria,
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                          ),
                          items: ['Todas', ...categorias]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _categoria = v ?? 'Todas'),
                        ),
                      ),
                      FilterChip(
                        selected: _mostrarInativos,
                        onSelected: (v) => setState(() => _mostrarInativos = v),
                        label: const Text('Mostrar inativos'),
                      ),
                      Text(
                        '${itens.length} resultado(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (itens.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('Nenhum serviço encontrado.')),
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
                      dataRowMinHeight: 60,
                      dataRowMaxHeight: 76,
                      columns: const [
                        DataColumn(label: Text('SERVIÇO')),
                        DataColumn(label: Text('CATEGORIA')),
                        DataColumn(label: Text('PREÇO PADRÃO')),
                        DataColumn(label: Text('DURAÇÃO')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('AÇÕES')),
                      ],
                      rows: itens.map((item) {
                        final ativo = item['ativo'] != false;
                        final minutos = _int(item['duracao_minutos']);
                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 310,
                                child: Text(
                                  (item['nome'] ?? 'Serviço').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 170,
                                child: Text(
                                  (item['categoria'] ?? '—').toString(),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _moeda.format(_double(item['preco_padrao'])),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            DataCell(Text(_duracao(minutos))),
                            DataCell(
                              Chip(
                                label: Text(ativo ? 'Ativo' : 'Inativo'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            DataCell(
                              Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: () => _editar(item),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: ativo ? 'Desativar' : 'Ativar',
                                    onPressed: () => _alternarAtivo(item),
                                    icon: Icon(
                                      ativo
                                          ? Icons.block_outlined
                                          : Icons.check_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                ...itens.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.design_services_outlined),
                        ),
                        title: Text(
                          (item['nome'] ?? 'Serviço').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          [
                            (item['categoria'] ?? '').toString(),
                            _moeda.format(_double(item['preco_padrao'])),
                            _duracao(_int(item['duracao_minutos'])),
                            if (item['ativo'] == false) 'Inativo',
                          ].where((e) => e.trim().isNotEmpty).join(' · '),
                        ),
                        onTap: () => _editar(item),
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

  String _duracao(int minutos) {
    if (minutos <= 0) return '—';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    if (horas == 0) return '${resto}min';
    if (resto == 0) return '${horas}h';
    return '${horas}h ${resto}min';
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

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
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
