import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final AgendamentoRepository _repository = AgendamentoRepository();

  final FinanceiroRepository _financeiroRepository = FinanceiroRepository();

  final VeiculoRepository _veiculoRepository = VeiculoRepository();

  List<_AgendamentoAgendaItem> _itensAgenda = [];

  bool carregando = true;
  bool _permissaoSolicitada = false;
  bool _mostrarAnteriores = false;

  String? _dataDestacada;

  int? _agendamentoAbrindoWhatsAppId;

  @override
  void initState() {
    super.initState();
    carregarAgendamentos();
  }

  Future<void> carregarAgendamentos() async {
    try {
      final listaDetalhes = await _repository.listarAgendamentosComDetalhes();
      final lista = listaDetalhes
          .map((mapa) => Agendamento.fromMap(mapa))
          .toList();

      if (!_permissaoSolicitada) {
        _permissaoSolicitada = true;

        await NotificationService.instance.solicitarPermissao();
      }

      await NotificationService.instance.sincronizarAgendamentos(lista);

      if (!mounted) return;

      setState(() {
        _itensAgenda = listaDetalhes
            .map(_AgendamentoAgendaItem.fromMap)
            .toList();
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar agenda: $erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> abrirNovoAgendamento() async {
    final retorno = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const NovoAgendamentoPage();
        },
      ),
    );

    final salvou = retorno == true || retorno is String;
    final dataCriada = retorno is String ? retorno.trim() : null;

    if (salvou == true) {
      final chaveDataCriada = dataCriada != null && dataCriada.isNotEmpty
          ? _chaveDia(_parseData(dataCriada))
          : null;

      setState(() {
        carregando = true;
        _dataDestacada = chaveDataCriada;
      });

      await carregarAgendamentos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agendamento salvo e lembrete atualizado.'),
        ),
      );
    }
  }

  Future<void> abrirDetalhes(Agendamento agendamento) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return AgendamentoDetalhesPage(agendamento: agendamento);
        },
      ),
    );

    if (agendamento.id != null) {
      final atualizado = await _repository.buscarAgendamentoPorId(
        agendamento.id!,
      );

      if (atualizado != null && atualizado.status == 'Finalizado') {
        await _oferecerLancamentoFinanceiro(atualizado);
      }
    }

    if (!mounted) return;

    setState(() {
      carregando = true;
    });

    await carregarAgendamentos();
  }

  Future<void> abrirWhatsApp(Agendamento agendamento) async {
    if (_agendamentoAbrindoWhatsAppId != null) {
      return;
    }

    setState(() {
      _agendamentoAbrindoWhatsAppId = agendamento.id ?? -1;
    });

    try {
      final dados = await _carregarDadosClienteVeiculoWhatsApp(agendamento);

      await WhatsAppService.confirmarAgendamento(
        telefone: dados.telefone,
        cliente: dados.cliente,
        data: agendamento.data,
        horario: agendamento.hora,
        veiculo: dados.veiculo,
        placa: dados.placa,
        servico: agendamento.servico,
      );
    } catch (erro) {
      if (!mounted) return;

      final mensagem = erro.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _agendamentoAbrindoWhatsAppId = null;
        });
      }
    }
  }


  Future<void> abrirOpcoesWhatsApp(Agendamento agendamento) async {
    final opcao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Enviar pelo WhatsApp',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.event_available_outlined),
                  ),
                  title: const Text('Confirmar agendamento'),
                  subtitle: const Text(
                    'Envia data, horário, veículo '
                    'e serviço.',
                  ),
                  onTap: () {
                    Navigator.pop(context, 'confirmacao');
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.notifications_active_outlined),
                  ),
                  title: const Text('Enviar lembrete'),
                  subtitle: const Text(
                    'Lembra o cliente sobre o '
                    'agendamento.',
                  ),
                  onTap: () {
                    Navigator.pop(context, 'lembrete');
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
      await abrirWhatsApp(agendamento);

      return;
    }

    if (opcao == 'lembrete') {
      await enviarLembreteWhatsApp(agendamento);
    }
  }

  Future<void> enviarLembreteWhatsApp(Agendamento agendamento) async {
    if (_agendamentoAbrindoWhatsAppId != null) {
      return;
    }

    setState(() {
      _agendamentoAbrindoWhatsAppId = agendamento.id ?? -1;
    });

    try {
      final dados = await _carregarDadosClienteVeiculoWhatsApp(agendamento);

      await WhatsAppService.enviarLembreteAgendamento(
        telefone: dados.telefone,
        cliente: dados.cliente,
        data: agendamento.data,
        horario: agendamento.hora,
        veiculo: dados.veiculo,
        placa: dados.placa,
      );
    } catch (erro) {
      if (!mounted) return;

      final mensagem = erro.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _agendamentoAbrindoWhatsAppId = null;
      });
    }
  }

  Future<_ContatoAgendamentoWhatsApp> _carregarDadosClienteVeiculoWhatsApp(
    Agendamento agendamento,
  ) async {
    final dados = await _veiculoRepository.buscarVeiculoComClientePorId(
      agendamento.veiculoId,
    );

    if (dados == null) {
      throw Exception(
        'Não foi possível localizar o veículo e o cliente deste agendamento.',
      );
    }

    final cliente = (dados['cliente_nome'] ?? '').toString().trim();

    final telefone = (dados['cliente_telefone'] ?? '').toString().trim();

    final marca = (dados['marca'] ?? '').toString().trim();

    final modelo = (dados['modelo'] ?? '').toString().trim();

    final placa = (dados['placa'] ?? '').toString().trim();

    if (cliente.isEmpty) {
      throw Exception('O nome do cliente não foi encontrado.');
    }

    if (telefone.isEmpty) {
      throw Exception('O cliente $cliente não possui telefone cadastrado.');
    }

    final veiculo = '$marca $modelo'.trim();

    return _ContatoAgendamentoWhatsApp(
      cliente: cliente,
      telefone: telefone,
      veiculo: veiculo,
      placa: placa,
    );
  }

  Future<void> _oferecerLancamentoFinanceiro(Agendamento agendamento) async {
    if (agendamento.id == null) {
      return;
    }

    final jaExiste = await _financeiroRepository.existeMovimentoDoAgendamento(
      agendamento.id!,
    );

    if (jaExiste || !mounted) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lançar no financeiro?'),
          content: Text(
            'O serviço "${agendamento.servico}" foi '
            'finalizado.\n\n'
            'Deseja registrar uma entrada de '
            '${formatarValor(agendamento.valor)}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Agora não'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.attach_money),
              label: const Text('Lançar'),
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
        descricao: 'Serviço finalizado: ${agendamento.servico}',
        valor: agendamento.valor,
        formaPagamento: 'Não informado',
        data: DateTime.now().toIso8601String(),
        clienteId: agendamento.clienteId,
        agendamentoId: agendamento.id,
      );

      await _financeiroRepository.inserirMovimento(movimento);

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
          content: Text('Erro ao lançar no financeiro: $erro'),
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

  bool estaAbrindoWhatsApp(Agendamento agendamento) {
    return _agendamentoAbrindoWhatsAppId == (agendamento.id ?? -1);
  }

  DateTime _parseData(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final iso = DateTime.tryParse(texto);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final partes = texto.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]) ?? 1;
      final mes = int.tryParse(partes[1]) ?? 1;
      final ano = int.tryParse(partes[2]) ?? 1970;

      return DateTime(ano, mes, dia);
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Duration _parseHora(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return Duration.zero;
    }

    final partes = texto.split(':');
    if (partes.length < 2) {
      return Duration.zero;
    }

    final hora = int.tryParse(partes[0]) ?? 0;
    final minuto = int.tryParse(partes[1]) ?? 0;

    return Duration(hours: hora, minutes: minuto);
  }

  DateTime _momento(Agendamento agendamento) {
    final data = _parseData(agendamento.data);
    final hora = _parseHora(agendamento.hora);

    return DateTime(
      data.year,
      data.month,
      data.day,
      hora.inHours,
      hora.inMinutes.remainder(60),
    );
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) {
      return texto;
    }

    return texto[0].toUpperCase() + texto.substring(1);
  }

  String _chaveDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');

    return '$ano-$mes-$dia';
  }

  String _rotuloDia(DateTime data) {
    final diaSemana = _capitalizar(DateFormat('EEEE', 'pt_BR').format(data));
    final hoje = DateTime.now();
    final formatoData = data.year == hoje.year ? 'dd/MM' : 'dd/MM/yyyy';
    final dataFormatada = DateFormat(formatoData, 'pt_BR').format(data);

    return '$diaSemana — $dataFormatada';
  }

  List<_BlocoAgendaDia> _agruparItensPorDia(
    List<_AgendamentoAgendaItem> itens,
  ) {
    final blocos = <_BlocoAgendaDia>[];
    String? chaveAtual;

    for (final item in itens) {
      final momento = _momento(item.agendamento);
      final chave = _chaveDia(momento);

      if (chaveAtual != chave) {
        blocos.add(
          _BlocoAgendaDia(
            chaveDia: chave,
            titulo: _rotuloDia(momento),
            itens: [item],
          ),
        );
        chaveAtual = chave;
      } else {
        blocos.last.itens.add(item);
      }
    }

    return blocos;
  }

  Widget _cabecalhoDia(_BlocoAgendaDia bloco) {
    final destacado =
        _dataDestacada != null && _dataDestacada == bloco.chaveDia;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(
          0xFFD6A84B,
        ).withValues(alpha: destacado ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(
            0xFFD6A84B,
          ).withValues(alpha: destacado ? 0.62 : 0.36),
        ),
      ),
      child: Text(
        bloco.titulo,
        style: TextStyle(
          color: Colors.amber.shade100,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget construirCardAgendamento(_AgendamentoAgendaItem item) {
    final agendamento = item.agendamento;
    final cor = corDoStatus(agendamento.status);

    final abrindoWhatsApp = estaAbrindoWhatsApp(agendamento);

    final podeEnviarWhatsApp = agendamento.status != 'Cancelado';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          abrirDetalhes(agendamento);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: cor.withValues(alpha: 0.18),
                    child: Icon(iconeDoStatus(agendamento.status), color: cor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agendamento.servico,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${agendamento.hora} • ${item.cliente}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.veiculo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.placa.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.placa.toUpperCase()),
                        ],
                        if (item.responsavel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Responsável: ${item.responsavel}'),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${formatarValor(agendamento.valor)} • '
                          '${agendamento.status}',
                          style: TextStyle(
                            color: cor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(Icons.chevron_right),
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
                            abrirOpcoesWhatsApp(agendamento);
                          },
                    icon: abrindoWhatsApp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_outlined),
                    label: Text(abrindoWhatsApp ? 'Abrindo...' : 'WhatsApp'),
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
      appBar: AppBar(title: const Text('Agenda de serviços')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : _construirCorpoAgenda(),
      floatingActionButton: FloatingActionButton(
        onPressed: abrirNovoAgendamento,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _construirCorpoAgenda() {
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);

    final itensFiltrados = _itensAgenda.where((item) {
      if (_mostrarAnteriores) {
        return true;
      }

      final momento = _momento(item.agendamento);
      return !momento.isBefore(inicioHoje);
    }).toList();

    final blocos = _agruparItensPorDia(itensFiltrados);

    if (blocos.isEmpty) {
      return RefreshIndicator(
        onRefresh: carregarAgendamentos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Hoje em diante'),
                        selected: !_mostrarAnteriores,
                        onSelected: (_) {
                          setState(() {
                            _mostrarAnteriores = false;
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Incluir anteriores'),
                        selected: _mostrarAnteriores,
                        onSelected: (_) {
                          setState(() {
                            _mostrarAnteriores = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            const Icon(
              Icons.calendar_month_outlined,
              size: 72,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum agendamento cadastrado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toque no botão + para agendar',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: carregarAgendamentos,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: blocos.length,
        itemBuilder: (context, index) {
          final bloco = blocos[index];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index == 0) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Hoje em diante'),
                      selected: !_mostrarAnteriores,
                      onSelected: (_) {
                        setState(() {
                          _mostrarAnteriores = false;
                        });
                      },
                    ),
                    FilterChip(
                      label: const Text('Incluir anteriores'),
                      selected: _mostrarAnteriores,
                      onSelected: (_) {
                        setState(() {
                          _mostrarAnteriores = true;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              _cabecalhoDia(bloco),
              ...List.generate(bloco.itens.length, (itemIndex) {
                final item = bloco.itens[itemIndex];

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: itemIndex == bloco.itens.length - 1 ? 10 : 8,
                  ),
                  child: construirCardAgendamento(item),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ContatoAgendamentoWhatsApp {
  const _ContatoAgendamentoWhatsApp({
    required this.cliente,
    required this.telefone,
    required this.veiculo,
    required this.placa,
  });

  final String cliente;
  final String telefone;
  final String veiculo;
  final String placa;
}

class _AgendamentoAgendaItem {
  const _AgendamentoAgendaItem({
    required this.agendamento,
    required this.cliente,
    required this.veiculo,
    required this.placa,
    required this.responsavel,
  });

  factory _AgendamentoAgendaItem.fromMap(Map<String, dynamic> mapa) {
    final marca = (mapa['veiculo_marca'] ?? '').toString().trim();
    final modelo = (mapa['veiculo_modelo'] ?? '').toString().trim();
    final veiculo = '$marca $modelo'.trim();

    return _AgendamentoAgendaItem(
      agendamento: Agendamento.fromMap(mapa),
      cliente: (mapa['cliente_nome'] ?? '').toString().trim(),
      veiculo: veiculo.isEmpty ? 'Veículo não informado' : veiculo,
      placa: (mapa['veiculo_placa'] ?? '').toString().trim(),
      responsavel: (mapa['responsavel'] ?? '').toString().trim(),
    );
  }

  final Agendamento agendamento;
  final String cliente;
  final String veiculo;
  final String placa;
  final String responsavel;
}

class _BlocoAgendaDia {
  _BlocoAgendaDia({
    required this.chaveDia,
    required this.titulo,
    required this.itens,
  });

  final String chaveDia;
  final String titulo;
  final List<_AgendamentoAgendaItem> itens;
}
