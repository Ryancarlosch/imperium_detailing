import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/conta_financeira.dart';
import '../models/servico_catalogo.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/pagamento_repository.dart';
import '../repositories/servico_repository.dart';
import '../repositories/precificacao_repository.dart';
import '../repositories/fidelidade_repository.dart';
import 'nova_ordem_servico_page.dart';
import 'corrigir_ordem_servico_page.dart';
import 'ordem_servico_checklist_page.dart';
import 'ordem_servico_fotos_page.dart';
import 'ordem_servico_assinatura_page.dart';
import 'pagamentos_page.dart';
import '../repositories/ordem_servico_repository.dart';
import '../services/ordem_servico_pdf_service.dart';
import '../services/whatsapp_service.dart';

class OrdensServicoPage extends StatefulWidget {
  const OrdensServicoPage({super.key, this.statusInicial});

  final String? statusInicial;

  @override
  State<OrdensServicoPage> createState() => _OrdensServicoPageState();
}

class _OrdensServicoPageState extends State<OrdensServicoPage> {
  final OrdemServicoRepository _repository = OrdemServicoRepository();
  final PagamentoRepository _pagamentoRepository = PagamentoRepository();
  final ServicoRepository _servicoRepository = ServicoRepository();
  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();
  final FidelidadeRepository _fidelidadeRepository = FidelidadeRepository();
  final ContaFinanceiraRepository _contaFinanceiraRepository =
      ContaFinanceiraRepository();

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

  late String _statusSelecionado;

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

    _statusSelecionado = widget.statusInicial ?? 'Todos';

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

  Color _corStatusPagamento(String status) {
    switch (status) {
      case 'Pago':
        return Colors.green.shade700;
      case 'Parcialmente pago':
        return Colors.blue.shade700;
      case 'Vencido':
        return Colors.red.shade700;
      case 'Cancelado':
        return Colors.grey.shade700;
      case 'Pendente':
      default:
        return Colors.amber.shade700;
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

    final entrada = await showDialog<DateTime>(
      context: context,
      builder: (_) => _DataHoraEntradaDialog(inicial: DateTime.now()),
    );

    if (entrada == null || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.iniciarOrdemServico(id, dataHoraEntrada: entrada);

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

    final periodo = await _selecionarPeriodoFinalizacao(ordem);
    if (periodo == null || !mounted) {
      return;
    }

    final recebimento = await _selecionarRecebimentoFinalizacao(
      ordem,
      dataPagamentoPadrao: periodo.saida,
    );

    if (recebimento == null) {
      return;
    }

    final descricaoPagamento = recebimento.receberAgora
        ? recebimento.descricaoConfirmacao
        : 'Pagamento: receber depois';
    final descricaoPeriodo =
        'Entrada: ${_formatarDataHoraResumo(periodo.entrada)}\n'
        'Saída: ${_formatarDataHoraResumo(periodo.saida)}';

    final confirmar = await _confirmarAcao(
      titulo: 'Finalizar serviço',
      mensagem:
          'Deseja finalizar esta Ordem de Serviço?\n\n'
          '$descricaoPeriodo\n\n'
          '$descricaoPagamento\n\n'
          'Os produtos utilizados serão baixados do estoque. '
          'Somente valores realmente recebidos serão lançados no financeiro.',
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
        formaPagamento: recebimento.formaPagamento,
        valorPagamento: recebimento.valorPagamento,
        contaFinanceiraId: recebimento.contaFinanceiraId,
        parcelasTaxa: recebimento.parcelasTaxa,
        dataHoraEntrada: periodo.entrada,
        dataHoraSaida: periodo.saida,
        dataHoraPagamento: recebimento.dataPagamento,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        recebimento.receberAgora
            ? 'Ordem de Serviço finalizada e pagamento registrado.'
            : 'Ordem de Serviço finalizada. Saldo criado em contas a receber.',
      );

      await _carregarOrdens();

      if (!mounted) {
        return;
      }

      setState(() {
        _executandoAcao = false;
      });

      final ordemAtualizada = await _repository.buscarOrdemServicoCompletaPorId(
        id,
      );

      if (!mounted) {
        return;
      }

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
                    Icons.payments_outlined,
                    color: Color(0xFFD6A84B),
                  ),
                  title: const Text('Gerenciar pagamentos'),
                  subtitle: const Text(
                    'Registrar recebimento, parcelas, vencimento ou cobrança.',
                  ),
                  onTap: () {
                    Navigator.of(bottomContext).pop('pagamentos');
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
      } else if (acao == 'pagamentos') {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                PagamentosPage(ordemServicoIdInicial: ordemServicoId),
          ),
        );
        await _carregarOrdens();
      }
    } catch (erro) {
      _mostrarMensagem('Não foi possível concluir a ação.\n$erro', erro: true);
    }
  }

  Future<_PeriodoFinalizacao?> _selecionarPeriodoFinalizacao(
    Map<String, dynamic> ordem,
  ) {
    final agora = DateTime.now();
    final entradaInicial =
        _dataHoraOrdem(
          ordem,
          campoData: 'data_inicio',
          campoHora: 'hora_entrada',
        ) ??
        agora;
    final saidaInicial = agora.isBefore(entradaInicial)
        ? entradaInicial
        : agora;

    return showDialog<_PeriodoFinalizacao>(
      context: context,
      builder: (_) => _PeriodoFinalizacaoDialog(
        entradaInicial: entradaInicial,
        saidaInicial: saidaInicial,
      ),
    );
  }

  DateTime? _dataHoraOrdem(
    Map<String, dynamic> ordem, {
    required String campoData,
    required String campoHora,
  }) {
    final textoData = _obterTexto(ordem, campoData);
    final data = DateTime.tryParse(textoData);
    if (data == null) {
      return null;
    }

    var hora = 0;
    var minuto = 0;
    final textoHora = _obterTexto(ordem, campoHora);
    final partes = textoHora.split(':');
    if (partes.length >= 2) {
      hora = int.tryParse(partes[0]) ?? 0;
      minuto = int.tryParse(partes[1]) ?? 0;
    }

    return DateTime(data.year, data.month, data.day, hora, minuto);
  }

  String _formatarDataHoraResumo(DateTime valor) {
    final dia = valor.day.toString().padLeft(2, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${valor.year} às $hora:$minuto';
  }

  String _formatarDataBancoPeriodo(DateTime valor) {
    final ano = valor.year.toString().padLeft(4, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final dia = valor.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  String _formatarHoraBancoPeriodo(DateTime valor) {
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  Future<DateTime?> _selecionarDataHoraPagamento(DateTime inicial) async {
    final data = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Data real do recebimento',
    );
    if (data == null || !mounted) {
      return null;
    }

    final horario = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(inicial),
      helpText: 'Hora real do recebimento',
    );
    if (horario == null || !mounted) {
      return null;
    }

    return DateTime(
      data.year,
      data.month,
      data.day,
      horario.hour,
      horario.minute,
    );
  }

  Future<_RecebimentoFinalizacao?> _selecionarRecebimentoFinalizacao(
    Map<String, dynamic> ordem, {
    required DateTime dataPagamentoPadrao,
  }) async {
    final opcao = await showModalBottomSheet<String>(
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
                      'Recebimento da Ordem de Serviço',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: const Text('Receber tudo agora'),
                  subtitle: const Text(
                    'Registra o pagamento total e lança a entrada no financeiro.',
                  ),
                  onTap: () => Navigator.of(bottomContext).pop('agora'),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Receber depois'),
                  subtitle: const Text(
                    'Finaliza a OS sem criar entrada financeira. O saldo fica em contas a receber.',
                  ),
                  onTap: () => Navigator.of(bottomContext).pop('depois'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (opcao == null) {
      return null;
    }

    if (opcao == 'depois') {
      return const _RecebimentoFinalizacao(receberAgora: false);
    }

    final formaPagamento = await _selecionarFormaPagamento();
    if (formaPagamento == null || !mounted) {
      return null;
    }

    final dataPagamento = await _selecionarDataHoraPagamento(
      dataPagamentoPadrao,
    );
    if (dataPagamento == null || !mounted) {
      return null;
    }

    final valorBase = _valorFinalOrdem(ordem);
    if (_ehFormaCartao(formaPagamento)) {
      final configuracao = await _selecionarConfiguracaoCartao(
        formaPagamento: formaPagamento,
        valorBase: valorBase,
      );
      if (configuracao == null) {
        return null;
      }

      return _RecebimentoFinalizacao(
        receberAgora: true,
        formaPagamento: formaPagamento,
        valorPagamento: valorBase,
        contaFinanceiraId: configuracao.contaId,
        contaNome: configuracao.contaNome,
        parcelasTaxa: configuracao.parcelas,
        regraTaxa: configuracao.regraTaxa,
        dataPagamento: dataPagamento,
      );
    }

    final contaRecebimento = await _selecionarContaRecebimento();
    if (contaRecebimento == null || !mounted) {
      return null;
    }

    return _RecebimentoFinalizacao(
      receberAgora: true,
      formaPagamento: formaPagamento,
      valorPagamento: valorBase,
      contaFinanceiraId: contaRecebimento.id,
      contaNome: contaRecebimento.nome,
      dataPagamento: dataPagamento,
    );
  }

  Future<_ContaFinalizacao?> _selecionarContaRecebimento() async {
    List<ContaFinanceira> contas;

    try {
      contas = await _contaFinanceiraRepository.listar();
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível carregar as contas financeiras.\n$erro',
        erro: true,
      );
      return null;
    }

    if (!mounted) {
      return null;
    }

    final contasValidas = contas
        .where((conta) => conta.id != null)
        .toList();

    if (contasValidas.isEmpty) {
      _mostrarMensagem(
        'Cadastre uma conta financeira antes de registrar o recebimento.',
        erro: true,
      );
      return null;
    }

    if (contasValidas.length == 1) {
      final conta = contasValidas.single;
      return _ContaFinalizacao(id: conta.id, nome: conta.nome);
    }

    return showModalBottomSheet<_ContaFinalizacao>(
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
                      'Conta de recebimento',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Selecione onde o dinheiro realmente entrou.',
                    ),
                  ),
                ),
                ...contasValidas.map(
                  (conta) => ListTile(
                    leading: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                    title: Text(conta.nome),
                    onTap: () => Navigator.of(bottomContext).pop(
                      _ContaFinalizacao(id: conta.id, nome: conta.nome),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _ehFormaCartao(String formaPagamento) {
    return formaPagamento == 'Cartão de crédito' ||
        formaPagamento == 'Cartão de débito';
  }

  Future<_ConfiguracaoCartaoFinalizacao?> _selecionarConfiguracaoCartao({
    required String formaPagamento,
    required double valorBase,
  }) async {
    List<ContaFinanceira> contas;
    try {
      contas = await _contaFinanceiraRepository.listar();
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível carregar as contas/maquininhas.\n$erro',
        erro: true,
      );
      return null;
    }

    if (!mounted) {
      return null;
    }

    final conta = await _selecionarContaMaquininha(contas);
    if (conta == null || !mounted) {
      return null;
    }

    var parcelas = 1;
    if (formaPagamento == 'Cartão de crédito') {
      final escolhidas = await _selecionarParcelasCartao();
      if (escolhidas == null || !mounted) {
        return null;
      }
      parcelas = escolhidas;
    }

    Map<String, dynamic>? regra;
    try {
      regra = await _pagamentoRepository.calcularTaxaAutomatica(
        formaPagamento: formaPagamento,
        valor: valorBase,
        parcelas: parcelas,
        contaFinanceiraId: conta.id,
      );
    } catch (erro) {
      _mostrarMensagem('Não foi possível calcular a taxa.\n$erro', erro: true);
      return null;
    }

    if (!mounted) {
      return null;
    }

    if (regra == null) {
      _mostrarMensagem(
        'Nenhuma regra da maquininha foi encontrada para '
        '$formaPagamento ${parcelas}x nesta conta.',
        erro: true,
      );
      return null;
    }

    final confirmar = await _confirmarConfiguracaoCartao(
      formaPagamento: formaPagamento,
      valorBase: valorBase,
      conta: conta,
      parcelas: parcelas,
      regra: regra,
    );
    if (!confirmar) {
      return null;
    }

    return _ConfiguracaoCartaoFinalizacao(
      contaId: conta.id,
      contaNome: conta.nome,
      parcelas: parcelas,
      regraTaxa: regra,
    );
  }

  Future<_ContaFinalizacao?> _selecionarContaMaquininha(
    List<ContaFinanceira> contas,
  ) {
    return showModalBottomSheet<_ContaFinalizacao>(
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
                      'Conta / maquininha',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (contas.where((conta) => conta.id != null).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Nenhuma conta de maquininha foi cadastrada.',
                    ),
                  ),
                ...contas.where((conta) => conta.id != null).map(
                  (conta) => ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(conta.nome),
                    onTap: () => Navigator.of(
                      bottomContext,
                    ).pop(_ContaFinalizacao(id: conta.id, nome: conta.nome)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<int?> _selecionarParcelasCartao() {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Parcelas no cartão',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: 24,
                    itemBuilder: (_, index) {
                      final parcelas = index + 1;
                      return ListTile(
                        leading: const Icon(Icons.view_week_outlined),
                        title: Text('${parcelas}x'),
                        onTap: () => Navigator.of(bottomContext).pop(parcelas),
                      );
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

  Future<bool> _confirmarConfiguracaoCartao({
    required String formaPagamento,
    required double valorBase,
    required _ContaFinalizacao conta,
    required int parcelas,
    required Map<String, dynamic>? regra,
  }) async {
    final nomeRegra = (regra?['nome'] ?? '').toString().trim();
    final taxaPercentual = _doubleMapa(regra?['taxa_percentual']);
    final taxaFixa = _doubleMapa(regra?['taxa_fixa']);
    final taxaOperacao = _doubleMapa(regra?['taxa_operacao']);
    final acrescimoCliente = _doubleMapa(regra?['acrescimo_cliente']);
    final valorCobrado = regra == null
        ? valorBase
        : _doubleMapa(regra['valor_cobrado']);
    final valorLiquido = regra == null
        ? valorBase
        : _doubleMapa(regra['valor_liquido']);
    final repassar =
        regra?['repassar_cliente'] == true ||
        regra?['repassar_cliente'] == 1 ||
        regra?['repassar_cliente']?.toString() == '1';

    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar cartão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$formaPagamento • ${parcelas}x'),
              Text('Maquininha/conta: ${conta.nome}'),
              const SizedBox(height: 12),
              if (regra == null) ...[
                const Text(
                  'Nenhuma regra de taxa foi encontrada para esta combinação.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Você pode continuar, mas o pagamento será registrado sem taxa automática.',
                ),
              ] else ...[
                Text('Regra: $nomeRegra'),
                Text(
                  'Taxa: ${taxaPercentual.toStringAsFixed(2).replaceAll('.', ',')}%'
                  '${taxaFixa > 0 ? ' + ${_moeda.format(taxaFixa)}' : ''}',
                ),
                const SizedBox(height: 10),
                _linhaResumoCartao('Valor do serviço', valorBase),
                if (acrescimoCliente > 0.000001)
                  _linhaResumoCartao('Repasse ao cliente', acrescimoCliente),
                _linhaResumoCartao(
                  'Total a cobrar',
                  valorCobrado,
                  destaque: true,
                ),
                _linhaResumoCartao('Taxa da maquininha', taxaOperacao),
                _linhaResumoCartao('Líquido previsto', valorLiquido),
                const SizedBox(height: 8),
                Text(
                  repassar
                      ? 'A taxa será repassada automaticamente ao cliente.'
                      : 'A empresa absorverá a taxa da maquininha.',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Usar esta forma'),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  Widget _linhaResumoCartao(
    String titulo,
    double valor, {
    bool destaque = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            _moeda.format(valor),
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  double _doubleMapa(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
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

  Future<bool> _confirmarExclusaoOrdemDeTeste({
    required String numero,
  }) async {
    final controller = TextEditingController();

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final confirmado =
                controller.text.trim().toUpperCase() == 'EXCLUIR';

            return AlertDialog(
              icon: Icon(
                Icons.warning_amber_rounded,
                size: 42,
                color: Colors.red.shade700,
              ),
              title: const Text('Excluir OS de teste'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A Ordem de Serviço $numero será apagada '
                      'definitivamente.',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'O sistema também vai:\n'
                      '• remover pagamentos, parcelas, taxas e lançamentos '
                      'financeiros desta OS;\n'
                      '• devolver ao estoque os produtos baixados por ela;\n'
                      '• remover checklist, fotos, assinatura, revisões, '
                      'itens e produtos vinculados à OS.\n\n'
                      'Cliente, veículo, produtos cadastrados, serviços e '
                      'demais dados do sistema NÃO serão excluídos.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Esta ação não pode ser desfeita. Para confirmar, '
                      'digite EXCLUIR abaixo.',
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Digite EXCLUIR',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: confirmado
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Excluir definitivamente'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return resultado ?? false;
  }

  Future<void> _excluirOrdemDeTeste(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');
    final numero = _obterTexto(ordem, 'numero', padrao: 'sem número');

    if (id <= 0 || _executandoAcao) {
      return;
    }

    final confirmar = await _confirmarExclusaoOrdemDeTeste(numero: numero);
    if (!confirmar || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.excluirOrdemServicoDeTeste(id);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      _mostrarMensagem(
        'OS de teste excluída. Financeiro e estoque foram revertidos.',
      );

      await _carregarOrdens();
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível excluir a OS de teste.\n$erro',
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

  double _converterValorDigitado(String texto) {
    var valor = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');

    if (valor.isEmpty) {
      return 0;
    }

    if (valor.contains(',')) {
      valor = valor.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(valor) ?? 0;
  }

  String _formatarNumeroCampo(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _nomePerfilPrecoOs(String perfil) {
    switch (perfil) {
      case 'cliente':
        return 'Cliente final';
      case 'parceiro_1_4':
        return 'Parceiro • 1 a 4/mês';
      case 'parceiro_5_9':
        return 'Parceiro • 5 a 9/mês';
      case 'parceiro_10_mais':
        return 'Parceiro • 10+/mês';
      case 'informado':
      default:
        return 'Preço informado / combinado';
    }
  }

  String _origemDescontoOs(String origem, double desconto) {
    switch (origem) {
      case 'fidelidade_sugerida':
        return 'Fidelidade aplicada após sugestão';
      case 'fidelidade_automatica':
        return 'Fidelidade automática';
      case 'nenhum':
        return 'Sem desconto';
      case 'manual':
        return 'Desconto manual';
      default:
        return desconto > 0 ? 'Desconto manual' : 'Sem desconto';
    }
  }

  Future<String> _perfilPrecoDaOrdem(int ordemServicoId) async {
    try {
      return await _precificacaoRepository.buscarPerfilDocumento(
            documentoTipo: 'OS',
            documentoId: ordemServicoId,
          ) ??
          'informado';
    } catch (_) {
      return 'informado';
    }
  }

  Future<Map<int, PrecificacaoServico>> _carregarPrecificacaoPorId() async {
    try {
      final painel = await _precificacaoRepository.carregar();
      return {
        for (final servico in painel.servicos) servico.id: servico,
      };
    } catch (_) {
      return const <int, PrecificacaoServico>{};
    }
  }

  double _precoServicoPorPerfil({
    required ServicoCatalogo servico,
    required String perfil,
    required Map<int, PrecificacaoServico> precificacaoPorId,
  }) {
    final id = servico.id;
    final precificacao = id == null ? null : precificacaoPorId[id];

    if (perfil == 'informado') {
      return servico.precoPadrao;
    }

    if (perfil == 'cliente') {
      final sugerido = precificacao?.precoSugerido ?? 0;
      return sugerido > 0 ? sugerido : servico.precoPadrao;
    }

    if (precificacao == null || !precificacao.aceitaRevenda) {
      final sugerido = precificacao?.precoSugerido ?? 0;
      return sugerido > 0 ? sugerido : servico.precoPadrao;
    }

    final fallbackCliente = precificacao.precoSugerido > 0
        ? precificacao.precoSugerido
        : servico.precoPadrao;

    switch (perfil) {
      case 'parceiro_1_4':
        return precificacao.precoRevenda1a4 > 0
            ? precificacao.precoRevenda1a4
            : fallbackCliente;
      case 'parceiro_5_9':
        return precificacao.precoRevenda5a9 > 0
            ? precificacao.precoRevenda5a9
            : fallbackCliente;
      case 'parceiro_10_mais':
        return precificacao.precoRevenda10Mais > 0
            ? precificacao.precoRevenda10Mais
            : fallbackCliente;
      default:
        return servico.precoPadrao;
    }
  }

  Future<ServicoCatalogo?> _selecionarServicoCatalogoParaOs({
    required String perfilPreco,
    required Map<int, PrecificacaoServico> precificacaoPorId,
  }) async {
    List<ServicoCatalogo> servicos;

    try {
      servicos = await _servicoRepository.listarServicos(
        somenteAtivos: true,
      );
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível carregar o catálogo de serviços.\n$erro',
        erro: true,
      );
      return null;
    }

    if (!mounted) {
      return null;
    }

    if (servicos.isEmpty) {
      _mostrarMensagem(
        'Nenhum serviço ativo foi encontrado no catálogo.',
        erro: true,
      );
      return null;
    }

    final pesquisaController = TextEditingController();
    var pesquisa = '';

    final selecionado = await showModalBottomSheet<ServicoCatalogo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (bottomContext) {
        return StatefulBuilder(
          builder: (context, atualizarModal) {
            final termo = pesquisa.trim().toLowerCase();
            final filtrados = servicos.where((servico) {
              if (termo.isEmpty) {
                return true;
              }

              return servico.nome.toLowerCase().contains(termo) ||
                  servico.categoria.toLowerCase().contains(termo) ||
                  servico.descricao.toLowerCase().contains(termo);
            }).toList();

            return FractionallySizedBox(
              heightFactor: 0.82,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 2, 18, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Adicionar serviço à OS',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: pesquisaController,
                      autofocus: false,
                      decoration: const InputDecoration(
                        labelText: 'Pesquisar serviço',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (valor) {
                        atualizarModal(() {
                          pesquisa = valor;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(
                            child: Text('Nenhum serviço encontrado.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 18),
                            itemCount: filtrados.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, indice) {
                              final servico = filtrados[indice];

                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(
                                    Icons.cleaning_services_outlined,
                                  ),
                                ),
                                title: Text(servico.nome),
                                subtitle: Text(
                                  [
                                    if (servico.categoria.trim().isNotEmpty)
                                      servico.categoria.trim(),
                                    _moeda.format(
                                      _precoServicoPorPerfil(
                                        servico: servico,
                                        perfil: perfilPreco,
                                        precificacaoPorId: precificacaoPorId,
                                      ),
                                    ),
                                    servico.duracaoFormatada,
                                  ].join(' • '),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  FocusScope.of(bottomContext).unfocus();
                                  Navigator.of(bottomContext).pop(servico);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pesquisaController.dispose();
    return selecionado;
  }

  Future<_NovoServicoConfiguracao?> _configurarNovoServico(
    ServicoCatalogo servico, {
    required double valorInicial,
    required String perfilPreco,
  }) async {
    final quantidadeController = TextEditingController(text: '1');
    final valorController = TextEditingController(
      text: _formatarNumeroCampo(valorInicial),
    );
    final descricaoController = TextEditingController(text: servico.descricao);
    String erro = '';

    final resultado = await showDialog<_NovoServicoConfiguracao>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, atualizarDialog) {
            final quantidade = _converterValorDigitado(
              quantidadeController.text,
            );
            final valor = _converterValorDigitado(valorController.text);
            final subtotal = quantidade * valor;

            return AlertDialog(
              title: Text(servico.nome),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 430,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_nomePerfilPrecoOs(perfilPreco)}: '
                        '${_moeda.format(valorInicial)}'
                        ' • Catálogo: ${_moeda.format(servico.precoPadrao)}'
                        ' • Tempo: ${servico.duracaoFormatada}',
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: quantidadeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Quantidade',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => atualizarDialog(() {
                                erro = '';
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: valorController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9,.]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Valor unitário',
                                prefixText: 'R\$ ',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => atualizarDialog(() {
                                erro = '';
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descricaoController,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Valor que será acrescentado à OS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              _moeda.format(subtotal),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Produtos obrigatórios ou marcados por padrão no '
                        'cadastro deste serviço também serão incluídos na OS. '
                        'O estoque só será baixado quando a OS for finalizada.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (erro.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          erro,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final quantidade = _converterValorDigitado(
                      quantidadeController.text,
                    );
                    final valor = _converterValorDigitado(
                      valorController.text,
                    );

                    if (quantidade <= 0) {
                      atualizarDialog(() {
                        erro = 'Informe uma quantidade maior que zero.';
                      });
                      return;
                    }

                    if (valor < 0) {
                      atualizarDialog(() {
                        erro = 'O valor não pode ser negativo.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _NovoServicoConfiguracao(
                        quantidade: quantidade,
                        valorUnitario: valor,
                        descricao: descricaoController.text.trim(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar à OS'),
                ),
              ],
            );
          },
        );
      },
    );

    quantidadeController.dispose();
    valorController.dispose();
    descricaoController.dispose();

    return resultado;
  }

  Future<void> _adicionarServicoNaOrdem(Map<String, dynamic> ordem) async {
    final ordemId = _obterInt(ordem, 'id');
    final status = _obterTexto(ordem, 'status');

    if (ordemId <= 0 || _executandoAcao) {
      return;
    }

    if (status != 'Aberta' && status != 'Em andamento') {
      _mostrarMensagem(
        'Só é possível adicionar serviços em uma OS aberta ou em andamento.',
        erro: true,
      );
      return;
    }

    final perfilPreco = await _perfilPrecoDaOrdem(ordemId);
    final precificacaoPorId = await _carregarPrecificacaoPorId();

    if (!mounted) {
      return;
    }

    final servico = await _selecionarServicoCatalogoParaOs(
      perfilPreco: perfilPreco,
      precificacaoPorId: precificacaoPorId,
    );
    if (servico == null || !mounted) {
      return;
    }

    final servicoId = servico.id;
    if (servicoId == null) {
      _mostrarMensagem('Serviço inválido no catálogo.', erro: true);
      return;
    }

    final precificacao = precificacaoPorId[servicoId];
    final parceiro = perfilPreco.startsWith('parceiro_');
    final elegivelParceiro = precificacao?.aceitaRevenda == true;
    final valorInicial = _precoServicoPorPerfil(
      servico: servico,
      perfil: perfilPreco,
      precificacaoPorId: precificacaoPorId,
    );

    if (parceiro && !elegivelParceiro) {
      _mostrarMensagem(
        '${servico.nome} não está habilitado para revenda. '
        'O preço de cliente final será usado.',
      );
    }

    final configuracao = await _configurarNovoServico(
      servico,
      valorInicial: valorInicial,
      perfilPreco: parceiro && !elegivelParceiro ? 'cliente' : perfilPreco,
    );
    if (configuracao == null || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    Map<String, dynamic>? resultado;
    Object? falha;

    try {
      resultado = await _repository.adicionarServicoCatalogoNaOrdem(
        ordemServicoId: ordemId,
        servicoCatalogoId: servicoId,
        quantidade: configuracao.quantidade,
        valorUnitario: configuracao.valorUnitario,
        descricao: configuracao.descricao,
      );
    } catch (erro) {
      falha = erro;
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (falha != null) {
      _mostrarMensagem(
        'Não foi possível adicionar o serviço.\n$falha',
        erro: true,
      );
      return;
    }

    final resultadoSeguro = resultado ?? <String, dynamic>{};
    final produtos = _obterInt(
      resultadoSeguro,
      'produtos_adicionados',
    );
    final novoSubtotal = _obterDouble(
      resultadoSeguro,
      'novo_subtotal_os',
    );

    Navigator.of(context).pop();
    await _carregarOrdens();

    if (!mounted) {
      return;
    }

    final perfilMensagem = perfilPreco == 'informado'
        ? ''
        : ' • ${_nomePerfilPrecoOs(perfilPreco)}';

    _mostrarMensagem(
      produtos > 0
          ? '${servico.nome} adicionado. '
                '$produtos produto${produtos == 1 ? '' : 's'} '
                'padrão incluído${produtos == 1 ? '' : 's'}. '
                'Subtotal: ${_moeda.format(novoSubtotal)}$perfilMensagem.'
          : '${servico.nome} adicionado. '
                'Subtotal: ${_moeda.format(novoSubtotal)}$perfilMensagem.',
    );

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!mounted) {
      return;
    }

    await _abrirDetalhes({'id': ordemId});
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

      final perfilPreco = await _perfilPrecoDaOrdem(id);
      ordemCompleta['perfil_preco'] = perfilPreco;

      try {
        final snapshot =
            await _fidelidadeRepository.buscarDescontoDocumento(
          documentoTipo: 'OS',
          documentoId: id,
        );

        if (snapshot != null) {
          ordemCompleta['origem_desconto'] = snapshot.origem;
          ordemCompleta['percentual_desconto_origem'] = snapshot.percentual;
          ordemCompleta['cliente_desde_desconto'] =
              snapshot.clienteDesde?.toIso8601String();
        }
      } catch (_) {
        // OS antigas continuam sem metadado de origem do desconto.
      }

      if (!mounted) {
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

  Future<void> _corrigirPeriodoOrdemFinalizada(
    Map<String, dynamic> ordem,
  ) async {
    final id = _obterInt(ordem, 'id');
    final status = _obterTexto(ordem, 'status');

    if (id <= 0 || status != 'Finalizada' || _executandoAcao) {
      return;
    }

    final entradaAtual = _dataHoraOrdem(
      ordem,
      campoData: 'data_inicio',
      campoHora: 'hora_entrada',
    );
    final saidaAtual = _dataHoraOrdem(
      ordem,
      campoData: 'data_finalizacao',
      campoHora: 'hora_saida',
    );

    if (entradaAtual == null || saidaAtual == null) {
      _mostrarMensagem(
        'A OS não possui um período de entrada/saída válido para corrigir.',
        erro: true,
      );
      return;
    }

    final periodo = await showDialog<_PeriodoFinalizacao>(
      context: context,
      builder: (_) => _PeriodoFinalizacaoDialog(
        entradaInicial: entradaAtual,
        saidaInicial: saidaAtual,
      ),
    );

    if (periodo == null || !mounted) {
      return;
    }

    if (periodo.entrada == entradaAtual && periodo.saida == saidaAtual) {
      _mostrarMensagem('Nenhuma alteração foi feita no período.');
      return;
    }

    final motivo = await _solicitarMotivoCorrecao(
      titulo: 'Corrigir entrada e saída',
      descricao:
          'Informe por que a data/hora real de entrada ou saída precisa ser '
          'corrigida. A alteração ficará registrada no histórico da OS.',
    );

    if (motivo == null || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      final numeroRevisao = await _repository.corrigirOrdemFinalizada(
        ordemServicoId: id,
        motivo: motivo,
        funcionarioResponsavel: _obterTexto(
          ordem,
          'funcionario_responsavel',
        ),
        observacoes: _obterTexto(ordem, 'observacoes'),
        quilometragemEntrada: _obterTexto(
          ordem,
          'quilometragem_entrada',
        ),
        combustivelEntrada: _obterTexto(
          ordem,
          'combustivel_entrada',
        ),
        dataInicio: _formatarDataBancoPeriodo(periodo.entrada),
        horaEntrada: _formatarHoraBancoPeriodo(periodo.entrada),
        dataFinalizacao: _formatarDataBancoPeriodo(periodo.saida),
        horaSaida: _formatarHoraBancoPeriodo(periodo.saida),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
      await _carregarOrdens();

      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Período corrigido. Revisão nº $numeroRevisao registrada.',
      );
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível corrigir entrada/saída.\n$erro',
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

  Future<void> _corrigirOrdemFinalizada(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');
    final status = _obterTexto(ordem, 'status');

    if (id <= 0 || status != 'Finalizada' || _executandoAcao) {
      return;
    }

    final numeroRevisao = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) {
          return CorrigirOrdemServicoPage(ordem: ordem);
        },
      ),
    );

    if (numeroRevisao == null || !mounted) {
      return;
    }

    Navigator.of(context).pop();

    await _carregarOrdens();

    if (!mounted) {
      return;
    }

    _mostrarMensagem('Correção nº $numeroRevisao registrada com sucesso.');
  }

  Future<String?> _solicitarMotivoCorrecao({
    required String titulo,
    required String descricao,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _MotivoCorrecaoDialog(titulo: titulo, descricao: descricao);
      },
    );
  }

  Future<void> _abrirChecklist(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');
    String? motivoCorrecao;

    if (status == 'Finalizada') {
      motivoCorrecao = await _solicitarMotivoCorrecao(
        titulo: 'Corrigir checklist',
        descricao:
            'Informe por que o checklist de entrada precisa ser '
            'alterado após a finalização da Ordem de Serviço.',
      );

      if (motivoCorrecao == null || !mounted) {
        return;
      }
    }

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
          somenteLeitura: status == 'Cancelada',
          motivoCorrecao: motivoCorrecao,
        ),
      ),
    );

    if (alterou != true || !mounted) {
      return;
    }

    if (status == 'Finalizada') {
      Navigator.of(context).pop();
      await _carregarOrdens();

      if (!mounted) {
        return;
      }

      _mostrarMensagem('Correção do checklist registrada com sucesso.');
      return;
    }

    _mostrarMensagem('Checklist atualizado.');
  }

  Future<void> _abrirFotos(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    final status = _obterTexto(ordem, 'status', padrao: 'Aberta');
    String? motivoCorrecao;

    if (status == 'Finalizada') {
      motivoCorrecao = await _solicitarMotivoCorrecao(
        titulo: 'Corrigir fotos',
        descricao:
            'Informe por que as fotos de antes ou depois precisam ser '
            'alteradas após a finalização da Ordem de Serviço.',
      );

      if (motivoCorrecao == null || !mounted) {
        return;
      }
    }

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
          somenteLeitura: status == 'Cancelada',
          motivoCorrecao: motivoCorrecao,
        ),
      ),
    );

    if (alterou != true || !mounted) {
      return;
    }

    if (status == 'Finalizada') {
      Navigator.of(context).pop();
      await _carregarOrdens();

      if (!mounted) {
        return;
      }

      _mostrarMensagem('Correção das fotos registrada com sucesso.');
      return;
    }

    _mostrarMensagem('Fotos da Ordem de Serviço atualizadas.');
  }

  Future<void> _abrirPagamentosDaOrdem(Map<String, dynamic> ordem) async {
    final id = _obterInt(ordem, 'id');

    if (id <= 0) {
      _mostrarMensagem('Ordem de Serviço inválida.', erro: true);
      return;
    }

    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PagamentosPage(ordemServicoIdInicial: id),
      ),
    );

    await _carregarOrdens();
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
    final descontoNegociacao = _obterDouble(ordem, 'desconto_negociacao');
    final acrescimoNegociacao = _obterDouble(ordem, 'acrescimo_negociacao');
    final jurosParcelamento = _obterDouble(ordem, 'juros_parcelamento');

    return (valorTotal -
            desconto -
            descontoNegociacao +
            acrescimoNegociacao +
            jurosParcelamento)
        .clamp(0, double.infinity)
        .toDouble();
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

    final valorFinal = _valorFinalOrdem(ordem);
    final valorRecebido = _obterDouble(ordem, 'valor_recebido');
    final saldoPendente = (valorFinal - valorRecebido)
        .clamp(0, double.infinity)
        .toDouble();

    if (saldoPendente <= 0.000001) {
      _mostrarMensagem('Esta Ordem de Serviço já está quitada.');
      return;
    }

    final valor = _moeda.format(saldoPendente);

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

    final perfilPreco = _obterTexto(
      ordem,
      'perfil_preco',
      padrao: 'informado',
    );

    final origemDesconto = _obterTexto(ordem, 'origem_desconto');
    final percentualDescontoOrigem = _obterDouble(
      ordem,
      'percentual_desconto_origem',
    );

    final quilometragemEntrada = _obterTexto(
      ordem,
      'quilometragem_entrada',
      padrao: '-',
    );

    final combustivelEntrada = _obterTexto(
      ordem,
      'combustivel_entrada',
      padrao: '-',
    );

    final valorTotal = _obterDouble(ordem, 'valor_total');
    final desconto = _obterDouble(ordem, 'desconto');
    final descontoNegociacao = _obterDouble(ordem, 'desconto_negociacao');
    final acrescimoNegociacao = _obterDouble(ordem, 'acrescimo_negociacao');
    final jurosParcelamento = _obterDouble(ordem, 'juros_parcelamento');
    final valorFinal = _valorFinalOrdem(ordem);

    final quantidadeRevisoes = _obterInt(ordem, 'quantidade_revisoes');

    final revisadaEm = _obterTexto(ordem, 'revisada_em');

    final motivoUltimaRevisao = _obterTexto(ordem, 'motivo_ultima_revisao');

    final assinaturaDesatualizada =
        _obterInt(ordem, 'assinatura_desatualizada') == 1;

    final statusPagamento = _obterTexto(
      ordem,
      'status_pagamento',
      padrao: status == 'Cancelada' ? 'Cancelado' : 'Pendente',
    );
    final valorRecebido = _obterDouble(ordem, 'valor_recebido');
    final saldoPendente = (valorFinal - valorRecebido)
        .clamp(0, double.infinity)
        .toDouble();
    final vencimentoPagamento = _obterTexto(ordem, 'vencimento_pagamento');

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
          if (quantidadeRevisoes > 0) ...[
            Card(
              color: Colors.amber.withValues(alpha: 0.10),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.history_edu_outlined,
                  color: Colors.amber,
                ),
                title: Text(
                  quantidadeRevisoes == 1
                      ? '1 correção registrada'
                      : '$quantidadeRevisoes correções registradas',
                ),
                subtitle: Text(
                  [
                    if (revisadaEm.isNotEmpty)
                      'Última: ${_formatarData(revisadaEm)}',
                    if (motivoUltimaRevisao.isNotEmpty) motivoUltimaRevisao,
                  ].join(' • '),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (assinaturaDesatualizada) ...[
            Card(
              color: Colors.orange.withValues(alpha: 0.10),
              margin: EdgeInsets.zero,
              child: const ListTile(
                leading: Icon(
                  Icons.warning_amber_outlined,
                  color: Colors.orange,
                ),
                title: Text('Assinatura anterior desatualizada'),
                subtitle: Text(
                  'A Ordem de Serviço foi corrigida após a assinatura. '
                  'Recomenda-se coletar uma nova assinatura.',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
              _LinhaInformacao(
                titulo: 'Quilometragem entrada',
                valor: quilometragemEntrada,
              ),
              _LinhaInformacao(
                titulo: 'Combustível entrada',
                valor: combustivelEntrada,
              ),
              if (status == 'Finalizada') ...[
                const Divider(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _executandoAcao
                        ? null
                        : () => _corrigirPeriodoOrdemFinalizada(ordem),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Corrigir entrada / saída'),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use quando a OS foi finalizada depois, mas o veículo '
                  'entrou ou saiu em outra data/hora.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
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
          if (status == 'Finalizada') ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.payments_outlined,
                  color: _corStatusPagamento(statusPagamento),
                ),
                title: const Text(
                  'Pagamentos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '$statusPagamento • Recebido ${_moeda.format(valorRecebido)} • '
                  'Pendente ${_moeda.format(saldoPendente)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _abrirPagamentosDaOrdem(ordem),
              ),
            ),
          ],
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
              if (status == 'Aberta' || status == 'Em andamento') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _executandoAcao
                        ? null
                        : () => _adicionarServicoNaOrdem(ordem),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar serviço'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Você pode incluir novos serviços enquanto a OS estiver '
                  'aberta ou em andamento.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Divider(),
              ],
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
              if (desconto > 0.000001 || origemDesconto.isNotEmpty)
                _LinhaInformacao(
                  titulo: 'Origem do desconto',
                  valor: [
                    _origemDescontoOs(origemDesconto, desconto),
                    if (percentualDescontoOrigem > 0.000001)
                      '${percentualDescontoOrigem.toStringAsFixed(1).replaceAll('.', ',')}%',
                  ].join(' • '),
                ),
              if (descontoNegociacao > 0.000001)
                _LinhaInformacao(
                  titulo: 'Desconto negociação',
                  valor: '- ${_moeda.format(descontoNegociacao)}',
                ),
              if (acrescimoNegociacao > 0.000001)
                _LinhaInformacao(
                  titulo: 'Acréscimos',
                  valor: '+ ${_moeda.format(acrescimoNegociacao)}',
                ),
              if (jurosParcelamento > 0.000001)
                _LinhaInformacao(
                  titulo: 'Juros',
                  valor: '+ ${_moeda.format(jurosParcelamento)}',
                ),
              const Divider(),
              _LinhaInformacao(
                titulo: 'Total',
                valor: _moeda.format(valorFinal),
                destaque: true,
              ),
              _LinhaInformacao(
                titulo: 'Perfil de preço',
                valor: _nomePerfilPrecoOs(perfilPreco),
              ),
              _LinhaInformacao(titulo: 'Pagamento', valor: formaPagamento),
              if (status == 'Finalizada') ...[
                _LinhaInformacao(titulo: 'Status', valor: statusPagamento),
                _LinhaInformacao(
                  titulo: 'Recebido',
                  valor: _moeda.format(valorRecebido),
                ),
                _LinhaInformacao(
                  titulo: 'Pendente',
                  valor: _moeda.format(saldoPendente),
                  destaque: saldoPendente > 0.000001,
                ),
                if (vencimentoPagamento.isNotEmpty)
                  _LinhaInformacao(
                    titulo: 'Vencimento',
                    valor: _formatarData(vencimentoPagamento),
                  ),
              ],
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

    if (status == 'Finalizada') {
      botoes.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _executandoAcao
                ? null
                : () => _corrigirOrdemFinalizada(ordem),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Corrigir OS'),
          ),
        ),
      );
      botoes.add(const SizedBox(width: 10));
      botoes.add(
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade700),
            ),
            onPressed: _executandoAcao
                ? null
                : () => _excluirOrdemDeTeste(ordem),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir teste'),
          ),
        ),
      );
    }

    if (status == 'Cancelada') {
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
            separatorBuilder: (_, _) {
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
        separatorBuilder: (_, _) {
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

    final valorFinal = _valorFinalOrdem(ordem);

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
              if (status == 'Finalizada') ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _EtiquetaPagamento(
                    status: _obterTexto(
                      ordem,
                      'status_pagamento',
                      padrao: 'Pendente',
                    ),
                    cor: _corStatusPagamento(
                      _obterTexto(
                        ordem,
                        'status_pagamento',
                        padrao: 'Pendente',
                      ),
                    ),
                  ),
                ),
              ],
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

class _NovoServicoConfiguracao {
  const _NovoServicoConfiguracao({
    required this.quantidade,
    required this.valorUnitario,
    required this.descricao,
  });

  final double quantidade;
  final double valorUnitario;
  final String descricao;
}

class _DataHoraEntradaDialog extends StatefulWidget {
  const _DataHoraEntradaDialog({required this.inicial});

  final DateTime inicial;

  @override
  State<_DataHoraEntradaDialog> createState() => _DataHoraEntradaDialogState();
}

class _DataHoraEntradaDialogState extends State<_DataHoraEntradaDialog> {
  late DateTime _valor;

  @override
  void initState() {
    super.initState();
    _valor = widget.inicial;
  }

  String _formatar(DateTime valor) {
    final dia = valor.day.toString().padLeft(2, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${valor.year} às $hora:$minuto';
  }

  Future<void> _editar() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _valor,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Data de entrada do veículo',
    );
    if (data == null || !mounted) {
      return;
    }

    final horario = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_valor),
      helpText: 'Hora de entrada do veículo',
    );
    if (horario == null || !mounted) {
      return;
    }

    setState(() {
      _valor = DateTime(
        data.year,
        data.month,
        data.day,
        horario.hour,
        horario.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Iniciar serviço'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A entrada vem preenchida com o horário atual. Altere somente se '
            'estiver registrando a chegada do veículo depois.',
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login_outlined),
            title: const Text('Entrada do veículo'),
            subtitle: Text(_formatar(_valor)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _editar,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_valor),
          child: const Text('Iniciar'),
        ),
      ],
    );
  }
}

class _PeriodoFinalizacao {
  const _PeriodoFinalizacao({required this.entrada, required this.saida});

  final DateTime entrada;
  final DateTime saida;
}

class _PeriodoFinalizacaoDialog extends StatefulWidget {
  const _PeriodoFinalizacaoDialog({
    required this.entradaInicial,
    required this.saidaInicial,
  });

  final DateTime entradaInicial;
  final DateTime saidaInicial;

  @override
  State<_PeriodoFinalizacaoDialog> createState() =>
      _PeriodoFinalizacaoDialogState();
}

class _PeriodoFinalizacaoDialogState extends State<_PeriodoFinalizacaoDialog> {
  late DateTime _entrada;
  late DateTime _saida;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    _entrada = widget.entradaInicial;
    _saida = widget.saidaInicial;
  }

  String _formatar(DateTime valor) {
    final dia = valor.day.toString().padLeft(2, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${valor.year} às $hora:$minuto';
  }

  Future<void> _editar({required bool entrada}) async {
    final atual = entrada ? _entrada : _saida;
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: entrada ? 'Data de entrada' : 'Data de saída',
    );
    if (data == null || !mounted) {
      return;
    }

    final horario = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(atual),
      helpText: entrada ? 'Hora de entrada' : 'Hora de saída',
    );
    if (horario == null || !mounted) {
      return;
    }

    final novo = DateTime(
      data.year,
      data.month,
      data.day,
      horario.hour,
      horario.minute,
    );

    setState(() {
      if (entrada) {
        _entrada = novo;
        if (_saida.isBefore(_entrada)) {
          _saida = _entrada;
        }
      } else {
        _saida = novo;
      }
      _erro = '';
    });
  }

  void _confirmar() {
    if (_saida.isBefore(_entrada)) {
      setState(() {
        _erro = 'A saída não pode ser anterior à entrada.';
      });
      return;
    }

    Navigator.of(
      context,
    ).pop(_PeriodoFinalizacao(entrada: _entrada, saida: _saida));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entrada e saída do veículo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confira os horários reais. Você pode finalizar a OS depois sem '
            'perder a data em que o veículo realmente entrou e saiu.',
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login_outlined),
            title: const Text('Entrada'),
            subtitle: Text(_formatar(_entrada)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _editar(entrada: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_outlined),
            title: const Text('Saída'),
            subtitle: Text(_formatar(_saida)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () => _editar(entrada: false),
          ),
          if (_erro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _erro,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Continuar')),
      ],
    );
  }
}

class _RecebimentoFinalizacao {
  const _RecebimentoFinalizacao({
    required this.receberAgora,
    this.formaPagamento,
    this.valorPagamento,
    this.contaFinanceiraId,
    this.contaNome = '',
    this.parcelasTaxa = 1,
    this.regraTaxa,
    this.dataPagamento,
  });

  final bool receberAgora;
  final String? formaPagamento;
  final double? valorPagamento;
  final int? contaFinanceiraId;
  final String contaNome;
  final int parcelasTaxa;
  final Map<String, dynamic>? regraTaxa;
  final DateTime? dataPagamento;

  String get descricaoConfirmacao {
    final forma = formaPagamento ?? 'Não informada';
    if (forma != 'Cartão de crédito' && forma != 'Cartão de débito') {
      final partes = <String>['Recebimento: $forma'];
      if (contaNome.trim().isNotEmpty) {
        partes.add('Conta: $contaNome');
      }
      if (dataPagamento != null) {
        partes.add('Data do recebimento: ${_formatarDataHora(dataPagamento!)}');
      }
      return partes.join('\n');
    }

    final valorCobrado = regraTaxa?['valor_cobrado'];
    final acrescimo = regraTaxa?['acrescimo_cliente'];
    final regra = (regraTaxa?['nome'] ?? '').toString().trim();
    final partes = <String>[
      'Recebimento: $forma ${parcelasTaxa}x',
      if (contaNome.trim().isNotEmpty) 'Maquininha/conta: $contaNome',
      if (regra.isNotEmpty) 'Regra: $regra',
      if (_numero(acrescimo) > 0.000001)
        'Repasse automático: R\$ ${_numero(acrescimo).toStringAsFixed(2).replaceAll('.', ',')}',
      if (_numero(valorCobrado) > 0.000001)
        'Total a cobrar: R\$ ${_numero(valorCobrado).toStringAsFixed(2).replaceAll('.', ',')}',
      if (dataPagamento != null)
        'Data do recebimento: ${_formatarDataHora(dataPagamento!)}',
    ];
    return partes.join('\n');
  }

  static String _formatarDataHora(DateTime valor) {
    final dia = valor.day.toString().padLeft(2, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${valor.year} às $hora:$minuto';
  }

  static double _numero(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _ConfiguracaoCartaoFinalizacao {
  const _ConfiguracaoCartaoFinalizacao({
    required this.contaId,
    required this.contaNome,
    required this.parcelas,
    required this.regraTaxa,
  });

  final int? contaId;
  final String contaNome;
  final int parcelas;
  final Map<String, dynamic>? regraTaxa;
}

class _ContaFinalizacao {
  const _ContaFinalizacao({this.id, required this.nome});

  final int? id;
  final String nome;
}

class _EtiquetaPagamento extends StatelessWidget {
  const _EtiquetaPagamento({required this.status, required this.cor});

  final String status;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MotivoCorrecaoDialog extends StatefulWidget {
  const _MotivoCorrecaoDialog({required this.titulo, required this.descricao});

  final String titulo;
  final String descricao;

  @override
  State<_MotivoCorrecaoDialog> createState() => _MotivoCorrecaoDialogState();
}

class _MotivoCorrecaoDialogState extends State<_MotivoCorrecaoDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continuar() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.descricao),
            const SizedBox(height: 14),
            TextFormField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo da correção *',
                hintText: 'Ex.: faltou registrar a foto traseira',
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
              onFieldSubmitted: (_) {
                _continuar();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _continuar, child: const Text('Continuar')),
      ],
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
