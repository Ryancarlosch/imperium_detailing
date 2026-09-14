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
  Map<String, dynamic> _config = const {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
      ]);

      if (!mounted) return;
      setState(() {
        _colaboradores = dados[0] as List<Map<String, dynamic>>;
        _registros = dados[1] as List<Map<String, dynamic>>;
        _jornada = dados[2] as List<Map<String, dynamic>>;
        _config = dados[3] as Map<String, dynamic>;
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
                    items: const [
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ponto e funcionários'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.groups_2_outlined), text: 'Equipe e ponto'),
            Tab(icon: Icon(Icons.schedule_outlined), text: 'Jornada'),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? _erroView()
          : TabBarView(
              controller: _tabs,
              children: [_equipeView(), _jornadaView()],
            ),
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
    final registrosHoje = _registros.where((e) => '${e['data']}' == hoje).toList();
    final vinculados = ativos.where((e) => '${e['auth_user_id'] ?? ''}'.isNotEmpty).length;
    final completos = registrosHoje.where((e) => _hora(e['saida']).isNotEmpty).length;
    final nomes = {for (final c in _colaboradores) '${c['id']}': '${c['nome']}'};

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _cabecalho(
          'Equipe e ponto',
          'Acompanhe as batidas da nuvem e faça correções administrativas com auditoria.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ResumoCard('Funcionários ativos', '${ativos.length}', Icons.groups_2_outlined),
            _ResumoCard('Batidas hoje', '${registrosHoje.length}', Icons.fingerprint_rounded),
            _ResumoCard('Jornada concluída', '$completos', Icons.task_alt_rounded),
            _ResumoCard('Acessos vinculados', '$vinculados', Icons.verified_user_outlined),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Funcionários',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...ativos.map((colaborador) {
          final registro = _primeiroOuNulo(
            registrosHoje.where(
              (r) => '${r['colaborador_id']}' == '${colaborador['id']}',
            ),
          );
          final vinculado = '${colaborador['auth_user_id'] ?? ''}'.isNotEmpty;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                child: const Icon(Icons.person_outline_rounded),
              ),
              title: Text(
                '${colaborador['nome'] ?? 'Funcionário'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  '${colaborador['funcao'] ?? ''}',
                  registro == null ? 'Sem registro hoje' : _resumoRegistro(registro),
                  vinculado ? 'Login vinculado' : 'Sem login vinculado',
                ].where((e) => e.trim().isNotEmpty).join(' · '),
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Editar ponto de hoje',
                    onPressed: () => _editarRegistro(colaborador, registro),
                    icon: const Icon(Icons.edit_calendar_outlined),
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
          );
        }),
        const SizedBox(height: 24),
        const Text(
          'Registros do mês',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._registros.take(60).map(
          (registro) => Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(
                '${nomes['${registro['colaborador_id']}'] ?? 'Funcionário'} · ${_dataExibicao('${registro['data']}')}',
              ),
              subtitle: Text(_resumoRegistro(registro)),
              trailing: Text('${registro['situacao'] ?? ''}'),
            ),
          ),
        ),
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              leading: Icon(ativo ? Icons.event_available_rounded : Icons.event_busy_outlined),
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
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitulo,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFAAB3BD),
          ),
        ),
      ],
    );
  }

  void _snack(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Theme.of(context).colorScheme.errorContainer : null,
      ),
    );
  }

  static String _textoErro(Object e) {
    var texto = e.toString();
    for (final prefixo in const ['PostgrestException: ', 'StateError: ', 'Bad state: ', 'ArgumentError: ']) {
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
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? fallback;
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
  const _ResumoCard(this.label, this.valor, this.icon);

  final String label;
  final String valor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
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
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
