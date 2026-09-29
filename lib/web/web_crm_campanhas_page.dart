import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_expansao_service.dart';
import 'imperium_web_theme.dart';

class WebCrmCampanhasPage extends StatefulWidget {
  const WebCrmCampanhasPage({super.key});

  @override
  State<WebCrmCampanhasPage> createState() => _WebCrmCampanhasPageState();
}

class _WebCrmCampanhasPageState extends State<WebCrmCampanhasPage> {
  final _service = WebCloudExpansaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _gerando = false;
  String? _erro;
  List<Map<String, dynamic>> _campanhas = const [];
  List<Map<String, dynamic>> _cupons = const [];

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
      final dados = await Future.wait([
        _service.listarCampanhas(),
        _service.listarCuponsDetalhados(),
      ]);

      if (!mounted) return;
      setState(() {
        _campanhas = dados[0];
        _cupons = dados[1];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editarCampanha([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: (atual?['nome'] ?? '').toString());
    final beneficioValor = TextEditingController(
      text: _double(atual?['beneficio_valor']).toStringAsFixed(2),
    );
    final beneficioDescricao = TextEditingController(
      text: (atual?['beneficio_descricao'] ?? '').toString(),
    );
    final valorMinimo = TextEditingController(
      text: _double(atual?['valor_minimo']).toStringAsFixed(2),
    );
    final diasValidade = TextEditingController(
      text: ((atual?['dias_validade'] as num?)?.toInt() ?? 30).toString(),
    );
    final diasSemRetorno = TextEditingController(
      text: ((atual?['dias_sem_retorno'] as num?)?.toInt() ?? 180).toString(),
    );

    const tipos = <String>['Aniversário', 'Reativação', 'Indicação', 'Manual'];
    const beneficios = <String>['Percentual', 'Valor', 'Serviço', 'Crédito'];

    var tipo = (atual?['tipo'] ?? 'Manual').toString();
    if (!tipos.contains(tipo)) tipo = 'Manual';

    var beneficioTipo = (atual?['beneficio_tipo'] ?? 'Percentual').toString();
    if (!beneficios.contains(beneficioTipo)) beneficioTipo = 'Percentual';

    var ativo = atual?['ativo'] != false;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Nova campanha' : 'Editar campanha'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    autofocus: atual == null,
                    decoration: const InputDecoration(
                      labelText: 'Nome da campanha *',
                      prefixIcon: Icon(Icons.campaign_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: tipo,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tipo *',
                          ),
                          items: tipos
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: beneficioTipo,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Benefício *',
                          ),
                          items: beneficios
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setLocal(() => beneficioTipo = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: beneficioValor,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: beneficioTipo == 'Percentual'
                                ? 'Percentual do benefício'
                                : 'Valor do benefício',
                            prefixIcon: Icon(
                              beneficioTipo == 'Percentual'
                                  ? Icons.percent_rounded
                                  : Icons.payments_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: valorMinimo,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor mínimo da OS',
                            prefixIcon: Icon(Icons.price_check_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: beneficioDescricao,
                    decoration: const InputDecoration(
                      labelText: 'Descrição do benefício',
                      hintText: 'Ex.: 10% de desconto ou lavagem cortesia',
                      prefixIcon: Icon(Icons.redeem_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: diasValidade,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Validade (dias) *',
                            prefixIcon: Icon(Icons.event_outlined),
                          ),
                        ),
                      ),
                      if (tipo == 'Reativação') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: diasSemRetorno,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cliente sem retornar há (dias)',
                              prefixIcon: Icon(Icons.history_toggle_off),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    value: ativo,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Campanha ativa'),
                    subtitle: const Text(
                      'Campanhas inativas permanecem no histórico e não geram benefícios.',
                    ),
                    onChanged: (v) => setLocal(() => ativo = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (nome.text.trim().length < 3) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Informe o nome da campanha.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar campanha'),
            ),
          ],
        ),
      ),
    );

    if (salvar != true || !mounted) {
      nome.dispose();
      beneficioValor.dispose();
      beneficioDescricao.dispose();
      valorMinimo.dispose();
      diasValidade.dispose();
      diasSemRetorno.dispose();
      return;
    }

    try {
      await _service.salvarCampanha(
        id: atual?['id']?.toString(),
        atualizadoEmEsperado: atual?['atualizado_em']?.toString(),
        nome: nome.text,
        tipo: tipo,
        beneficioTipo: beneficioTipo,
        beneficioValor: _double(beneficioValor.text),
        beneficioDescricao: beneficioDescricao.text,
        valorMinimo: _double(valorMinimo.text),
        diasValidade: int.tryParse(diasValidade.text.trim()) ?? 30,
        diasSemRetorno: int.tryParse(diasSemRetorno.text.trim()) ?? 180,
        ativo: ativo,
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    } finally {
      nome.dispose();
      beneficioValor.dispose();
      beneficioDescricao.dispose();
      valorMinimo.dispose();
      diasValidade.dispose();
      diasSemRetorno.dispose();
    }
  }

  Future<void> _alternarCampanha(Map<String, dynamic> campanha) async {
    try {
      await _service.salvarCampanha(
        id: campanha['id'].toString(),
        atualizadoEmEsperado: (campanha['atualizado_em'] ?? '').toString(),
        nome: (campanha['nome'] ?? '').toString(),
        tipo: (campanha['tipo'] ?? 'Manual').toString(),
        beneficioTipo: (campanha['beneficio_tipo'] ?? 'Percentual').toString(),
        beneficioValor: _double(campanha['beneficio_valor']),
        beneficioDescricao: (campanha['beneficio_descricao'] ?? '').toString(),
        valorMinimo: _double(campanha['valor_minimo']),
        diasValidade: (campanha['dias_validade'] as num?)?.toInt() ?? 30,
        diasSemRetorno: (campanha['dias_sem_retorno'] as num?)?.toInt() ?? 180,
        ativo: campanha['ativo'] == false,
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    }
  }

  Future<void> _gerarBeneficios() async {
    if (_gerando) return;
    setState(() => _gerando = true);

    try {
      final resultado = await _service.gerarBeneficiosCrm();
      if (!mounted) return;

      final aniversario = (resultado['aniversario'] as num?)?.toInt() ?? 0;
      final reativacao = (resultado['reativacao'] as num?)?.toInt() ?? 0;
      final expirados = (resultado['expirados'] as num?)?.toInt() ?? 0;

      _snack(
        'Benefícios gerados: ${aniversario + reativacao} '
        '(aniversário: $aniversario, reativação: $reativacao). '
        'Cupons expirados: $expirados.',
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  Future<void> _cancelarCupom(Map<String, dynamic> cupom) async {
    if ((cupom['status'] ?? '').toString() != 'Ativo') return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar benefício?'),
        content: Text(
          'O cupom ${(cupom['codigo'] ?? '').toString()} ficará cancelado '
          'e não poderá ser utilizado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar benefício'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      await _service.cancelarCupom(
        id: cupom['id'].toString(),
        atualizadoEmEsperado: (cupom['atualizado_em'] ?? '').toString(),
      );
      await _carregar();
    } catch (e) {
      _snack(e.toString(), erro: true);
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

  String _beneficio(Map<String, dynamic> campanha) {
    final tipo = (campanha['beneficio_tipo'] ?? '').toString();
    final valor = _double(campanha['beneficio_valor']);
    final descricao = (campanha['beneficio_descricao'] ?? '').toString().trim();

    if (tipo == 'Percentual') return '${valor.toStringAsFixed(1)}%';
    if (tipo == 'Valor' || tipo == 'Crédito') return _moeda.format(valor);
    return descricao.isEmpty ? 'Serviço' : descricao;
  }

  String _beneficioCupom(Map<String, dynamic> cupom) {
    final tipo = (cupom['beneficio_tipo'] ?? '').toString();
    final valor = _double(cupom['beneficio_valor']);
    final descricao = (cupom['beneficio_descricao'] ?? '').toString().trim();

    if (tipo == 'Percentual') return '${valor.toStringAsFixed(1)}%';
    if (tipo == 'Valor' || tipo == 'Crédito') return _moeda.format(valor);
    return descricao.isEmpty ? tipo : descricao;
  }

  Widget _campanhasTab() {
    if (_campanhas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nenhuma campanha cadastrada.'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      itemCount: _campanhas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final campanha = _campanhas[index];
        final ativa = campanha['ativo'] != false;
        final tipo = (campanha['tipo'] ?? 'Manual').toString();

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            leading: CircleAvatar(
              backgroundColor: ativa
                  ? ImperiumWebTheme.accentStrong.withValues(alpha: 0.12)
                  : null,
              child: Icon(
                tipo == 'Aniversário'
                    ? Icons.cake_outlined
                    : tipo == 'Reativação'
                    ? Icons.replay_outlined
                    : Icons.campaign_outlined,
                color: ativa ? ImperiumWebTheme.accentStrong : null,
              ),
            ),
            title: Text(
              (campanha['nome'] ?? 'Campanha').toString(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                tipo,
                '${campanha['beneficio_tipo'] ?? 'Benefício'}: ${_beneficio(campanha)}',
                '${campanha['dias_validade'] ?? 30} dias',
                if (!ativa) 'Inativa',
              ].join(' · '),
            ),
            trailing: Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'Editar campanha',
                  onPressed: () => _editarCampanha(campanha),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: ativa ? 'Desativar campanha' : 'Ativar campanha',
                  onPressed: () => _alternarCampanha(campanha),
                  icon: Icon(
                    ativa
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cuponsTab() {
    if (_cupons.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nenhum benefício gerado.'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      itemCount: _cupons.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cupom = _cupons[index];
        final status = (cupom['status'] ?? 'Ativo').toString();

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            leading: CircleAvatar(
              child: Icon(
                status == 'Ativo'
                    ? Icons.redeem_outlined
                    : status == 'Usado'
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
              ),
            ),
            title: Text(
              (cupom['codigo'] ?? 'Cupom').toString(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                (cupom['cliente_nome'] ?? 'Cliente').toString(),
                (cupom['campanha_nome'] ?? 'Campanha').toString(),
                _beneficioCupom(cupom),
                'Até ${cupom['validade_fim'] ?? '—'}',
                status,
              ].join(' · '),
            ),
            trailing: status == 'Ativo'
                ? IconButton(
                    tooltip: 'Cancelar benefício',
                    onPressed: () => _cancelarCupom(cupom),
                    icon: const Icon(Icons.cancel_outlined),
                  )
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ativas = _campanhas.where((e) => e['ativo'] != false).length;
    final cuponsAtivos = _cupons
        .where((e) => (e['status'] ?? '').toString() == 'Ativo')
        .length;

    return Scaffold(
      backgroundColor: ImperiumWebTheme.background,
      appBar: AppBar(
        title: const Text('Campanhas e benefícios'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _erro!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 760;
                final padding = compacto ? 16.0 : 24.0;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ImperiumWebTheme.contentMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padding, 18, padding, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _editarCampanha(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Nova campanha'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _gerando ? null : _gerarBeneficios,
                                icon: _gerando
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome_outlined),
                                label: Text(
                                  _gerando
                                      ? 'Gerando...'
                                      : 'Gerar benefícios agora',
                                ),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.campaign_outlined,
                                  size: 17,
                                ),
                                label: Text('$ativas campanha(s) ativa(s)'),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.redeem_outlined,
                                  size: 17,
                                ),
                                label: Text('$cuponsAtivos cupom(ns) ativo(s)'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  const TabBar(
                                    tabs: [
                                      Tab(
                                        icon: Icon(Icons.campaign_outlined),
                                        text: 'Campanhas',
                                      ),
                                      Tab(
                                        icon: Icon(Icons.redeem_outlined),
                                        text: 'Cupons e benefícios',
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      children: [_campanhasTab(), _cuponsTab()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
