import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/ordem_servico_repository.dart';
import '../services/ordem_servico_pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'veiculos_cliente_page.dart';

enum _AcaoCliente { editar, arquivarOuReativar }

class ClienteDetalhesPage extends StatefulWidget {
  const ClienteDetalhesPage({super.key, required this.cliente});

  final Cliente cliente;

  @override
  State<ClienteDetalhesPage> createState() => _ClienteDetalhesPageState();
}

class _ClienteDetalhesPageState extends State<ClienteDetalhesPage> {
  late Cliente cliente;

  final ClienteRepository _clienteRepository = ClienteRepository();

  final OrdemServicoRepository _ordemServicoRepository =
      OrdemServicoRepository();

  final OrdemServicoPdfService _pdfService = OrdemServicoPdfService();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _dataBrasileira = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _gerandoPdf = false;
  bool _abrindoWhatsApp = false;
  bool _alterandoArquivamento = false;

  int _quantidadeVeiculos = 0;
  int _quantidadeOrdens = 0;
  double _totalGasto = 0;
  double _ticketMedio = 0;
  String _ultimoAtendimento = '';

  List<Map<String, dynamic>> _historico = [];

  @override
  void initState() {
    super.initState();
    cliente = widget.cliente;
    _carregarHistorico();
  }

  Future<void> _carregarHistorico() async {
    final clienteId = cliente.id;

    if (clienteId == null) {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final resultados = await Future.wait([
        _clienteRepository.contarVeiculosDoCliente(clienteId),
        _ordemServicoRepository.obterResumoDoCliente(clienteId),
        _ordemServicoRepository.listarHistoricoDoCliente(clienteId),
      ]);

      if (!mounted) {
        return;
      }

      final resumo = resultados[1] as Map<String, dynamic>;

      setState(() {
        _quantidadeVeiculos = resultados[0] as int;
        _quantidadeOrdens = (resumo['quantidade_ordens'] as num?)?.toInt() ?? 0;
        _totalGasto = (resumo['total_gasto'] as num?)?.toDouble() ?? 0;
        _ticketMedio = (resumo['ticket_medio'] as num?)?.toDouble() ?? 0;
        _ultimoAtendimento = (resumo['ultimo_atendimento'] ?? '').toString();
        _historico = resultados[2] as List<Map<String, dynamic>>;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar o histórico do cliente.\n$erro',
        erro: true,
      );
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

  Future<void> _editarCliente() async {
    if (!cliente.ativo) {
      _mostrarMensagem(
        'Reative o cliente antes de editar seus dados.',
        erro: true,
      );
      return;
    }

    final clienteAtualizado = await showDialog<Cliente>(
      context: context,
      builder: (context) {
        return _EditarClienteDialog(cliente: cliente);
      },
    );

    if (clienteAtualizado == null || !mounted) {
      return;
    }

    try {
      await _clienteRepository.atualizarCliente(clienteAtualizado);

      if (!mounted) {
        return;
      }

      setState(() {
        cliente = clienteAtualizado;
      });

      _mostrarMensagem('Cliente atualizado com sucesso.');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível atualizar o cliente.\n$erro',
        erro: true,
      );
    }
  }

  Future<void> _alterarArquivamento() async {
    final clienteId = cliente.id;

    if (clienteId == null || _alterandoArquivamento) {
      return;
    }

    final vaiArquivar = cliente.ativo;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(vaiArquivar ? 'Arquivar cliente' : 'Reativar cliente'),
          content: Text(
            vaiArquivar
                ? 'O cliente deixará de aparecer nos cadastros ativos, '
                      'mas veículos, agendamentos, orçamentos, ordens de '
                      'serviço e histórico financeiro serão preservados.'
                : 'O cliente voltará a aparecer nos cadastros ativos e '
                      'poderá ser utilizado em novos atendimentos.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              icon: Icon(
                vaiArquivar ? Icons.archive_outlined : Icons.restore_outlined,
              ),
              label: Text(vaiArquivar ? 'Arquivar' : 'Reativar'),
            ),
          ],
        );
      },
    );

    if (confirmou != true || !mounted) {
      return;
    }

    setState(() {
      _alterandoArquivamento = true;
    });

    try {
      final registrosAlterados = vaiArquivar
          ? await _clienteRepository.arquivarCliente(clienteId)
          : await _clienteRepository.reativarCliente(clienteId);

      if (registrosAlterados == 0) {
        throw StateError(
          vaiArquivar
              ? 'O cliente já estava arquivado ou não foi encontrado.'
              : 'O cliente já estava ativo ou não foi encontrado.',
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, vaiArquivar ? 'arquivado' : 'reativado');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _alterandoArquivamento = false;
      });

      _mostrarMensagem(
        vaiArquivar
            ? 'Não foi possível arquivar o cliente.\n$erro'
            : 'Não foi possível reativar o cliente.\n$erro',
        erro: true,
      );
    }
  }

  void _tratarAcao(_AcaoCliente acao) {
    switch (acao) {
      case _AcaoCliente.editar:
        _editarCliente();
        return;
      case _AcaoCliente.arquivarOuReativar:
        _alterarArquivamento();
        return;
    }
  }

  void _abrirVeiculos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return VeiculosClientePage(cliente: cliente);
        },
      ),
    ).then((_) {
      _carregarHistorico();
    });
  }

  Future<void> _enviarAgradecimentoWhatsApp() async {
    final telefone = cliente.telefone.trim();

    if (telefone.isEmpty) {
      _mostrarMensagem('O cliente não possui telefone cadastrado.', erro: true);
      return;
    }

    if (_abrindoWhatsApp) {
      return;
    }

    setState(() {
      _abrindoWhatsApp = true;
    });

    try {
      await WhatsAppService.enviarAgradecimentoPosServico(
        telefone: telefone,
        cliente: cliente.nome,
      );
    } catch (erro) {
      _mostrarMensagem('Não foi possível abrir o WhatsApp.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _abrindoWhatsApp = false;
        });
      }
    }
  }

  Future<void> _enviarMensagemPersonalizadaWhatsApp() async {
    String mensagem = '';

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mensagem personalizada'),
          content: TextFormField(
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Digite a mensagem para o cliente',
              border: OutlineInputBorder(),
            ),
            onChanged: (valor) {
              mensagem = valor;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(mensagem.trim());
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (resultado == null || resultado.trim().isEmpty) {
      return;
    }

    final telefone = cliente.telefone.trim();

    if (telefone.isEmpty) {
      _mostrarMensagem('O cliente não possui telefone cadastrado.', erro: true);
      return;
    }

    if (_abrindoWhatsApp) {
      return;
    }

    setState(() {
      _abrindoWhatsApp = true;
    });

    try {
      await WhatsAppService.enviarMensagemPersonalizada(
        telefone: telefone,
        mensagem: resultado.trim(),
      );
    } catch (erro) {
      _mostrarMensagem('Não foi possível abrir o WhatsApp.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _abrindoWhatsApp = false;
        });
      }
    }
  }

  Future<void> _abrirOpcoesWhatsApp() async {
    final opcao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (bottomContext) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Enviar pelo WhatsApp',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.favorite_outline),
                ),
                title: const Text('Agradecimento pós-serviço'),
                subtitle: const Text('Mensagem pronta de agradecimento'),
                onTap: () {
                  Navigator.of(bottomContext).pop('agradecimento');
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_note_outlined),
                ),
                title: const Text('Mensagem personalizada'),
                subtitle: const Text('Escrever texto livre'),
                onTap: () {
                  Navigator.of(bottomContext).pop('personalizada');
                },
              ),
            ],
          ),
        );
      },
    );

    if (opcao == null) {
      return;
    }

    if (opcao == 'agradecimento') {
      await _enviarAgradecimentoWhatsApp();
      return;
    }

    if (opcao == 'personalizada') {
      await _enviarMensagemPersonalizadaWhatsApp();
    }
  }

  Future<void> _abrirPdf(int ordemServicoId) async {
    if (_gerandoPdf) {
      return;
    }

    setState(() {
      _gerandoPdf = true;
    });

    try {
      await _pdfService.visualizarPdf(ordemServicoId: ordemServicoId);
    } catch (erro) {
      _mostrarMensagem('Não foi possível gerar o PDF.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _gerandoPdf = false;
        });
      }
    }
  }

  String _texto(
    Map<String, dynamic> dados,
    String campo, {
    String padrao = '',
  }) {
    final valor = (dados[campo] ?? '').toString().trim();

    return valor.isEmpty ? padrao : valor;
  }

  int _inteiro(Map<String, dynamic> dados, String campo) {
    final valor = dados[campo];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _numero(Map<String, dynamic> dados, String campo) {
    final valor = dados[campo];

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return 'Nenhum atendimento';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _dataBrasileira.format(data);
  }

  String _dataDaOrdem(Map<String, dynamic> ordem) {
    final valor = _texto(
      ordem,
      'data_finalizacao',
      padrao: _texto(
        ordem,
        'data_inicio',
        padrao: _texto(ordem, 'data_abertura'),
      ),
    );

    return _formatarData(valor);
  }

  String _nomeVeiculo(Map<String, dynamic> ordem) {
    final marca = _texto(ordem, 'veiculo_marca');
    final modelo = _texto(ordem, 'veiculo_modelo');
    final placa = _texto(ordem, 'veiculo_placa');

    final nome = '$marca $modelo'.trim();

    if (nome.isEmpty && placa.isEmpty) {
      return 'Veículo não informado';
    }

    if (placa.isEmpty) {
      return nome;
    }

    if (nome.isEmpty) {
      return placa.toUpperCase();
    }

    return '$nome • ${placa.toUpperCase()}';
  }

  double _valorFinal(Map<String, dynamic> ordem) {
    final valorTotal = _numero(ordem, 'valor_total');
    final desconto = _numero(ordem, 'desconto');
    final resultado = valorTotal - desconto;

    return resultado < 0 ? 0 : resultado;
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Finalizada':
        return Colors.green;
      case 'Em andamento':
        return Colors.blue;
      case 'Cancelada':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _cardIndicador({
    required String titulo,
    required String valor,
    required IconData icone,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: const Color(0xFFD6A84B)),
            const SizedBox(height: 10),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Text(
              titulo,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _informacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    final texto = valor.trim().isEmpty ? 'Não informado' : valor;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icone, color: const Color(0xFFD6A84B)),
        title: Text(titulo),
        subtitle: Text(texto),
      ),
    );
  }

  Widget _cardOrdem(Map<String, dynamic> ordem) {
    final id = _inteiro(ordem, 'id');
    final numero = _texto(ordem, 'numero', padrao: 'Ordem de Serviço');
    final status = _texto(ordem, 'status', padrao: 'Aberta');
    final servicos = _texto(
      ordem,
      'servicos',
      padrao: 'Serviços não informados',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: id <= 0 ? null : () => _abrirPdf(id),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      numero,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _corStatus(status).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _corStatus(status),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                servicos,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.directions_car_outlined,
                    size: 17,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _nomeVeiculo(ordem),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dataDaOrdem(ordem),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    _moeda.format(_valorFinal(ordem)),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD6A84B),
                    ),
                  ),
                ],
              ),
              if (id > 0) ...[
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Toque para visualizar o PDF',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _avisoArquivado() {
    final arquivadoEm = cliente.arquivadoEm;
    final data = arquivadoEm == null ? '' : _formatarData(arquivadoEm);

    return Card(
      color: Colors.amber.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.archive_outlined, color: Colors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.isEmpty || data == 'Nenhum atendimento'
                    ? 'Cliente arquivado. O histórico foi preservado.'
                    : 'Cliente arquivado em $data. '
                          'O histórico foi preservado.',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do cliente'),
        actions: [
          IconButton(
            onPressed: _abrindoWhatsApp ? null : _abrirOpcoesWhatsApp,
            tooltip: 'WhatsApp',
            icon: _abrindoWhatsApp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chat_outlined),
          ),
          IconButton(
            onPressed: _carregando ? null : _carregarHistorico,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_outlined),
          ),
          if (_alterandoArquivamento)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PopupMenuButton<_AcaoCliente>(
              tooltip: 'Mais opções',
              onSelected: _tratarAcao,
              itemBuilder: (context) {
                return [
                  if (cliente.ativo)
                    const PopupMenuItem<_AcaoCliente>(
                      value: _AcaoCliente.editar,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar cliente'),
                      ),
                    ),
                  PopupMenuItem<_AcaoCliente>(
                    value: _AcaoCliente.arquivarOuReativar,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        cliente.ativo
                            ? Icons.archive_outlined
                            : Icons.restore_outlined,
                      ),
                      title: Text(
                        cliente.ativo ? 'Arquivar cliente' : 'Reativar cliente',
                      ),
                    ),
                  ),
                ];
              },
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarHistorico,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (!cliente.ativo) ...[
                    _avisoArquivado(),
                    const SizedBox(height: 12),
                  ],
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: const Color(0xFF252525),
                    child: Icon(
                      cliente.ativo ? Icons.person : Icons.archive_outlined,
                      size: 48,
                      color: const Color(0xFFD6A84B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    cliente.nome,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: [
                      _cardIndicador(
                        titulo: 'Total gasto',
                        valor: _moeda.format(_totalGasto),
                        icone: Icons.payments_outlined,
                      ),
                      _cardIndicador(
                        titulo: 'Ordens',
                        valor: _quantidadeOrdens.toString(),
                        icone: Icons.assignment_outlined,
                      ),
                      _cardIndicador(
                        titulo: 'Ticket médio',
                        valor: _moeda.format(_ticketMedio),
                        icone: Icons.trending_up_outlined,
                      ),
                      _cardIndicador(
                        titulo: 'Veículos',
                        valor: _quantidadeVeiculos.toString(),
                        icone: Icons.directions_car_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.event_available_outlined,
                        color: Color(0xFFD6A84B),
                      ),
                      title: const Text('Último atendimento'),
                      subtitle: Text(_formatarData(_ultimoAtendimento)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _abrirVeiculos,
                    icon: const Icon(Icons.directions_car_outlined),
                    label: const Text('Ver veículos do cliente'),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Dados do cliente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _informacao(
                    icone: Icons.phone_outlined,
                    titulo: 'Telefone',
                    valor: cliente.telefone,
                  ),
                  _informacao(
                    icone: Icons.email_outlined,
                    titulo: 'E-mail',
                    valor: cliente.email,
                  ),
                  _informacao(
                    icone: Icons.location_on_outlined,
                    titulo: 'Endereço',
                    valor: cliente.endereco,
                  ),
                  _informacao(
                    icone: Icons.notes_outlined,
                    titulo: 'Observações',
                    valor: cliente.observacoes,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Histórico de Ordens',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${_historico.length} registro(s)',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_historico.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history_toggle_off_outlined,
                              size: 44,
                              color: Colors.white38,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Este cliente ainda não possui '
                              'Ordens de Serviço.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._historico.map(_cardOrdem),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _EditarClienteDialog extends StatefulWidget {
  const _EditarClienteDialog({required this.cliente});

  final Cliente cliente;

  @override
  State<_EditarClienteDialog> createState() => _EditarClienteDialogState();
}

class _EditarClienteDialogState extends State<_EditarClienteDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomeController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _enderecoController;
  late final TextEditingController _observacoesController;

  @override
  void initState() {
    super.initState();

    _nomeController = TextEditingController(text: widget.cliente.nome);
    _telefoneController = TextEditingController(text: widget.cliente.telefone);
    _emailController = TextEditingController(text: widget.cliente.email);
    _enderecoController = TextEditingController(text: widget.cliente.endereco);
    _observacoesController = TextEditingController(
      text: widget.cliente.observacoes,
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _enderecoController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final clienteAtualizado = widget.cliente.copyWith(
      nome: _nomeController.text.trim(),
      telefone: _telefoneController.text.trim(),
      email: _emailController.text.trim(),
      endereco: _enderecoController.text.trim(),
      observacoes: _observacoesController.text.trim(),
    );

    Navigator.pop(context, clienteAtualizado);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar cliente'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomeController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (valor) {
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Informe o nome do cliente.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _enderecoController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacoesController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
