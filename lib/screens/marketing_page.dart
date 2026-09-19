import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/comercial_growth_cloud_service.dart';

class MarketingPage extends StatefulWidget {
  const MarketingPage({super.key});

  @override
  State<MarketingPage> createState() => _MarketingPageState();
}

class _MarketingPageState extends State<MarketingPage> {
  final _service = ComercialGrowthCloudService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R$');

  bool _carregando = true;
  String? _erro;
  GrowthMarketingResumo? _resumo;
  List<Map<String, dynamic>> _campanhas = const [];

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
      final dados = await Future.wait<dynamic>([
        _service.carregarResumoMarketing(),
        _service.listarCampanhasMarketing(),
      ]);

      if (!mounted) return;
      setState(() {
        _resumo = dados[0] as GrowthMarketingResumo;
        _campanhas = dados[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editarCampanha([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: (atual?['nome'] ?? '').toString());
    final objetivo = TextEditingController(
      text: (atual?['objetivo'] ?? '').toString(),
    );
    final investimento = TextEditingController(
      text: _double(atual?['investimento']).toStringAsFixed(2),
    );
    final leads = TextEditingController(text: '${_int(atual?['leads'])}');
    final cliques = TextEditingController(text: '${_int(atual?['cliques'])}');
    final alcance = TextEditingController(text: '${_int(atual?['alcance'])}');
    final utm = TextEditingController(
      text: (atual?['utm_campaign'] ?? '').toString(),
    );

    var plataforma = (atual?['plataforma'] ?? 'Instagram').toString();
    var tipo = (atual?['tipo'] ?? 'Pago').toString();
    var status = (atual?['status'] ?? 'Rascunho').toString();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Nova campanha' : 'Editar campanha'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    decoration: const InputDecoration(labelText: 'Nome *'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: plataforma,
                    decoration: const InputDecoration(labelText: 'Plataforma'),
                    items: const <String>[
                      'Instagram',
                      'Facebook',
                      'Google',
                      'TikTok',
                      'Outro',
                    ].map((item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => plataforma = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipo,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const <String>[
                            'Pago',
                            'Orgânico',
                            'Impulsionado',
                            'Outro',
                          ].map((item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          )).toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => tipo = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const <String>[
                            'Rascunho',
                            'Ativa',
                            'Pausada',
                            'Finalizada',
                          ].map((item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          )).toList(),
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
                    decoration: const InputDecoration(labelText: 'Objetivo'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: investimento,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Investimento',
                      prefixText: 'R$ ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: utm,
                    decoration: const InputDecoration(
                      labelText: 'Identificador / UTM',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: alcance,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Alcance'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: cliques,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cliques'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: leads,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Leads'),
                        ),
                      ),
                    ],
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
              onPressed: () => Navigator.pop(
                context,
                nome.text.trim().isNotEmpty,
              ),
              child: const Text('Salvar'),
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
        cliques: _int(cliques.text),
        leads: _int(leads.text),
      );
      await _carregar();
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
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: campanhaId,
                    decoration: const InputDecoration(labelText: 'Campanha'),
                    items: _campanhas.map((item) {
                      return DropdownMenuItem<String>(
                        value: item['id'].toString(),
                        child: Text((item['nome'] ?? 'Campanha').toString()),
                      );
                    }).toList(),
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
                      return DropdownMenuItem<String>(
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
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Atribuir'),
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

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing'),
        actions: [
          IconButton(
            tooltip: 'Atribuir venda',
            onPressed: _atribuirResultado,
            icon: const Icon(Icons.link_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarCampanha(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Campanha'),
      ),
      body: _carregando && resumo == null
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && resumo == null
          ? Center(child: Text(_erro!))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
                children: [
                  const _MetaStatusCard(),
                  const SizedBox(height: 12),
                  _resumoCards(resumo!),
                  const SizedBox(height: 16),
                  const Text(
                    'Campanhas',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_campanhas.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhuma campanha cadastrada. Crie a primeira para começar a medir aquisição e retorno.',
                        ),
                      ),
                    )
                  else
                    ..._campanhas.map(_campanhaCard),
                ],
              ),
            ),
    );
  }

  Widget _resumoCards(GrowthMarketingResumo resumo) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetricaMarketing(
          'Investido',
          _moeda.format(resumo.investimento),
          Icons.payments_outlined,
        ),
        _MetricaMarketing(
          'Faturamento',
          _moeda.format(resumo.faturamentoAtribuido),
          Icons.trending_up_rounded,
        ),
        _MetricaMarketing(
          'ROAS',
          resumo.roas <= 0 ? '—' : '${resumo.roas.toStringAsFixed(2)}x',
          Icons.analytics_outlined,
        ),
        _MetricaMarketing(
          'Vendas atribuídas',
          '${resumo.ordens}',
          Icons.receipt_long_outlined,
        ),
      ],
    );
  }

  Widget _campanhaCard(Map<String, dynamic> item) {
    final investimento = _double(item['investimento']);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.campaign_outlined),
        ),
        title: Text((item['nome'] ?? 'Campanha').toString()),
        subtitle: Text(
          [
            (item['plataforma'] ?? '').toString(),
            (item['tipo'] ?? '').toString(),
            (item['status'] ?? '').toString(),
            if (investimento > 0) _moeda.format(investimento),
            '${_int(item['leads'])} leads',
          ].where((e) => e.trim().isNotEmpty).join(' · '),
        ),
        trailing: IconButton(
          tooltip: 'Editar',
          onPressed: () => _editarCampanha(item),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
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
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}

class _MetaStatusCard extends StatelessWidget {
  const _MetaStatusCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(Icons.hub_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Marketing e atribuição ativos',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Instagram/Facebook serão conectados pelo backend. Até lá, investimento e métricas podem ser informados manualmente.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            Chip(label: Text('Manual')),
          ],
        ),
      ),
    );
  }
}

class _MetricaMarketing extends StatelessWidget {
  const _MetricaMarketing(this.titulo, this.valor, this.icone);

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 165,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 20),
              const SizedBox(height: 9),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                titulo,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
