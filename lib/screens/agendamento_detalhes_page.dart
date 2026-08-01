import 'package:flutter/material.dart';

import '../models/agendamento.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/ordem_servico_repository.dart';
import '../repositories/veiculo_repository.dart';
import '../services/whatsapp_service.dart';
import 'nova_ordem_servico_page.dart';

class AgendamentoDetalhesPage extends StatefulWidget {
  final Agendamento agendamento;

  const AgendamentoDetalhesPage({super.key, required this.agendamento});

  @override
  State<AgendamentoDetalhesPage> createState() =>
      _AgendamentoDetalhesPageState();
}

class _AgendamentoDetalhesPageState extends State<AgendamentoDetalhesPage> {
  final AgendamentoRepository _repository = AgendamentoRepository();

  final OrdemServicoRepository _ordemServicoRepository =
      OrdemServicoRepository();

  final VeiculoRepository _veiculoRepository = VeiculoRepository();

  late Agendamento agendamento;

  bool _abrindoWhatsApp = false;
  bool _verificandoOrdemServico = true;
  bool _abrindoOrdemServico = false;

  final List<String> statusDisponiveis = [
    'Agendado',
    'Em andamento',
    'Finalizado',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    agendamento = widget.agendamento;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarOrdemServico();
    });
  }

  Future<void> _verificarOrdemServico() async {
    final agendamentoId = agendamento.id;

    if (agendamentoId == null) {
      if (mounted) {
        setState(() {
          _verificandoOrdemServico = false;
        });
      }
      return;
    }

    try {
      await _ordemServicoRepository.buscarIdOrdemPorAgendamento(agendamentoId);

      if (!mounted) {
        return;
      }

      setState(() {
        _verificandoOrdemServico = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _verificandoOrdemServico = false;
      });
    }
  }

  Future<void> _recarregarAgendamento() async {
    if (agendamento.id == null) {
      return;
    }

    try {
      final atualizado = await _repository.buscarAgendamentoPorId(
        agendamento.id!,
      );

      if (!mounted || atualizado == null) {
        return;
      }

      setState(() {
        agendamento = atualizado;
      });
    } catch (_) {
      // Ignorar falhas na recarga para não interromper a experiência.
    }
  }

  Future<void> _criarOuAbrirOrdemServico() async {
    if (_abrindoOrdemServico) {
      return;
    }

    setState(() {
      _abrindoOrdemServico = true;
    });

    try {
      final criou = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NovaOrdemServicoPage(agendamento: agendamento),
        ),
      );

      if (!mounted) {
        return;
      }

      if (criou == true) {
        await _verificarOrdemServico();
        await _recarregarAgendamento();

        if (mounted) {
          mostrarMensagem(
            'Ordem de Serviço criada e vinculada ao agendamento.',
          );
        }
      }
    } catch (erro, stackTrace) {
      debugPrint('Erro ao abrir nova Ordem de Serviço: $erro');

      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        mostrarMensagem(
          'Não foi possível abrir a nova Ordem de Serviço.\n$erro',
          erro: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _abrindoOrdemServico = false;
        });
      }
    }
  }

  String formatarValor(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Color corDoStatus(String status) {
    switch (status) {
      case 'Em andamento':
        return Colors.orange;
      case 'Finalizado':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget criarInformacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icone),
        title: Text(titulo),
        subtitle: Text(valor.trim().isEmpty ? 'Não informado' : valor),
      ),
    );
  }

  Future<Map<String, dynamic>?> buscarDadosParaWhatsApp() async {
    return _veiculoRepository.buscarVeiculoComClientePorId(
      agendamento.veiculoId,
    );
  }

  Future<void> enviarConfirmacaoWhatsApp() async {
    if (_abrindoWhatsApp) {
      return;
    }

    setState(() {
      _abrindoWhatsApp = true;
    });

    try {
      final dados = await buscarDadosParaWhatsApp();

      if (dados == null) {
        throw Exception('Cliente ou veículo não encontrado.');
      }

      final nomeCliente = (dados['cliente_nome'] ?? '').toString().trim();

      final telefone = (dados['cliente_telefone'] ?? '').toString().trim();

      final marca = (dados['marca'] ?? '').toString().trim();
      final modelo = (dados['modelo'] ?? '').toString().trim();
      final placa = (dados['placa'] ?? '').toString().trim();

      if (telefone.isEmpty) {
        mostrarMensagem(
          'O cliente não possui telefone cadastrado.',
          erro: true,
        );
        return;
      }

      final veiculo = '$marca $modelo'.trim();

      await WhatsAppService.confirmarAgendamento(
        telefone: telefone,
        cliente: nomeCliente,
        data: agendamento.data,
        horario: agendamento.hora,
        veiculo: veiculo,
        placa: placa,
        servico: agendamento.servico,
      );
    } catch (erro) {
      mostrarMensagem('Erro ao abrir o WhatsApp: $erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _abrindoWhatsApp = false;
        });
      }
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
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

  Future<void> alterarStatus() async {
    String novoStatus = agendamento.status;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Alterar status'),
              content: DropdownButtonFormField<String>(
                value: novoStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.info_outline),
                ),
                items: statusDisponiveis.map((status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
                onChanged: (status) {
                  if (status == null) {
                    return;
                  }

                  setDialogState(() {
                    novoStatus = status;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmou != true || agendamento.id == null) {
      return;
    }

    await _repository.atualizarStatus(agendamento.id!, novoStatus);

    if (!mounted) {
      return;
    }

    setState(() {
      agendamento = agendamento.copyWith(status: novoStatus);
    });

    mostrarMensagem('Status atualizado com sucesso.');
  }

  Future<void> excluirAgendamento() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir agendamento'),
          content: const Text('Deseja realmente excluir este agendamento?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmou != true || agendamento.id == null) {
      return;
    }

    await _repository.excluirAgendamento(agendamento.id!);

    if (!mounted) {
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final corStatus = corDoStatus(agendamento.status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do agendamento'),
        actions: [
          IconButton(
            onPressed: excluirAgendamento,
            tooltip: 'Excluir agendamento',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: corStatus.withValues(alpha: 0.18),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 46,
              color: corStatus,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            agendamento.servico,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Center(
            child: Chip(
              avatar: Icon(Icons.circle, size: 14, color: corStatus),
              label: Text(agendamento.status),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: alterarStatus,
            icon: const Icon(Icons.sync_outlined),
            label: const Text('Alterar status'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _abrindoWhatsApp ? null : enviarConfirmacaoWhatsApp,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            icon: _abrindoWhatsApp
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.chat_outlined),
            label: Text(
              _abrindoWhatsApp
                  ? 'Abrindo WhatsApp...'
                  : 'Enviar confirmação pelo WhatsApp',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _verificandoOrdemServico || _abrindoOrdemServico
                ? null
                : _criarOuAbrirOrdemServico,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD6A84B),
              foregroundColor: Colors.black,
            ),
            icon: _verificandoOrdemServico || _abrindoOrdemServico
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.add_task_outlined),
            label: const Text('Criar Ordem de Serviço'),
          ),
          const SizedBox(height: 24),
          criarInformacao(
            icone: Icons.calendar_today_outlined,
            titulo: 'Data',
            valor: agendamento.data,
          ),
          criarInformacao(
            icone: Icons.access_time_outlined,
            titulo: 'Horário',
            valor: agendamento.hora,
          ),
          criarInformacao(
            icone: Icons.attach_money_outlined,
            titulo: 'Valor',
            valor: formatarValor(agendamento.valor),
          ),
          criarInformacao(
            icone: Icons.notes_outlined,
            titulo: 'Observações',
            valor: agendamento.observacoes,
          ),
        ],
      ),
    );
  }
}
