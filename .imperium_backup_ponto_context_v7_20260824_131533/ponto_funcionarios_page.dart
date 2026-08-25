import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/ponto_repository.dart';
import '../repositories/ponto_sincronizado_repository.dart';
import 'funcionarios_resumo_page.dart';
import 'usuarios_permissoes_page.dart';

class PontoFuncionariosPage extends StatefulWidget {
  const PontoFuncionariosPage({super.key});

  @override
  State<PontoFuncionariosPage> createState() => _PontoFuncionariosPageState();
}

class _PontoFuncionariosPageState extends State<PontoFuncionariosPage> {
  final CustosRepository _custosRepository = CustosRepository();
  final PontoRepository _repository = PontoSincronizadoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  bool _carregando = true;
  bool _carregandoDetalhes = false;

  List<ColaboradorCusto> _colaboradores = const [];
  Map<int, Map<String, dynamic>> _resumos = const {};
  Map<int, Map<String, dynamic>> _estadosBatida = const {};

  DateTime get _inicioMes => DateTime(_mes.year, _mes.month, 1);
  DateTime get _fimMes => DateTime(_mes.year, _mes.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _carregandoDetalhes = false;
      });
    }

    try {
      // A lista de funcionários é local e deve aparecer imediatamente.
      final colaboradores = await _custosRepository.listarColaboradores();

      if (!mounted) return;

      setState(() {
        _colaboradores = colaboradores;
        _resumos = const {};
        _estadosBatida = const {};
        _carregando = false;
        _carregandoDetalhes = colaboradores.isNotEmpty;
      });

      if (colaboradores.isEmpty) {
        return;
      }

      await _repository.garantirEstrutura();

      // Carrega os funcionários e seus resumos em paralelo.
      final tarefas = colaboradores
          .where((colaborador) => colaborador.id != null)
          .map((colaborador) async {
            final id = colaborador.id!;

            try {
              final detalhes = await Future.wait<dynamic>([
                _repository.obterFechamentoMes(
                  colaboradorId: id,
                  inicio: _inicioMes,
                  fim: _fimMes,
                ),
                _repository.obterEstadoBatidaHoje(id),
              ]);

              return <String, dynamic>{
                'id': id,
                'resumo': Map<String, dynamic>.from(detalhes[0] as Map),
                'estado': Map<String, dynamic>.from(detalhes[1] as Map),
              };
            } catch (_) {
              return <String, dynamic>{'id': id};
            }
          })
          .toList();

      final detalhes = await Future.wait<Map<String, dynamic>>(tarefas);

      if (!mounted) return;

      final resumos = <int, Map<String, dynamic>>{};
      final estadosBatida = <int, Map<String, dynamic>>{};

      for (final item in detalhes) {
        final id = item['id'];
        if (id is! int) continue;

        final resumo = item['resumo'];
        final estado = item['estado'];

        if (resumo is Map) {
          resumos[id] = Map<String, dynamic>.from(resumo);
        }

        if (estado is Map) {
          estadosBatida[id] = Map<String, dynamic>.from(estado);
        }
      }

      setState(() {
        _resumos = resumos;
        _estadosBatida = estadosBatida;
        _carregandoDetalhes = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _carregandoDetalhes = false;
      });

      _mensagem(
        'Não foi possível atualizar os detalhes do ponto.\n$erro',
        erro: true,
      );
    }
  }

  void _mesAnterior() {
    setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
    _carregar();
  }

  void _mesSeguinte() {
    setState(() => _mes = DateTime(_mes.year, _mes.month + 1));
    _carregar();
  }

  String _tituloMes() {
    final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_mes);
    return texto.substring(0, 1).toUpperCase() + texto.substring(1);
  }

  String _horas(dynamic minutos) {
    final total = minutos is num ? minutos.toInt() : 0;
    final sinal = total < 0 ? '-' : '';
    final absoluto = total.abs();
    final h = absoluto ~/ 60;
    final m = absoluto % 60;
    return '$sinal${h}h ${m.toString().padLeft(2, '0')}min';
  }

  String _statusHoje(Map<String, dynamic>? estado) {
    if (estado == null) return 'Sem informação';

    final registroBruto = estado['registro'];
    final registro = registroBruto is Map
        ? Map<String, dynamic>.from(registroBruto)
        : null;

    if (registro != null) {
      final situacao = (registro['situacao'] ?? '').toString();

      if (situacao == 'Falta' ||
          situacao == 'Atestado' ||
          situacao == 'Folga') {
        return situacao;
      }

      final entrada = (registro['entrada'] ?? '').toString().trim();
      final intervaloInicio = (registro['intervalo_inicio'] ?? '')
          .toString()
          .trim();
      final intervaloFim = (registro['intervalo_fim'] ?? '').toString().trim();
      final saida = (registro['saida'] ?? '').toString().trim();

      if (saida.isNotEmpty) return 'Concluído';
      if (intervaloInicio.isNotEmpty && intervaloFim.isEmpty) {
        return 'No intervalo';
      }
      if (entrada.isNotEmpty) return 'Trabalhando';
    }

    final jornadaAtiva = estado['jornada_ativa'] == 1;
    if (!jornadaAtiva) return 'Sem expediente';

    return 'Ainda não entrou';
  }

  IconData _iconeStatusHoje(String status) {
    switch (status) {
      case 'Trabalhando':
        return Icons.play_circle_outline_rounded;
      case 'No intervalo':
        return Icons.coffee_outlined;
      case 'Concluído':
        return Icons.check_circle_outline_rounded;
      case 'Falta':
        return Icons.event_busy_outlined;
      case 'Atestado':
        return Icons.medical_information_outlined;
      case 'Folga':
        return Icons.weekend_outlined;
      case 'Sem expediente':
        return Icons.nights_stay_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }

  Map<String, int> get _contagemHoje {
    final resultado = <String, int>{
      'Ainda não entrou': 0,
      'Trabalhando': 0,
      'No intervalo': 0,
      'Concluído': 0,
      'Falta': 0,
      'Atestado': 0,
      'Folga': 0,
    };

    for (final colaborador in _colaboradores) {
      final id = colaborador.id;
      if (id == null) continue;

      final status = _statusHoje(_estadosBatida[id]);
      if (resultado.containsKey(status)) {
        resultado[status] = (resultado[status] ?? 0) + 1;
      }
    }

    return resultado;
  }

  Future<void> _baterPonto(ColaboradorCusto colaborador) async {
    final id = colaborador.id;
    if (id == null) return;

    final estado = _estadosBatida[id];
    final rotulo = (estado?['rotulo'] ?? 'Registrar batida').toString();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(rotulo),
        content: Text(
          'Funcionário: ${colaborador.nome}\n'
          'Horário atual: '
          '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      final resultado = await _repository.registrarBatida(colaboradorId: id);

      await _carregar();

      final acao = (resultado['acao'] ?? 'Batida').toString();
      final hora = (resultado['hora'] ?? '').toString();
      _mensagem('$acao registrada às $hora.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _configurarHoraExtra() async {
    final atual = await _repository.obterAdicionalHoraExtra();

    if (!mounted) return;

    final controller = TextEditingController(
      text: atual.toStringAsFixed(2).replaceAll('.', ','),
    );

    final valor = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicional de hora extra'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Adicional',
            suffixText: '%',
            helperText:
                'Percentual configurável usado somente na estimativa do ponto.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final numero = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (numero != null) {
                Navigator.of(dialogContext).pop(numero);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (valor == null) return;

    try {
      await _repository.salvarAdicionalHoraExtra(valor);
      await _carregar();
      _mensagem('Adicional de hora extra atualizado.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _abrirJornada() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _JornadaPontoPage(repository: _repository),
      ),
    );
    await _carregar();
  }

  // ponto-rapido-dia-anterior-v1
  Future<ColaboradorCusto?> _selecionarColaboradorPontoRapido() async {
    if (_colaboradores.isEmpty) return null;
    if (_colaboradores.length == 1) return _colaboradores.first;

    return showDialog<ColaboradorCusto>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Escolher funcionário'),
        children: [
          for (final colaborador in _colaboradores)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(colaborador),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(colaborador.nome)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pontoRapidoDiaAnterior() async {
    if (_colaboradores.isEmpty) {
      _mensagem('Cadastre pelo menos um funcionário ativo.', erro: true);
      return;
    }

    final colaborador = await _selecionarColaboradorPontoRapido();
    if (colaborador == null || !mounted) return;

    final id = colaborador.id;
    if (id == null) {
      _mensagem('Funcionário sem identificador válido.', erro: true);
      return;
    }

    final agora = DateTime.now();
    final ontem = DateTime(
      agora.year,
      agora.month,
      agora.day,
    ).subtract(const Duration(days: 1));

    final data = await showDatePicker(
      context: context,
      initialDate: ontem,
      firstDate: DateTime(2020, 1, 1),
      lastDate: ontem,
      locale: const Locale('pt', 'BR'),
      helpText: 'Dia para lançar a jornada programada',
      cancelText: 'Cancelar',
      confirmText: 'Continuar',
    );

    if (data == null || !mounted) return;

    try {
      final existente = await _repository.buscarRegistro(
        colaboradorId: id,
        data: data,
      );

      if (existente != null) {
        _mensagem(
          'Já existe ponto em ${DateFormat('dd/MM/yyyy').format(data)} '
          'para ${colaborador.nome}. Abra o espelho para editar.',
          erro: true,
        );
        return;
      }

      final jornada = await _repository.listarJornada();
      Map<String, dynamic>? jornadaDia;

      for (final item in jornada) {
        final dia = item['dia_semana'];
        final numero = dia is num
            ? dia.toInt()
            : int.tryParse(dia?.toString() ?? '');

        if (numero == data.weekday) {
          jornadaDia = Map<String, dynamic>.from(item);
          break;
        }
      }

      if (jornadaDia == null || jornadaDia['ativo'] != 1) {
        _mensagem(
          'Não existe jornada ativa programada para '
          '${DateFormat('EEEE, dd/MM/yyyy', 'pt_BR').format(data)}.',
          erro: true,
        );
        return;
      }

      String? horario(String chave) {
        final valor = jornadaDia![chave]?.toString().trim() ?? '';
        return valor.isEmpty ? null : valor;
      }

      final entrada = horario('entrada');
      final intervaloInicio = horario('intervalo_inicio');
      final intervaloFim = horario('intervalo_fim');
      final saida = horario('saida');

      if (entrada == null || saida == null) {
        _mensagem(
          'A jornada desse dia está incompleta. Revise Jornada padrão.',
          erro: true,
        );
        return;
      }

      final linhas = <String>[
        'Funcionário: ${colaborador.nome}',
        'Data: ${DateFormat('dd/MM/yyyy').format(data)}',
        '',
        'Entrada: $entrada',
        if (intervaloInicio != null) 'Intervalo: $intervaloInicio',
        if (intervaloFim != null) 'Volta: $intervaloFim',
        'Saída: $saida',
        '',
        'Esses horários serão lançados exatamente conforme a jornada programada.',
      ];

      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lançar ponto rápido?'),
          content: Text(linhas.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Lançar'),
            ),
          ],
        ),
      );

      if (confirmou != true) return;

      await _repository.salvarRegistro(
        colaboradorId: id,
        data: data,
        situacao: 'Trabalhado',
        entrada: entrada,
        intervaloInicio: intervaloInicio,
        intervaloFim: intervaloFim,
        saida: saida,
        observacoes: 'Ponto rápido lançado conforme a jornada programada.',
        motivoAjuste: 'Ponto rápido conforme jornada programada',
      );

      await _carregar();

      if (!mounted) return;

      _mensagem(
        'Ponto rápido de ${DateFormat('dd/MM/yyyy').format(data)} '
        'lançado para ${colaborador.nome}.',
      );
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _novoLancamento({
    ColaboradorCusto? colaborador,
    DateTime? data,
    Map<String, dynamic>? registro,
  }) async {
    if (_colaboradores.isEmpty) {
      _mensagem('Cadastre pelo menos um funcionário ativo.', erro: true);
      return;
    }

    final salvou = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PontoFormSheet(
        repository: _repository,
        colaboradores: _colaboradores,
        colaboradorInicial: colaborador,
        dataInicial: data,
        registroExistente: registro,
      ),
    );

    if (salvou == true) {
      await _carregar();
    }
  }

  Future<void> _abrirEspelho(ColaboradorCusto colaborador) async {
    final id = colaborador.id;
    if (id == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _EspelhoPontoPage(
          repository: _repository,
          colaborador: colaborador,
          mes: _mes,
          onEditar: ({required DateTime data, Map<String, dynamic>? registro}) {
            return _novoLancamento(
              colaborador: colaborador,
              data: data,
              registro: registro,
            );
          },
        ),
      ),
    );

    await _carregar();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de ponto'),
        actions: [
          IconButton(
            tooltip: 'Usuários e permissões',
            onPressed: _carregando
                ? null
                : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const UsuariosPermissoesPage(),
                      ),
                    );
                    await _carregar();
                  },
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: 'Resumo dos funcionários',
            onPressed: _carregando
                ? null
                : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const FuncionariosResumoPage(),
                      ),
                    );
                    await _carregar();
                  },
            icon: const Icon(Icons.groups_2_outlined),
          ),
          IconButton(
            tooltip: 'Configurar hora extra',
            onPressed: _carregando ? null : _configurarHoraExtra,
            icon: const Icon(Icons.calculate_outlined),
          ),
          IconButton(
            tooltip: 'Jornada padrão',
            onPressed: _carregando ? null : _abrirJornada,
            icon: const Icon(Icons.schedule_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _carregando ? null : () => _novoLancamento(),
        icon: const Icon(Icons.add),
        label: const Text('Lançar ponto'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Mês anterior',
                            onPressed: _mesAnterior,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              _tituloMes(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Próximo mês',
                            onPressed: _mesSeguinte,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_carregandoDetalhes) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  _PainelHojeCard(
                    data: DateTime.now(),
                    contagem: _contagemHoje,
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(13),
                      child: Text(
                        'O ponto controla presença, horas reais e uma '
                        'estimativa de pagamento. Use a batida rápida para '
                        'entrada, intervalo e saída. Correções continuam '
                        'sendo feitas manualmente e ficam auditadas.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ponto-rapido-card-v1
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.bolt_rounded),
                      ),
                      title: const Text(
                        'Ponto rápido de dia anterior',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Escolha funcionário e data. O sistema lança '
                        'automaticamente a jornada programada daquele dia.',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _carregando ? null : _pontoRapidoDiaAnterior,
                        child: const Text('Lançar'),
                      ),
                      onTap: _carregando ? null : _pontoRapidoDiaAnterior,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_colaboradores.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhum funcionário ativo cadastrado.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._colaboradores.map((colaborador) {
                      final id = colaborador.id;
                      final resumo = id == null ? null : _resumos[id];
                      final estadoBatida = id == null
                          ? null
                          : _estadosBatida[id];
                      final registroHojeBruto = estadoBatida?['registro'];
                      final registroHoje = registroHojeBruto is Map
                          ? Map<String, dynamic>.from(registroHojeBruto)
                          : null;
                      final batidaConcluida = estadoBatida?['concluido'] == 1;
                      final statusHoje = _statusHoje(estadoBatida);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _abrirEspelho(colaborador),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const CircleAvatar(
                                      child: Icon(Icons.badge_outlined),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            colaborador.nome,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(
                                                _iconeStatusHoje(statusHoje),
                                                size: 14,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                statusHoje,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.fingerprint_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              estadoBatida?['rotulo']
                                                      ?.toString() ??
                                                  'Registrar batida',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          FilledButton.tonalIcon(
                                            onPressed: batidaConcluida
                                                ? null
                                                : () =>
                                                      _baterPonto(colaborador),
                                            icon: Icon(
                                              batidaConcluida
                                                  ? Icons.check_rounded
                                                  : Icons.touch_app_rounded,
                                            ),
                                            label: Text(
                                              batidaConcluida
                                                  ? 'Concluído'
                                                  : 'Bater',
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (registroHoje != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          [
                                            if ((registroHoje['entrada'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              'Entrada ${registroHoje['entrada']}',
                                            if ((registroHoje['intervalo_inicio'] ??
                                                    '')
                                                .toString()
                                                .isNotEmpty)
                                              'Intervalo ${registroHoje['intervalo_inicio']}',
                                            if ((registroHoje['intervalo_fim'] ??
                                                    '')
                                                .toString()
                                                .isNotEmpty)
                                              'Volta ${registroHoje['intervalo_fim']}',
                                            if ((registroHoje['saida'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              'Saída ${registroHoje['saida']}',
                                          ].join(' • '),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _IndicadorPonto(
                                      titulo: 'Trabalhadas',
                                      valor: _horas(
                                        resumo?['minutos_trabalhados'],
                                      ),
                                      icone: Icons.timer_outlined,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Extras',
                                      valor: _horas(resumo?['minutos_extras']),
                                      icone: Icons.add_alarm_outlined,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Faltantes',
                                      valor: _horas(
                                        resumo?['minutos_faltantes'],
                                      ),
                                      icone: Icons.timer_off_outlined,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Faltas',
                                      valor: '${resumo?['faltas'] ?? 0}',
                                      icone: Icons.event_busy_outlined,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Pendentes',
                                      valor: '${resumo?['pendencias'] ?? 0}',
                                      icone: Icons.pending_actions_outlined,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Incompletos',
                                      valor: '${resumo?['incompletos'] ?? 0}',
                                      icone: Icons.error_outline_rounded,
                                    ),
                                    _IndicadorPonto(
                                      titulo: 'Fechamento',
                                      valor:
                                          '${resumo?['fechamento_status'] ?? 'Aberto'}',
                                      icone:
                                          resumo?['fechamento_status'] ==
                                              'Fechado'
                                          ? Icons.lock_outline_rounded
                                          : Icons.lock_open_rounded,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ValorPontoResumo(
                                        titulo: 'Estimado a pagar',
                                        valor: _moeda.format(
                                          resumo?['valor_estimado_pagar'] ?? 0,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _ValorPontoResumo(
                                        titulo: 'Já pago',
                                        valor: _moeda.format(
                                          resumo?['ja_pago_mes'] ?? 0,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _ValorPontoResumo(
                                        titulo: 'Restante',
                                        valor: _moeda.format(
                                          resumo?['restante_estimado'] ?? 0,
                                        ),
                                        destaque: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

class _PainelHojeCard extends StatelessWidget {
  const _PainelHojeCard({required this.data, required this.contagem});

  final DateTime data;
  final Map<String, int> contagem;

  @override
  Widget build(BuildContext context) {
    final totalAtivos =
        (contagem['Ainda não entrou'] ?? 0) +
        (contagem['Trabalhando'] ?? 0) +
        (contagem['No intervalo'] ?? 0) +
        (contagem['Concluído'] ?? 0) +
        (contagem['Falta'] ?? 0) +
        (contagem['Atestado'] ?? 0) +
        (contagem['Folga'] ?? 0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.today_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ponto de hoje • '
                    '${DateFormat('dd/MM/yyyy').format(data)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '$totalAtivos funcionários',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusHojeChip(
                  titulo: 'Não entrou',
                  quantidade: contagem['Ainda não entrou'] ?? 0,
                  icone: Icons.schedule_outlined,
                ),
                _StatusHojeChip(
                  titulo: 'Trabalhando',
                  quantidade: contagem['Trabalhando'] ?? 0,
                  icone: Icons.play_circle_outline_rounded,
                ),
                _StatusHojeChip(
                  titulo: 'Intervalo',
                  quantidade: contagem['No intervalo'] ?? 0,
                  icone: Icons.coffee_outlined,
                ),
                _StatusHojeChip(
                  titulo: 'Concluíram',
                  quantidade: contagem['Concluído'] ?? 0,
                  icone: Icons.check_circle_outline_rounded,
                ),
                _StatusHojeChip(
                  titulo: 'Faltas',
                  quantidade: contagem['Falta'] ?? 0,
                  icone: Icons.event_busy_outlined,
                ),
                _StatusHojeChip(
                  titulo: 'Atestados',
                  quantidade: contagem['Atestado'] ?? 0,
                  icone: Icons.medical_information_outlined,
                ),
                _StatusHojeChip(
                  titulo: 'Folgas',
                  quantidade: contagem['Folga'] ?? 0,
                  icone: Icons.weekend_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHojeChip extends StatelessWidget {
  const _StatusHojeChip({
    required this.titulo,
    required this.quantidade,
    required this.icone,
  });

  final String titulo;
  final int quantidade;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 17),
          const SizedBox(width: 6),
          Text(
            '$titulo: $quantidade',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _IndicadorPonto extends StatelessWidget {
  const _IndicadorPonto({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 18),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 11)),
              Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValorPontoResumo extends StatelessWidget {
  const _ValorPontoResumo({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 10.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: destaque ? 15 : 13,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EspelhoPontoPage extends StatefulWidget {
  const _EspelhoPontoPage({
    required this.repository,
    required this.colaborador,
    required this.mes,
    required this.onEditar,
  });

  final PontoRepository repository;
  final ColaboradorCusto colaborador;
  final DateTime mes;
  final Future<void> Function({
    required DateTime data,
    Map<String, dynamic>? registro,
  })
  onEditar;

  @override
  State<_EspelhoPontoPage> createState() => _EspelhoPontoPageState();
}

class _EspelhoPontoPageState extends State<_EspelhoPontoPage> {
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  bool _carregando = true;
  Map<String, dynamic>? _espelho;

  DateTime get _inicio => DateTime(widget.mes.year, widget.mes.month, 1);
  DateTime get _fim => DateTime(widget.mes.year, widget.mes.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.colaborador.id;
    if (id == null) return;

    if (mounted) {
      setState(() => _carregando = true);
    }

    final espelho = await widget.repository.obterFechamentoMes(
      colaboradorId: id,
      inicio: _inicio,
      fim: _fim,
    );

    if (!mounted) return;

    setState(() {
      _espelho = espelho;
      _carregando = false;
    });
  }

  String _horas(dynamic minutos) {
    final total = minutos is num ? minutos.toInt() : 0;
    final h = total ~/ 60;
    final m = total % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}min';
  }

  String _diaSemana(int dia) {
    const nomes = <int, String>{
      DateTime.monday: 'Seg',
      DateTime.tuesday: 'Ter',
      DateTime.wednesday: 'Qua',
      DateTime.thursday: 'Qui',
      DateTime.friday: 'Sex',
      DateTime.saturday: 'Sáb',
      DateTime.sunday: 'Dom',
    };
    return nomes[dia] ?? '';
  }

  Future<void> _fecharMes() async {
    final espelho = _espelho;
    if (espelho == null) return;

    final pendencias = (espelho['pendencias'] as num?)?.toInt() ?? 0;
    final incompletos = (espelho['incompletos'] as num?)?.toInt() ?? 0;

    if (pendencias > 0 || incompletos > 0) {
      final partes = <String>[];
      if (pendencias > 0) {
        partes.add('$pendencias pendente(s)');
      }
      if (incompletos > 0) {
        partes.add('$incompletos incompleto(s)');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resolva ${partes.join(' e ')} antes do fechamento.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fechar ponto do mês?'),
        content: Text(
          'Funcionário: ${widget.colaborador.nome}\n\n'
          'Estimado a pagar: '
          '${_moeda.format(espelho['valor_estimado_pagar'] ?? 0)}\n'
          'Já pago: '
          '${_moeda.format(espelho['ja_pago_mes'] ?? 0)}\n\n'
          'Depois do fechamento, os registros do mês ficam bloqueados. '
          'Para alterar será necessário reabrir com um motivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Fechar mês'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    final id = widget.colaborador.id;
    if (id == null) return;

    try {
      await widget.repository.fecharCompetencia(
        colaboradorId: id,
        competencia: widget.mes,
      );
      await _carregar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ponto mensal fechado e aprovado.')),
      );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _reabrirMes() async {
    final controller = TextEditingController();

    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reabrir ponto do mês'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo da reabertura *',
            hintText: 'Ex.: correção de horário do dia 15',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (texto.length >= 5) {
                Navigator.of(dialogContext).pop(texto);
              }
            },
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (motivo == null) return;

    final id = widget.colaborador.id;
    if (id == null) return;

    try {
      await widget.repository.reabrirCompetencia(
        colaboradorId: id,
        competencia: widget.mes,
        motivo: motivo,
      );
      await _carregar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ponto mensal reaberto para correção.')),
      );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Widget _linhaFinanceira(
    String titulo,
    dynamic valor, {
    String prefixo = '',
    bool destaque = false,
  }) {
    final numero = valor is num ? valor.toDouble() : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            '$prefixo${_moeda.format(numero)}',
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final espelho = _espelho;
    final dias = espelho?['dias'] is List
        ? List<Map<String, dynamic>>.from(espelho!['dias'] as List<dynamic>)
        : const <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: Text(widget.colaborador.nome)),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          Text(
                            'Previstas: ${_horas(espelho?['minutos_previstos_mes'])}',
                          ),
                          Text(
                            'Trabalhadas: ${_horas(espelho?['minutos_trabalhados'])}',
                          ),
                          Text('Extras: ${_horas(espelho?['minutos_extras'])}'),
                          Text(
                            'Faltantes: ${_horas(espelho?['minutos_faltantes'])}',
                          ),
                          Text('Faltas: ${espelho?['faltas'] ?? 0}'),
                          Text('Atestados: ${espelho?['atestados'] ?? 0}'),
                          Text('Folgas: ${espelho?['folgas'] ?? 0}'),
                          Text('Pendentes: ${espelho?['pendencias'] ?? 0}'),
                          Text('Incompletos: ${espelho?['incompletos'] ?? 0}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            espelho?['fechamento_status'] == 'Fechado'
                                ? Icons.lock_outline_rounded
                                : Icons.lock_open_rounded,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  espelho?['fechamento_status'] == 'Fechado'
                                      ? 'Ponto fechado e aprovado'
                                      : 'Ponto aberto para conferência',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  espelho?['fechamento_status'] == 'Fechado'
                                      ? 'Os registros deste mês estão bloqueados.'
                                      : 'Resolva pendências antes de fechar o mês.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (espelho?['fechamento_status'] == 'Fechado')
                            OutlinedButton(
                              onPressed: _reabrirMes,
                              child: const Text('Reabrir'),
                            )
                          else
                            FilledButton.icon(
                              onPressed: _fecharMes,
                              icon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Fechar'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _linhaFinanceira(
                            'Salário base',
                            espelho?['salario_base'],
                          ),
                          _linhaFinanceira(
                            'Valor da hora',
                            espelho?['valor_hora'],
                          ),
                          _linhaFinanceira(
                            'Horas extras',
                            espelho?['valor_horas_extras'],
                            prefixo: '+ ',
                          ),
                          _linhaFinanceira(
                            'Desconto por horas faltantes',
                            espelho?['desconto_horas_faltantes'],
                            prefixo: '- ',
                          ),
                          const Divider(),
                          _linhaFinanceira(
                            'Estimado a pagar',
                            espelho?['valor_estimado_pagar'],
                            destaque: true,
                          ),
                          _linhaFinanceira(
                            'Já pago no mês',
                            espelho?['ja_pago_mes'],
                          ),
                          _linhaFinanceira(
                            'Restante estimado',
                            espelho?['restante_estimado'],
                            destaque: true,
                          ),
                          if ((espelho?['pago_acima_estimado'] as num?)
                                      ?.toDouble() !=
                                  null &&
                              ((espelho?['pago_acima_estimado'] as num?)
                                          ?.toDouble() ??
                                      0) >
                                  0.001)
                            _linhaFinanceira(
                              'Pago acima da estimativa',
                              espelho?['pago_acima_estimado'],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estimativa: salário ÷ horas-base mensais do funcionário. '
                    'Horas extras usam adicional configurável de '
                    '${((espelho?['adicional_hora_extra_percentual'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%. '
                    'Dias pendentes não geram desconto.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...dias.map((dia) {
                    final data = DateTime.tryParse(
                      dia['data']?.toString() ?? '',
                    );
                    if (data == null) {
                      return const SizedBox.shrink();
                    }

                    final registroBruto = dia['registro'];
                    final registro = registroBruto is Map
                        ? Map<String, dynamic>.from(registroBruto)
                        : null;
                    final status = (dia['status_exibido'] ?? '').toString();
                    final entrada = registro?['entrada']?.toString() ?? '';
                    final saida = registro?['saida']?.toString() ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: SizedBox(
                          width: 48,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                data.day.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _diaSemana(data.weekday),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        title: Text(status),
                        subtitle: Text(
                          registro != null && status == 'Trabalhado'
                              ? '${entrada.isEmpty ? '--:--' : entrada} → '
                                    '${saida.isEmpty ? '--:--' : saida} • '
                                    '${_horas(dia['minutos_trabalhados'])}'
                              : dia['jornada_ativa'] == 1
                              ? 'Previsto: '
                                    '${dia['jornada_entrada'] ?? '--:--'} → '
                                    '${dia['jornada_saida'] ?? '--:--'}'
                              : 'Sem jornada prevista',
                        ),
                        trailing: Icon(
                          espelho?['fechamento_status'] == 'Fechado'
                              ? Icons.lock_outline_rounded
                              : Icons.edit_outlined,
                        ),
                        onTap: espelho?['fechamento_status'] == 'Fechado'
                            ? null
                            : () async {
                                await widget.onEditar(
                                  data: data,
                                  registro: registro,
                                );
                                await _carregar();
                              },
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _PontoFormSheet extends StatefulWidget {
  const _PontoFormSheet({
    required this.repository,
    required this.colaboradores,
    this.colaboradorInicial,
    this.dataInicial,
    this.registroExistente,
  });

  final PontoRepository repository;
  final List<ColaboradorCusto> colaboradores;
  final ColaboradorCusto? colaboradorInicial;
  final DateTime? dataInicial;
  final Map<String, dynamic>? registroExistente;

  @override
  State<_PontoFormSheet> createState() => _PontoFormSheetState();
}

class _PontoFormSheetState extends State<_PontoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _observacoes = TextEditingController();
  final _motivo = TextEditingController();

  ColaboradorCusto? _colaborador;
  late DateTime _data;
  String _situacao = 'Trabalhado';
  String? _entrada;
  String? _intervaloInicio;
  String? _intervaloFim;
  String? _saida;
  bool _salvando = false;

  bool get _editando => widget.registroExistente != null;

  @override
  void initState() {
    super.initState();

    _colaborador =
        widget.colaboradorInicial ??
        (widget.colaboradores.length == 1 ? widget.colaboradores.first : null);
    _data = widget.dataInicial ?? DateTime.now();

    final registro = widget.registroExistente;
    if (registro != null) {
      _situacao = (registro['situacao'] ?? 'Trabalhado').toString();
      _entrada = _textoNulo(registro['entrada']);
      _intervaloInicio = _textoNulo(registro['intervalo_inicio']);
      _intervaloFim = _textoNulo(registro['intervalo_fim']);
      _saida = _textoNulo(registro['saida']);
      _observacoes.text = (registro['observacoes'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _observacoes.dispose();
    _motivo.dispose();
    super.dispose();
  }

  String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      locale: const Locale('pt', 'BR'),
    );

    if (data != null && mounted) {
      setState(() => _data = data);
    }
  }

  Future<String?> _selecionarHora(String? atual) async {
    TimeOfDay inicial = TimeOfDay.now();

    if (atual != null) {
      final partes = atual.split(':');
      if (partes.length >= 2) {
        inicial = TimeOfDay(
          hour: int.tryParse(partes[0]) ?? inicial.hour,
          minute: int.tryParse(partes[1]) ?? inicial.minute,
        );
      }
    }

    final hora = await showTimePicker(context: context, initialTime: inicial);

    if (hora == null) return null;

    return '${hora.hour.toString().padLeft(2, '0')}:'
        '${hora.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editarHora(
    String titulo,
    String? atual,
    void Function(String?) aplicar,
  ) async {
    final resultado = await _selecionarHora(atual);
    if (resultado != null && mounted) {
      setState(() => aplicar(resultado));
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final colaborador = _colaborador;
    if (colaborador?.id == null) {
      return;
    }

    setState(() => _salvando = true);

    try {
      await widget.repository.salvarRegistro(
        colaboradorId: colaborador!.id!,
        data: _data,
        situacao: _situacao,
        entrada: _entrada,
        intervaloInicio: _intervaloInicio,
        intervaloFim: _intervaloFim,
        saida: _saida,
        observacoes: _observacoes.text,
        motivoAjuste: _motivo.text,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
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
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, teclado + 18),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editando ? 'Editar ponto' : 'Lançar ponto',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _editando
                    ? 'Correção administrativa do ponto. A alteração ficará registrada no histórico.'
                    : 'Lançamento manual. Para o dia atual, prefira a batida rápida.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<ColaboradorCusto>(
                initialValue: _colaborador,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Funcionário *',
                  border: OutlineInputBorder(),
                ),
                items: widget.colaboradores
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.nome, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _editando || _salvando
                    ? null
                    : (valor) => setState(() => _colaborador = valor),
                validator: (valor) =>
                    valor == null ? 'Selecione o funcionário' : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _editando || _salvando ? null : _selecionarData,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Data: ${DateFormat('dd/MM/yyyy').format(_data)}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _situacao,
                decoration: const InputDecoration(
                  labelText: 'Situação',
                  border: OutlineInputBorder(),
                ),
                items: PontoRepository.situacoes
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor != null) {
                          setState(() => _situacao = valor);
                        }
                      },
              ),
              if (_situacao == 'Trabalhado') ...[
                const SizedBox(height: 12),
                _CampoHoraPonto(
                  titulo: 'Entrada *',
                  valor: _entrada,
                  onTap: () => _editarHora(
                    'Entrada',
                    _entrada,
                    (valor) => _entrada = valor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _CampoHoraPonto(
                        titulo: 'Início intervalo',
                        valor: _intervaloInicio,
                        onTap: () => _editarHora(
                          'Início intervalo',
                          _intervaloInicio,
                          (valor) => _intervaloInicio = valor,
                        ),
                        onLimpar: _intervaloInicio == null
                            ? null
                            : () => setState(() => _intervaloInicio = null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CampoHoraPonto(
                        titulo: 'Fim intervalo',
                        valor: _intervaloFim,
                        onTap: () => _editarHora(
                          'Fim intervalo',
                          _intervaloFim,
                          (valor) => _intervaloFim = valor,
                        ),
                        onLimpar: _intervaloFim == null
                            ? null
                            : () => setState(() => _intervaloFim = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CampoHoraPonto(
                  titulo: 'Saída *',
                  valor: _saida,
                  onTap: () =>
                      _editarHora('Saída', _saida, (valor) => _saida = valor),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacoes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_editando) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motivo,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo da alteração *',
                    hintText: 'Ex.: horário anotado incorretamente',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    if ((valor ?? '').trim().length < 5) {
                      return 'Informe pelo menos 5 caracteres';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_salvando ? 'Salvando...' : 'Salvar ponto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampoHoraPonto extends StatelessWidget {
  const _CampoHoraPonto({
    required this.titulo,
    required this.valor,
    required this.onTap,
    this.onLimpar,
  });

  final String titulo;
  final String? valor;
  final VoidCallback onTap;
  final VoidCallback? onLimpar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$titulo: ${valor ?? '--:--'}',
              textAlign: TextAlign.left,
            ),
          ),
          if (onLimpar != null)
            IconButton(
              tooltip: 'Limpar',
              onPressed: onLimpar,
              icon: const Icon(Icons.close_rounded, size: 18),
            )
          else
            const Icon(Icons.access_time_rounded, size: 18),
        ],
      ),
    );
  }
}

class _JornadaPontoPage extends StatefulWidget {
  const _JornadaPontoPage({required this.repository});

  final PontoRepository repository;

  @override
  State<_JornadaPontoPage> createState() => _JornadaPontoPageState();
}

class _JornadaPontoPageState extends State<_JornadaPontoPage> {
  bool _carregando = true;
  List<Map<String, dynamic>> _dias = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final dias = await widget.repository.listarJornada();
    if (!mounted) return;

    setState(() {
      _dias = dias;
      _carregando = false;
    });
  }

  String _nomeDia(int dia) {
    const nomes = <int, String>{
      DateTime.monday: 'Segunda-feira',
      DateTime.tuesday: 'Terça-feira',
      DateTime.wednesday: 'Quarta-feira',
      DateTime.thursday: 'Quinta-feira',
      DateTime.friday: 'Sexta-feira',
      DateTime.saturday: 'Sábado',
      DateTime.sunday: 'Domingo',
    };
    return nomes[dia] ?? 'Dia';
  }

  Future<String?> _hora(String? valor) async {
    var inicial = TimeOfDay.now();

    if (valor != null) {
      final partes = valor.split(':');
      if (partes.length >= 2) {
        inicial = TimeOfDay(
          hour: int.tryParse(partes[0]) ?? inicial.hour,
          minute: int.tryParse(partes[1]) ?? inicial.minute,
        );
      }
    }

    final selecionada = await showTimePicker(
      context: context,
      initialTime: inicial,
    );

    if (selecionada == null) return null;

    return '${selecionada.hour.toString().padLeft(2, '0')}:'
        '${selecionada.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editarDia(int indice) async {
    final atual = Map<String, dynamic>.from(_dias[indice]);

    final alterado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _JornadaDiaDialog(
        dia: atual,
        nomeDia: _nomeDia(indice + 1),
        selecionarHora: _hora,
      ),
    );

    if (alterado == null) return;

    try {
      await widget.repository.salvarJornadaDia(
        diaSemana: indice + 1,
        ativo: alterado['ativo'] == true,
        entrada: alterado['entrada']?.toString(),
        intervaloInicio: alterado['intervalo_inicio']?.toString(),
        intervaloFim: alterado['intervalo_fim']?.toString(),
        saida: alterado['saida']?.toString(),
      );
      await _carregar();
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jornada padrão')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Card(
                  margin: EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: EdgeInsets.all(13),
                    child: Text(
                      'Configure a jornada real da semana. A precificação '
                      'continua usando a carga mensal única informada nela.',
                    ),
                  ),
                ),
                ...List.generate(_dias.length, (indice) {
                  final dia = _dias[indice];
                  final ativo = (dia['ativo'] as num?)?.toInt() == 1;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        ativo
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                      title: Text(_nomeDia(indice + 1)),
                      subtitle: Text(
                        ativo
                            ? '${dia['entrada'] ?? '--:--'} → '
                                  '${dia['saida'] ?? '--:--'}'
                            : 'Sem expediente',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editarDia(indice),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _JornadaDiaDialog extends StatefulWidget {
  const _JornadaDiaDialog({
    required this.dia,
    required this.nomeDia,
    required this.selecionarHora,
  });

  final Map<String, dynamic> dia;
  final String nomeDia;
  final Future<String?> Function(String? valor) selecionarHora;

  @override
  State<_JornadaDiaDialog> createState() => _JornadaDiaDialogState();
}

class _JornadaDiaDialogState extends State<_JornadaDiaDialog> {
  late bool _ativo;
  String? _entrada;
  String? _intervaloInicio;
  String? _intervaloFim;
  String? _saida;

  @override
  void initState() {
    super.initState();
    _ativo = (widget.dia['ativo'] as num?)?.toInt() == 1;
    _entrada = widget.dia['entrada']?.toString();
    _intervaloInicio = widget.dia['intervalo_inicio']?.toString();
    _intervaloFim = widget.dia['intervalo_fim']?.toString();
    _saida = widget.dia['saida']?.toString();
  }

  Future<void> _editar(String? atual, void Function(String?) aplicar) async {
    final valor = await widget.selecionarHora(atual);
    if (valor != null && mounted) {
      setState(() => aplicar(valor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.nomeDia),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tem expediente'),
              value: _ativo,
              onChanged: (valor) => setState(() => _ativo = valor),
            ),
            if (_ativo) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Entrada'),
                trailing: Text(_entrada ?? '--:--'),
                onTap: () => _editar(_entrada, (valor) => _entrada = valor),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Início intervalo'),
                trailing: Text(_intervaloInicio ?? '--:--'),
                onTap: () => _editar(
                  _intervaloInicio,
                  (valor) => _intervaloInicio = valor,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fim intervalo'),
                trailing: Text(_intervaloFim ?? '--:--'),
                onTap: () =>
                    _editar(_intervaloFim, (valor) => _intervaloFim = valor),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Saída'),
                trailing: Text(_saida ?? '--:--'),
                onTap: () => _editar(_saida, (valor) => _saida = valor),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _intervaloInicio = null;
                    _intervaloFim = null;
                  });
                },
                child: const Text('Sem intervalo'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'ativo': _ativo,
              'entrada': _entrada,
              'intervalo_inicio': _intervaloInicio,
              'intervalo_fim': _intervaloFim,
              'saida': _saida,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
