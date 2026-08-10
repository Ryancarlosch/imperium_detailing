import 'package:flutter/material.dart';

import '../repositories/ordem_servico_repository.dart';

class CorrigirOrdemServicoPage extends StatefulWidget {
  const CorrigirOrdemServicoPage({super.key, required this.ordem});

  final Map<String, dynamic> ordem;

  @override
  State<CorrigirOrdemServicoPage> createState() =>
      _CorrigirOrdemServicoPageState();
}

class _CorrigirOrdemServicoPageState extends State<CorrigirOrdemServicoPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final OrdemServicoRepository _repository = OrdemServicoRepository();

  late final TextEditingController _responsavelController;
  late final TextEditingController _observacoesController;
  late final TextEditingController _quilometragemController;
  late final TextEditingController _combustivelController;
  late final TextEditingController _dataEntradaController;
  late final TextEditingController _dataSaidaController;
  late final TextEditingController _horaEntradaController;
  late final TextEditingController _horaSaidaController;
  late final TextEditingController _motivoController;

  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    _responsavelController = TextEditingController(
      text: _texto('funcionario_responsavel'),
    );
    _observacoesController = TextEditingController(text: _texto('observacoes'));
    _quilometragemController = TextEditingController(
      text: _texto('quilometragem_entrada'),
    );
    _combustivelController = TextEditingController(
      text: _texto('combustivel_entrada'),
    );
    _dataEntradaController = TextEditingController(
      text: _formatarDataTela(_texto('data_inicio')),
    );
    _dataSaidaController = TextEditingController(
      text: _formatarDataTela(_texto('data_finalizacao')),
    );
    _horaEntradaController = TextEditingController(
      text: _texto('hora_entrada'),
    );
    _horaSaidaController = TextEditingController(text: _texto('hora_saida'));
    _motivoController = TextEditingController();
  }

  @override
  void dispose() {
    _responsavelController.dispose();
    _observacoesController.dispose();
    _quilometragemController.dispose();
    _combustivelController.dispose();
    _dataEntradaController.dispose();
    _dataSaidaController.dispose();
    _horaEntradaController.dispose();
    _horaSaidaController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  String _texto(String campo) {
    return (widget.ordem[campo] ?? '').toString().trim();
  }

  int _ordemServicoId() {
    final valor = widget.ordem['id'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatarDataTela(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) {
      return '';
    }

    final data = DateTime.tryParse(texto);
    if (data == null) {
      return texto;
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year.toString().padLeft(4, '0')}';
  }

  DateTime? _lerDataController(TextEditingController controller) {
    final texto = controller.text.trim();
    if (texto.isEmpty) {
      return null;
    }

    final iso = DateTime.tryParse(texto);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final partes = texto.split('/');
    if (partes.length != 3) {
      return null;
    }

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) {
      return null;
    }

    final data = DateTime(ano, mes, dia);
    if (data.year != ano || data.month != mes || data.day != dia) {
      return null;
    }

    return data;
  }

  Future<void> _selecionarData(TextEditingController controller) async {
    final atual = _lerDataController(controller) ?? DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Selecionar data',
    );

    if (data == null || !mounted) {
      return;
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    setState(() {
      controller.text = '$dia/$mes/${data.year.toString().padLeft(4, '0')}';
    });
  }

  Future<void> _selecionarHorario(TextEditingController controller) async {
    TimeOfDay horarioInicial = TimeOfDay.now();
    final partes = controller.text.trim().split(':');

    if (partes.length >= 2) {
      final hora = int.tryParse(partes[0]);
      final minuto = int.tryParse(partes[1]);

      if (hora != null &&
          minuto != null &&
          hora >= 0 &&
          hora <= 23 &&
          minuto >= 0 &&
          minuto <= 59) {
        horarioInicial = TimeOfDay(hour: hora, minute: minuto);
      }
    }

    final horario = await showTimePicker(
      context: context,
      initialTime: horarioInicial,
      helpText: 'Selecionar horário',
    );

    if (horario == null || !mounted) {
      return;
    }

    final hora = horario.hour.toString().padLeft(2, '0');
    final minuto = horario.minute.toString().padLeft(2, '0');

    setState(() {
      controller.text = '$hora:$minuto';
    });
  }

  Future<void> _salvar() async {
    FocusScope.of(context).unfocus();

    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final ordemServicoId = _ordemServicoId();

    if (ordemServicoId <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final numeroRevisao = await _repository.corrigirOrdemFinalizada(
        ordemServicoId: ordemServicoId,
        motivo: _motivoController.text,
        funcionarioResponsavel: _responsavelController.text,
        observacoes: _observacoesController.text,
        quilometragemEntrada: _quilometragemController.text,
        combustivelEntrada: _combustivelController.text,
        dataInicio: _dataEntradaController.text,
        dataFinalizacao: _dataSaidaController.text,
        horaEntrada: _horaEntradaController.text,
        horaSaida: _horaSaidaController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, numeroRevisao);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível salvar a correção.\n$erro',
        erro: true,
      );

      setState(() {
        _salvando = false;
      });
    }
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  Widget _campoData({
    required String titulo,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: _salvando ? null : () => _selecionarData(controller),
      decoration: InputDecoration(
        labelText: titulo,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        border: const OutlineInputBorder(),
      ),
      validator: (valor) {
        if ((valor ?? '').trim().isEmpty) {
          return 'Informe a data.';
        }
        if (_lerDataController(controller) == null) {
          return 'Data inválida.';
        }
        return null;
      },
    );
  }

  Widget _campoHorario({
    required String titulo,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: _salvando ? null : () => _selecionarHorario(controller),
      decoration: InputDecoration(
        labelText: titulo,
        prefixIcon: const Icon(Icons.access_time_outlined),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar horário',
                onPressed: _salvando
                    ? null
                    : () {
                        setState(controller.clear);
                      },
                icon: const Icon(Icons.close),
              ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numero = _texto('numero').isEmpty
        ? 'Ordem de Serviço'
        : _texto('numero');

    return Scaffold(
      appBar: AppBar(title: const Text('Corrigir Ordem de Serviço')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Card(
              color: Colors.amber.withValues(alpha: 0.10),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Esta correção preserva o status finalizado e cria '
                        'um registro de auditoria. As datas e horários reais '
                        'de entrada e saída podem ser corrigidos sem alterar '
                        'pagamentos, estoque ou valores da OS.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              numero,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _responsavelController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Responsável pelo serviço',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quilometragemController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quilometragem de entrada',
                prefixIcon: Icon(Icons.speed_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _combustivelController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Combustível de entrada',
                prefixIcon: Icon(Icons.local_gas_station_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Entrada e saída do veículo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _campoData(
                    titulo: 'Data de entrada',
                    controller: _dataEntradaController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoData(
                    titulo: 'Data de saída',
                    controller: _dataSaidaController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _campoHorario(
                    titulo: 'Hora de entrada',
                    controller: _horaEntradaController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoHorario(
                    titulo: 'Hora de saída',
                    controller: _horaSaidaController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _observacoesController,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _motivoController,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo da correção *',
                hintText: 'Explique por que a OS está sendo corrigida',
                prefixIcon: Icon(Icons.history_edu_outlined),
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                final motivo = valor?.trim() ?? '';

                if (motivo.isEmpty) {
                  return 'Informe o motivo da correção.';
                }

                if (motivo.length < 5) {
                  return 'Descreva o motivo com pelo menos 5 caracteres.';
                }

                return null;
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_as_outlined),
            label: Text(_salvando ? 'Salvando correção...' : 'Salvar correção'),
          ),
        ),
      ),
    );
  }
}
