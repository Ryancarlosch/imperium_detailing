import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_ponto_service.dart';
import 'imperium_web_theme.dart';

class WebPontoPage extends StatefulWidget {
  const WebPontoPage({super.key});

  @override
  State<WebPontoPage> createState() => _WebPontoPageState();
}

class _WebPontoPageState extends State<WebPontoPage>
    with SingleTickerProviderStateMixin {
  final _service = WebCloudPontoService.instance;
  final _dataBr = DateFormat('dd/MM/yyyy', 'pt_BR');
  late final TabController _tabs;

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _colaboradores = const [];
  List<Map<String, dynamic>> _registros = const [];
  List<Map<String, dynamic>> _jornada = const [];
  List<Map<String, dynamic>> _solicitacoesAjuste = const [];
  String _statusSolicitacoes = 'Pendente';
  Map<String, dynamic> _config = const {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final agora = DateTime.now();
      final inicio = DateTime(agora.year, agora.month, 1);
      final fim = DateTime(agora.year, agora.month + 1, 0);
      final dados = await Future.wait<dynamic>([
        _service.listarColaboradores(),
        _service.listarRegistros(inicio: inicio, fim: fim),
        _service.listarJornada(),
        _service.obterConfig(),
        _service.listarSolicitacoesAjusteAdmin(
          status: _statusSolicitacoes,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _colaboradores = dados[0] as List<Map<String, dynamic>>;
        _registros = dados[1] as List<Map<String, dynamic>>;
        _jornada = dados[2] as List<Map<String, dynamic>>;
        _config = dados[3] as Map<String, dynamic>;
        _solicitacoesAjuste = dados[4] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _vincular(Map<String, dynamic> colaborador) async {
    final email = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Vincular acesso · ${colaborador['nome'] ?? ''}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informe o e-mail Supabase do funcionário. O vínculo respeita a empresa ativa e as regras de acesso do Ponto.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail do funcionário',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
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
            child: const Text('Vincular'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;
    try {
      await _service.vincularUsuario(
        colaboradorId: colaborador['id'].toString(),
        email: email.text,
      );
      await _carregar();
      _snack('Acesso do funcionário vinculado.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _editarRegistro(
    Map<String, dynamic> colaborador,
    Map<String, dynamic>? atual,
  ) async {
    var data = atual == null
        ? DateTime.now()
        : DateTime.tryParse('${atual['data']}') ?? DateTime.now();
    var situacao = (atual?['situacao'] ?? 'Trabalhado').toString();
    final entrada = TextEditingController(text: _hora(atual?['entrada']));
    final intervaloInicio = TextEditingController(
      text: _hora(atual?['intervalo_inicio']),
    );
    final intervaloFim = TextEditingController(
      text: _hora(atual?['intervalo_fim']),
    );
    final saida = TextEditingController(text: _hora(atual?['saida']));
    final observacoes = TextEditingController(
      text: (atual?['observacoes'] ?? '').toString(),
    );
    final motivo = TextEditingController();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Ponto · ${colaborador['nome'] ?? ''}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Data'),
                    subtitle: Text(_dataBr.format(data)),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final escolhida = await showDatePicker(
                          context: context,
                          initialDate: data,
                          firstDate: DateTime(DateTime.now().year - 1),
                          lastDate: DateTime(DateTime.now().year + 1),
                        );
                        if (escolhida != null) setLocal(() => data = escolhida);
                      },
                      child: const Text('Alterar'),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: situacao,
                    decoration: const InputDecoration(labelText: 'Situação'),
                    items:
                        const [
                              'Trabalhado',
                              'Folga',
                              'Falta',
                              'Atestado',
                              'Férias',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => situacao = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _campoHora(entrada, 'Entrada')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _campoHora(intervaloInicio, 'Início intervalo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _campoHora(intervaloFim, 'Fim intervalo'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _campoHora(saida, 'Saída')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: observacoes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Observações'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: motivo,
                    decoration: const InputDecoration(
                      labelText: 'Motivo do ajuste',
                      hintText: 'Obrigatório para auditoria quando necessário',
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
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar ponto'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true) return;
    try {
      await _service.salvarRegistroAdmin(
        colaboradorId: colaborador['id'].toString(),
        data: data,
        situacao: situacao,
        entrada: entrada.text,
        intervaloInicio: intervaloInicio.text,
        intervaloFim: intervaloFim.text,
        saida: saida.text,
        observacoes: observacoes.text,
        motivo: motivo.text,
      );
      await _carregar();
      _snack('Registro de ponto salvo.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Widget _campoHora(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: '08:00'),
    );
  }

  Future<void> _editarJornada(Map<String, dynamic> atual) async {
    var ativo = atual['ativo'] == true;
    final entrada = TextEditingController(text: _hora(atual['entrada']));
    final intervaloInicio = TextEditingController(
      text: _hora(atual['intervalo_inicio']),
    );
    final intervaloFim = TextEditingController(
      text: _hora(atual['intervalo_fim']),
    );
    final saida = TextEditingController(text: _hora(atual['saida']));

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_nomeDia(_int(atual['dia_semana']))),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dia de trabalho'),
                  value: ativo,
                  onChanged: (v) => setLocal(() => ativo = v),
                ),
                if (ativo) ...[
                  Row(
                    children: [
                      Expanded(child: _campoHora(entrada, 'Entrada')),
                      const SizedBox(width: 10),
                      Expanded(child: _campoHora(saida, 'Saída')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _campoHora(intervaloInicio, 'Início intervalo'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _campoHora(intervaloFim, 'Fim intervalo'),
                      ),
                    ],
                  ),
                ],
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
              child: const Text('Salvar jornada'),
            ),
          ],
        ),
      ),
    );

    if (confirmou != true) return;
    try {
      await _service.salvarJornada(
        diaSemana: _int(atual['dia_semana']),
        ativo: ativo,
        entrada: entrada.text,
        intervaloInicio: intervaloInicio.text,
        intervaloFim: intervaloFim.text,
        saida: saida.text,
      );
      await _carregar();
      _snack('Jornada atualizada.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Future<void> _editarHoraExtra() async {
    final controller = TextEditingController(
      text: _double(_config['adicional_hora_extra'], 50).toStringAsFixed(0),
    );
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicional de hora extra'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Percentual',
              suffixText: '%',
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
      await _service.salvarConfig(_double(controller.text, 50));
      await _carregar();
      _snack('Adicional de hora extra atualizado.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ponto e funcionários',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Equipe, registros de jornada, acessos e configurações do ponto.',
                      style: TextStyle(color: Color(0xFFAAB3BD)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.groups_2_outlined), text: 'Equipe e ponto'),
              Tab(icon: Icon(Icons.schedule_outlined), text: 'Jornada'),
              Tab(
                icon: Icon(Icons.rule_folder_outlined),
                text: 'Solicitações',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
              ? _erroView()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _equipeView(),
                    _jornadaView(),
                    _solicitacoesView(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _erroView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                Text(_erro!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _equipeView() {
    final agora = DateTime.now();
    final hoje = _data(agora);
    final ativos = _colaboradores.where((e) => e['ativo'] != false).toList();
    final registrosHoje = _registros
        .where((e) => '${e['data']}' == hoje)
        .toList();
    final vinculados = ativos
        .where((e) => '${e['auth_user_id'] ?? ''}'.isNotEmpty)
        .length;
    final completos = registrosHoje
        .where((e) => _hora(e['saida']).isNotEmpty)
        .length;
    final nomes = {
      for (final c in _colaboradores) '${c['id']}': '${c['nome']}',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 980;
        final larguraDisponivel = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        final larguraCard =
            (larguraDisponivel - (12 * (colunas - 1))) / colunas;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            compacto ? 16 : 24,
            20,
            compacto ? 16 : 24,
            40,
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ResumoCard(
                  'Funcionários ativos',
                  '${ativos.length}',
                  Icons.groups_2_outlined,
                  width: larguraCard,
                ),
                _ResumoCard(
                  'Batidas hoje',
                  '${registrosHoje.length}',
                  Icons.fingerprint_rounded,
                  width: larguraCard,
                ),
                _ResumoCard(
                  'Jornada concluída',
                  '$completos',
                  Icons.task_alt_rounded,
                  width: larguraCard,
                ),
                _ResumoCard(
                  'Acessos vinculados',
                  '$vinculados',
                  Icons.verified_user_outlined,
                  width: larguraCard,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Funcionários',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${ativos.length} ativo(s)',
                  style: const TextStyle(
                    color: Color(0xFF89939E),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ativos.isEmpty)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('Nenhum funcionário ativo cadastrado.'),
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
                    dataRowMinHeight: 62,
                    dataRowMaxHeight: 78,
                    columns: const [
                      DataColumn(label: Text('FUNCIONÁRIO')),
                      DataColumn(label: Text('FUNÇÃO')),
                      DataColumn(label: Text('PONTO HOJE')),
                      DataColumn(label: Text('SITUAÇÃO')),
                      DataColumn(label: Text('ACESSO')),
                      DataColumn(label: Text('AÇÕES')),
                    ],
                    rows: ativos.map((colaborador) {
                      final registro = _primeiroOuNulo(
                        registrosHoje.where(
                          (r) =>
                              '${r['colaborador_id']}' ==
                              '${colaborador['id']}',
                        ),
                      );
                      final vinculado =
                          '${colaborador['auth_user_id'] ?? ''}'.isNotEmpty;

                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 230,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 17,
                                    backgroundColor: ImperiumWebTheme
                                        .accentStrong
                                        .withValues(alpha: 0.10),
                                    child: const Icon(
                                      Icons.person_outline_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${colaborador['nome'] ?? 'Funcionário'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 150,
                              child: Text('${colaborador['funcao'] ?? '—'}'),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 210,
                              child: Text(
                                registro == null
                                    ? 'Sem registro hoje'
                                    : _resumoRegistro(registro),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              registro == null
                                  ? '—'
                                  : '${registro['situacao'] ?? '—'}',
                            ),
                          ),
                          DataCell(
                            Chip(
                              avatar: Icon(
                                vinculado
                                    ? Icons.verified_user_rounded
                                    : Icons.person_off_outlined,
                                size: 16,
                              ),
                              label: Text(
                                vinculado ? 'Vinculado' : 'Sem login',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          DataCell(
                            Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: 'Editar ponto de hoje',
                                  onPressed: () =>
                                      _editarRegistro(colaborador, registro),
                                  icon: const Icon(
                                    Icons.edit_calendar_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Vincular login',
                                  onPressed: () => _vincular(colaborador),
                                  icon: Icon(
                                    vinculado
                                        ? Icons.verified_user_rounded
                                        : Icons.person_add_alt_1_rounded,
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
              ...ativos.map((colaborador) {
                final registro = _primeiroOuNulo(
                  registrosHoje.where(
                    (r) => '${r['colaborador_id']}' == '${colaborador['id']}',
                  ),
                );
                final vinculado =
                    '${colaborador['auth_user_id'] ?? ''}'.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: ImperiumWebTheme.accentStrong
                            .withValues(alpha: 0.10),
                        child: const Icon(Icons.person_outline_rounded),
                      ),
                      title: Text(
                        '${colaborador['nome'] ?? 'Funcionário'}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        [
                          '${colaborador['funcao'] ?? ''}',
                          registro == null
                              ? 'Sem registro hoje'
                              : _resumoRegistro(registro),
                          vinculado ? 'Login vinculado' : 'Sem login',
                        ].where((e) => e.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (acao) {
                          if (acao == 'ponto') {
                            _editarRegistro(colaborador, registro);
                          } else if (acao == 'acesso') {
                            _vincular(colaborador);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'ponto',
                            child: Text('Editar ponto'),
                          ),
                          PopupMenuItem(
                            value: 'acesso',
                            child: Text('Vincular acesso'),
                          ),
                        ],
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
                    'Registros do mês',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${_registros.length} registro(s)',
                  style: const TextStyle(
                    color: Color(0xFF89939E),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_registros.isEmpty)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('Nenhum registro no mês atual.'),
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
                      DataColumn(label: Text('FUNCIONÁRIO')),
                      DataColumn(label: Text('ENTRADA')),
                      DataColumn(label: Text('INTERVALO')),
                      DataColumn(label: Text('SAÍDA')),
                      DataColumn(label: Text('SITUAÇÃO')),
                    ],
                    rows: _registros.take(120).map((registro) {
                      final inicio = _hora(registro['intervalo_inicio']);
                      final fim = _hora(registro['intervalo_fim']);
                      return DataRow(
                        cells: [
                          DataCell(Text(_dataExibicao('${registro['data']}'))),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                nomes['${registro['colaborador_id']}'] ??
                                    'Funcionário',
                              ),
                            ),
                          ),
                          DataCell(Text(_hora(registro['entrada']))),
                          DataCell(
                            Text(
                              inicio.isEmpty && fim.isEmpty
                                  ? '—'
                                  : '$inicio – $fim',
                            ),
                          ),
                          DataCell(Text(_hora(registro['saida']))),
                          DataCell(Text('${registro['situacao'] ?? '—'}')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              )
            else
              ..._registros
                  .take(60)
                  .map(
                    (registro) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.schedule_rounded),
                          title: Text(
                            '${nomes['${registro['colaborador_id']}'] ?? 'Funcionário'} · '
                            '${_dataExibicao('${registro['data']}')}',
                          ),
                          subtitle: Text(_resumoRegistro(registro)),
                          trailing: Text('${registro['situacao'] ?? ''}'),
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }

  Future<void> _decidirSolicitacao(
    Map<String, dynamic> solicitacao, {
    required bool aprovar,
  }) async {
    final motivo = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          aprovar ? 'Aprovar solicitação?' : 'Rejeitar solicitação?',
        ),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: motivo,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: aprovar
                  ? 'Observação da aprovação'
                  : 'Motivo da rejeição *',
              helperText: aprovar
                  ? 'Opcional. O pedido do funcionário ficará preservado no histórico.'
                  : 'Obrigatório, com pelo menos 5 caracteres.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!aprovar && motivo.text.trim().length < 5) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Informe o motivo da rejeição com pelo menos 5 caracteres.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(aprovar ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );

    if (confirmou != true) {
      motivo.dispose();
      return;
    }

    final textoMotivo = motivo.text;
    motivo.dispose();

    try {
      await _service.decidirSolicitacaoAjuste(
        solicitacaoId: (solicitacao['id'] ?? '').toString(),
        aprovar: aprovar,
        motivo: textoMotivo,
      );
      await _carregar();
      _snack(
        aprovar
            ? 'Solicitação aprovada e ponto atualizado.'
            : 'Solicitação rejeitada.',
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  Widget _solicitacoesView() {
    final pendentes = _solicitacoesAjuste
        .where((e) => (e['status'] ?? '').toString() == 'Pendente')
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 680,
              child: _cabecalho(
                'Solicitações de ajuste',
                'Pedidos enviados pelos funcionários para corrigir o ponto. '
                    'A aprovação atualiza o registro usando a mesma regra do Android.',
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _statusSolicitacoes,
                decoration: const InputDecoration(labelText: 'Exibir'),
                items: const [
                  DropdownMenuItem(
                    value: 'Pendente',
                    child: Text('Pendentes'),
                  ),
                  DropdownMenuItem(
                    value: 'Aprovada',
                    child: Text('Aprovadas'),
                  ),
                  DropdownMenuItem(
                    value: 'Rejeitada',
                    child: Text('Rejeitadas'),
                  ),
                  DropdownMenuItem(
                    value: 'Cancelada',
                    child: Text('Canceladas'),
                  ),
                  DropdownMenuItem(value: 'Todos', child: Text('Todas')),
                ],
                onChanged: (valor) {
                  if (valor == null || valor == _statusSolicitacoes) return;
                  setState(() => _statusSolicitacoes = valor);
                  _carregar();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(
              _statusSolicitacoes == 'Pendente'
                  ? '$pendentes solicitação(ões) pendente(s)'
                  : '${_solicitacoesAjuste.length} registro(s)',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'As decisões ficam registradas no histórico do Ponto.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_solicitacoesAjuste.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma solicitação encontrada neste filtro.'),
            ),
          )
        else
          ..._solicitacoesAjuste.map((item) {
            final status = (item['status'] ?? 'Pendente').toString();
            final atualRaw = item['registro_atual_json'];
            final atual = atualRaw is Map
                ? Map<String, dynamic>.from(atualRaw)
                : const <String, dynamic>{};
            final solicitado = [
              (item['situacao_solicitada'] ?? '').toString(),
              if (_hora(item['entrada_solicitada']).isNotEmpty)
                'Entrada ${_hora(item['entrada_solicitada'])}',
              if (_hora(item['intervalo_inicio_solicitado']).isNotEmpty)
                'Intervalo ${_hora(item['intervalo_inicio_solicitado'])}'
                    '–${_hora(item['intervalo_fim_solicitado'])}',
              if (_hora(item['saida_solicitada']).isNotEmpty)
                'Saída ${_hora(item['saida_solicitada'])}',
            ].where((e) => e.trim().isNotEmpty).join(' · ');

            final atualTexto = atual.isEmpty
                ? 'Sem registro anterior'
                : [
                    (atual['situacao'] ?? '').toString(),
                    if (_hora(atual['entrada']).isNotEmpty)
                      'Entrada ${_hora(atual['entrada'])}',
                    if (_hora(atual['intervalo_inicio']).isNotEmpty)
                      'Intervalo ${_hora(atual['intervalo_inicio'])}'
                          '–${_hora(atual['intervalo_fim'])}',
                    if (_hora(atual['saida']).isNotEmpty)
                      'Saída ${_hora(atual['saida'])}',
                  ].where((e) => e.trim().isNotEmpty).join(' · ');

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 540,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['colaborador_nome'] ?? 'Funcionário')
                                    .toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                [
                                  (item['colaborador_funcao'] ?? '').toString(),
                                  _dataExibicao(
                                    (item['data'] ?? '').toString(),
                                  ),
                                  status,
                                ].where((e) => e.trim().isNotEmpty).join(' · '),
                                style: const TextStyle(
                                  color: Color(0xFF89939E),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (status == 'Pendente')
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _decidirSolicitacao(
                                  item,
                                  aprovar: false,
                                ),
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Rejeitar'),
                              ),
                              FilledButton.icon(
                                onPressed: () => _decidirSolicitacao(
                                  item,
                                  aprovar: true,
                                ),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Aprovar'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      'Motivo do funcionário',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text((item['motivo'] ?? 'Sem motivo informado').toString()),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 420,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Registro atual',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(atualTexto),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 420,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Solicitado',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(solicitado),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if ((item['observacoes_solicitadas'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Observação solicitada: '
                        '${item['observacoes_solicitadas']}',
                      ),
                    ],
                    if ((item['decisao_motivo'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Decisão: ${item['decisao_motivo']}',
                        style: const TextStyle(color: Color(0xFF89939E)),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _jornadaView() {
    final adicional = _double(_config['adicional_hora_extra'], 50);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _cabecalho(
          'Jornada da empresa',
          'A mesma configuração usada pelo aplicativo e pelo cálculo do ponto.',
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.more_time_rounded),
            title: const Text('Adicional de hora extra'),
            subtitle: const Text('Percentual aplicado sobre a hora normal.'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${adicional.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _editarHoraExtra,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._jornada.map((dia) {
          final ativo = dia['ativo'] == true;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: Icon(
                ativo
                    ? Icons.event_available_rounded
                    : Icons.event_busy_outlined,
              ),
              title: Text(
                _nomeDia(_int(dia['dia_semana'])),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                ativo
                    ? '${_hora(dia['entrada'])} — ${_hora(dia['intervalo_inicio'])} / ${_hora(dia['intervalo_fim'])} — ${_hora(dia['saida'])}'
                    : 'Sem expediente',
              ),
              trailing: IconButton(
                tooltip: 'Editar jornada',
                onPressed: () => _editarJornada(dia),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _cabecalho(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          subtitulo,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFAAB3BD)),
        ),
      ],
    );
  }

  void _snack(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  static String _textoErro(Object e) {
    var texto = e.toString();
    for (final prefixo in const [
      'PostgrestException: ',
      'StateError: ',
      'Bad state: ',
      'ArgumentError: ',
    ]) {
      if (texto.startsWith(prefixo)) texto = texto.substring(prefixo.length);
    }
    return texto.trim();
  }

  static String _data(DateTime data) =>
      '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';

  String _dataExibicao(String valor) {
    final data = DateTime.tryParse(valor);
    return data == null ? valor : _dataBr.format(data);
  }

  static String _hora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.length >= 5) return texto.substring(0, 5);
    return texto;
  }

  static String _resumoRegistro(Map<String, dynamic> registro) {
    final partes = <String>[];
    final entrada = _hora(registro['entrada']);
    final saida = _hora(registro['saida']);
    if (entrada.isNotEmpty) partes.add('Entrada $entrada');
    if (saida.isNotEmpty) partes.add('Saída $saida');
    if (partes.isEmpty) partes.add('${registro['situacao'] ?? 'Sem horários'}');
    return partes.join(' · ');
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor, [double fallback = 0]) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ??
        fallback;
  }

  static String _nomeDia(int dia) {
    return switch (dia) {
      1 => 'Segunda-feira',
      2 => 'Terça-feira',
      3 => 'Quarta-feira',
      4 => 'Quinta-feira',
      5 => 'Sexta-feira',
      6 => 'Sábado',
      7 => 'Domingo',
      _ => 'Dia $dia',
    };
  }

  static Map<String, dynamic>? _primeiroOuNulo(
    Iterable<Map<String, dynamic>> itens,
  ) {
    for (final item in itens) {
      return item;
    }
    return null;
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard(this.label, this.valor, this.icon, {this.width = 230});

  final String label;
  final String valor;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ImperiumWebTheme.accentStrong),
              const SizedBox(height: 14),
              Text(label),
              const SizedBox(height: 4),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
