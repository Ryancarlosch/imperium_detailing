import 'package:flutter/material.dart';

import '../models/agendamento.dart';
import '../models/cliente.dart';
import '../models/veiculo.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/veiculo_repository.dart';

class NovoAgendamentoPage extends StatefulWidget {
  const NovoAgendamentoPage({super.key});

  @override
  State<NovoAgendamentoPage> createState() => _NovoAgendamentoPageState();
}

class _NovoAgendamentoPageState extends State<NovoAgendamentoPage> {
  final ClienteRepository _clienteRepository = ClienteRepository();

  final VeiculoRepository _veiculoRepository = VeiculoRepository();

  final AgendamentoRepository _agendamentoRepository = AgendamentoRepository();

  final TextEditingController _servicoController = TextEditingController();

  final TextEditingController _valorController = TextEditingController();

  final TextEditingController _observacoesController = TextEditingController();

  List<Cliente> clientes = [];
  List<Veiculo> veiculos = [];

  Cliente? clienteSelecionado;
  Veiculo? veiculoSelecionado;

  DateTime dataSelecionada = DateTime.now();

  TimeOfDay horaSelecionada = const TimeOfDay(hour: 8, minute: 0);

  String statusSelecionado = 'Agendado';

  bool carregando = true;
  bool salvando = false;

  final List<String> statusDisponiveis = [
    'Agendado',
    'Em andamento',
    'Finalizado',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    carregarClientes();
  }

  @override
  void dispose() {
    _servicoController.dispose();
    _valorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> carregarClientes() async {
    try {
      final lista = await _clienteRepository.listarClientes();

      if (!mounted) return;

      setState(() {
        clientes = lista;
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar clientes: $erro')),
      );
    }
  }

  Future<void> carregarVeiculosDoCliente(Cliente? cliente) async {
    setState(() {
      clienteSelecionado = cliente;
      veiculoSelecionado = null;
      veiculos = [];
    });

    if (cliente?.id == null) {
      return;
    }

    try {
      final lista = await _veiculoRepository.listarVeiculosDoCliente(
        cliente!.id!,
      );

      if (!mounted) return;

      setState(() {
        veiculos = lista;
      });
    } catch (erro) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar veículos: $erro')),
      );
    }
  }

  Future<void> selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: dataSelecionada,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (data == null) return;

    setState(() {
      dataSelecionada = data;
    });
  }

  Future<void> selecionarHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: horaSelecionada,
    );

    if (hora == null) return;

    setState(() {
      horaSelecionada = hora;
    });
  }

  String formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();

    return '$dia/$mes/$ano';
  }

  String formatarHora(TimeOfDay hora) {
    final horas = hora.hour.toString().padLeft(2, '0');
    final minutos = hora.minute.toString().padLeft(2, '0');

    return '$horas:$minutos';
  }

  double converterValor(String texto) {
    String valor = texto.trim();

    valor = valor.replaceAll('R\$', '');
    valor = valor.replaceAll(' ', '');

    if (valor.contains(',')) {
      valor = valor.replaceAll('.', '');
      valor = valor.replaceAll(',', '.');
    }

    return double.tryParse(valor) ?? 0;
  }

  Future<void> salvarAgendamento() async {
    final cliente = clienteSelecionado;
    final veiculo = veiculoSelecionado;
    final servico = _servicoController.text.trim();

    if (cliente?.id == null) {
      mostrarMensagem('Selecione um cliente.');
      return;
    }

    if (veiculo?.id == null) {
      mostrarMensagem('Selecione um veículo.');
      return;
    }

    if (servico.isEmpty) {
      mostrarMensagem('Informe o serviço.');
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      final agendamento = Agendamento(
        clienteId: cliente!.id!,
        veiculoId: veiculo!.id!,
        servico: servico,
        data: formatarData(dataSelecionada),
        hora: formatarHora(horaSelecionada),
        valor: converterValor(_valorController.text),
        status: statusSelecionado,
        observacoes: _observacoesController.text.trim(),
      );

      await _agendamentoRepository.inserirAgendamento(agendamento);

      if (!mounted) return;

      Navigator.pop(context, agendamento.data);
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        salvando = false;
      });

      mostrarMensagem('Erro ao salvar agendamento: $erro');
    }
  }

  void mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  InputDecoration criarDecoracao({
    required String label,
    required IconData icone,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icone),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo agendamento')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Cliente>(
                  value: clienteSelecionado,
                  decoration: criarDecoracao(
                    label: 'Cliente',
                    icone: Icons.person_outline,
                  ),
                  items: clientes.map((cliente) {
                    return DropdownMenuItem<Cliente>(
                      value: cliente,
                      child: Text(cliente.nome),
                    );
                  }).toList(),
                  onChanged: carregarVeiculosDoCliente,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Veiculo>(
                  value: veiculoSelecionado,
                  decoration: criarDecoracao(
                    label: 'Veículo',
                    icone: Icons.directions_car_outlined,
                  ),
                  items: veiculos.map((veiculo) {
                    final placa = veiculo.placa.isEmpty
                        ? ''
                        : ' • ${veiculo.placa}';

                    return DropdownMenuItem<Veiculo>(
                      value: veiculo,
                      child: Text(
                        '${veiculo.marca} '
                        '${veiculo.modelo}$placa',
                      ),
                    );
                  }).toList(),
                  onChanged: clienteSelecionado == null
                      ? null
                      : (veiculo) {
                          setState(() {
                            veiculoSelecionado = veiculo;
                          });
                        },
                ),
                if (clienteSelecionado != null && veiculos.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Este cliente não possui veículos cadastrados.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _servicoController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: criarDecoracao(
                    label: 'Serviço',
                    icone: Icons.cleaning_services_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _valorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: criarDecoracao(
                    label: 'Valor em R\$',
                    icone: Icons.attach_money_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    onTap: selecionarData,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Data'),
                    subtitle: Text(formatarData(dataSelecionada)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    onTap: selecionarHora,
                    leading: const Icon(Icons.access_time_outlined),
                    title: const Text('Horário'),
                    subtitle: Text(formatarHora(horaSelecionada)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: statusSelecionado,
                  decoration: criarDecoracao(
                    label: 'Status',
                    icone: Icons.info_outline,
                  ),
                  items: statusDisponiveis.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status),
                    );
                  }).toList(),
                  onChanged: (status) {
                    if (status == null) return;

                    setState(() {
                      statusSelecionado = status;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _observacoesController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: criarDecoracao(
                    label: 'Observações',
                    icone: Icons.notes_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: salvando ? null : salvarAgendamento,
                  icon: salvando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar agendamento'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
