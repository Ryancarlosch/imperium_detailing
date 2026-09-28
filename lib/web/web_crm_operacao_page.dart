import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_expansao_service.dart';
import '../services/whatsapp_service.dart';
import 'imperium_web_theme.dart';

class WebCrmOperacaoPage extends StatefulWidget {
  const WebCrmOperacaoPage({super.key});

  @override
  State<WebCrmOperacaoPage> createState() => _WebCrmOperacaoPageState();
}

class _WebCrmOperacaoPageState extends State<WebCrmOperacaoPage> {
  final _service = WebCloudExpansaoService.instance;

  bool _carregando = true;
  String? _erro;
  String _status = 'Pendente';
  List<Map<String, dynamic>> _acoes = const [];

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
      final acoes = await _service.listarAcoesCrm(status: 'Todos');
      if (!mounted) return;
      setState(() => _acoes = acoes);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    if (_status == 'Todos') return _acoes;
    if (_status == 'Pendente') {
      return _acoes
          .where(
            (e) =>
                (e['status'] ?? '').toString() == 'Pendente' ||
                (e['status'] ?? '').toString() == 'Adiada',
          )
          .toList();
    }
    return _acoes
        .where((e) => (e['status'] ?? '').toString() == _status)
        .toList();
  }

  Future<void> _whatsApp(Map<String, dynamic> acao) async {
    final telefone = (acao['telefone'] ?? '').toString().trim();
    final mensagem = (acao['mensagem_sugerida'] ?? '').toString().trim();

    if (telefone.isEmpty) {
      _snack('Este contato não possui telefone cadastrado.', erro: true);
      return;
    }

    try {
      await WhatsAppService.enviarMensagemPersonalizada(
        telefone: telefone,
        mensagem: mensagem,
      );
    } catch (e) {
      _snack('Não foi possível abrir o WhatsApp. $e', erro: true);
    }
  }

  Future<void> _concluir(Map<String, dynamic> acao) async {
    final observacoes = TextEditingController();
    DateTime? proximoContato;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Concluir ação'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (acao['titulo'] ?? 'Ação de relacionamento').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacoes,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observações do contato',
                    hintText: 'Opcional',
                    alignLabelWithHint: true,
                  ),
                ),
                if ((acao['tipo'] ?? '').toString() == 'Follow-up lead') ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('Próximo contato'),
                    subtitle: Text(
                      proximoContato == null
                          ? 'Sem próximo follow-up'
                          : DateFormat('dd/MM/yyyy').format(proximoContato!),
                    ),
                    trailing: Wrap(
                      spacing: 2,
                      children: [
                        if (proximoContato != null)
                          IconButton(
                            tooltip: 'Remover próximo contato',
                            onPressed: () =>
                                setLocal(() => proximoContato = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        IconButton(
                          tooltip: 'Selecionar data',
                          onPressed: () async {
                            final escolhida = await showDatePicker(
                              context: dialogContext,
                              initialDate: DateTime.now().add(
                                const Duration(days: 2),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (escolhida != null) {
                              setLocal(() => proximoContato = escolhida);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Concluir'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true || !mounted) {
      observacoes.dispose();
      return;
    }

    try {
      await _service.concluirAcaoCrm(
        acao: acao,
        observacoes: observacoes.text,
        proximoContato: proximoContato,
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    } finally {
      observacoes.dispose();
    }
  }

  Future<void> _adiar(Map<String, dynamic> acao) async {
    final hoje = DateTime.now();
    final atual = DateTime.tryParse((acao['vencimento'] ?? '').toString());
    final inicial = atual != null && !atual.isBefore(hoje)
        ? atual
        : hoje.add(const Duration(days: 1));

    final data = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 730)),
      helpText: 'Adiar ação para',
    );
    if (data == null || !mounted) return;

    try {
      await _service.adiarAcaoCrm(acao: acao, novaData: data);
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    }
  }

  Future<void> _ignorar(Map<String, dynamic> acao) async {
    final motivo = TextEditingController();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ignorar esta ação?'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text((acao['titulo'] ?? '').toString()),
              const SizedBox(height: 12),
              TextField(
                controller: motivo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Opcional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ignorar'),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) {
      motivo.dispose();
      return;
    }

    try {
      await _service.ignorarAcaoCrm(
        acao: acao,
        motivo: motivo.text,
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    } finally {
      motivo.dispose();
    }
  }

  void _snack(String texto, {bool erro = false}) {
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

  bool _pendente(Map<String, dynamic> acao) {
    final status = (acao['status'] ?? '').toString();
    return status == 'Pendente' || status == 'Adiada';
  }

  DateTime? _data(dynamic raw) {
    final texto = raw?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    return DateTime.tryParse(texto);
  }

  Widget _resumo({
    required String titulo,
    required String valor,
    required IconData icone,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    ImperiumWebTheme.accentStrong.withValues(alpha: 0.11),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(titulo),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _acaoCard(Map<String, dynamic> acao) {
    final status = (acao['status'] ?? 'Pendente').toString();
    final prioridade = (acao['prioridade'] ?? 'Normal').toString();
    final data = _data(acao['vencimento']);
    final pendente = _pendente(acao);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: prioridade == 'Alta'
                  ? Colors.orange.withValues(alpha: 0.14)
                  : ImperiumWebTheme.accentStrong.withValues(alpha: 0.11),
              child: Icon(
                (acao['tipo'] ?? '').toString() == 'Pós-venda'
                    ? Icons.favorite_border
                    : (acao['tipo'] ?? '').toString() == 'Benefício/cupom'
                    ? Icons.redeem_outlined
                    : Icons.forum_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        (acao['titulo'] ?? 'Ação').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(prioridade),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      (acao['nome_contato'] ?? '').toString(),
                      (acao['telefone'] ?? '').toString(),
                      if (data != null) DateFormat('dd/MM/yyyy').format(data),
                    ].where((e) => e.trim().isNotEmpty).join(' · '),
                    style: const TextStyle(color: Color(0xFFAAB3BD)),
                  ),
                  if ((acao['mensagem_sugerida'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      (acao['mensagem_sugerida'] ?? '').toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if ((acao['observacoes'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      'Observação: ${acao['observacoes']}',
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'WhatsApp',
                  onPressed:
                      (acao['telefone'] ?? '').toString().trim().isEmpty
                      ? null
                      : () => _whatsApp(acao),
                  icon: const Icon(Icons.chat_outlined),
                ),
                if (pendente)
                  IconButton(
                    tooltip: 'Concluir',
                    onPressed: () => _concluir(acao),
                    icon: const Icon(Icons.check_circle_outline),
                  ),
                if (pendente)
                  IconButton(
                    tooltip: 'Adiar',
                    onPressed: () => _adiar(acao),
                    icon: const Icon(Icons.schedule_send_outlined),
                  ),
                if (pendente)
                  IconButton(
                    tooltip: 'Ignorar',
                    onPressed: () => _ignorar(acao),
                    icon: const Icon(Icons.visibility_off_outlined),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    final diaHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final fimSete = diaHoje.add(const Duration(days: 7));

    final pendentes = _acoes.where(_pendente).toList();
    final atrasadas = pendentes.where((acao) {
      final data = _data(acao['vencimento']);
      if (data == null) return false;
      return DateTime(data.year, data.month, data.day).isBefore(diaHoje);
    }).length;
    final vencemHoje = pendentes.where((acao) {
      final data = _data(acao['vencimento']);
      if (data == null) return false;
      final dia = DateTime(data.year, data.month, data.day);
      return dia == diaHoje;
    }).length;
    final proximas = pendentes.where((acao) {
      final data = _data(acao['vencimento']);
      if (data == null) return false;
      final dia = DateTime(data.year, data.month, data.day);
      return dia.isAfter(diaHoje) && !dia.isAfter(fimSete);
    }).length;
    final inicioMes = DateTime(hoje.year, hoje.month, 1);
    final concluidasMes = _acoes.where((acao) {
      if ((acao['status'] ?? '').toString() != 'Concluida') return false;
      final data = _data(acao['concluida_em']);
      return data != null && !data.isBefore(inicioMes);
    }).length;

    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: ImperiumWebTheme.background,
      appBar: AppBar(
        title: const Text('Central de relacionamento'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar ações',
            onPressed: _carregar,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _carregar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 760;
                final padding = compacto ? 16.0 : 24.0;
                final largura = constraints.maxWidth - (padding * 2);
                final colunas = constraints.maxWidth >= 1100
                    ? 4
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                final larguraCard =
                    (largura - (12 * (colunas - 1))) / colunas;

                return RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(padding, 20, padding, 40),
                    children: [
                      const Text(
                        'Operação comercial',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Follow-ups, orçamentos, pós-venda e benefícios em uma fila compartilhada com o aplicativo.',
                        style: TextStyle(color: Color(0xFFAAB3BD)),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _resumo(
                            titulo: 'Atrasadas',
                            valor: '$atrasadas',
                            icone: Icons.warning_amber_rounded,
                            width: larguraCard,
                          ),
                          _resumo(
                            titulo: 'Hoje',
                            valor: '$vencemHoje',
                            icone: Icons.today_outlined,
                            width: larguraCard,
                          ),
                          _resumo(
                            titulo: 'Próximos 7 dias',
                            valor: '$proximas',
                            icone: Icons.date_range_outlined,
                            width: larguraCard,
                          ),
                          _resumo(
                            titulo: 'Concluídas no mês',
                            valor: '$concluidasMes',
                            icone: Icons.task_alt_outlined,
                            width: larguraCard,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_alt_outlined),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 210,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _status,
                                  decoration: const InputDecoration(
                                    labelText: 'Status',
                                    isDense: true,
                                  ),
                                  items: const [
                                    'Pendente',
                                    'Concluida',
                                    'Ignorada',
                                    'Todos',
                                  ]
                                      .map(
                                        (item) => DropdownMenuItem(
                                          value: item,
                                          child: Text(
                                            item == 'Concluida'
                                                ? 'Concluída'
                                                : item,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _status = v);
                                    }
                                  },
                                ),
                              ),
                              const Spacer(),
                              Text('${_filtradas.length} ação(ões)'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_filtradas.isEmpty)
                        const Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text('Nenhuma ação neste filtro.'),
                            ),
                          ),
                        )
                      else
                        ..._filtradas.map(
                          (acao) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _acaoCard(acao),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
