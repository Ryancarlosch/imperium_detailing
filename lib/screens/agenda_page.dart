
import 'package:flutter/material.dart';

import '../models/agendamento.dart';
import '../models/movimento_financeiro.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/financeiro_repository.dart';
import '../services/notification_service.dart';
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

  List<Agendamento> agendamentos = [];
  bool carregando = true;
  bool _permissaoSolicitada = false;

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
                    mainAxisSize: MainAxisSize.min,
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
                          fontWeight: FontWeight.bold,
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
                    padding: const EdgeInsets.all(16),
                    itemCount: agendamentos.length,
                    separatorBuilder: (_, __) {
                      return const SizedBox(
                        height: 10,
                      );
                    },
                    itemBuilder: (context, index) {
                      final agendamento =
                          agendamentos[index];

                      final cor = corDoStatus(
                        agendamento.status,
                      );

                      return Card(
                        child: ListTile(
                          onTap: () {
                            abrirDetalhes(
                              agendamento,
                            );
                          },
                          leading: CircleAvatar(
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
                          title: Text(
                            agendamento.servico,
                          ),
                          subtitle: Text(
                            '${agendamento.data} às '
                            '${agendamento.hora}\n'
                            '${formatarValor(agendamento.valor)}'
                            ' • ${agendamento.status}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(
                            Icons.chevron_right,
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: abrirNovoAgendamento,
        child: const Icon(
          Icons.add,
        ),
      ),
    );
  }
}
