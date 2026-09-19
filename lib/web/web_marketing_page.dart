import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/comercial_growth_cloud_service.dart';
import 'imperium_web_theme.dart';

class WebMarketingPage extends StatefulWidget {
  const WebMarketingPage({super.key});

  @override
  State<WebMarketingPage> createState() => _WebMarketingPageState();
}

class _WebMarketingPageState extends State<WebMarketingPage> {
  final _service = ComercialGrowthCloudService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final _buscaCampanha = TextEditingController();
  final _buscaPublicacao = TextEditingController();

  bool _carregando = true;
  String? _erro;
  GrowthMarketingResumo? _resumo;
  List<Map<String, dynamic>> _campanhas = const [];
  List<Map<String, dynamic>> _publicacoes = const [];
  Map<String, GrowthMarketingCampanhaDesempenho> _desempenhoPorCampanha =
      const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCampanha.dispose();
    _buscaPublicacao.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final dados = await Future.wait<dynamic>([
        _service.carregarResumoMarketing(),
        _service.listarCampanhasMarketing(),
        _service.listarPublicacoesMarketing(),
        _service.carregarDesempenhoCampanhas(),
      ]);

      if (!mounted) return;
      final desempenho =
          dados[3] as List<GrowthMarketingCampanhaDesempenho>;

      setState(() {
        _resumo = dados[0] as GrowthMarketingResumo;
        _campanhas = dados[1] as List<Map<String, dynamic>>;
        _publicacoes = dados[2] as List<Map<String, dynamic>>;
        _desempenhoPorCampanha = {
          for (final item in desempenho) item.campanhaId: item,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editarCampanha([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(
      text: (atual?['nome'] ?? '').toString(),
    );
    final objetivo = TextEditingController(
      text: (atual?['objetivo'] ?? '').toString(),
    );
    final investimento = TextEditingController(
      text: _double(atual?['investimento']).toStringAsFixed(2),
    );
    final leads = TextEditingController(
      text: '${_int(atual?['leads'])}',
    );
    final cliques = TextEditingController(
      text: '${_int(atual?['cliques'])}',
    );
    final alcance = TextEditingController(
      text: '${_int(atual?['alcance'])}',
    );
    final impressoes = TextEditingController(
      text: '${_int(atual?['impressoes'])}',
    );
    final utm = TextEditingController(
      text: (atual?['utm_campaign'] ?? '').toString(),
    );
    final observacoes = TextEditingController(
      text: (atual?['observacoes'] ?? '').toString(),
    );

    var plataforma = (atual?['plataforma'] ?? 'Instagram').toString();
    var tipo = (atual?['tipo'] ?? 'Pago').toString();
    var status = (atual?['status'] ?? 'Rascunho').toString();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            atual == null ? 'Nova campanha' : 'Editar campanha',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    decoration: const InputDecoration(
                      labelText: 'Nome da campanha *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: plataforma,
                          decoration: const InputDecoration(
                            labelText: 'Plataforma',
                          ),
                          items: const [
                            'Instagram',
                            'Facebook',
                            'Google',
                            'TikTok',
                            'Outro',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setLocal(() => plataforma = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipo,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                          ),
                          items: const [
                            'Pago',
                            'Orgânico',
                            'Impulsionado',
                            'Outro',
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            'Rascunho',
                            'Ativa',
                            'Pausada',
                            'Finalizada',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => status = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: objetivo,
                    decoration: const InputDecoration(
                      labelText: 'Objetivo',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: investimento,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: const InputDecoration(
                            labelText: 'Investimento',
                            prefixText: r'R$ ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: utm,
                          decoration: const InputDecoration(
                            labelText: 'Identificador / UTM campaign',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: alcance,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Alcance',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: impressoes,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Impressões',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: cliques,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cliques',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: leads,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Leads',
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
                      labelText: 'Observações',
                      alignLabelWithHint: true,
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
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                nome.text.trim().isNotEmpty,
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar campanha'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    try {
      await _service.salvarCampanhaMarketing(
        id: atual?['id']?.toString(),
        nome: nome.text,
        plataforma: plataforma,
        tipo: tipo,
        objetivo: objetivo.text,
        status: status,
        investimento: _double(investimento.text),
        utmSource: plataforma.toLowerCase(),
        utmMedium: tipo == 'Pago' ? 'paid_social' : 'organic_social',
        utmCampaign: utm.text,
        alcance: _int(alcance.text),
        impressoes: _int(impressoes.text),
        cliques: _int(cliques.text),
        leads: _int(leads.text),
        observacoes: observacoes.text,
      );
      await _carregar();
      _snack(
        atual == null ? 'Campanha criada.' : 'Campanha atualizada.',
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _editarPublicacao([Map<String, dynamic>? atual]) async {
    final titulo = TextEditingController(
      text: (atual?['titulo'] ?? '').toString(),
    );
    final legenda = TextEditingController(
      text: (atual?['legenda'] ?? '').toString(),
    );

    var campanhaId = (atual?['campanha_id'] ?? '').toString();
    var plataforma = (atual?['plataforma'] ?? 'Instagram').toString();
    var tipoConteudo = (atual?['tipo_conteudo'] ?? 'Post').toString();
    var status = (atual?['status'] ?? 'Rascunho').toString();
    DateTime? agendadoPara = DateTime.tryParse(
      (atual?['agendado_para'] ?? '').toString(),
    )?.toLocal();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            atual == null ? 'Nova publicação' : 'Editar publicação',
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: campanhaId,
                    decoration: const InputDecoration(
                      labelText: 'Campanha relacionada',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Sem campanha'),
                      ),
                      ..._campanhas.map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(
                            (item['nome'] ?? 'Campanha').toString(),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setLocal(() => campanhaId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: plataforma,
                          decoration: const InputDecoration(
                            labelText: 'Plataforma',
                          ),
                          items: const [
                            'Instagram',
                            'Facebook',
                            'TikTok',
                            'Outro',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setLocal(() => plataforma = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipoConteudo,
                          decoration: const InputDecoration(
                            labelText: 'Conteúdo',
                          ),
                          items: const [
                            'Post',
                            'Reel',
                            'Story',
                            'Carrossel',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setLocal(() => tipoConteudo = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            'Rascunho',
                            'Planejado',
                            'Publicado',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => status = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titulo,
                    decoration: const InputDecoration(
                      labelText: 'Título / assunto',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: legenda,
                    minLines: 5,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      labelText: 'Legenda / roteiro',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Data planejada'),
                    subtitle: Text(
                      agendadoPara == null
                          ? 'Não definida'
                          : _dataHora.format(agendadoPara!),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (agendadoPara != null)
                          IconButton(
                            tooltip: 'Limpar',
                            onPressed: () =>
                                setLocal(() => agendadoPara = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        OutlinedButton(
                          onPressed: () async {
                            final base = agendadoPara ?? DateTime.now();
                            final data = await showDatePicker(
                              context: context,
                              initialDate: base,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 1),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (data == null || !context.mounted) return;
                            final hora = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(base),
                            );
                            if (hora == null) return;

                            setLocal(() {
                              agendadoPara = DateTime(
                                data.year,
                                data.month,
                                data.day,
                                hora.hour,
                                hora.minute,
                              );
                              if (status == 'Rascunho') {
                                status = 'Planejado';
                              }
                            });
                          },
                          child: const Text('Definir'),
                        ),
                      ],
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Por enquanto esta agenda organiza o conteúdo. A conexão Meta futura reutilizará estes registros.',
                      style: TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 12,
                      ),
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
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                titulo.text.trim().isNotEmpty ||
                    legenda.text.trim().isNotEmpty,
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar publicação'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;

    try {
      await _service.salvarPublicacaoMarketing(
        id: atual?['id']?.toString(),
        campanhaId: campanhaId.isEmpty ? null : campanhaId,
        plataforma: plataforma,
        tipoConteudo: tipoConteudo,
        titulo: titulo.text,
        legenda: legenda.text,
        status: status,
        agendadoPara: agendadoPara,
      );
      await _carregar();
      _snack(
        atual == null
            ? 'Publicação planejada.'
            : 'Publicação atualizada.',
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _atribuirResultado() async {
    if (_campanhas.isEmpty) {
      _snack('Crie uma campanha antes de atribuir uma venda.', erro: true);
      return;
    }

    try {
      final snapshot = await _service.carregarSnapshotParaAtribuicao();
      if (!mounted) return;

      final clientes = _lista(snapshot['clientes']);
      final ordens = _lista(snapshot['ordens']);
      if (ordens.isEmpty) {
        _snack('Não há OS finalizada para atribuir.', erro: true);
        return;
      }

      final nomes = <String, String>{
        for (final cliente in clientes)
          (cliente['id'] ?? '').toString():
              (cliente['nome'] ?? 'Cliente').toString(),
      };

      var campanhaId = _campanhas.first['id'].toString();
      var ordemId = ordens.first['id'].toString();

      final salvar = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Atribuir venda à campanha'),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: campanhaId,
                    decoration: const InputDecoration(
                      labelText: 'Campanha',
                    ),
                    items: _campanhas
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['id'].toString(),
                            child: Text(
                              (item['nome'] ?? 'Campanha').toString(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => campanhaId = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: ordemId,
                    decoration: const InputDecoration(
                      labelText: 'OS gerada pela campanha',
                    ),
                    items: ordens.map((ordem) {
                      final cliente =
                          nomes[(ordem['cliente_id'] ?? '').toString()] ??
                          'Cliente';
                      return DropdownMenuItem(
                        value: ordem['id'].toString(),
                        child: Text(
                          'OS ${ordem['numero'] ?? ''} · $cliente',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => ordemId = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Atribuir venda'),
              ),
            ],
          ),
        ),
      );

      if (salvar != true) return;

      final ordem = ordens.firstWhere(
        (item) => item['id'].toString() == ordemId,
      );

      await _service.registrarAtribuicaoMarketing(
        campanhaId: campanhaId,
        clienteId: ordem['cliente_id']?.toString(),
        ordemServicoId: ordemId,
      );
      await _carregar();
      _snack('Venda vinculada à campanha.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
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
                  color: ImperiumWebTheme.accentStrong.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icone,
                  color: ImperiumWebTheme.accentStrong,
                ),
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

  String _campanhaNome(String id) {
    for (final campanha in _campanhas) {
      if ((campanha['id'] ?? '').toString() == id) {
        return (campanha['nome'] ?? 'Campanha').toString();
      }
    }
    return '';
  }

  List<Map<String, dynamic>> _campanhasFiltradas() {
    final termo = _buscaCampanha.text.trim().toLowerCase();
    if (termo.isEmpty) return _campanhas;

    return _campanhas.where((item) {
      return [
        item['nome'],
        item['plataforma'],
        item['tipo'],
        item['status'],
        item['objetivo'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();
  }

  List<Map<String, dynamic>> _publicacoesFiltradas() {
    final termo = _buscaPublicacao.text.trim().toLowerCase();
    if (termo.isEmpty) return _publicacoes;

    return _publicacoes.where((item) {
      return [
        item['titulo'],
        item['legenda'],
        item['plataforma'],
        item['tipo_conteudo'],
        item['status'],
        _campanhaNome((item['campanha_id'] ?? '').toString()),
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();
  }

  Widget _campanhasTabela(List<Map<String, dynamic>> campanhas) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 78,
          columns: const [
            DataColumn(label: Text('CAMPANHA')),
            DataColumn(label: Text('PLATAFORMA')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('INVESTIMENTO')),
            DataColumn(label: Text('LEADS')),
            DataColumn(label: Text('VENDAS')),
            DataColumn(label: Text('FATURAMENTO')),
            DataColumn(label: Text('ROAS')),
            DataColumn(label: Text('AÇÃO')),
          ],
          rows: campanhas.map((item) {
            final desempenho =
                _desempenhoPorCampanha[(item['id'] ?? '').toString()];
            final investimento = _double(item['investimento']);
            final faturamento =
                desempenho?.faturamentoAtribuido ?? 0;
            final roas = desempenho?.roas ?? 0;

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
                          (item['nome'] ?? 'Campanha').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          (item['objetivo'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(Text((item['plataforma'] ?? '—').toString())),
                DataCell(Text((item['status'] ?? '—').toString())),
                DataCell(Text(_moeda.format(investimento))),
                DataCell(
                  Text(
                    '${desempenho?.leads ?? _int(item['leads'])}',
                  ),
                ),
                DataCell(Text('${desempenho?.ordens ?? 0}')),
                DataCell(
                  Text(
                    _moeda.format(faturamento),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    roas > 0 ? '${roas.toStringAsFixed(2)}x' : '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: 'Editar campanha',
                    onPressed: () => _editarCampanha(item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _publicacoesTabela(List<Map<String, dynamic>> publicacoes) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 78,
          columns: const [
            DataColumn(label: Text('DATA')),
            DataColumn(label: Text('CONTEÚDO')),
            DataColumn(label: Text('PLATAFORMA')),
            DataColumn(label: Text('TIPO')),
            DataColumn(label: Text('CAMPANHA')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('AÇÃO')),
          ],
          rows: publicacoes.map((item) {
            final agendado = DateTime.tryParse(
              (item['agendado_para'] ?? '').toString(),
            )?.toLocal();
            final titulo =
                (item['titulo'] ?? '').toString().trim().isEmpty
                ? (item['legenda'] ?? 'Publicação').toString()
                : (item['titulo'] ?? 'Publicação').toString();

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    agendado == null
                        ? '—'
                        : _dataHora.format(agendado),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 300,
                    child: Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                DataCell(Text((item['plataforma'] ?? '—').toString())),
                DataCell(Text((item['tipo_conteudo'] ?? '—').toString())),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      _campanhaNome(
                        (item['campanha_id'] ?? '').toString(),
                      ).isEmpty
                          ? '—'
                          : _campanhaNome(
                              (item['campanha_id'] ?? '').toString(),
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text((item['status'] ?? '—').toString())),
                DataCell(
                  IconButton(
                    tooltip: 'Editar publicação',
                    onPressed: () => _editarPublicacao(item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;

    if (_carregando && resumo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null && resumo == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 12),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final campanhas = _campanhasFiltradas();
    final publicacoes = _publicacoesFiltradas();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final desktop = constraints.maxWidth >= 1050;
        final larguraDisponivel =
            constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1180
            ? 6
            : constraints.maxWidth >= 720
            ? 3
            : 1;
        final larguraCard =
            (larguraDisponivel - (12 * (colunas - 1))) / colunas;

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
                          'Marketing',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Campanhas, conteúdo e atribuição de vendas em uma visão única.',
                          style: TextStyle(
                            color: Color(0xFFAAB3BD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _carregando ? null : _carregar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  if (!compacto) ...[
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: _atribuirResultado,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Atribuir venda'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () => _editarPublicacao(),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('Nova publicação'),
                    ),
                  ],
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: () => _editarCampanha(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(compacto ? 'Campanha' : 'Nova campanha'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.hub_outlined),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Integração social preparada',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Dados e atribuição já funcionam manualmente. Instagram/Facebook serão conectados pelo backend em uma etapa posterior.',
                              style: TextStyle(
                                color: Color(0xFF89939E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Chip(label: Text('Manual')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Investido',
                    valor: _moeda.format(resumo!.investimento),
                    detalhe: 'Investimento cadastrado',
                    icone: Icons.payments_outlined,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Faturamento',
                    valor: _moeda.format(
                      resumo.faturamentoAtribuido,
                    ),
                    detalhe: 'Receita de OS atribuídas',
                    icone: Icons.trending_up_rounded,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'ROAS',
                    valor: resumo.roas > 0
                        ? '${resumo.roas.toStringAsFixed(2)}x'
                        : '—',
                    detalhe: 'Receita por real investido',
                    icone: Icons.analytics_outlined,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Leads',
                    valor: '${resumo.leads}',
                    detalhe: 'Leads informados/atribuídos',
                    icone: Icons.person_search_outlined,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Vendas atribuídas',
                    valor: '${resumo.ordens}',
                    detalhe: 'OS vinculadas às campanhas',
                    icone: Icons.receipt_long_outlined,
                  ),
                  _resumoCard(
                    width: larguraCard,
                    titulo: 'Conteúdo planejado',
                    valor: '${resumo.publicacoesPlanejadas}',
                    detalhe: 'Publicações ainda não publicadas',
                    icone: Icons.edit_calendar_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Campanhas',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (compacto)
                    IconButton(
                      tooltip: 'Atribuir venda',
                      onPressed: _atribuirResultado,
                      icon: const Icon(Icons.link_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _buscaCampanha,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText:
                          'Buscar campanha, plataforma, status ou objetivo',
                      suffixIcon: _buscaCampanha.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _buscaCampanha.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (campanhas.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Text(
                      'Nenhuma campanha encontrada. Crie uma campanha para começar a medir aquisição e retorno.',
                    ),
                  ),
                )
              else if (desktop)
                _campanhasTabela(campanhas)
              else
                ...campanhas.map((item) {
                  final desempenho =
                      _desempenhoPorCampanha[
                        (item['id'] ?? '').toString()
                      ];
                  final faturamento =
                      desempenho?.faturamentoAtribuido ?? 0;
                  final roas = desempenho?.roas ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.campaign_outlined),
                        ),
                        title: Text(
                          (item['nome'] ?? 'Campanha').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          [
                            (item['plataforma'] ?? '').toString(),
                            (item['status'] ?? '').toString(),
                            _moeda.format(
                              _double(item['investimento']),
                            ),
                            '${desempenho?.ordens ?? 0} venda(s)',
                            if (faturamento > 0)
                              _moeda.format(faturamento),
                            if (roas > 0)
                              'ROAS ${roas.toStringAsFixed(2)}x',
                          ]
                              .where((e) => e.trim().isNotEmpty)
                              .join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Editar',
                          onPressed: () => _editarCampanha(item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Conteúdo e publicações',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editarPublicacao(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nova publicação'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _buscaPublicacao,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText:
                          'Buscar conteúdo, plataforma, status ou campanha',
                      suffixIcon: _buscaPublicacao.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _buscaPublicacao.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (publicacoes.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Text(
                      'Nenhuma publicação planejada. Crie conteúdos para montar o calendário de marketing.',
                    ),
                  ),
                )
              else if (desktop)
                _publicacoesTabela(publicacoes)
              else
                ...publicacoes.map((item) {
                  final agendado = DateTime.tryParse(
                    (item['agendado_para'] ?? '').toString(),
                  )?.toLocal();
                  final titulo =
                      (item['titulo'] ?? '').toString().trim().isEmpty
                      ? (item['legenda'] ?? 'Publicação').toString()
                      : (item['titulo'] ?? 'Publicação').toString();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            (item['tipo_conteudo'] ?? '').toString() ==
                                    'Reel'
                                ? Icons.play_circle_outline_rounded
                                : Icons.photo_camera_outlined,
                          ),
                        ),
                        title: Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          [
                            (item['plataforma'] ?? '').toString(),
                            (item['tipo_conteudo'] ?? '').toString(),
                            (item['status'] ?? '').toString(),
                            if (agendado != null)
                              _dataHora.format(agendado),
                          ]
                              .where((e) => e.trim().isNotEmpty)
                              .join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Editar',
                          onPressed: () => _editarPublicacao(item),
                          icon: const Icon(Icons.edit_outlined),
                        ),
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

  List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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
    return double.tryParse(
          value?.toString().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
