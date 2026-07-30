import 'package:flutter/material.dart';

import '../models/agendamento.dart';
import '../models/movimento_financeiro.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../repositories/veiculo_repository.dart';
import '../services/notification_service.dart';
import '../services/whatsapp_service.dart';
import 'agendamento_detalhes_page.dart';
import 'novo_agendamento_page.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final AgendamentoRepository _repository =
  AgendamentoRepository();

  final FinanceiroRepository _financeiroRepository =
  FinanceiroRepository();

  final VeiculoRepository _veiculoRepository =
  VeiculoRepository();

  List<Agendamento> agendamentos = [];

  bool carregando = true;
  bool _permissaoSolicitada = false;

  int? _agendamentoAbrindoWhatsAppId;

  @override
  void initState() {
    super.initState();
    carregarAgendamentos();
  }

  Future<void> carregarAgendamentos() async {
    try {
      final lista =
      await _repository.listarAgendamentos();

      if (!_permissaoSolicitada) {
        _permissaoSolicitada = true;

        await NotificationService.instance
            .solicitarPermissao();
      }

      await NotificationService.instance
          .sincronizarAgendamentos(lista);

      if (!mounted) return;

      setState(() {
        agendamentos = lista;
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar agenda: $erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> abrirNovoAgendamento() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const NovoAgendamentoPage();
        },
      ),
    );

    if (salvou == true) {
      setState(() {
        carregando = true;
      });

      await carregarAgendamentos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agendamento salvo e lembrete atualizado.',
          ),
        ),
      );
    }
  }

  Future<void> abrirDetalhes(
      Agendamento agendamento,
      ) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return AgendamentoDetalhesPage(
            agendamento: agendamento,
          );
        },
      ),
    );

    if (agendamento.id != null) {
      final atualizado =
      await _repository.buscarAgendamentoPorId(
        agendamento.id!,
      );

      if (atualizado != null &&
          atualizado.status == 'Finalizado') {
        await _oferecerLancamentoFinanceiro(
          atualizado,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      carregando = true;
    });

    await carregarAgendamentos();
  }

  Future<void> abrirWhatsApp(
      Agendamento agendamento,
      ) async {
    if (_agendamentoAbrindoWhatsAppId != null) {
      return;
    }

    setState(() {
      _agendamentoAbrindoWhatsAppId =
          agendamento.id ?? -1;
    });

    try {
      final dados =
      await _veiculoRepository
          .buscarVeiculoComClientePorId(
        agendamento.veiculoId,
      );

      if (dados == null) {
        throw Exception(
          'Não foi possível localizar o veículo '
              'e o cliente deste agendamento.',
        );
      }

      final cliente =
      (dados['cliente_nome'] ?? '')
          .toString()
          .trim();

      final telefone =
      (dados['cliente_telefone'] ?? '')
          .toString()
          .trim();

      final marca =
      (dados['marca'] ?? '')
          .toString()
          .trim();

      final modelo =
      (dados['modelo'] ?? '')
          .toString()
          .trim();

      final placa =
      (dados['placa'] ?? '')
          .toString()
          .trim();

      if (cliente.isEmpty) {
        throw Exception(
          'O nome do cliente não foi encontrado.',
        );
      }

      if (telefone.isEmpty) {
        throw Exception(
          'O cliente $cliente não possui '
              'telefone cadastrado.',
        );
      }

      final partesVeiculo = <String>[
        marca,
        modelo,
      ].where(
            (parte) => parte.isNotEmpty,
      ).toList();

      var veiculo = partesVeiculo.join(' ');

      if (placa.isNotEmpty) {
        if (veiculo.isNotEmpty) {
          veiculo = '$veiculo • $placa';
        } else {
          veiculo = placa;
        }
      }

      if (veiculo.isEmpty) {
        veiculo = 'Veículo não informado';
      }

      await WhatsAppService.confirmarAgendamento(
        telefone: telefone,
        cliente: cliente,
        data: agendamento.data,
        horario: agendamento.hora,
        veiculo: veiculo,
        servico: agendamento.servico,
      );
    } catch (erro) {
      if (!mounted) return;

      final mensagem = erro
          .toString()
          .replaceFirst(
        'Exception: ',
        '',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _agendamentoAbrindoWhatsAppId = null;
      });
    }
  }

  Future<void> abrirOpcoesWhatsApp(
      Agendamento agendamento,
      ) async {
    final opcao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Enviar pelo WhatsApp',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(
                      Icons.event_available_outlined,
                    ),
                  ),
                  title: const Text(
                    'Confirmar agendamento',
                  ),
                  subtitle: const Text(
                    'Envia data, horário, veículo '
                        'e serviço.',
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                      'confirmacao',
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(
                      Icons.notifications_active_outlined,
                    ),
                  ),
                  title: const Text(
                    'Enviar lembrete',
                  ),
                  subtitle: const Text(
                    'Lembra o cliente sobre o '
                        'agendamento.',
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                      'lembrete',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (opcao == null) {
      return;
    }

    if (opcao == 'confirmacao') {
      await abrirWhatsApp(
        agendamento,
      );

      return;
    }

    if (opcao == 'lembrete') {
      await enviarLembreteWhatsApp(
        agendamento,
      );
    }
  }

  Future<void> enviarLembreteWhatsApp(
      Agendamento agendamento,
      ) async {
    if (_agendamentoAbrindoWhatsAppId != null) {
      return;
    }

    setState(() {
      _agendamentoAbrindoWhatsAppId =
          agendamento.id ?? -1;
    });

    try {
      final dados =
      await _veiculoRepository
          .buscarVeiculoComClientePorId(
        agendamento.veiculoId,
      );

      if (dados == null) {
        throw Exception(
          'Não foi possível localizar o veículo '
              'e o cliente deste agendamento.',
        );
      }

      final cliente =
      (dados['cliente_nome'] ?? '')
          .toString()
          .trim();

      final telefone =
      (dados['cliente_telefone'] ?? '')
          .toString()
          .trim();

      final marca =
      (dados['marca'] ?? '')
          .toString()
          .trim();

      final modelo =
      (dados['modelo'] ?? '')
          .toString()
          .trim();

      final placa =
      (dados['placa'] ?? '')
          .toString()
          .trim();

      if (cliente.isEmpty) {
        throw Exception(
          'O nome do cliente não foi encontrado.',
        );
      }

      if (telefone.isEmpty) {
        throw Exception(
          'O cliente $cliente não possui '
              'telefone cadastrado.',
        );
      }

      final partesVeiculo = <String>[
        marca,
        modelo,
      ].where(
            (parte) => parte.isNotEmpty,
      ).toList();

      var veiculo = partesVeiculo.join(' ');

      if (placa.isNotEmpty) {
        if (veiculo.isNotEmpty) {
          veiculo = '$veiculo • $placa';
        } else {
          veiculo = placa;
        }
      }

      if (veiculo.isEmpty) {
        veiculo = 'Veículo não informado';
      }

      await WhatsAppService
          .enviarLembreteAgendamento(
        telefone: telefone,
        cliente: cliente,
        data: agendamento.data,
        horario: agendamento.hora,
        veiculo: veiculo,
      );
    } catch (erro) {
      if (!mounted) return;

      final mensagem = erro
          .toString()
          .replaceFirst(
        'Exception: ',
        '',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _agendamentoAbrindoWhatsAppId = null;
      });
    }
  }

  Future<void> _oferecerLancamentoFinanceiro(
      Agendamento agendamento,
      ) async {
    if (agendamento.id == null) {
      return;
    }

    final jaExiste =
    await _financeiroRepository
        .existeMovimentoDoAgendamento(
      agendamento.id!,
    );

    if (jaExiste || !mounted) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Lançar no financeiro?',
          ),
          content: Text(
            'O serviço "${agendamento.servico}" foi '
                'finalizado.\n\n'
                'Deseja registrar uma entrada de '
                '${formatarValor(agendamento.valor)}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Agora não',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              icon: const Icon(
                Icons.attach_money,
              ),
              label: const Text(
                'Lançar',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    try {
      final movimento = MovimentoFinanceiro(
        tipo: 'Entrada',
        descricao:
        'Serviço finalizado: ${agendamento.servico}',
        valor: agendamento.valor,
        formaPagamento: 'Não informado',
        data: DateTime.now().toIso8601String(),
        clienteId: agendamento.clienteId,
        agendamentoId: agendamento.id,
      );

      await _financeiroRepository.inserirMovimento(
        movimento,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entrada de '
                '${formatarValor(agendamento.valor)} '
                'lançada no financeiro.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (erro) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao lançar no financeiro: $erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String formatarValor(double valor) {
    return 'R\$ '
        '${valor.toStringAsFixed(2).replaceAll('.', ',')}';
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

  IconData iconeDoStatus(String status) {
    switch (status) {
      case 'Em andamento':
        return Icons.sync;
      case 'Finalizado':
        return Icons.check_circle_outline;
      case 'Cancelado':
        return Icons.cancel_outlined;
      default:
        return Icons.schedule;
    }
  }

  bool estaAbrindoWhatsApp(
      Agendamento agendamento,
      ) {
    return _agendamentoAbrindoWhatsAppId ==
        (agendamento.id ?? -1);
  }

  Widget construirCardAgendamento(
      Agendamento agendamento,
      ) {
    final cor = corDoStatus(
      agendamento.status,
    );

    final abrindoWhatsApp =
    estaAbrindoWhatsApp(
      agendamento,
    );

    final podeEnviarWhatsApp =
        agendamento.status != 'Cancelado';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          abrirDetalhes(
            agendamento,
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            14,
            10,
            10,
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor:
                    cor.withValues(
                      alpha: 0.18,
                    ),
                    child: Icon(
                      iconeDoStatus(
                        agendamento.status,
                      ),
                      color: cor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          agendamento.servico,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${agendamento.data} às '
                              '${agendamento.hora}',
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatarValor(
                            agendamento.valor,
                          )} • '
                              '${agendamento.status}',
                          style: TextStyle(
                            color: cor,
                            fontWeight:
                            FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(
                      top: 8,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                    ),
                  ),
                ],
              ),
              if (podeEnviarWhatsApp) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: abrindoWhatsApp
                        ? null
                        : () {
                      abrirOpcoesWhatsApp(
                        agendamento,
                      );
                    },
                    icon: abrindoWhatsApp
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(
                      Icons.chat_outlined,
                    ),
                    label: Text(
                      abrindoWhatsApp
                          ? 'Abrindo...'
                          : 'WhatsApp',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agenda de serviços',
        ),
      ),
      body: carregando
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : agendamentos.isEmpty
          ? const Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 72,
              color: Colors.white38,
            ),
            SizedBox(height: 16),
            Text(
              'Nenhum agendamento cadastrado',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Toque no botão + para agendar',
              style: TextStyle(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: carregarAgendamentos,
        child: ListView.separated(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.all(16),
          itemCount:
          agendamentos.length,
          separatorBuilder:
              (_, __) {
            return const SizedBox(
              height: 10,
            );
          },
          itemBuilder:
              (context, index) {
            final agendamento =
            agendamentos[index];

            return construirCardAgendamento(
              agendamento,
            );
          },
        ),
      ),
      floatingActionButton:
      FloatingActionButton(
        onPressed: abrirNovoAgendamento,
        child: const Icon(
          Icons.add,
        ),
      ),
    );
  }
}