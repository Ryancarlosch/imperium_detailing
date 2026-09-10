import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/crm_campanha.dart';
import '../models/crm_lead.dart';
import '../repositories/crm_repository.dart';
import '../repositories/precificacao_repository.dart';
import 'crm_operacao_page.dart';

class CrmPage extends StatefulWidget {
  const CrmPage({super.key});

  @override
  State<CrmPage> createState() => _CrmPageState();
}

class _CrmPageState extends State<CrmPage> {
  final CrmRepository _repository = CrmRepository();
  final TextEditingController _pesquisa = TextEditingController();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String _etapa = 'Todos';
  List<CrmLead> _leads = const [];
  CrmResumo? _resumo;

  @override
  void initState() {
    super.initState();
    _pesquisa.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    _pesquisa.removeListener(_carregar);
    _pesquisa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    try {
      final resultados = await Future.wait<Object>([
        _repository.listarLeads(
          etapa: _etapa == 'Todos' ? null : _etapa,
          pesquisa: _pesquisa.text,
        ),
        _repository.carregarResumo(),
      ]);
      if (!mounted) return;
      setState(() {
        _leads = resultados[0] as List<CrmLead>;
        _resumo = resultados[1] as CrmResumo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar o CRM.\n$erro', erro: true);
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

  Future<void> _editarLead([CrmLead? lead]) async {
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LeadEditor(repository: _repository, lead: lead),
    );
    if (salvo == true) await _carregar();
  }

  Future<void> _abrirLead(CrmLead lead) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _LeadDetalhesPage(leadId: lead.id!, repository: _repository),
      ),
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM'),
        actions: [
          IconButton(
            tooltip: 'Central de relacionamento',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const CrmOperacaoPage()),
              );
              await _carregar();
            },
            icon: const Icon(Icons.checklist_rounded),
          ),
          IconButton(
            tooltip: 'Campanhas e benefícios',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CrmCampanhasPage(repository: _repository),
                ),
              );
              await _carregar();
            },
            icon: const Icon(Icons.card_giftcard_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarLead(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Novo lead'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
          children: [
            if (resumo != null) _CrmResumoCard(resumo: resumo, moeda: _moeda),
            const SizedBox(height: 12),
            TextField(
              controller: _pesquisa,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar nome, telefone, serviço ou veículo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final etapa in ['Todos', ...CrmLead.etapas])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(etapa),
                        selected: _etapa == etapa,
                        onSelected: (_) {
                          setState(() => _etapa = etapa);
                          _carregar();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_leads.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(Icons.filter_alt_off_outlined, size: 48),
                      SizedBox(height: 8),
                      Text('Nenhuma oportunidade neste filtro.'),
                    ],
                  ),
                ),
              )
            else
              ..._leads.map(
                (lead) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LeadCard(
                    lead: lead,
                    moeda: _moeda,
                    onTap: () => _abrirLead(lead),
                    onEdit: () => _editarLead(lead),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CrmResumoCard extends StatelessWidget {
  const _CrmResumoCard({required this.resumo, required this.moeda});

  final CrmResumo resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pipeline comercial',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _kpi('Oportunidades', '${resumo.totalAbertos}'),
                _kpi('Potencial', moeda.format(resumo.valorPipeline)),
                _kpi(
                  'Follow-ups atrasados',
                  '${resumo.followUpsAtrasados}',
                  alerta: resumo.followUpsAtrasados > 0,
                ),
                _kpi('Ganhos no mês', '${resumo.ganhosMes}'),
                _kpi(
                  'Conversão',
                  '${resumo.taxaConversaoMes.toStringAsFixed(1)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String titulo, String valor, {bool alerta = false}) => SizedBox(
    width: 145,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        Text(
          valor,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: alerta ? Colors.orangeAccent : null,
          ),
        ),
      ],
    ),
  );
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.moeda,
    required this.onTap,
    required this.onEdit,
  });

  final CrmLead lead;
  final NumberFormat moeda;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final proximo = DateTime.tryParse(lead.proximoContato ?? '');
    final atrasado =
        lead.aberto && proximo != null && proximo.isBefore(DateTime.now());
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            lead.etapa == 'Ganho'
                ? Icons.check_rounded
                : lead.etapa == 'Perdido'
                ? Icons.close_rounded
                : Icons.person_outline,
          ),
        ),
        title: Text(
          lead.nome,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lead.etapa} • ${lead.origem}'),
            if (lead.servicoInteresse.isNotEmpty) Text(lead.servicoInteresse),
            if (lead.valorPotencial > 0)
              Text('Potencial: ${moeda.format(lead.valorPotencial)}'),
            if (proximo != null)
              Text(
                'Próximo contato: ${DateFormat('dd/MM/yyyy HH:mm').format(proximo)}',
                style: TextStyle(
                  color: atrasado ? Colors.orangeAccent : Colors.white60,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Editar',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}

class _LeadEditor extends StatefulWidget {
  const _LeadEditor({required this.repository, this.lead});

  final CrmRepository repository;
  final CrmLead? lead;

  @override
  State<_LeadEditor> createState() => _LeadEditorState();
}

class _LeadEditorState extends State<_LeadEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _telefone;
  late final TextEditingController _email;
  late final TextEditingController _servico;
  late final TextEditingController _veiculo;
  late final TextEditingController _valor;
  late final TextEditingController _responsavel;
  late final TextEditingController _observacoes;
  late String _origem;
  late String _etapa;
  DateTime? _proximoContato;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final lead = widget.lead;
    _nome = TextEditingController(text: lead?.nome ?? '');
    _telefone = TextEditingController(text: lead?.telefone ?? '');
    _email = TextEditingController(text: lead?.email ?? '');
    _servico = TextEditingController(text: lead?.servicoInteresse ?? '');
    _veiculo = TextEditingController(text: lead?.veiculoInteresse ?? '');
    _valor = TextEditingController(
      text: lead == null || lead.valorPotencial == 0
          ? ''
          : lead.valorPotencial.toStringAsFixed(2).replaceAll('.', ','),
    );
    _responsavel = TextEditingController(text: lead?.responsavel ?? '');
    _observacoes = TextEditingController(text: lead?.observacoes ?? '');
    _origem = CrmLead.origens.contains(lead?.origem) ? lead!.origem : 'Outro';
    _etapa = CrmLead.etapas.contains(lead?.etapa)
        ? lead!.etapa
        : 'Novo contato';
    _proximoContato = DateTime.tryParse(lead?.proximoContato ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _nome,
      _telefone,
      _email,
      _servico,
      _veiculo,
      _valor,
      _responsavel,
      _observacoes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      0;

  Future<void> _selecionarFollowUp() async {
    final base = _proximoContato ?? DateTime.now().add(const Duration(days: 1));
    final data = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (hora == null) return;
    setState(() {
      _proximoContato = DateTime(
        data.year,
        data.month,
        data.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  Future<void> _salvar() async {
    if (_salvando || !(_form.currentState?.validate() ?? false)) return;
    if (_etapa == 'Perdido') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use a tela do lead para marcar como Perdido e informar o motivo.',
          ),
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      final atual = widget.lead;
      final lead = CrmLead(
        id: atual?.id,
        nome: _nome.text.trim(),
        telefone: _telefone.text.trim(),
        email: _email.text.trim(),
        clienteId: atual?.clienteId,
        veiculoId: atual?.veiculoId,
        origem: _origem,
        servicoInteresse: _servico.text.trim(),
        veiculoInteresse: _veiculo.text.trim(),
        valorPotencial: _numero(_valor.text),
        etapa: _etapa,
        responsavel: _responsavel.text.trim(),
        proximoContato: _proximoContato?.toIso8601String(),
        observacoes: _observacoes.text.trim(),
        motivoPerda: atual?.motivoPerda ?? '',
        agendamentoId: atual?.agendamentoId,
        criadoEm: atual?.criadoEm ?? agora,
        atualizadoEm: agora,
        convertidoEm: atual?.convertidoEm,
      );
      await widget.repository.salvarLead(lead);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.lead == null ? 'Novo lead' : 'Editar lead',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _telefone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _origem,
                decoration: const InputDecoration(
                  labelText: 'Origem',
                  border: OutlineInputBorder(),
                ),
                items: CrmLead.origens
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _origem = v ?? 'Outro'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _etapa,
                decoration: const InputDecoration(
                  labelText: 'Etapa',
                  border: OutlineInputBorder(),
                ),
                items: CrmLead.etapas
                    .where((v) => v != 'Perdido')
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _etapa = v ?? _etapa),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _servico,
                decoration: const InputDecoration(
                  labelText: 'Serviço de interesse',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _veiculo,
                decoration: const InputDecoration(
                  labelText: 'Veículo de interesse',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _valor,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Valor potencial',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _responsavel,
                      decoration: const InputDecoration(
                        labelText: 'Responsável',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _selecionarFollowUp,
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  _proximoContato == null
                      ? 'Definir próximo contato'
                      : 'Follow-up: ${DateFormat('dd/MM/yyyy HH:mm').format(_proximoContato!)}',
                ),
              ),
              if (_proximoContato != null)
                TextButton(
                  onPressed: () => setState(() => _proximoContato = null),
                  child: const Text('Remover follow-up'),
                ),
              TextFormField(
                controller: _observacoes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_salvando ? 'Salvando...' : 'Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadDetalhesPage extends StatefulWidget {
  const _LeadDetalhesPage({required this.leadId, required this.repository});

  final int leadId;
  final CrmRepository repository;

  @override
  State<_LeadDetalhesPage> createState() => _LeadDetalhesPageState();
}

class _LeadDetalhesPageState extends State<_LeadDetalhesPage> {
  CrmLead? _lead;
  List<CrmInteracao> _interacoes = const [];
  bool _carregando = true;

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lead = await widget.repository.buscarLead(widget.leadId);
    final interacoes = await widget.repository.listarInteracoes(widget.leadId);
    if (!mounted) return;
    setState(() {
      _lead = lead;
      _interacoes = interacoes;
      _carregando = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _mudarEtapa(String etapa) async {
    String motivo = '';
    if (etapa == 'Perdido') {
      final controller = TextEditingController();
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Motivo da perda'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Preço, concorrência, não respondeu, adiou...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmar != true) {
        controller.dispose();
        return;
      }
      motivo = controller.text.trim();
      controller.dispose();
    }
    try {
      await widget.repository.atualizarEtapa(
        widget.leadId,
        etapa,
        motivoPerda: motivo,
      );
      await _carregar();
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _interacao() async {
    final controller = TextEditingController();
    String tipo = 'WhatsApp';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Registrar contato'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: tipo,
                items:
                    const [
                          'WhatsApp',
                          'Ligação',
                          'Instagram',
                          'E-mail',
                          'Presencial',
                          'Observação',
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => setModalState(() => tipo = v ?? tipo),
                decoration: const InputDecoration(labelText: 'Tipo'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'O que aconteceu?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (confirmar == true) {
      try {
        await widget.repository.adicionarInteracao(
          leadId: widget.leadId,
          tipo: tipo,
          descricao: controller.text,
        );
        await _carregar();
      } catch (erro) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$erro'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    }
    controller.dispose();
  }

  Future<void> _converter() async {
    try {
      final id = await widget.repository.converterEmCliente(widget.leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lead convertido e vinculado ao cliente #$id.')),
      );
      await _carregar();
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _agendar() async {
    final lead = _lead;
    final clienteId = lead?.clienteId;
    if (lead == null || clienteId == null) return;

    final veiculos = await widget.repository.listarVeiculosCliente(clienteId);
    if (!mounted) return;
    if (veiculos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre um veículo para este cliente antes de agendar.',
          ),
        ),
      );
      return;
    }

    var veiculoId = (veiculos.first['id'] as num).toInt();
    var data = DateTime.now().add(const Duration(days: 1));
    var hora = const TimeOfDay(hour: 9, minute: 0);
    final servico = TextEditingController(text: lead.servicoInteresse);
    final valor = TextEditingController(
      text: lead.valorPotencial > 0
          ? lead.valorPotencial.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final observacoes = TextEditingController(
      text: 'Agendamento originado do CRM - ${lead.nome}',
    );

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Criar agendamento'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: veiculoId,
                    decoration: const InputDecoration(
                      labelText: 'Veículo',
                      border: OutlineInputBorder(),
                    ),
                    items: veiculos.map((v) {
                      final id = (v['id'] as num).toInt();
                      final modelo = (v['modelo'] ?? '').toString();
                      final placa = (v['placa'] ?? '').toString();
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$modelo${placa.isEmpty ? '' : ' • $placa'}',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => veiculoId = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: servico,
                    decoration: const InputDecoration(
                      labelText: 'Serviço',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: valor,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor previsto',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(DateFormat('dd/MM/yyyy').format(data)),
                          onPressed: () async {
                            final escolhida = await showDatePicker(
                              context: ctx,
                              initialDate: data,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 730),
                              ),
                            );
                            if (escolhida != null) {
                              setModalState(() => data = escolhida);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(hora.format(ctx)),
                          onPressed: () async {
                            final escolhida = await showTimePicker(
                              context: ctx,
                              initialTime: hora,
                            );
                            if (escolhida != null) {
                              setModalState(() => hora = escolhida);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: observacoes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agendar'),
            ),
          ],
        ),
      ),
    );

    try {
      if (confirmar == true) {
        final valorNumero =
            double.tryParse(
              valor.text.replaceAll('.', '').replaceAll(',', '.'),
            ) ??
            0;
        await widget.repository.agendarLead(
          leadId: widget.leadId,
          clienteId: clienteId,
          veiculoId: veiculoId,
          data: data,
          hora:
              '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}',
          servico: servico.text,
          valor: valorNumero,
          observacoes: observacoes.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agendamento criado pelo CRM.')),
        );
        await _carregar();
      }
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      servico.dispose();
      valor.dispose();
      observacoes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    return Scaffold(
      appBar: AppBar(title: Text(lead?.nome ?? 'Lead')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : lead == null
          ? const Center(child: Text('Lead não encontrado.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.nome,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text('${lead.etapa} • ${lead.origem}'),
                        if (lead.telefone.isNotEmpty)
                          Text('Telefone: ${lead.telefone}'),
                        if (lead.email.isNotEmpty)
                          Text('E-mail: ${lead.email}'),
                        if (lead.servicoInteresse.isNotEmpty)
                          Text('Interesse: ${lead.servicoInteresse}'),
                        if (lead.veiculoInteresse.isNotEmpty)
                          Text('Veículo: ${lead.veiculoInteresse}'),
                        if (lead.motivoPerda.isNotEmpty)
                          Text('Motivo da perda: ${lead.motivoPerda}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (lead.aberto)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _interacao,
                        icon: const Icon(Icons.add_comment_outlined),
                        label: const Text('Registrar contato'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: lead.clienteId == null ? _converter : null,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: Text(
                          lead.clienteId == null
                              ? 'Converter em cliente'
                              : 'Cliente vinculado',
                        ),
                      ),
                      if (lead.clienteId != null)
                        FilledButton.tonalIcon(
                          onPressed: _agendar,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Agendar'),
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: lead.etapa,
                  decoration: const InputDecoration(
                    labelText: 'Mover no funil',
                    border: OutlineInputBorder(),
                  ),
                  items: CrmLead.etapas
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null && v != lead.etapa) _mudarEtapa(v);
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Histórico',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (_interacoes.isEmpty)
                  const Text(
                    'Nenhum contato registrado.',
                    style: TextStyle(color: Colors.white60),
                  )
                else
                  ..._interacoes.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(item.tipo),
                      subtitle: Text(item.descricao),
                      trailing: Text(
                        _dataCurta(item.dataInteracao),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _dataCurta(String value) {
    final data = DateTime.tryParse(value);
    if (data == null) return '';
    return DateFormat('dd/MM HH:mm').format(data);
  }
}

class CrmCampanhasPage extends StatefulWidget {
  const CrmCampanhasPage({super.key, required this.repository});

  final CrmRepository repository;

  @override
  State<CrmCampanhasPage> createState() => _CrmCampanhasPageState();
}

class _CrmCampanhasPageState extends State<CrmCampanhasPage> {
  List<CrmCampanha> _campanhas = const [];
  List<Map<String, dynamic>> _cupons = const [];
  List<Map<String, dynamic>> _clientes = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final resultado = await Future.wait<Object>([
        widget.repository.listarCampanhas(),
        widget.repository.listarCupons(),
        widget.repository.listarClientesParaBeneficios(),
      ]);
      if (!mounted) return;
      setState(() {
        _campanhas = resultado[0] as List<CrmCampanha>;
        _cupons = resultado[1] as List<Map<String, dynamic>>;
        _clientes = resultado[2] as List<Map<String, dynamic>>;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _msg('$erro', erro: true);
    }
  }

  void _msg(String texto, {bool erro = false}) {
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

  Future<void> _editarCampanha([CrmCampanha? campanha]) async {
    final salvo = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CampanhaDialog(repository: widget.repository, campanha: campanha),
    );
    if (salvo == true) await _carregar();
  }

  Future<void> _gerar() async {
    try {
      final niver = await widget.repository.gerarBeneficiosAniversario();
      final reativacao = await widget.repository.gerarBeneficiosReativacao();
      _msg(
        'Benefícios gerados: $niver aniversário(s) e $reativacao reativação(ões).',
      );
      await _carregar();
    } catch (erro) {
      _msg('$erro', erro: true);
    }
  }

  Future<void> _simularMargem() async {
    final campanhas = _campanhas.where((c) => c.ativo).toList();
    if (campanhas.isEmpty) {
      _msg('Ative uma campanha para simular o impacto na precificação.');
      return;
    }

    final painel = await PrecificacaoRepository().carregar();
    if (!mounted) return;
    if (painel.servicos.isEmpty) {
      _msg('Nenhum serviço disponível na precificação.', erro: true);
      return;
    }

    var campanha = campanhas.first;
    var servico = painel.servicos.first;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          double desconto = 0;
          if (campanha.beneficioTipo == 'Percentual') {
            desconto = servico.precoAtual * campanha.beneficioValor / 100;
          } else if (campanha.beneficioTipo == 'Valor' ||
              campanha.beneficioTipo == 'Crédito') {
            desconto = campanha.beneficioValor;
          }
          if (desconto > servico.precoAtual) desconto = servico.precoAtual;
          final valorFinal = servico.precoAtual - desconto;
          final margemFinal = valorFinal <= 0
              ? -100.0
              : (valorFinal - servico.custoBase) / valorFinal * 100;
          final abaixoSeguro =
              valorFinal + 0.000001 < servico.precoMinimoSeguro;

          return AlertDialog(
            title: const Text('Impacto do benefício na margem'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: campanha.id,
                      decoration: const InputDecoration(
                        labelText: 'Campanha',
                        border: OutlineInputBorder(),
                      ),
                      items: campanhas
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.nome),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setModalState(
                          () => campanha = campanhas.firstWhere(
                            (c) => c.id == id,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: servico.id,
                      decoration: const InputDecoration(
                        labelText: 'Serviço',
                        border: OutlineInputBorder(),
                      ),
                      items: painel.servicos
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.nome),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setModalState(
                          () => servico = painel.servicos.firstWhere(
                            (s) => s.id == id,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _linhaSimulacao('Preço atual', servico.precoAtual),
                    _linhaSimulacao('Custo base', servico.custoBase),
                    _linhaSimulacao(
                      'Preço mínimo seguro',
                      servico.precoMinimoSeguro,
                    ),
                    _linhaSimulacao('Benefício/desconto', desconto),
                    _linhaSimulacao('Preço após benefício', valorFinal),
                    const SizedBox(height: 8),
                    Text(
                      'Margem estimada após benefício: ${margemFinal.toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      color: abaixoSeguro
                          ? Colors.red.shade900.withValues(alpha: 0.38)
                          : Colors.green.shade900.withValues(alpha: 0.28),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          abaixoSeguro
                              ? 'Atenção: este benefício deixa o preço abaixo do mínimo seguro calculado pela precificação.'
                              : 'Benefício dentro do preço mínimo seguro atual.',
                        ),
                      ),
                    ),
                    if (campanha.beneficioTipo == 'Serviço') ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Benefício do tipo Serviço deve ter o custo do serviço oferecido analisado separadamente.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _linhaSimulacao(String titulo, double valor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(titulo)),
        Text(
          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Future<void> _editarNascimento(Map<String, dynamic> cliente) async {
    final atual = DateTime.tryParse(
      (cliente['data_nascimento'] ?? '').toString(),
    );
    final selecionada = await showDatePicker(
      context: context,
      initialDate: atual ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'Data de nascimento',
    );
    if (selecionada == null) return;
    await widget.repository.atualizarNascimentoCliente(
      (cliente['id'] as num).toInt(),
      selecionada,
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM • Campanhas'),
        actions: [
          IconButton(
            tooltip: 'Simular margem',
            onPressed: _simularMargem,
            icon: const Icon(Icons.calculate_outlined),
          ),
          IconButton(
            tooltip: 'Gerar benefícios',
            onPressed: _gerar,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarCampanha(),
        icon: const Icon(Icons.add),
        label: const Text('Campanha'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              children: [
                const Text(
                  'Campanhas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (_campanhas.isEmpty)
                  const Text('Nenhuma campanha cadastrada.')
                else
                  ..._campanhas.map(
                    (c) => Card(
                      child: ListTile(
                        leading: Icon(
                          c.tipo == 'Aniversário'
                              ? Icons.cake_outlined
                              : Icons.campaign_outlined,
                        ),
                        title: Text(c.nome),
                        subtitle: Text(
                          '${c.tipo} • ${c.beneficioTipo} ${_beneficio(c)} • ${c.diasValidade} dias',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!c.ativo) const Chip(label: Text('Inativa')),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _editarCampanha(c),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Aniversários',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _gerar,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Gerar agora'),
                    ),
                  ],
                ),
                const Text(
                  'Cadastre a data de nascimento. Campanhas de aniversário ativas geram cupom uma única vez por ano.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 6),
                ..._clientes.take(30).map((c) {
                  final data = DateTime.tryParse(
                    (c['data_nascimento'] ?? '').toString(),
                  );
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text((c['nome'] ?? '').toString()),
                    subtitle: Text(
                      data == null
                          ? 'Nascimento não informado'
                          : DateFormat('dd/MM/yyyy').format(data),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () => _editarNascimento(c),
                  );
                }),
                const SizedBox(height: 18),
                const Text(
                  'Cupons e benefícios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (_cupons.isEmpty)
                  const Text(
                    'Nenhum benefício gerado.',
                    style: TextStyle(color: Colors.white60),
                  )
                else
                  ..._cupons
                      .take(50)
                      .map(
                        (cp) => Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.confirmation_number_outlined,
                            ),
                            title: Text(
                              '${cp['codigo']} • ${cp['cliente_nome'] ?? 'Cliente'}',
                            ),
                            subtitle: Text(
                              '${cp['beneficio_descricao'] ?? ''}\nValidade: ${_validade(cp['validade_fim'])}',
                            ),
                            isThreeLine: true,
                            trailing: Chip(
                              label: Text((cp['status'] ?? '').toString()),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
    );
  }

  static String _beneficio(CrmCampanha c) {
    if (c.beneficioTipo == 'Percentual') {
      return '${c.beneficioValor.toStringAsFixed(1)}%';
    }
    if (c.beneficioTipo == 'Valor' || c.beneficioTipo == 'Crédito') {
      return 'R\$ ${c.beneficioValor.toStringAsFixed(2)}';
    }
    return c.beneficioDescricao;
  }

  static String _validade(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null ? '-' : DateFormat('dd/MM/yyyy').format(data);
  }
}

class _CampanhaDialog extends StatefulWidget {
  const _CampanhaDialog({required this.repository, this.campanha});

  final CrmRepository repository;
  final CrmCampanha? campanha;

  @override
  State<_CampanhaDialog> createState() => _CampanhaDialogState();
}

class _CampanhaDialogState extends State<_CampanhaDialog> {
  late final TextEditingController _nome;
  late final TextEditingController _valor;
  late final TextEditingController _descricao;
  late final TextEditingController _minimo;
  late final TextEditingController _validade;
  late final TextEditingController _reativacao;
  late String _tipo;
  late String _beneficioTipo;
  late bool _ativo;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final c = widget.campanha;
    _nome = TextEditingController(text: c?.nome ?? '');
    _valor = TextEditingController(
      text: c == null ? '10' : c.beneficioValor.toString().replaceAll('.', ','),
    );
    _descricao = TextEditingController(text: c?.beneficioDescricao ?? '');
    _minimo = TextEditingController(
      text: c == null ? '0' : c.valorMinimo.toString().replaceAll('.', ','),
    );
    _validade = TextEditingController(text: '${c?.diasValidade ?? 30}');
    _reativacao = TextEditingController(text: '${c?.diasSemRetorno ?? 180}');
    _tipo = c?.tipo ?? 'Manual';
    _beneficioTipo = c?.beneficioTipo ?? 'Percentual';
    _ativo = c?.ativo ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _nome,
      _valor,
      _descricao,
      _minimo,
      _validade,
      _reativacao,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _double(String valor) =>
      double.tryParse(valor.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      await widget.repository.salvarCampanha(
        CrmCampanha(
          id: widget.campanha?.id,
          nome: _nome.text.trim(),
          tipo: _tipo,
          beneficioTipo: _beneficioTipo,
          beneficioValor: _double(_valor.text),
          beneficioDescricao: _descricao.text.trim(),
          valorMinimo: _double(_minimo.text),
          diasValidade: int.tryParse(_validade.text) ?? 30,
          diasSemRetorno: int.tryParse(_reativacao.text) ?? 180,
          ativo: _ativo,
          criadoEm: widget.campanha?.criadoEm ?? agora,
          atualizadoEm: agora,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.campanha == null ? 'Nova campanha' : 'Editar campanha',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                items: CrmCampanha.tipos
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                decoration: const InputDecoration(labelText: 'Tipo'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _beneficioTipo,
                items: CrmCampanha.tiposBeneficio
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _beneficioTipo = v ?? _beneficioTipo),
                decoration: const InputDecoration(labelText: 'Benefício'),
              ),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor / percentual',
                ),
              ),
              TextField(
                controller: _descricao,
                decoration: const InputDecoration(
                  labelText: 'Descrição do benefício',
                ),
              ),
              TextField(
                controller: _minimo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor mínimo da OS',
                ),
              ),
              TextField(
                controller: _validade,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Validade (dias)'),
              ),
              if (_tipo == 'Reativação')
                TextField(
                  controller: _reativacao,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cliente sem retornar há (dias)',
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Campanha ativa'),
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
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
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}
