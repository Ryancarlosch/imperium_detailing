import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'nova_ordem_servico_page.dart';
import 'ordem_servico_checklist_page.dart';
import 'ordem_servico_fotos_page.dart';
import 'ordem_servico_assinatura_page.dart';
import '../repositories/ordem_servico_repository.dart';
import '../services/ordem_servico_pdf_service.dart';
import '../services/whatsapp_service.dart';

class OrdensServicoPage extends StatefulWidget {
  const OrdensServicoPage({super.key});

  @override
  State<OrdensServicoPage> createState() => _OrdensServicoPageState();
}

class _OrdensServicoPageState extends State<OrdensServicoPage> {
  final OrdemServicoRepository _repository = OrdemServicoRepository();

  final OrdemServicoPdfService _pdfService = OrdemServicoPdfService();

  final TextEditingController _pesquisaController = TextEditingController();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _dataBrasileira = DateFormat('dd/MM/yyyy');

  List<Map<String, dynamic>> _ordens = [];

  bool _carregando = true;
  bool _executandoAcao = false;

  String _statusSelecionado = 'Todos';

  final List<String> _statusDisponiveis = const [
    'Todos',
    'Aberta',
    'Em andamento',
    'Finalizada',
    'Cancelada',
  ];

  @override
  void initState() {
    super.initState();

    _pesquisaController.addListener(_aoAlterarPesquisa);

    _carregarOrdens();
  }

  @override
  void dispose() {
    _pesquisaController.removeListener(_aoAlterarPesquisa);

    _pesquisaController.dispose();

    super.dispose();
  }

  void _aoAlterarPesquisa() {
    _carregarOrdens();
  }

  Future<void> _carregarOrdens() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final resultado = await _repository.listarOrdensServicoComDetalhes(
        status: _statusSelecionado,
        pesquisa: _pesquisaController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _ordens = resultado;
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
        'Não foi possível carregar as Ordens de Serviço.\n'
        '$erro',
        erro: true,
      );
    }
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : null,
      ),
    );
  }

  String _obterTexto(
    Map<String, dynamic> ordem,
    String campo, {
    String padrao = '',
  }) {
    final texto = (ordem[campo] ?? '').toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  int _obterInt(Map<String, dynamic> ordem, String campo) {
    final valor = ordem[campo];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString().trim() ?? '') ?? 0;
  }

  double _obterDouble(Map<String, dynamic> ordem, String campo) {
    final valor = ordem[campo];

    if (valor is num) {
      return valor.toDouble();
    }

    final texto =
        valor?.toString().trim().replaceAll('R\$', '').replaceAll(' ', '') ??
        '';

    if (texto.isEmpty) {
      return 0;
    }

    if (texto.contains(',')) {
      return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }

    return double.tryParse(texto) ?? 0;
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return '-';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _dataBrasileira.format(data);
  }

  String _montarNomeVeiculo(Map<String, dynamic> ordem) {
    final marca = _obterTexto(ordem, 'veiculo_marca');

    final modelo = _obterTexto(ordem, 'veiculo_modelo');

    final nome = '$marca $modelo'.trim();

    if (nome.isEmpty) {
      return 'Veículo não informado';
    }

    return nome;
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Aberta':
        return Colors.orange.shade700;

      case 'Em andamento':
        return Colors.blue.shade700;

      case 'Finalizada':
        return Colors.green.shade700;

      case 'Cancelada':
        return Colors.red.shade700;

      default:
        return Colors.grey.shade700;
    }
  }

  IconData _iconeStatus(String status) {
    switch (status) {
      case 'Aberta':
        return Icons.assignment_outlined;

      case 'Em andamento':
        return Icons.build_circle_outlined;

      case 'Finalizada':
        return Icons.check_circle_outline;

      case 'Cancelada':
        return Icons.cancel_outlined;

      default:
        return Icons.description_outlined;
    }
  }

  Future<bool> _confirmarAcao({
    required String titulo,
    required String mensagem,
    String textoConfirmar = 'Confirmar',
    Color? corConfirmar,
  }) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(mensagem),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: corConfirmar),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(textoConfirmar),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  Future<void> _iniciarOrdem(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Iniciar serviço',
      mensagem: 'Deseja iniciar esta Ordem de Serviço agora?',
      textoConfirmar: 'Iniciar',
    );

    if (!confirmar) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.iniciarOrdemServico(id);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      _mostrarMensagem('Ordem de Serviço iniciada.');

      await _carregarOrdens();
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível iniciar o serviço.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _finalizarOrdem(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    final formaPagamento = await _selecionarFormaPagamento();

    if (formaPagamento == null) {
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Finalizar serviço',
      mensagem:
          'Deseja finalizar esta Ordem de Serviço?\n\n'
          'Forma de pagamento: $formaPagamento\n\n'
          'Os produtos utilizados serão baixados do estoque '
          'e o valor será lançado no financeiro.',
      textoConfirmar: 'Finalizar',
      corConfirmar: Colors.green.shade700,
    );

    if (!confirmar) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.finalizarOrdemServico(
        ordemServicoId: id,
        formaPagamento: formaPagamento,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;

      _mostrarMensagem(
        'Ordem de Serviço finalizada. '
        'Estoque e financeiro atualizados.',
      );

      await _carregarOrdens();

      if (!mounted) return;

      setState(() {
        _executandoAcao = false;
      });

      final ordemAtualizada = await _repository.buscarOrdemServicoCompletaPorId(
        id,
      );

      if (!mounted) return;

      await _executarFluxoPosFinalizacao(
        ordem: ordemAtualizada ?? ordem,
        ordemServicoId: id,
      );
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível finalizar o serviço.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted && _executandoAcao) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _executarFluxoPosFinalizacao({
    required Map<String, dynamic> ordem,
    required int ordemServicoId,
  }) async {
    final registrarFotos = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.add_a_photo_outlined,
            size: 42,
            color: Color(0xFFD6A84B),
          ),
          title: const Text('Registrar fotos do serviço?'),
          content: const Text(
            'Deseja abrir agora as fotos da Ordem de Serviço '
            'para registrar o resultado final do veículo?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Agora não'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Registrar fotos'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (registrarFotos == true) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OrdemServicoFotosPage(
            ordemServicoId: ordemServicoId,
            numeroOrdem: _obterTexto(
              ordem,
              'numero',
              padrao: 'Ordem de Serviço',
            ),
            cliente: _obterTexto(
              ordem,
              'cliente_nome',
              padrao: 'Cliente não informado',
            ),
            veiculo: _montarNomeVeiculo(ordem),
            somenteLeitura: false,
          ),
        ),
      );
    }

    if (!mounted) return;

    await _mostrarAcoesPosFinalizacao(
      ordem: ordem,
      ordemServicoId: ordemServicoId,
    );
  }

  Future<void> _mostrarAcoesPosFinalizacao({
    required Map<String, dynamic> ordem,
    required int ordemServicoId,
  }) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ordem de Serviço finalizada',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Color(0xFFD6A84B),
                  ),
                  title: const Text('Visualizar PDF'),
                  subtitle: const Text(
                    'Gera o documento com os dados e as fotos atuais.',
                  ),
                  onTap: () {
                    Navigator.of(bottomContext).pop('visualizar');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.share_outlined,
                    color: Color(0xFFD6A84B),
                  ),
                  title: const Text('Compartilhar PDF'),
                  subtitle: const Text(
                    'Abre as opções de compartilhamento do celular.',
                  ),
                  onTap: () {
                    Navigator.of(bottomContext).pop('compartilhar');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.chat_outlined,
                    color: Color(0xFF25D366),
                  ),
                  title: const Text('Avisar cliente no WhatsApp'),
                  subtitle: const Text(
                    'Envia a mensagem de veículo pronto para retirada.',
                  ),
                  onTap: () {
                    Navigator.of(bottomContext).pop('whatsapp');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Concluir'),
                  onTap: () {
                    Navigator.of(bottomContext).pop('concluir');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || acao == null || acao == 'concluir') {
      return;
    }

    try {
      if (acao == 'visualizar') {
        await _pdfService.visualizarPdf(ordemServicoId: ordemServicoId);
      } else if (acao == 'compartilhar') {
        await _pdfService.compartilharPdf(ordemServicoId: ordemServicoId);
      } else if (acao == 'whatsapp') {
        await _enviarVeiculoProntoWhatsApp(ordem);
      }
    } catch (erro) {
      _mostrarMensagem('Não foi possível concluir a ação.\n$erro', erro: true);
    }
  }

  Future<String?> _selecionarFormaPagamento() {
    const formas = [
      'Dinheiro',
      'Pix',
      'Cartão de débito',
      'Cartão de crédito',
      'Transferência',
      'Outro',
    ];

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Forma de pagamento',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ...formas.map(
                  (forma) => ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(forma),
                    onTap: () {
                      Navigator.of(bottomContext).pop(forma);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelarOrdem(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Cancelar Ordem de Serviço',
      mensagem:
          'Tem certeza de que deseja cancelar esta '
          'Ordem de Serviço?',
      textoConfirmar: 'Cancelar OS',
      corConfirmar: Colors.red.shade700,
    );

    if (!confirmar) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.cancelarOrdemServico(id);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      _mostrarMensagem('Ordem de Serviço cancelada.');

      await _carregarOrdens();
    } catch (erro) {
      _mostrarMensagem('Não foi possível cancelar a ordem.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _excluirOrdem(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');
    final numero = _obterTexto(ordem, 'numero', padrao: 'sem número');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    final confirmar = await _confirmarAcao(
      titulo: 'Excluir Ordem de Serviço',
      mensagem:
          'Deseja excluir permanentemente a Ordem de '
          'Serviço $numero?\n\n'
          'Esta ação não poderá ser desfeita.',
      textoConfirmar: 'Excluir',
      corConfirmar: Colors.red.shade700,
    );

    if (!confirmar) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.excluirOrdemServico(id);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      _mostrarMensagem('Ordem de Serviço excluída.');

      await _carregarOrdens();
    } catch (erro) {
      _mostrarMensagem('Não foi possível excluir a ordem.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _abrirDetalhes(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);

      return;
    }

    try {
      final ordemCompleta = await _repository.buscarOrdemServicoCompletaPorId(
        id,
      );

      if (!mounted) {
        return;
      }

      if (ordemCompleta == null) {
        _mostrarMensagem('Ordem de Serviço não encontrada.', erro: true);

        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (bottomContext) {
          return FractionallySizedBox(
            heightFactor: 0.92,
            child: _construirDetalhes(ordemCompleta),
          );
        },
      );
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível abrir os detalhes.\n$erro',
        erro: true,
      );
    }
  }

  Future<void> _abrirChecklist(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrdemServicoChecklistPage(
          ordemServicoId: id,
          numeroOrdem: _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço'),
          cliente: _obterTexto(
            ordem,
            'cliente_nome',
            padrao: 'Cliente não informado',
          ),
          veiculo: _montarNomeVeiculo(ordem),
          somenteLeitura: status == 'Finalizada' || status == 'Cancelada',
        ),
      ),
    );

    if (alterou == true && mounted) {
      _mostrarMensagem('Checklist atualizado.');
    }
  }

  Future<void> _abrirFotos(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrdemServicoFotosPage(
          ordemServicoId: id,
          numeroOrdem: _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço'),
          cliente: _obterTexto(
            ordem,
            'cliente_nome',
            padrao: 'Cliente não informado',
          ),
          veiculo: _montarNomeVeiculo(ordem),
          somenteLeitura: status == 'Finalizada' || status == 'Cancelada',
        ),
      ),
    );

    if (alterou == true && mounted) {
      _mostrarMensagem('Fotos da Ordem de Serviço atualizadas.');
    }
  }

  Future<void> _abrirAssinatura(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrdemServicoAssinaturaPage(
          ordemServicoId: id,
          numeroOrdem: _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço'),
          cliente: _obterTexto(
            ordem,
            'cliente_nome',
            padrao: 'Cliente não informado',
          ),
          veiculo: _montarNomeVeiculo(ordem),
          somenteLeitura: status == 'Finalizada' || status == 'Cancelada',
        ),
      ),
    );

    if (alterou == true && mounted) {
      _mostrarMensagem('Assinatura do cliente atualizada.');

      await _carregarOrdens();
    }
  }

  Future<void> _visualizarPdf(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _pdfService.visualizarPdf(ordemServicoId: id);
    } catch (erro) {
      _mostrarMensagem('Não foi possível gerar o PDF.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _compartilharPdf(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _pdfService.compartilharPdf(ordemServicoId: id);
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível compartilhar o PDF.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  double _valorFinalOrdem(Map<String, dynamic> ordem) {
    final valorTotal = _obterDouble(ordem, 'valor_total');

    final desconto = _obterDouble(ordem, 'desconto');

    return (valorTotal - desconto).clamp(0, double.infinity);
  }

  String _previsaoWhatsApp(Map<String, dynamic> ordem) {
    final previsao = _obterTexto(ordem, 'data_finalizacao');

    if (previsao.isNotEmpty) {
      return _formatarData(previsao);
    }

    final inicio = _obterTexto(ordem, 'data_inicio');

    if (inicio.isNotEmpty) {
      return _formatarData(inicio);
    }

    return '';
  }

  Future<void> _executarAcaoWhatsApp(
    Map<String, dynamic> ordem,
    Future<void> Function({required String telefone, required String cliente})
    acao,
  ) async {
    if (_executandoAcao) {
      return;
    }

    final telefone = _obterTexto(ordem, 'cliente_telefone');

    final cliente = _obterTexto(ordem, 'cliente_nome', padrao: 'Cliente');

    if (telefone.isEmpty) {
      _mostrarMensagem(
        'O cliente $cliente não possui telefone cadastrado.',
        erro: true,
      );
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await acao(telefone: telefone, cliente: cliente);
    } catch (erro) {
      _mostrarMensagem('Não foi possível abrir o WhatsApp.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Future<void> _enviarMensagemWhatsApp({
    required Map<String, dynamic> ordem,
    required String mensagem,
  }) async {
    await _executarAcaoWhatsApp(ordem, ({
      required String telefone,
      required String cliente,
    }) {
      return WhatsAppService.enviarMensagemPersonalizada(
        telefone: telefone,
        mensagem: mensagem,
      );
    });
  }

  Future<void> _enviarServicoIniciadoWhatsApp(
    Map<String, dynamic> ordem,
  ) async {
    final numero = _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço');

    final status = _obterTexto(ordem, 'status', padrao: 'Em andamento');

    final valor = _moeda.format(_valorFinalOrdem(ordem));

    await _executarAcaoWhatsApp(ordem, ({
      required String telefone,
      required String cliente,
    }) {
      return WhatsAppService.enviarAtualizacaoOrdemServico(
        telefone: telefone,
        cliente: cliente,
        numeroOrdem: numero,
        status: status,
        valor: valor,
        previsao: _previsaoWhatsApp(ordem),
        mensagemPersonalizada:
            'Informamos que o serviço foi iniciado e manteremos você atualizado sobre o andamento.',
      );
    });
  }

  Future<void> _enviarVeiculoProntoWhatsApp(Map<String, dynamic> ordem) async {
    final numero = _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço');

    final valor = _moeda.format(_valorFinalOrdem(ordem));

    await _executarAcaoWhatsApp(ordem, ({
      required String telefone,
      required String cliente,
    }) {
      return WhatsAppService.enviarVeiculoPronto(
        telefone: telefone,
        cliente: cliente,
        numeroOrdem: numero,
        valor: valor,
        previsao: _previsaoWhatsApp(ordem),
      );
    });
  }

  Future<void> _enviarResumoOrdemWhatsApp(Map<String, dynamic> ordem) async {
    final numero = _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço');

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final valor = _moeda.format(_valorFinalOrdem(ordem));

    await _executarAcaoWhatsApp(ordem, ({
      required String telefone,
      required String cliente,
    }) {
      return WhatsAppService.enviarAtualizacaoOrdemServico(
        telefone: telefone,
        cliente: cliente,
        numeroOrdem: numero,
        status: status,
        valor: valor,
        previsao: _previsaoWhatsApp(ordem),
      );
    });
  }

  Future<void> _enviarCobrancaWhatsApp(Map<String, dynamic> ordem) async {
    final numero = _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço');

    final valor = _moeda.format(_valorFinalOrdem(ordem));

    final formaPagamento = _obterTexto(
      ordem,
      'forma_pagamento',
      padrao: 'a combinar',
    );

    await _executarAcaoWhatsApp(ordem, ({
      required String telefone,
      required String cliente,
    }) {
      return WhatsAppService.enviarCobrancaOrdemServico(
        telefone: telefone,
        cliente: cliente,
        numeroOrdem: numero,
        valor: valor,
        formaPagamento: formaPagamento,
      );
    });
  }

  Future<void> _enviarMensagemPersonalizadaWhatsApp(
    Map<String, dynamic> ordem,
  ) async {
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
              label: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    if (resultado == null || resultado.trim().isEmpty) {
      return;
    }

    await _enviarMensagemWhatsApp(ordem: ordem, mensagem: resultado.trim());
  }

  Future<void> _abrirOpcoesWhatsApp(Map<String, dynamic> ordem) async {
    final telefone = _obterTexto(ordem, 'cliente_telefone');

    final cliente = _obterTexto(ordem, 'cliente_nome', padrao: 'Cliente');

    if (telefone.isEmpty) {
      _mostrarMensagem(
        'O cliente $cliente não possui telefone cadastrado.',
        erro: true,
      );
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

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
              if (status == 'Aberta' || status == 'Em andamento')
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.play_arrow_outlined),
                  ),
                  title: const Text('Serviço iniciado'),
                  subtitle: const Text(
                    'Avisar que o veículo entrou em serviço',
                  ),
                  onTap: () {
                    Navigator.of(bottomContext).pop('iniciado');
                  },
                ),
              if (status == 'Finalizada')
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.check_circle_outline),
                  ),
                  title: const Text('Veículo pronto'),
                  subtitle: const Text('Avisar que o serviço foi finalizado'),
                  onTap: () {
                    Navigator.of(bottomContext).pop('pronto');
                  },
                ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_long_outlined),
                ),
                title: const Text('Resumo da Ordem de Serviço'),
                subtitle: const Text('Enviar serviços, status e valor'),
                onTap: () {
                  Navigator.of(bottomContext).pop('resumo');
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.payments_outlined),
                ),
                title: const Text('Enviar cobrança'),
                subtitle: const Text('Enviar o valor total ao cliente'),
                onTap: () {
                  Navigator.of(bottomContext).pop('cobranca');
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_note_outlined),
                ),
                title: const Text('Mensagem personalizada'),
                subtitle: const Text('Escrever uma mensagem livre'),
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

    switch (opcao) {
      case 'iniciado':
        await _enviarServicoIniciadoWhatsApp(ordem);
        break;
      case 'pronto':
        await _enviarVeiculoProntoWhatsApp(ordem);
        break;
      case 'resumo':
        await _enviarResumoOrdemWhatsApp(ordem);
        break;
      case 'cobranca':
        await _enviarCobrancaWhatsApp(ordem);
        break;
      case 'personalizada':
        await _enviarMensagemPersonalizadaWhatsApp(ordem);
        break;
    }
  }

  Widget _construirDetalhes(Map<String, dynamic> ordem) {
    final numero = _obterTexto(ordem, 'numero', padrao: 'Ordem de Serviço');

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final cliente = _obterTexto(
      ordem,
      'cliente_nome',
      padrao: 'Cliente não informado',
    );

    final telefone = _obterTexto(ordem, 'cliente_telefone');

    final placa = _obterTexto(ordem, 'veiculo_placa');

    final responsavel = _obterTexto(
      ordem,
      'funcionario_responsavel',
      padrao: 'Não informado',
    );

    final observacoes = _obterTexto(ordem, 'observacoes');

    final dataAbertura = _formatarData(_obterTexto(ordem, 'data_abertura'));

    final dataInicio = _formatarData(_obterTexto(ordem, 'data_inicio'));

    final dataFinalizacao = _formatarData(
      _obterTexto(ordem, 'data_finalizacao'),
    );

    final horaEntrada = _obterTexto(ordem, 'hora_entrada', padrao: '-');

    final horaSaida = _obterTexto(ordem, 'hora_saida', padrao: '-');

    final formaPagamento = _obterTexto(
      ordem,
      'forma_pagamento',
      padrao: 'Não informada',
    );

    final valorTotal = _obterDouble(ordem, 'valor_total');

    final desconto = _obterDouble(ordem, 'desconto');

    final valorFinal = (valorTotal - desconto).clamp(0, double.infinity);

    final itensBrutos = ordem['itens'];

    final itens = itensBrutos is List
        ? itensBrutos
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(numero),
        actions: [
          IconButton(
            tooltip: 'Fechar',
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cliente,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _EtiquetaStatus(
                status: status,
                cor: _corStatus(status),
                icone: _iconeStatus(status),
              ),
            ],
          ),
          if (telefone.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(telefone, style: TextStyle(color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 20),
          _CartaoInformacao(
            titulo: 'Veículo',
            icone: Icons.directions_car_outlined,
            children: [
              _LinhaInformacao(
                titulo: 'Veículo',
                valor: _montarNomeVeiculo(ordem),
              ),
              if (placa.isNotEmpty)
                _LinhaInformacao(titulo: 'Placa', valor: placa.toUpperCase()),
            ],
          ),
          const SizedBox(height: 12),
          _CartaoInformacao(
            titulo: 'Execução',
            icone: Icons.build_outlined,
            children: [
              _LinhaInformacao(titulo: 'Responsável', valor: responsavel),
              _LinhaInformacao(titulo: 'Abertura', valor: dataAbertura),
              _LinhaInformacao(
                titulo: 'Início',
                valor: '$dataInicio às $horaEntrada',
              ),
              _LinhaInformacao(
                titulo: 'Finalização',
                valor: '$dataFinalizacao às $horaSaida',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text(
                'Checklist de entrada',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Conferir estado e itens do veículo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrirChecklist(ordem),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(
                'Fotos do serviço',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Registrar fotos de antes e depois'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrirFotos(ordem),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text(
                'Assinatura do cliente',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Capturar ou visualizar a assinatura digital',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrirAssinatura(ordem),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text(
                'WhatsApp',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Avisar início, conclusão, enviar resumo ou cobrança',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _executandoAcao ? null : () => _abrirOpcoesWhatsApp(ordem),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text(
                    'PDF da Ordem de Serviço',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Visualizar, imprimir ou compartilhar o documento',
                  ),
                ),
                const Divider(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _executandoAcao
                            ? null
                            : () => _visualizarPdf(ordem),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Visualizar'),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _executandoAcao
                            ? null
                            : () => _compartilharPdf(ordem),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartilhar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CartaoInformacao(
            titulo: 'Serviços',
            icone: Icons.checklist_outlined,
            children: [
              if (itens.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Nenhum serviço cadastrado.'),
                ),
              ...itens.map(
                (item) => _ItemServicoDetalhes(
                  servico: _obterTexto(item, 'servico', padrao: 'Serviço'),
                  descricao: _obterTexto(item, 'descricao'),
                  quantidade: _obterDouble(item, 'quantidade'),
                  valorUnitario: _obterDouble(item, 'valor_unitario'),
                  concluido: _obterInt(item, 'concluido') == 1,
                  moeda: _moeda,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CartaoInformacao(
            titulo: 'Valores',
            icone: Icons.payments_outlined,
            children: [
              _LinhaInformacao(
                titulo: 'Subtotal',
                valor: _moeda.format(valorTotal),
              ),
              _LinhaInformacao(
                titulo: 'Desconto',
                valor: _moeda.format(desconto),
              ),
              const Divider(),
              _LinhaInformacao(
                titulo: 'Total',
                valor: _moeda.format(valorFinal),
                destaque: true,
              ),
              _LinhaInformacao(titulo: 'Pagamento', valor: formaPagamento),
            ],
          ),
          if (observacoes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CartaoInformacao(
              titulo: 'Observações',
              icone: Icons.notes_outlined,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(observacoes),
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: _construirAcoesDetalhes(ordem, status),
    );
  }

  Widget _construirAcoesDetalhes(Map<String, dynamic> ordem, String status) {
    final botoes = <Widget>[];

    if (status == 'Aberta') {
      botoes.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _executandoAcao ? null : () => _iniciarOrdem(ordem),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar'),
          ),
        ),
      );
    }

    if (status == 'Em andamento') {
      botoes.add(
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: _executandoAcao ? null : () => _finalizarOrdem(ordem),
            icon: const Icon(Icons.check),
            label: const Text('Finalizar'),
          ),
        ),
      );
    }

    if (status == 'Aberta' || status == 'Em andamento') {
      if (botoes.isNotEmpty) {
        botoes.add(const SizedBox(width: 10));
      }

      botoes.add(
        IconButton.filledTonal(
          tooltip: 'Cancelar OS',
          onPressed: _executandoAcao ? null : () => _cancelarOrdem(ordem),
          icon: const Icon(Icons.cancel_outlined),
        ),
      );
    }

    if (status == 'Finalizada' || status == 'Cancelada') {
      botoes.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _executandoAcao ? null : () => _excluirOrdem(ordem),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ),
      );
    }

    if (botoes.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(children: botoes),
      ),
    );
  }

  Widget _construirFiltros() {
    return Column(
      children: [
        TextField(
          controller: _pesquisaController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Pesquisar cliente, veículo, placa ou OS',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _pesquisaController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar pesquisa',
                    onPressed: () {
                      _pesquisaController.clear();
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statusDisponiveis.length,
            separatorBuilder: (_, __) {
              return const SizedBox(width: 8);
            },
            itemBuilder: (context, index) {
              final status = _statusDisponiveis[index];

              return ChoiceChip(
                label: Text(status),
                selected: _statusSelecionado == status,
                onSelected: (_) {
                  setState(() {
                    _statusSelecionado = status;
                  });

                  _carregarOrdens();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ordens.isEmpty) {
      return RefreshIndicator(
        onRefresh: _carregarOrdens,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_outlined, size: 70, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Nenhuma Ordem de Serviço encontrada',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 7),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 30),
                    child: Text(
                      'As Ordens de Serviço criadas a '
                      'partir dos orçamentos aparecerão aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregarOrdens,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _ordens.length,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final ordem = _ordens[index];

          return _construirCartaoOrdem(ordem);
        },
      ),
    );
  }

  Widget _construirCartaoOrdem(Map<String, dynamic> ordem) {
    final numero = _obterTexto(ordem, 'numero', padrao: 'OS sem número');

    final cliente = _obterTexto(
      ordem,
      'cliente_nome',
      padrao: 'Cliente não informado',
    );

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');

    final placa = _obterTexto(ordem, 'veiculo_placa');

    final dataAbertura = _formatarData(_obterTexto(ordem, 'data_abertura'));

    final quantidadeItens = _obterInt(ordem, 'quantidade_itens');

    final itensConcluidos = _obterInt(ordem, 'itens_concluidos');

    final valorTotal = _obterDouble(ordem, 'valor_total');

    final desconto = _obterDouble(ordem, 'desconto');

    final valorFinal = (valorTotal - desconto).clamp(0, double.infinity);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalhes(ordem),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _corStatus(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconeStatus(status),
                      color: _corStatus(status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          numero,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _EtiquetaStatus(
                    status: status,
                    cor: _corStatus(status),
                    icone: _iconeStatus(status),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.directions_car_outlined,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _montarNomeVeiculo(ordem),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (placa.isNotEmpty)
                    Text(
                      placa.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 17,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 7),
                  Text(dataAbertura),
                  const Spacer(),
                  Text(
                    _moeda.format(valorFinal),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (quantidadeItens > 0) ...[
                const SizedBox(height: 13),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: quantidadeItens <= 0
                        ? 0
                        : itensConcluidos / quantidadeItens,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$itensConcluidos de '
                  '$quantidadeItens serviços concluídos',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _novaOrdemServico() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovaOrdemServicoPage()),
    );

    if (resultado == true) {
      await _carregarOrdens();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordens de Serviço'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarOrdens,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaOrdemServico,
        icon: const Icon(Icons.add),
        label: const Text('Nova OS'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(
          children: [
            _construirFiltros(),
            const SizedBox(height: 14),
            Expanded(child: _construirConteudo()),
          ],
        ),
      ),
    );
  }
}

class _EtiquetaStatus extends StatelessWidget {
  const _EtiquetaStatus({
    required this.status,
    required this.cor,
    required this.icone,
  });

  final String status;
  final Color cor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoInformacao extends StatelessWidget {
  const _CartaoInformacao({
    required this.titulo,
    required this.icone,
    required this.children,
  });

  final String titulo;
  final IconData icone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LinhaInformacao extends StatelessWidget {
  const _LinhaInformacao({
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(titulo, style: TextStyle(color: Colors.grey.shade700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: destaque ? 17 : 14,
                fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemServicoDetalhes extends StatelessWidget {
  const _ItemServicoDetalhes({
    required this.servico,
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
    required this.concluido,
    required this.moeda,
  });

  final String servico;
  final String descricao;
  final double quantidade;
  final double valorUnitario;
  final bool concluido;
  final NumberFormat moeda;

  String _formatarQuantidade() {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = quantidade * valorUnitario;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: concluido
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: concluido ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            concluido ? Icons.check_circle : Icons.radio_button_unchecked,
            color: concluido ? Colors.green.shade700 : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  servico,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (descricao.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    descricao,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${_formatarQuantidade()} × '
                  '${moeda.format(valorUnitario)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            moeda.format(subtotal),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
