import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/imperium_regras_negocio.dart';
import '../models/crm_lead.dart';
import '../services/web_cloud_expansao_service.dart';
import '../services/web_cloud_operacional_service.dart';
import 'imperium_web_theme.dart';

class WebCrmPage extends StatefulWidget {
  const WebCrmPage({super.key});

  @override
  State<WebCrmPage> createState() => _WebCrmPageState();
}

class _WebCrmPageState extends State<WebCrmPage> {
  final _service = WebCloudExpansaoService.instance;
  final _busca = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _carregando = true;
  String? _erro;
  String _etapa = 'Todos';
  String _origem = 'Todos';
  bool _modoPipeline = true;
  List<Map<String, dynamic>> _leads = const [];
  List<Map<String, dynamic>> _campanhas = const [];
  List<Map<String, dynamic>> _cupons = const [];

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
        _service.listarLeads(),
        _service.listarCampanhas(),
        _service.listarCupons(),
      ]);

      if (!mounted) return;
      setState(() {
        _leads = dados[0];
        _campanhas = dados[1];
        _cupons = dados[2];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editarLead([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final telefone = TextEditingController(text: '${atual?['telefone'] ?? ''}');
    final email = TextEditingController(text: '${atual?['email'] ?? ''}');
    final servico = TextEditingController(
      text: '${atual?['servico_interesse'] ?? ''}',
    );
    final veiculo = TextEditingController(
      text: '${atual?['veiculo_interesse'] ?? ''}',
    );
    final valor = TextEditingController(
      text: _double(atual?['valor_potencial']).toStringAsFixed(2),
    );
    final responsavel = TextEditingController(
      text: '${atual?['responsavel'] ?? ''}',
    );
    final proximo = TextEditingController(
      text: '${atual?['proximo_contato'] ?? ''}',
    );
    final observacoes = TextEditingController(
      text: '${atual?['observacoes'] ?? ''}',
    );
    final motivoPerda = TextEditingController(
      text: '${atual?['motivo_perda'] ?? ''}',
    );

    var etapa = (atual?['etapa'] ?? 'Novo contato').toString();
    if (!CrmLead.etapas.contains(etapa)) etapa = 'Novo contato';

    var origem = (atual?['origem'] ?? 'Outro').toString();
    if (!CrmLead.origens.contains(origem)) origem = 'Outro';

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo lead' : 'Editar lead'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: nome,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nome *'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: telefone,
                          decoration: const InputDecoration(
                            labelText: 'Telefone',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: email,
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                          ),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: origem,
                    decoration: const InputDecoration(labelText: 'Origem'),
                    items: CrmLead.origens
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => origem = v);
                    },
                  ),
                  TextField(
                    controller: servico,
                    decoration: const InputDecoration(
                      labelText: 'Serviço de interesse',
                    ),
                  ),
                  TextField(
                    controller: veiculo,
                    decoration: const InputDecoration(
                      labelText: 'Veículo de interesse',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: valor,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor potencial',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: etapa,
                          decoration: const InputDecoration(labelText: 'Etapa'),
                          items: CrmLead.etapas
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => etapa = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: responsavel,
                    decoration: const InputDecoration(labelText: 'Responsável'),
                  ),
                  TextField(
                    controller: proximo,
                    decoration: const InputDecoration(
                      labelText: 'Próximo contato',
                      hintText: 'dd/mm/aaaa ou observação de prazo',
                    ),
                  ),
                  if (etapa == 'Perdido')
                    TextField(
                      controller: motivoPerda,
                      decoration: const InputDecoration(
                        labelText: 'Motivo da perda',
                      ),
                    ),
                  TextField(
                    controller: observacoes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Observações'),
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
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, nome.text.trim().isNotEmpty),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true) return;

    try {
      await _service.salvarLead(
        id: atual?['id']?.toString(),
        atualizadoEmEsperado: atual?['atualizado_em']?.toString(),
        nome: nome.text,
        telefone: telefone.text,
        email: email.text,
        origem: origem,
        servicoInteresse: servico.text,
        veiculoInteresse: veiculo.text,
        valorPotencial: _double(valor.text),
        etapa: etapa,
        responsavel: responsavel.text,
        proximoContato: proximo.text,
        observacoes: observacoes.text,
        motivoPerda: motivoPerda.text,
        convertidoEmAtual: atual?['convertido_em']?.toString(),
      );
      await _carregar();
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _interagir(Map<String, dynamic> lead) async {
    final descricao = TextEditingController();
    var tipo = 'Contato';

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Interação · ${lead['nome'] ?? ''}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items:
                      const [
                            'Contato',
                            'WhatsApp',
                            'Ligação',
                            'E-mail',
                            'Proposta',
                            'Retorno',
                            'Observação',
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => tipo = v);
                  },
                ),
                TextField(
                  controller: descricao,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Descrição *'),
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
              onPressed: () =>
                  Navigator.pop(context, descricao.text.trim().isNotEmpty),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true) return;

    try {
      await _service.adicionarInteracao(
        leadId: lead['id'].toString(),
        tipo: tipo,
        descricao: descricao.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Interação registrada.')));
      }
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _historico(Map<String, dynamic> lead) async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico · ${lead['nome'] ?? ''}'),
        content: SizedBox(
          width: 650,
          height: 430,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _service.listarInteracoes(lead['id'].toString()),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text(snapshot.error.toString());
              }
              final itens = snapshot.data!;
              if (itens.isEmpty) {
                return const Center(child: Text('Nenhuma interação.'));
              }
              return ListView.builder(
                itemCount: itens.length,
                itemBuilder: (context, i) {
                  final item = itens[i];
                  return ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text((item['tipo'] ?? 'Contato').toString()),
                    subtitle: Text(
                      '${item['descricao'] ?? ''}\n'
                      '${item['data_interacao'] ?? ''}',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  Widget _resumoCrm({
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

  Widget _acoesLead(Map<String, dynamic> lead) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Nova interação',
          onPressed: () => _interagir(lead),
          icon: const Icon(Icons.add_comment_outlined),
        ),
        IconButton(
          tooltip: 'Histórico',
          onPressed: () => _historico(lead),
          icon: const Icon(Icons.history_rounded),
        ),
        IconButton(
          tooltip: 'Editar lead',
          onPressed: () => _editarLead(lead),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }

  Widget _leadCardCompacto(Map<String, dynamic> lead) {
    final potencial = _double(lead['valor_potencial']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: ImperiumWebTheme.accentStrong.withValues(
                alpha: 0.10,
              ),
              child: Text(
                (lead['nome'] ?? '?').toString().trim().isEmpty
                    ? '?'
                    : (lead['nome'] ?? '?').toString().trim()[0].toUpperCase(),
                style: const TextStyle(
                  color: ImperiumWebTheme.accentStrong,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (lead['nome'] ?? 'Lead').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      (lead['etapa'] ?? '').toString(),
                      (lead['origem'] ?? '').toString(),
                      (lead['servico_interesse'] ?? '').toString(),
                      if (potencial > 0) _moeda.format(potencial),
                    ].where((e) => e.trim().isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFAAB3BD),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _acoesLead(lead),
          ],
        ),
      ),
    );
  }

  Widget _pipeline(List<Map<String, dynamic>> leads) {
    final etapas = CrmLead.etapas;
    return SizedBox(
      height: 620,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: etapas.map((etapa) {
            final itens = leads
                .where((lead) => (lead['etapa'] ?? '').toString() == etapa)
                .toList();
            final potencial = itens.fold<double>(
              0,
              (total, item) => total + _double(item['valor_potencial']),
            );

            return Container(
              width: 310,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: ImperiumWebTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ImperiumWebTheme.border),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                etapa,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text('${itens.length}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          potencial > 0
                              ? _moeda.format(potencial)
                              : 'Sem valor potencial',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: itens.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Nenhum lead',
                                style: TextStyle(color: Color(0xFF89939E)),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(10),
                            itemCount: itens.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final lead = itens[index];
                              final valor = _double(lead['valor_potencial']);
                              return Card(
                                margin: EdgeInsets.zero,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _editarLead(lead),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (lead['nome'] ?? 'Lead').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          [
                                                (lead['servico_interesse'] ??
                                                        '')
                                                    .toString(),
                                                (lead['origem'] ?? '')
                                                    .toString(),
                                              ]
                                              .where((e) => e.trim().isNotEmpty)
                                              .join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFAAB3BD),
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (valor > 0) ...[
                                          const SizedBox(height: 7),
                                          Text(
                                            _moeda.format(valor),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                        if ((lead['proximo_contato'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            'Próximo: ${lead['proximo_contato']}',
                                            style: const TextStyle(
                                              color: Color(0xFF89939E),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: _acoesLead(lead),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) return _ErroExpansao(_erro!);

    final termo = _busca.text.trim().toLowerCase();
    final filtrados = _leads.where((lead) {
      if (_etapa != 'Todos' && '${lead['etapa']}' != _etapa) return false;
      if (_origem != 'Todos' && '${lead['origem']}' != _origem) {
        return false;
      }
      if (termo.isEmpty) return true;
      return [
        lead['nome'],
        lead['telefone'],
        lead['email'],
        lead['servico_interesse'],
        lead['veiculo_interesse'],
        lead['responsavel'],
        lead['origem'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    final abertos = _leads
        .where((e) => e['etapa'] != 'Ganho' && e['etapa'] != 'Perdido')
        .length;
    final ganhos = _leads.where((e) => e['etapa'] == 'Ganho').length;
    final perdidos = _leads.where((e) => e['etapa'] == 'Perdido').length;
    final potencial = _leads
        .where((e) => e['etapa'] != 'Perdido')
        .fold<double>(0, (s, e) => s + _double(e['valor_potencial']));
    final encerrados = ganhos + perdidos;
    final conversao = encerrados == 0 ? 0.0 : (ganhos / encerrados) * 100;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final desktop = constraints.maxWidth >= 1080;
        final larguraDisponivel = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final larguraResumo =
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
                        'CRM',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Pipeline comercial para acompanhar novos contatos até ganho ou perda.',
                        style: TextStyle(color: Color(0xFFAAB3BD)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => _editarLead(),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(compacto ? 'Novo' : 'Novo lead'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _resumoCrm(
                  width: larguraResumo,
                  titulo: 'Leads abertos',
                  valor: '$abertos',
                  detalhe: 'Oportunidades ainda em negociação',
                  icone: Icons.person_search_outlined,
                ),
                _resumoCrm(
                  width: larguraResumo,
                  titulo: 'Potencial',
                  valor: _moeda.format(potencial),
                  detalhe: 'Valor potencial fora das perdas',
                  icone: Icons.trending_up_rounded,
                ),
                _resumoCrm(
                  width: larguraResumo,
                  titulo: 'Ganhos',
                  valor: '$ganhos',
                  detalhe: 'Leads marcados como ganho',
                  icone: Icons.verified_outlined,
                ),
                _resumoCrm(
                  width: larguraResumo,
                  titulo: 'Conversão',
                  valor: '${conversao.toStringAsFixed(1)}%',
                  detalhe: 'Ganhos sobre oportunidades encerradas',
                  icone: Icons.analytics_outlined,
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
                      width: compacto ? larguraDisponivel - 28 : 380,
                      child: TextField(
                        controller: _busca,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText:
                              'Buscar nome, telefone, serviço, veículo ou responsável',
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
                      width: 185,
                      child: DropdownButtonFormField<String>(
                        initialValue: _etapa,
                        decoration: const InputDecoration(labelText: 'Etapa'),
                        items: ['Todos', ...CrmLead.etapas]
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _etapa = v ?? 'Todos'),
                      ),
                    ),
                    SizedBox(
                      width: 175,
                      child: DropdownButtonFormField<String>(
                        initialValue: _origem,
                        decoration: const InputDecoration(labelText: 'Origem'),
                        items: ['Todos', ...CrmLead.origens]
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _origem = v ?? 'Todos'),
                      ),
                    ),
                    if (desktop)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.view_kanban_outlined),
                            label: Text('Pipeline'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.table_rows_outlined),
                            label: Text('Lista'),
                          ),
                        ],
                        selected: <bool>{_modoPipeline},
                        onSelectionChanged: (value) {
                          setState(() => _modoPipeline = value.first);
                        },
                      ),
                    Text(
                      '${filtrados.length} resultado(s)',
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
            if (filtrados.isEmpty)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_search_outlined,
                        size: 42,
                        color: Color(0xFF89939E),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Nenhum lead encontrado',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (desktop && _modoPipeline)
              _pipeline(filtrados)
            else if (desktop)
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 52,
                    dataRowMinHeight: 60,
                    dataRowMaxHeight: 78,
                    columns: const [
                      DataColumn(label: Text('LEAD')),
                      DataColumn(label: Text('ETAPA')),
                      DataColumn(label: Text('ORIGEM')),
                      DataColumn(label: Text('INTERESSE')),
                      DataColumn(label: Text('POTENCIAL')),
                      DataColumn(label: Text('RESPONSÁVEL')),
                      DataColumn(label: Text('PRÓXIMO CONTATO')),
                      DataColumn(label: Text('AÇÕES')),
                    ],
                    rows: filtrados.map((lead) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 230,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (lead['nome'] ?? 'Lead').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    (lead['telefone'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFAAB3BD),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(Text((lead['etapa'] ?? '—').toString())),
                          DataCell(Text((lead['origem'] ?? '—').toString())),
                          DataCell(
                            SizedBox(
                              width: 210,
                              child: Text(
                                (lead['servico_interesse'] ?? '—').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              _double(lead['valor_potencial']) > 0
                                  ? _moeda.format(
                                      _double(lead['valor_potencial']),
                                    )
                                  : '—',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: Text(
                                (lead['responsavel'] ?? '—').toString(),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 170,
                              child: Text(
                                (lead['proximo_contato'] ?? '—').toString(),
                              ),
                            ),
                          ),
                          DataCell(_acoesLead(lead)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              )
            else
              ...filtrados.map(
                (lead) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _leadCardCompacto(lead),
                ),
              ),
            const SizedBox(height: 20),
            if (_campanhas.isNotEmpty || _cupons.isNotEmpty)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    children: [
                      Text(
                        'Campanhas CRM ativas: '
                        '${_campanhas.where((e) => e['ativo'] != false).length}',
                      ),
                      Text(
                        'Cupons ativos: '
                        '${_cupons.where((e) => '${e['status']}' == 'Ativo').length}',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class WebOrcamentosPage extends StatefulWidget {
  const WebOrcamentosPage({super.key});

  @override
  State<WebOrcamentosPage> createState() => _WebOrcamentosPageState();
}

class _WebOrcamentosPageState extends State<WebOrcamentosPage> {
  final _service = WebCloudExpansaoService.instance;
  final _operacional = WebCloudOperacionalService.instance;
  final _busca = TextEditingController();
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _carregando = true;
  String? _erro;
  String _status = 'Todos';
  List<Map<String, dynamic>> _orcamentos = const [];
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
        _service.listarOrcamentos(),
        _operacional.listarClientes(),
        _operacional.listarVeiculos(),
      ]);

      if (!mounted) return;
      setState(() {
        _orcamentos = dados[0];
        _clientes = dados[1];
        _veiculos = dados[2];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _novo() async {
    if (_clientes.isEmpty) {
      _mostrarErro('Cadastre um cliente antes de criar orçamento.');
      return;
    }

    final draft = await showDialog<_OrcamentoDraft>(
      context: context,
      builder: (context) =>
          _NovoOrcamentoWebDialog(clientes: _clientes, veiculos: _veiculos),
    );

    if (draft == null) return;

    try {
      await _service.criarOrcamento(
        clienteId: draft.clienteId,
        veiculoId: draft.veiculoId,
        validade: draft.validade,
        observacoes: draft.observacoes,
        desconto: draft.desconto,
        perfilPreco: draft.perfilPreco,
        itens: draft.itens,
      );
      await _carregar();
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _alterarStatus(
    Map<String, dynamic> orcamento,
    String status,
  ) async {
    if (status == '${orcamento['status']}') return;

    try {
      await _service.alterarStatusOrcamento(
        id: orcamento['id'].toString(),
        status: status,
        atualizadoEmEsperado: '${orcamento['atualizado_em'] ?? ''}',
      );
      await _carregar();
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _detalhes(Map<String, dynamic> orcamento) async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Itens do orçamento'),
        content: SizedBox(
          width: 700,
          height: 430,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _service.listarItensOrcamento(orcamento['id'].toString()),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text(snapshot.error.toString());
              }

              final itens = snapshot.data!;
              return ListView.separated(
                itemCount: itens.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final item = itens[i];
                  final subtotal =
                      _double(item['quantidade']) *
                      _double(item['valor_unitario']);
                  return ListTile(
                    title: Text((item['servico'] ?? 'Serviço').toString()),
                    subtitle: Text(
                      '${_double(item['quantidade']).toStringAsFixed(2)} × '
                      '${_moeda.format(_double(item['valor_unitario']))}',
                    ),
                    trailing: Text(_moeda.format(subtotal)),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) return _ErroExpansao(_erro!);

    final nomes = <String, String>{
      for (final c in _clientes)
        c['id'].toString(): (c['nome'] ?? 'Cliente').toString(),
    };
    final carros = <String, String>{
      for (final v in _veiculos)
        v['id'].toString():
            '${v['marca'] ?? ''} ${v['modelo'] ?? ''} ${v['placa'] ?? ''}'
                .trim(),
    };

    final termo = _busca.text.trim().toLowerCase();
    final filtrados = _orcamentos.where((item) {
      if (_status != 'Todos' && '${item['status']}' != _status) return false;
      if (termo.isEmpty) return true;
      return [
        nomes[item['cliente_id']?.toString()],
        carros[item['veiculo_id']?.toString()],
        item['servico'],
        item['status'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    final pendentes = _orcamentos
        .where((e) => '${e['status']}' == 'Pendente')
        .length;
    final aprovados = _orcamentos
        .where((e) => '${e['status']}' == 'Aprovado')
        .fold<double>(0, (s, e) => s + _double(e['valor']));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Orçamentos',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Criação multi-itens e alteração de status com controle de versão.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ResumoExpansao('Total', '${_orcamentos.length}'),
            _ResumoExpansao('Pendentes', '$pendentes'),
            _ResumoExpansao('Aprovados', _moeda.format(aprovados)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _busca,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar cliente, veículo ou serviço',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const ['Todos', 'Pendente', 'Aprovado', 'Recusado']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? 'Todos'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _novo,
              icon: const Icon(Icons.add),
              label: const Text('Novo orçamento'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...filtrados.map(
          (item) => Card(
            child: ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: Text(nomes[item['cliente_id']?.toString()] ?? 'Cliente'),
              subtitle: Text(
                [
                  carros[item['veiculo_id']?.toString()] ?? '',
                  (item['servico'] ?? '').toString(),
                  (item['data_emissao'] ?? '').toString(),
                  (item['validade'] ?? '').toString(),
                ].where((e) => e.trim().isNotEmpty).join(' · '),
              ),
              onTap: () => _detalhes(item),
              trailing: SizedBox(
                width: 240,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _moeda.format(_double(item['valor'])),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Alterar status',
                      initialValue: (item['status'] ?? 'Pendente').toString(),
                      onSelected: (v) => _alterarStatus(item, v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'Pendente',
                          child: Text('Pendente'),
                        ),
                        PopupMenuItem(
                          value: 'Aprovado',
                          child: Text('Aprovado'),
                        ),
                        PopupMenuItem(
                          value: 'Recusado',
                          child: Text('Recusado'),
                        ),
                      ],
                      child: Chip(
                        label: Text((item['status'] ?? 'Pendente').toString()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NovoOrcamentoWebDialog extends StatefulWidget {
  const _NovoOrcamentoWebDialog({
    required this.clientes,
    required this.veiculos,
  });

  final List<Map<String, dynamic>> clientes;
  final List<Map<String, dynamic>> veiculos;

  @override
  State<_NovoOrcamentoWebDialog> createState() =>
      _NovoOrcamentoWebDialogState();
}

class _NovoOrcamentoWebDialogState extends State<_NovoOrcamentoWebDialog> {
  late String _clienteId;
  String? _veiculoId;
  String _perfil = 'informado';

  final _validade = TextEditingController();
  final _desconto = TextEditingController(text: '0');
  final _observacoes = TextEditingController();
  final List<_ItemOrcamentoController> _itens = [_ItemOrcamentoController()];

  @override
  void initState() {
    super.initState();
    _clienteId = widget.clientes.first['id'].toString();
    _ajustarVeiculo();
  }

  @override
  void dispose() {
    _validade.dispose();
    _desconto.dispose();
    _observacoes.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _veiculosCliente => widget.veiculos
      .where((v) => v['cliente_id'].toString() == _clienteId)
      .toList();

  void _ajustarVeiculo() {
    final lista = _veiculosCliente;
    if (_veiculoId == null ||
        !lista.any((v) => v['id'].toString() == _veiculoId)) {
      _veiculoId = lista.isEmpty ? null : lista.first['id'].toString();
    }
  }

  void _salvar() {
    final itens = <Map<String, Object?>>[];

    for (final item in _itens) {
      if (item.servico.text.trim().isEmpty ||
          _double(item.quantidade.text) <= 0 ||
          _double(item.valor.text) < 0) {
        return;
      }

      itens.add(<String, Object?>{
        'servico': item.servico.text.trim(),
        'descricao': item.descricao.text.trim(),
        'quantidade': _double(item.quantidade.text),
        'valor_unitario': _double(item.valor.text),
      });
    }

    Navigator.pop(
      context,
      _OrcamentoDraft(
        clienteId: _clienteId,
        veiculoId: _veiculoId,
        validade: _validade.text.trim(),
        observacoes: _observacoes.text.trim(),
        desconto: maxDouble(0, _double(_desconto.text)),
        perfilPreco: _perfil,
        itens: itens,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo orçamento'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _clienteId,
              decoration: const InputDecoration(labelText: 'Cliente *'),
              items: widget.clientes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['id'].toString(),
                      child: Text((c['nome'] ?? 'Cliente').toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _clienteId = v;
                  _ajustarVeiculo();
                });
              },
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(_clienteId),
              initialValue: _veiculoId,
              decoration: const InputDecoration(labelText: 'Veículo'),
              items: _veiculosCliente
                  .map(
                    (v) => DropdownMenuItem(
                      value: v['id'].toString(),
                      child: Text(
                        '${v['marca'] ?? ''} ${v['modelo'] ?? ''} '
                                '${v['placa'] ?? ''}'
                            .trim(),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _veiculoId = v),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _validade,
                    decoration: const InputDecoration(
                      labelText: 'Validade',
                      hintText: 'dd/mm/aaaa',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _desconto,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Desconto R\$',
                    ),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _perfil,
              decoration: const InputDecoration(labelText: 'Perfil de preço'),
              items:
                  const {
                        'informado': 'Preço informado',
                        'cliente': 'Cliente final',
                        'parceiro_1_4': 'Parceiro 1–4/mês',
                        'parceiro_5_9': 'Parceiro 5–9/mês',
                        'parceiro_10_mais': 'Parceiro 10+/mês',
                      }.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() => _perfil = v ?? 'informado'),
            ),
            TextField(
              controller: _observacoes,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Serviços',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      setState(() => _itens.add(_ItemOrcamentoController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            ...List.generate(_itens.length, (i) {
              final item = _itens[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Serviço ${i + 1}')),
                          IconButton(
                            onPressed: _itens.length == 1
                                ? null
                                : () {
                                    final removido = _itens.removeAt(i);
                                    removido.dispose();
                                    setState(() {});
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: item.servico,
                        decoration: const InputDecoration(
                          labelText: 'Serviço *',
                        ),
                      ),
                      TextField(
                        controller: item.descricao,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: item.quantidade,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Quantidade *',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: item.valor,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Valor unitário *',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _salvar, child: const Text('Criar orçamento')),
      ],
    );
  }
}

class _OrcamentoDraft {
  const _OrcamentoDraft({
    required this.clienteId,
    required this.veiculoId,
    required this.validade,
    required this.observacoes,
    required this.desconto,
    required this.perfilPreco,
    required this.itens,
  });

  final String clienteId;
  final String? veiculoId;
  final String validade;
  final String observacoes;
  final double desconto;
  final String perfilPreco;
  final List<Map<String, Object?>> itens;
}

class _ItemOrcamentoController {
  final servico = TextEditingController();
  final descricao = TextEditingController();
  final quantidade = TextEditingController(text: '1');
  final valor = TextEditingController();

  void dispose() {
    servico.dispose();
    descricao.dispose();
    quantidade.dispose();
    valor.dispose();
  }
}

class WebPrecificacaoPage extends StatefulWidget {
  const WebPrecificacaoPage({super.key});

  @override
  State<WebPrecificacaoPage> createState() => _WebPrecificacaoPageState();
}

class _WebPrecificacaoPageState extends State<WebPrecificacaoPage> {
  final _service = WebCloudExpansaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _catalogo = const [];
  List<Map<String, dynamic>> _snapshots = const [];
  List<Map<String, dynamic>> _simulacoes = const [];

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
      final config = await _service.carregarConfigPrecificacao();
      final dados = await Future.wait([
        _service.listarCatalogoPrecificacao(),
        _service.listarSnapshotsPrecificacao(),
        _service.listarSimulacoesPrecificacao(),
      ]);

      if (!mounted) return;
      setState(() {
        _config = config;
        _catalogo = dados[0];
        _snapshots = dados[1];
        _simulacoes = dados[2];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editarConfig() async {
    final config = _config;
    if (config == null) return;

    final meses = TextEditingController(text: '${config['meses_media'] ?? 3}');
    final cliente = TextEditingController(
      text: '${config['margem_cliente'] ?? 35}',
    );
    final r14 = TextEditingController(
      text: '${config['margem_revenda_1_4'] ?? 25}',
    );
    final r59 = TextEditingController(
      text: '${config['margem_revenda_5_9'] ?? 20}',
    );
    final r10 = TextEditingController(
      text: '${config['margem_revenda_10_mais'] ?? 16}',
    );
    final minima = TextEditingController(
      text: '${config['margem_minima'] ?? 10}',
    );

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuração de precificação'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('Horas produtivas da empresa'),
                  subtitle: Text(
                    '220 horas/mês fixas. Não multiplicar por funcionário.',
                  ),
                  trailing: Text(
                    '220 h',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextField(
                  controller: meses,
                  decoration: const InputDecoration(
                    labelText: 'Meses para média (1–12)',
                  ),
                ),
                TextField(
                  controller: cliente,
                  decoration: const InputDecoration(
                    labelText: 'Margem cliente final %',
                  ),
                ),
                TextField(
                  controller: r14,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 1–4 %',
                  ),
                ),
                TextField(
                  controller: r59,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 5–9 %',
                  ),
                ),
                TextField(
                  controller: r10,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 10+ %',
                  ),
                ),
                TextField(
                  controller: minima,
                  decoration: const InputDecoration(
                    labelText: 'Margem mínima %',
                  ),
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await _service.salvarConfigPrecificacao(
        atualizadoEmEsperado: config['atualizado_em']?.toString(),
        mesesMedia: int.tryParse(meses.text) ?? 3,
        margemCliente: _double(cliente.text),
        margemRevenda1a4: _double(r14.text),
        margemRevenda5a9: _double(r59.text),
        margemRevenda10Mais: _double(r10.text),
        margemMinima: _double(minima.text),
      );
      await _carregar();
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _novaSimulacao() async {
    final config = _config;
    if (config == null) return;

    final nome = TextEditingController();
    final mc = TextEditingController(text: '${config['margem_cliente'] ?? 35}');
    final r14 = TextEditingController(
      text: '${config['margem_revenda_1_4'] ?? 25}',
    );
    final r59 = TextEditingController(
      text: '${config['margem_revenda_5_9'] ?? 20}',
    );
    final r10 = TextEditingController(
      text: '${config['margem_revenda_10_mais'] ?? 16}',
    );
    final mm = TextEditingController(text: '${config['margem_minima'] ?? 10}');
    final taxa = TextEditingController(
      text: _snapshots.isEmpty
          ? '0'
          : '${_snapshots.first['taxa_cartao_media_percentual'] ?? 0}',
    );
    final custoHora = TextEditingController(
      text: _snapshots.isEmpty ? '0' : '${_snapshots.first['custo_hora'] ?? 0}',
    );
    final meta = TextEditingController(text: '0');
    final obs = TextEditingController();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo cenário'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nome,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                ),
                TextField(
                  controller: mc,
                  decoration: const InputDecoration(
                    labelText: 'Margem cliente %',
                  ),
                ),
                TextField(
                  controller: r14,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 1–4 %',
                  ),
                ),
                TextField(
                  controller: r59,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 5–9 %',
                  ),
                ),
                TextField(
                  controller: r10,
                  decoration: const InputDecoration(
                    labelText: 'Margem revenda 10+ %',
                  ),
                ),
                TextField(
                  controller: mm,
                  decoration: const InputDecoration(
                    labelText: 'Margem mínima %',
                  ),
                ),
                TextField(
                  controller: taxa,
                  decoration: const InputDecoration(
                    labelText: 'Taxa cartão média %',
                  ),
                ),
                TextField(
                  controller: custoHora,
                  decoration: const InputDecoration(
                    labelText: 'Custo-hora do cenário',
                  ),
                ),
                TextField(
                  controller: meta,
                  decoration: const InputDecoration(
                    labelText: 'Meta de faturamento',
                  ),
                ),
                TextField(
                  controller: obs,
                  decoration: const InputDecoration(labelText: 'Observações'),
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
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, nome.text.trim().isNotEmpty),
            child: const Text('Simular e salvar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await _service.criarSimulacaoPrecificacao(
        nome: nome.text,
        margemCliente: _double(mc.text),
        margemRevenda1a4: _double(r14.text),
        margemRevenda5a9: _double(r59.text),
        margemRevenda10Mais: _double(r10.text),
        margemMinima: _double(mm.text),
        taxaCartaoPercentual: _double(taxa.text),
        custoHora: _double(custoHora.text),
        metaFaturamento: _double(meta.text),
        mesesMedia: int.tryParse('${config['meses_media']}') ?? 3,
        observacoes: obs.text,
      );
      await _carregar();
    } catch (e) {
      _mostrarErro(e);
    }
  }

  void _mostrarErro(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) return _ErroExpansao(_erro!);

    final config = _config;
    final nomes = <String, String>{
      for (final item in _catalogo)
        item['id'].toString(): (item['nome'] ?? 'Serviço').toString(),
    };

    final abaixoMinimo = _snapshots.where((s) {
      return _double(s['margem_atual']) < _double(config?['margem_minima']) ||
          _double(s['preco_atual']) < _double(s['preco_equilibrio']);
    }).length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Precificação',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Configuração oficial, preços sugeridos e cenários compartilhados.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ResumoExpansao(
              'Horas da empresa',
              '${ImperiumRegrasNegocio.horasMensaisPadrao.toInt()} h/mês',
            ),
            _ResumoExpansao('Serviços calculados', '${_snapshots.length}'),
            _ResumoExpansao('Alertas de preço', '$abaixoMinimo'),
            _ResumoExpansao('Cenários', '${_simulacoes.length}'),
          ],
        ),
        const SizedBox(height: 18),
        if (config != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Margem cliente: ${config['margem_cliente']}%'),
                  Text('Revenda 1–4: ${config['margem_revenda_1_4']}%'),
                  Text('Revenda 5–9: ${config['margem_revenda_5_9']}%'),
                  Text('Revenda 10+: ${config['margem_revenda_10_mais']}%'),
                  Text('Mínima: ${config['margem_minima']}%'),
                  Text('Média: ${config['meses_media']} meses'),
                  FilledButton.tonalIcon(
                    onPressed: _editarConfig,
                    icon: const Icon(Icons.tune),
                    label: const Text('Editar margens'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _novaSimulacao,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Novo cenário'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Serviços',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._snapshots.map((s) {
          final atual = _double(s['preco_atual']);
          final sugerido = _double(s['preco_sugerido']);
          final equilibrio = _double(s['preco_equilibrio']);
          final margem = _double(s['margem_atual']);
          final alerta =
              margem < _double(config?['margem_minima']) || atual < equilibrio;

          return Card(
            child: ListTile(
              leading: Icon(
                alerta ? Icons.warning_amber_rounded : Icons.price_check,
              ),
              title: Text(nomes[s['servico_id']?.toString()] ?? 'Serviço'),
              subtitle: Text(
                'Atual ${_moeda.format(atual)} · '
                'Equilíbrio ${_moeda.format(equilibrio)} · '
                'Margem ${margem.toStringAsFixed(1)}%',
              ),
              trailing: Text(
                'Sugerido\n${_moeda.format(sugerido)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
        if (_simulacoes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Cenários salvos',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._simulacoes
              .take(20)
              .map(
                (s) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: Text((s['nome'] ?? 'Cenário').toString()),
                    subtitle: Text(
                      'Margem cliente ${s['margem_cliente']}% · '
                      'Taxa ${s['taxa_cartao_percentual']}% · '
                      '${s['criado_em'] ?? ''}',
                    ),
                    trailing: Text(
                      _moeda.format(_double(s['meta_faturamento'])),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class WebCentralCloudPage extends StatefulWidget {
  const WebCentralCloudPage({super.key});

  @override
  State<WebCentralCloudPage> createState() => _WebCentralCloudPageState();
}

class _WebCentralCloudPageState extends State<WebCentralCloudPage> {
  final _service = WebCloudExpansaoService.instance;
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.diagnosticarCentral();
  }

  void _atualizar() {
    setState(() {
      _future = _service.diagnosticarCentral();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErroExpansao(snapshot.error.toString());
        }

        final dados = snapshot.data!;
        final modulos = (dados['modulos'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Central Web',
                    style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _atualizar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Atualizar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${dados['plataforma']} · Tenant ${dados['empresa_id']}'),
            Text('Usuário: ${dados['usuario']}'),
            Text('Base de horas: ${dados['horas_mensais_empresa']} h/mês'),
            if (dados['ultima_atualizacao'] != null)
              Text('Última alteração: ${dados['ultima_atualizacao']}'),
            const SizedBox(height: 18),
            ...modulos.map(
              (item) => Card(
                child: ListTile(
                  leading: Icon(
                    item['status'] == 'Disponível'
                        ? Icons.cloud_done_outlined
                        : item['status'] == 'Sem permissão'
                        ? Icons.lock_outline
                        : Icons.cloud_off_outlined,
                  ),
                  title: Text('${item['nome']}'),
                  subtitle: Text(
                    [
                      '${item['status']}',
                      if (item['ultima_atualizacao'] != null)
                        'Atualizado ${item['ultima_atualizacao']}',
                    ].join(' · '),
                  ),
                  trailing: Text(
                    item['registros'] == null
                        ? '—'
                        : '${item['registros']} registros*',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '* A Central Web limita a leitura diagnóstica a 500 registros '
              'por módulo para manter a página leve.',
            ),
          ],
        );
      },
    );
  }
}

class _ResumoExpansao extends StatelessWidget {
  const _ResumoExpansao(this.titulo, this.valor);

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
                  fontSize: 21,
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

class _ErroExpansao extends StatelessWidget {
  const _ErroExpansao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texto,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

double maxDouble(double a, double b) => a > b ? a : b;
