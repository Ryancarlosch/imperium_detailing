import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import '../models/ajuste_financeiro_ordem_servico.dart';
import '../models/conta_financeira.dart';
import '../models/pagamento_ordem_servico.dart';
import '../repositories/conta_financeira_repository.dart';
import '../repositories/pagamento_repository.dart';
import '../services/comprovante_pagamento_service.dart';
import '../services/whatsapp_service.dart';

class PagamentosPage extends StatefulWidget {
  const PagamentosPage({super.key, this.ordemServicoIdInicial});

  final int? ordemServicoIdInicial;

  @override
  State<PagamentosPage> createState() => _PagamentosPageState();
}

class _PagamentosPageState extends State<PagamentosPage> {
  final PagamentoRepository _repository = PagamentoRepository();
  final TextEditingController _pesquisaController = TextEditingController();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _abriuOrdemInicial = false;
  String _pesquisa = '';
  String _status = 'Todos';
  List<Map<String, dynamic>> _ordens = [];
  Map<String, double> _resumo = const {
    'a_receber': 0,
    'vencido': 0,
    'recebido': 0,
    'taxas': 0,
    'liquido': 0,
  };

  static const _statusDisponiveis = <String>[
    'Todos',
    'Pendente',
    'Parcialmente pago',
    'Vencido',
    'Pago',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.listarContasReceber(incluirPagas: true),
        _repository.obterResumoGeral(),
      ]);

      var ordens = List<Map<String, dynamic>>.from(
        resultados[0] as List<dynamic>,
      );

      final ordemInicial = widget.ordemServicoIdInicial;
      if (ordemInicial != null) {
        ordens = ordens
            .where((item) => _int(item['id']) == ordemInicial)
            .toList();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _ordens = ordens;
        _resumo = Map<String, double>.from(
          resultados[1] as Map<String, double>,
        );
        _carregando = false;
      });

      if (widget.ordemServicoIdInicial != null &&
          !_abriuOrdemInicial &&
          ordens.isNotEmpty) {
        _abriuOrdemInicial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _abrirOrdem(ordens.first);
          }
        });
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mensagem('Não foi possível carregar os pagamentos.\n$erro', erro: true);
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    final termo = _pesquisa.trim().toLowerCase();

    return _ordens.where((item) {
      final status = _texto(item['status_pagamento']);
      final numero = _texto(item['numero']).toLowerCase();
      final cliente = _texto(item['cliente_nome']).toLowerCase();
      final placa = _texto(item['veiculo_placa']).toLowerCase();

      final correspondeStatus = _status == 'Todos' || status == _status;
      final correspondePesquisa =
          termo.isEmpty ||
          numero.contains(termo) ||
          cliente.contains(termo) ||
          placa.contains(termo);

      return correspondeStatus && correspondePesquisa;
    }).toList();
  }

  Future<void> _abrirOrdem(Map<String, dynamic> ordem) async {
    final id = _int(ordem['id']);
    if (id == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PagamentoOrdemDetalhesPage(ordemServicoId: id),
      ),
    );

    await _carregar();
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }

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
    final ordens = _filtradas;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ordemServicoIdInicial == null
              ? 'Pagamentos e contas a receber'
              : 'Pagamentos da OS',
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (widget.ordemServicoIdInicial == null) ...[
                    _ResumoPagamentos(
                      aReceber: _resumo['a_receber'] ?? 0,
                      vencido: _resumo['vencido'] ?? 0,
                      recebido: _resumo['recebido'] ?? 0,
                      taxas: _resumo['taxas'] ?? 0,
                      liquido: _resumo['liquido'] ?? 0,
                      moeda: _moeda,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _pesquisaController,
                    onChanged: (valor) {
                      setState(() {
                        _pesquisa = valor;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Pesquisar OS, cliente ou placa',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _pesquisa.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar',
                              onPressed: () {
                                _pesquisaController.clear();
                                setState(() {
                                  _pesquisa = '';
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _statusDisponiveis.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final status = _statusDisponiveis[index];
                        return ChoiceChip(
                          label: Text(status),
                          selected: _status == status,
                          onSelected: (_) {
                            setState(() {
                              _status = status;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (ordens.isEmpty)
                    const _EstadoVazioPagamentos()
                  else
                    ...ordens.map(
                      (ordem) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CardContaReceber(
                          ordem: ordem,
                          moeda: _moeda,
                          data: _data,
                          onTap: () => _abrirOrdem(ordem),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PagamentoOrdemDetalhesPage extends StatefulWidget {
  const _PagamentoOrdemDetalhesPage({required this.ordemServicoId});

  final int ordemServicoId;

  @override
  State<_PagamentoOrdemDetalhesPage> createState() =>
      _PagamentoOrdemDetalhesPageState();
}

class _PagamentoOrdemDetalhesPageState
    extends State<_PagamentoOrdemDetalhesPage> {
  final PagamentoRepository _repository = PagamentoRepository();
  final ComprovantePagamentoService _comprovanteService =
      const ComprovantePagamentoService();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _executando = false;
  Map<String, dynamic>? _ordem;
  List<PagamentoOrdemServico> _pagamentos = [];
  List<AjusteFinanceiroOrdemServico> _ajustes = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.buscarResumoOrdem(widget.ordemServicoId),
        _repository.listarPagamentosDaOrdem(widget.ordemServicoId),
        _repository.listarAjustesDaOrdem(widget.ordemServicoId),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _ordem = resultados[0] as Map<String, dynamic>?;
        _pagamentos = List<PagamentoOrdemServico>.from(
          resultados[1] as List<dynamic>,
        );
        _ajustes = List<AjusteFinanceiroOrdemServico>.from(
          resultados[2] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mensagem('Não foi possível carregar a OS.\n$erro', erro: true);
    }
  }

  double get _valorOriginal => _double(_ordem?['valor_total']);
  double get _descontoOs => _double(_ordem?['desconto']);
  double get _valorBase => _double(_ordem?['valor_base']);
  double get _descontoNegociacao => _double(_ordem?['desconto_negociacao']);
  double get _acrescimoNegociacao => _double(_ordem?['acrescimo_negociacao']);
  double get _jurosParcelamento => _double(_ordem?['juros_parcelamento']);
  double get _total => _double(_ordem?['valor_final']);
  double get _recebido => _double(_ordem?['valor_recebido']);
  double get _taxas => _double(_ordem?['taxas_operacao']);
  double get _liquidoRecebido => _double(_ordem?['valor_liquido_recebido']);
  double get _custoProdutos => _double(_ordem?['custo_produtos']);
  double get _resultadoAposTaxasProdutos =>
      _double(_ordem?['resultado_apos_taxas_produtos']);
  double get _pendente => _double(_ordem?['valor_pendente']);

  bool get _temParcelasPendentes {
    return _pagamentos.any(
      (item) => item.estaPendente && item.parcelaNumero != null,
    );
  }

  Future<void> _adicionarAjuste() async {
    if (_executando) {
      return;
    }

    if (_temParcelasPendentes) {
      _mensagem(
        'Cancele as parcelas pendentes antes de alterar a negociação.',
        erro: true,
      );
      return;
    }

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AjusteComercialSheet(
        ordemServicoId: widget.ordemServicoId,
        repository: _repository,
      ),
    );

    if (resultado == true) {
      await _carregar();
      _mensagem('Ajuste comercial registrado.');
    }
  }

  Future<void> _estornarAjuste(AjusteFinanceiroOrdemServico ajuste) async {
    if (ajuste.id == null || _executando) {
      return;
    }

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _MotivoCancelamentoAjusteDialog(),
    );

    if (motivo == null) {
      return;
    }

    final sucesso = await _executar(() {
      return _repository.estornarAjusteComercial(
        ajusteId: ajuste.id!,
        motivo: motivo,
      );
    });

    if (!sucesso) {
      return;
    }

    await _carregar();
    _mensagem('Ajuste comercial estornado.');
  }

  Future<void> _registrarPagamento({PagamentoOrdemServico? parcela}) async {
    if (_executando) {
      return;
    }

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PagamentoFormSheet(
        ordemServicoId: widget.ordemServicoId,
        saldoPendente: _pendente,
        parcela: parcela,
        repository: _repository,
        comprovanteService: _comprovanteService,
      ),
    );

    if (resultado == true) {
      await _carregar();
      _mensagem('Pagamento registrado com sucesso.');
    }
  }

  Future<void> _parcelar() async {
    if (_executando || _pendente <= 0.000001) {
      return;
    }

    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ParcelamentoSheet(
        ordemServicoId: widget.ordemServicoId,
        saldoPendente: _pendente,
        repository: _repository,
      ),
    );

    if (resultado == true) {
      await _carregar();
      _mensagem('Parcelamento criado.');
    }
  }

  Future<void> _cancelarParcelamento() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar parcelas pendentes'),
        content: const Text(
          'As parcelas ainda não recebidas serão canceladas. '
          'Pagamentos já confirmados serão preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar parcelas'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    final sucesso = await _executar(() {
      return _repository.cancelarParcelamentoPendente(widget.ordemServicoId);
    });

    if (!sucesso) {
      return;
    }

    await _carregar();
    _mensagem('Parcelas pendentes canceladas.');
  }

  Future<void> _definirVencimento() async {
    final atual = DateTime.tryParse(_texto(_ordem?['vencimento_pagamento']));
    final hoje = DateTime.now();

    final data = await showDatePicker(
      context: context,
      initialDate: atual ?? hoje,
      firstDate: DateTime(2020),
      lastDate: DateTime(hoje.year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
      helpText: 'Vencimento da conta a receber',
    );

    if (data == null) {
      return;
    }

    final sucesso = await _executar(() {
      return _repository.definirVencimento(
        ordemServicoId: widget.ordemServicoId,
        vencimento: data,
      );
    });

    if (!sucesso) {
      return;
    }

    await _carregar();
    _mensagem('Vencimento atualizado.');
  }

  Future<void> _removerVencimento() async {
    final sucesso = await _executar(() {
      return _repository.definirVencimento(
        ordemServicoId: widget.ordemServicoId,
      );
    });

    if (!sucesso) {
      return;
    }

    await _carregar();
    _mensagem('Vencimento removido.');
  }

  Future<void> _ajustarPagamento(
    PagamentoOrdemServico pagamento,
  ) async {
    final tipo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('O que aconteceu com este recebimento?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_off_outlined),
              title: const Text('Marquei como pago por engano'),
              subtitle: const Text(
                'O cliente não pagou. A correção não cria uma saída de caixa '
                'e a taxa da maquininha também é anulada.',
              ),
              onTap: () => Navigator.of(dialogContext).pop('correcao'),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.keyboard_return_rounded),
              title: const Text('Devolvi dinheiro ao cliente'),
              subtitle: const Text(
                'O dinheiro entrou e depois saiu de verdade. A devolução '
                'aparece no Caixa e a taxa já cobrada é preservada.',
              ),
              onTap: () => Navigator.of(dialogContext).pop('devolucao'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (tipo == null || !mounted) {
      return;
    }

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _MotivoEstornoDialog(),
    );

    if (motivo == null) {
      return;
    }

    final sucesso = await _executar(() {
      if (tipo == 'correcao') {
        return _repository.corrigirPagamentoLancadoPorEngano(
          pagamentoId: pagamento.id!,
          motivo: motivo,
        );
      }

      return _repository.devolverPagamentoAoCliente(
        pagamentoId: pagamento.id!,
        motivo: motivo,
      );
    });

    if (!sucesso) {
      return;
    }

    await _carregar();
    _mensagem(
      tipo == 'correcao'
          ? 'Recebimento corrigido. Nenhuma saída de caixa foi criada.'
          : 'Devolução registrada e Caixa atualizado.',
    );
  }

  Future<void> _cobrarWhatsApp() async {
    final ordem = _ordem;
    if (ordem == null) {
      return;
    }

    if (_pendente <= 0.000001) {
      _mensagem('Esta Ordem de Serviço já está quitada.');
      return;
    }

    final telefone = _texto(ordem['cliente_telefone']);
    final cliente = _texto(ordem['cliente_nome'], padrao: 'Cliente');

    if (telefone.isEmpty) {
      _mensagem(
        'O cliente $cliente não possui telefone cadastrado.',
        erro: true,
      );
      return;
    }

    await _executar(() {
      return WhatsAppService.enviarCobrancaOrdemServico(
        telefone: telefone,
        cliente: cliente,
        numeroOrdem: _texto(ordem['numero'], padrao: 'Ordem de Serviço'),
        valor: _moeda.format(_pendente),
        formaPagamento: _texto(ordem['forma_pagamento'], padrao: 'a combinar'),
      );
    });
  }

  Future<bool> _executar(Future<void> Function() acao) async {
    if (_executando) {
      return false;
    }

    setState(() {
      _executando = true;
    });

    try {
      await acao();
      return true;
    } catch (erro) {
      _mensagem('$erro', erro: true);
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _executando = false;
        });
      }
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }

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
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ordem = _ordem;
    if (ordem == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pagamentos')),
        body: const Center(child: Text('Ordem de Serviço não encontrada.')),
      );
    }

    final status = _texto(ordem['status_pagamento'], padrao: 'Pendente');
    final vencimento = _texto(ordem['vencimento_pagamento']);
    final cliente = _texto(ordem['cliente_nome'], padrao: 'Cliente');
    final veiculo = [
      _texto(ordem['veiculo_marca']),
      _texto(ordem['veiculo_modelo']),
    ].where((item) => item.isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(
        title: Text(_texto(ordem['numero'], padrao: 'Pagamentos')),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _executando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (veiculo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        veiculo,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
              _ChipStatusPagamento(status: status),
            ],
          ),
          const SizedBox(height: 16),
          _ResumoOrdemPagamento(
            valorOriginal: _valorOriginal,
            descontoOs: _descontoOs,
            valorBase: _valorBase,
            descontoNegociacao: _descontoNegociacao,
            acrescimoNegociacao: _acrescimoNegociacao,
            jurosParcelamento: _jurosParcelamento,
            total: _total,
            recebido: _recebido,
            taxas: _taxas,
            liquidoRecebido: _liquidoRecebido,
            pendente: _pendente,
            custoProdutos: _custoProdutos,
            resultadoAposTaxasProdutos: _resultadoAposTaxasProdutos,
            moeda: _moeda,
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('Condições comerciais'),
                  subtitle: Text(
                    _temParcelasPendentes
                        ? 'Cancele as parcelas pendentes para alterar valores.'
                        : 'Desconto, acréscimo ou juros com histórico de auditoria.',
                  ),
                  trailing: IconButton(
                    tooltip: 'Adicionar ajuste',
                    onPressed: _executando || _temParcelasPendentes
                        ? null
                        : _adicionarAjuste,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ),
                if (_ajustes.isNotEmpty) const Divider(height: 1),
                ..._ajustes.map(
                  (ajuste) => _CardAjusteFinanceiro(
                    ajuste: ajuste,
                    moeda: _moeda,
                    data: _data,
                    onEstornar: ajuste.estaAtivo && !_temParcelasPendentes
                        ? () => _estornarAjuste(ajuste)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Vencimento'),
                  subtitle: Text(
                    vencimento.isEmpty
                        ? 'Sem vencimento definido'
                        : _formatarData(vencimento, _data),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _executando ? null : _definirVencimento,
                ),
                if (vencimento.isNotEmpty && !_temParcelasPendentes)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _executando ? null : _removerVencimento,
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Remover vencimento'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_pendente > 0.000001 && !_temParcelasPendentes)
                FilledButton.icon(
                  onPressed: _executando ? null : _registrarPagamento,
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Registrar pagamento'),
                ),
              if (_pendente > 0.000001 && !_temParcelasPendentes)
                OutlinedButton.icon(
                  onPressed: _executando ? null : _parcelar,
                  icon: const Icon(Icons.calendar_view_month_outlined),
                  label: const Text('Parcelar saldo'),
                ),
              if (_temParcelasPendentes)
                OutlinedButton.icon(
                  onPressed: _executando ? null : _cancelarParcelamento,
                  icon: const Icon(Icons.cancel_schedule_send_outlined),
                  label: const Text('Cancelar parcelas pendentes'),
                ),
              if (_pendente > 0.000001)
                OutlinedButton.icon(
                  onPressed: _executando ? null : _cobrarWhatsApp,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Cobrar no WhatsApp'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Histórico e parcelas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_pagamentos.isEmpty)
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Nenhum recebimento ou parcelamento registrado para esta OS.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._pagamentos.map(
              (pagamento) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CardPagamento(
                  pagamento: pagamento,
                  moeda: _moeda,
                  data: _data,
                  onReceber: pagamento.estaPendente
                      ? () => _registrarPagamento(parcela: pagamento)
                      : null,
                  onEstornar: pagamento.estaPago && pagamento.id != null
                      ? () => _ajustarPagamento(pagamento)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PagamentoFormSheet extends StatefulWidget {
  const _PagamentoFormSheet({
    required this.ordemServicoId,
    required this.saldoPendente,
    required this.repository,
    required this.comprovanteService,
    this.parcela,
  });

  final int ordemServicoId;
  final double saldoPendente;
  final PagamentoOrdemServico? parcela;
  final PagamentoRepository repository;
  final ComprovantePagamentoService comprovanteService;

  @override
  State<_PagamentoFormSheet> createState() => _PagamentoFormSheetState();
}

class _PagamentoFormSheetState extends State<_PagamentoFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _valorController;
  final TextEditingController _observacoesController = TextEditingController();
  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final ContaFinanceiraRepository _contaRepository =
      ContaFinanceiraRepository();

  String _formaPagamento = 'Pix';
  int _parcelasCartao = 1;
  Map<String, dynamic>? _regraTaxaAutomatica;
  DateTime _dataPagamento = DateTime.now();
  String? _comprovanteCaminho;
  List<ContaFinanceira> _contas = const [];
  int? _contaFinanceiraId;
  bool _carregandoContas = true;
  bool _salvando = false;
  bool _preservarComprovante = false;

  bool get _recebendoParcela => widget.parcela != null;

  @override
  void initState() {
    super.initState();
    final valor = widget.parcela?.valor ?? widget.saldoPendente;
    _valorController = TextEditingController(
      text: valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    // Parcelas da maquininha são independentes do parcelamento financeiro da OS.
    _parcelasCartao = 1;
    _carregarContas();
  }

  Future<void> _carregarContas() async {
    try {
      final contas = await _contaRepository.listar();

      if (!mounted) {
        return;
      }

      setState(() {
        _contas = contas;
        if (contas.length == 1) {
          _contaFinanceiraId = contas.single.id;
        }
        _carregandoContas = false;
      });
      unawaited(_atualizarRegraTaxa());
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoContas = false;
      });
    }
  }

  Future<void> _atualizarRegraTaxa() async {
    if (!_formaComTaxa) {
      if (mounted) {
        setState(() => _regraTaxaAutomatica = null);
      }
      return;
    }

    final valor = _valor() ?? 0;
    if (valor <= 0) {
      if (mounted) {
        setState(() => _regraTaxaAutomatica = null);
      }
      return;
    }

    try {
      final regra = await widget.repository.calcularTaxaAutomatica(
        formaPagamento: _formaPagamento,
        valor: valor,
        parcelas: _formaPagamento == 'Cartão de crédito' ? _parcelasCartao : 1,
        contaFinanceiraId: null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _regraTaxaAutomatica = regra;
        _contaFinanceiraId = _int(regra?['conta_id']);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _regraTaxaAutomatica = null);
    }
  }

  int? get _regraTaxaIdSelecionada {
    return _int(_regraTaxaAutomatica?['id']);
  }

  String get _nomeContaAutomatica {
    final contaId = _int(_regraTaxaAutomatica?['conta_id']);
    if (contaId == null) {
      return 'Conta não vinculada';
    }

    for (final conta in _contas) {
      if (conta.id == contaId) {
        return conta.nome;
      }
    }

    return 'Conta #$contaId';
  }

  @override
  void dispose() {
    _valorController.dispose();
    _observacoesController.dispose();

    if (!_preservarComprovante && _comprovanteCaminho != null) {
      unawaited(
        widget.comprovanteService.excluirBestEffort(_comprovanteCaminho),
      );
    }

    super.dispose();
  }

  double? _valor() {
    final texto = _valorController.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.'));
    }

    return double.tryParse(texto.replaceAll(',', '.'));
  }

  bool get _formaComTaxa {
    return _formaPagamento == 'Cartão de débito' ||
        _formaPagamento == 'Cartão de crédito';
  }

  double _taxaOperacao() {
    if (!_formaComTaxa) {
      return 0;
    }

    final automatica = _regraTaxaAutomatica?['taxa_operacao'];
    if (automatica is num) {
      return automatica.toDouble();
    }
    return double.tryParse(automatica?.toString() ?? '') ?? 0;
  }

  double? _taxaPercentual() {
    if (!_formaComTaxa) {
      return null;
    }

    final automatica = _regraTaxaAutomatica?['taxa_percentual'];
    if (automatica is num) {
      return automatica.toDouble();
    }
    return double.tryParse(automatica?.toString() ?? '');
  }

  double get _valorCobradoPrevisto {
    final valorBase = _valor() ?? 0;
    final automatico = _regraTaxaAutomatica?['valor_cobrado'];
    if (automatico is num) {
      return automatico.toDouble();
    }
    return double.tryParse(automatico?.toString() ?? '') ?? valorBase;
  }

  double get _acrescimoClientePrevisto {
    final automatico = _regraTaxaAutomatica?['acrescimo_cliente'];
    if (automatico is num) {
      return automatico.toDouble();
    }
    return double.tryParse(automatico?.toString() ?? '') ?? 0;
  }

  bool get _repassarClienteAutomatico {
    final valor = _regraTaxaAutomatica?['repassar_cliente'];
    return valor == true || valor == 1 || valor?.toString() == '1';
  }

  double get _valorLiquidoPrevisto {
    return (_valorCobradoPrevisto - _taxaOperacao())
        .clamp(0, double.infinity)
        .toDouble();
  }

  double get _saldoDepoisPrevisto {
    final valorBase = _valor() ?? 0;
    return (widget.saldoPendente - valorBase)
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataPagamento,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );

    if (data != null && mounted) {
      setState(() {
        _dataPagamento = data;
      });
    }
  }

  Future<void> _selecionarComprovante() async {
    try {
      final caminho = await widget.comprovanteService.selecionarESalvar(
        ordemServicoId: widget.ordemServicoId,
      );

      if (caminho == null || !mounted) {
        return;
      }

      if (_comprovanteCaminho != null) {
        await widget.comprovanteService.excluirBestEffort(_comprovanteCaminho);
      }

      setState(() {
        _comprovanteCaminho = caminho;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível anexar o comprovante.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final valor = _valor();
    if (!_recebendoParcela &&
        (valor == null ||
            valor <= 0 ||
            valor > widget.saldoPendente + 0.000001)) {
      return;
    }

    if (_formaComTaxa && _regraTaxaAutomatica == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma regra da maquininha foi encontrada para esta quantidade de parcelas.',
          ),
        ),
      );
      return;
    }

    if (_contaFinanceiraId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _formaComTaxa
                ? 'A regra da maquininha precisa indicar a conta que receberá o valor.'
                : 'Selecione a conta onde este pagamento entrou.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      if (_recebendoParcela) {
        await widget.repository.receberParcela(
          pagamentoId: widget.parcela!.id!,
          formaPagamento: _formaPagamento,
          dataPagamento: _dataPagamento,
          comprovanteCaminho: _comprovanteCaminho,
          observacoes: _observacoesController.text,
          contaFinanceiraId: _contaFinanceiraId,
          parcelasTaxa: _formaPagamento == 'Cartão de crédito'
              ? _parcelasCartao
              : 1,
          regraTaxaId: _regraTaxaIdSelecionada,
        );
      } else {
        await widget.repository.registrarPagamento(
          ordemServicoId: widget.ordemServicoId,
          valor: valor!,
          formaPagamento: _formaPagamento,
          dataPagamento: _dataPagamento,
          comprovanteCaminho: _comprovanteCaminho,
          observacoes: _observacoesController.text,
          contaFinanceiraId: _contaFinanceiraId,
          parcelasTaxa: _formaPagamento == 'Cartão de crédito'
              ? _parcelasCartao
              : 1,
          regraTaxaId: _regraTaxaIdSelecionada,
        );
      }

      _preservarComprovante = true;

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível registrar o pagamento.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final parcela = widget.parcela;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 45,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                parcela == null
                    ? 'Registrar pagamento'
                    : 'Receber parcela ${parcela.parcelaNumero}/${parcela.totalParcelas}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _valorController,
                enabled: !_recebendoParcela && !_salvando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor recebido',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
                onChanged: (_) {
                  setState(() {});
                  unawaited(_atualizarRegraTaxa());
                },
                validator: (_) {
                  final valor = _valor();

                  if (valor == null || valor <= 0) {
                    return 'Informe um valor maior que zero.';
                  }

                  if (!_recebendoParcela &&
                      valor > widget.saldoPendente + 0.000001) {
                    return 'O valor não pode ultrapassar o saldo pendente.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _formaPagamento,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                  DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(
                    value: 'Cartão de débito',
                    child: Text('Cartão de débito'),
                  ),
                  DropdownMenuItem(
                    value: 'Cartão de crédito',
                    child: Text('Cartão de crédito'),
                  ),
                  DropdownMenuItem(
                    value: 'Transferência',
                    child: Text('Transferência'),
                  ),
                  DropdownMenuItem(value: 'Boleto', child: Text('Boleto')),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor != null) {
                          setState(() {
                            _formaPagamento = valor;
                            if (_formaPagamento == 'Cartão de débito') {
                              _parcelasCartao = 1;
                            }
                            _regraTaxaAutomatica = null;
                            if (_formaComTaxa) {
                              _contaFinanceiraId = null;
                            } else if (_contas.length == 1) {
                              _contaFinanceiraId = _contas.single.id;
                            }
                          });
                          unawaited(_atualizarRegraTaxa());
                        }
                      },
              ),
              if (!_formaComTaxa) ...[
                const SizedBox(height: 14),
                if (_contas.isEmpty)
                  Card(
                    margin: EdgeInsets.zero,
                    color: Colors.red.withValues(alpha: 0.08),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cadastre pelo menos uma conta financeira para registrar onde o dinheiro entrou.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<int?>(
                  initialValue: _contaFinanceiraId,
                  decoration: const InputDecoration(
                    labelText: 'Conta de recebimento',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    helperText: 'Onde este dinheiro entrou',
                  ),
                  items: _contas
                      .map(
                        (conta) => DropdownMenuItem<int?>(
                          value: conta.id,
                          child: Text(conta.nome),
                        ),
                      )
                      .toList(),
                  onChanged: _salvando || _carregandoContas
                      ? null
                      : (valor) {
                          setState(() {
                            _contaFinanceiraId = valor;
                          });
                        },
                ),
              ],
              if (_formaComTaxa) ...[
                if (_formaPagamento == 'Cartão de crédito') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: _parcelasCartao,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade de parcelas',
                      prefixIcon: Icon(Icons.view_week_outlined),
                      helperText:
                          'Selecione as parcelas. A taxa e a conta serão puxadas automaticamente.',
                    ),
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}x'),
                      ),
                    ),
                    onChanged: _salvando
                        ? null
                        : (valor) {
                            setState(() {
                              _parcelasCartao = valor ?? 1;
                              _regraTaxaAutomatica = null;
                              _contaFinanceiraId = null;
                            });
                            unawaited(_atualizarRegraTaxa());
                          },
                  ),
                ],
                const SizedBox(height: 14),
                if (_regraTaxaAutomatica == null)
                  Card(
                    margin: EdgeInsets.zero,
                    color: Colors.red.withValues(alpha: 0.08),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Nenhuma regra encontrada. Cadastre a maquininha e a taxa desta parcela em Financeiro > Regras de maquininha.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _LinhaValor(
                            titulo: 'Regra',
                            valor: (_regraTaxaAutomatica!['nome'] ?? '')
                                .toString(),
                          ),
                          _LinhaValor(
                            titulo: 'Parcelas',
                            valor:
                                '${_int(_regraTaxaAutomatica!['parcelas']) ?? _parcelasCartao}x',
                          ),
                          _LinhaValor(
                            titulo: 'Taxa cadastrada',
                            valor:
                                '${(_taxaPercentual() ?? 0).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '').replaceAll('.', ',')}%',
                          ),
                          _LinhaValor(
                            titulo: 'Conta da maquininha',
                            valor: _nomeContaAutomatica,
                          ),
                          if (_acrescimoClientePrevisto > 0.000001)
                            _LinhaValor(
                              titulo: 'Acréscimo ao cliente',
                              valor: NumberFormat.currency(
                                locale: 'pt_BR',
                                symbol: 'R\$',
                              ).format(_acrescimoClientePrevisto),
                            ),
                          if (_repassarClienteAutomatico)
                            _LinhaValor(
                              titulo: 'Total a cobrar',
                              valor: NumberFormat.currency(
                                locale: 'pt_BR',
                                symbol: 'R\$',
                              ).format(_valorCobradoPrevisto),
                              destaque: true,
                            ),
                          _LinhaValor(
                            titulo: 'Taxa da operação',
                            valor: NumberFormat.currency(
                              locale: 'pt_BR',
                              symbol: 'R\$',
                            ).format(_taxaOperacao()),
                          ),
                          _LinhaValor(
                            titulo: 'Valor líquido',
                            valor: NumberFormat.currency(
                              locale: 'pt_BR',
                              symbol: 'R\$',
                            ).format(_valorLiquidoPrevisto),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _LinhaValor(
                        titulo: 'Saldo atual da OS',
                        valor: NumberFormat.currency(
                          locale: 'pt_BR',
                          symbol: 'R\$',
                        ).format(widget.saldoPendente),
                      ),
                      _LinhaValor(
                        titulo: 'Saldo após este recebimento',
                        valor: NumberFormat.currency(
                          locale: 'pt_BR',
                          symbol: 'R\$',
                        ).format(_saldoDepoisPrevisto),
                        destaque: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Data do pagamento'),
                subtitle: Text(_data.format(_dataPagamento)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _salvando ? null : _selecionarData,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(
                  _comprovanteCaminho == null
                      ? 'Anexar comprovante'
                      : 'Comprovante anexado',
                ),
                subtitle: _comprovanteCaminho == null
                    ? const Text('PDF ou imagem')
                    : Text(path.basename(_comprovanteCaminho!)),
                trailing: _comprovanteCaminho == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: 'Remover comprovante',
                        onPressed: _salvando
                            ? null
                            : () async {
                                final caminho = _comprovanteCaminho;
                                setState(() {
                                  _comprovanteCaminho = null;
                                });
                                await widget.comprovanteService
                                    .excluirBestEffort(caminho);
                              },
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: _salvando || _comprovanteCaminho != null
                    ? null
                    : _selecionarComprovante,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _observacoesController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  prefixIcon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_salvando ? 'Salvando...' : 'Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParcelamentoSheet extends StatefulWidget {
  const _ParcelamentoSheet({
    required this.ordemServicoId,
    required this.saldoPendente,
    required this.repository,
  });

  final int ordemServicoId;
  final double saldoPendente;
  final PagamentoRepository repository;

  @override
  State<_ParcelamentoSheet> createState() => _ParcelamentoSheetState();
}

class _ParcelamentoSheetState extends State<_ParcelamentoSheet> {
  final TextEditingController _parcelasController = TextEditingController(
    text: '2',
  );
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  DateTime _primeiroVencimento = DateTime.now().add(const Duration(days: 30));
  bool _salvando = false;

  @override
  void dispose() {
    _parcelasController.dispose();
    super.dispose();
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _primeiroVencimento,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
      locale: const Locale('pt', 'BR'),
    );

    if (data != null && mounted) {
      setState(() {
        _primeiroVencimento = data;
      });
    }
  }

  Future<void> _salvar() async {
    final parcelas = int.tryParse(_parcelasController.text.trim());

    if (parcelas == null || parcelas < 2 || parcelas > 48) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe entre 2 e 48 parcelas.')),
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      await widget.repository.criarParcelamento(
        ordemServicoId: widget.ordemServicoId,
        totalParcelas: parcelas,
        primeiroVencimento: _primeiroVencimento,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final parcelas = int.tryParse(_parcelasController.text.trim()) ?? 0;
    final valorEstimado = parcelas > 0 ? widget.saldoPendente / parcelas : 0;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Parcelar saldo pendente',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Saldo: ${_moeda.format(widget.saldoPendente)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _parcelasController,
              enabled: !_salvando,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade de parcelas',
                prefixIcon: Icon(Icons.view_week_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Primeiro vencimento'),
              subtitle: Text(_data.format(_primeiroVencimento)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _salvando ? null : _selecionarData,
            ),
            if (parcelas >= 2) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Valor aproximado por parcela'),
                  trailing: Text(
                    _moeda.format(valorEstimado),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _salvando
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: const Icon(Icons.calendar_view_month_outlined),
                    label: const Text('Criar parcelas'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AjusteComercialSheet extends StatefulWidget {
  const _AjusteComercialSheet({
    required this.ordemServicoId,
    required this.repository,
  });

  final int ordemServicoId;
  final PagamentoRepository repository;

  @override
  State<_AjusteComercialSheet> createState() => _AjusteComercialSheetState();
}

class _AjusteComercialSheetState extends State<_AjusteComercialSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  String _tipo = 'Desconto';
  bool _salvando = false;

  @override
  void dispose() {
    _valorController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  double? _valor() {
    final texto = _valorController.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');

    if (texto.contains(',') && texto.contains('.')) {
      return double.tryParse(texto.replaceAll('.', '').replaceAll(',', '.'));
    }

    return double.tryParse(texto.replaceAll(',', '.'));
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      await widget.repository.registrarAjusteComercial(
        ordemServicoId: widget.ordemServicoId,
        tipo: _tipo,
        valor: _valor()!,
        motivo: _motivoController.text,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ajustar negociação',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'O valor original da OS será preservado. O ajuste ficará no histórico.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo do ajuste',
                  prefixIcon: Icon(Icons.tune_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Desconto',
                    child: Text('Desconto negociado'),
                  ),
                  DropdownMenuItem(
                    value: 'Acréscimo',
                    child: Text('Acréscimo negociado'),
                  ),
                  DropdownMenuItem(
                    value: 'Juros',
                    child: Text('Juros / parcelamento'),
                  ),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor != null) {
                          setState(() {
                            _tipo = valor;
                          });
                        }
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _valorController,
                enabled: !_salvando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor do ajuste',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
                validator: (_) {
                  final valor = _valor();
                  if (valor == null || valor <= 0) {
                    return 'Informe um valor maior que zero.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _motivoController,
                enabled: !_salvando,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Ex.: acréscimo para parcelamento em 6x',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.length < 5) {
                    return 'Informe pelo menos 5 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(_salvando ? 'Salvando...' : 'Aplicar ajuste'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MotivoCancelamentoAjusteDialog extends StatefulWidget {
  const _MotivoCancelamentoAjusteDialog();

  @override
  State<_MotivoCancelamentoAjusteDialog> createState() =>
      _MotivoCancelamentoAjusteDialogState();
}

class _MotivoCancelamentoAjusteDialogState
    extends State<_MotivoCancelamentoAjusteDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Estornar ajuste comercial'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motivo do estorno',
            alignLabelWithHint: true,
          ),
          validator: (valor) {
            final texto = valor?.trim() ?? '';
            if (texto.length < 5) {
              return 'Informe pelo menos 5 caracteres.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text('Estornar ajuste'),
        ),
      ],
    );
  }
}

class _MotivoEstornoDialog extends StatefulWidget {
  const _MotivoEstornoDialog();

  @override
  State<_MotivoEstornoDialog> createState() => _MotivoEstornoDialogState();
}

class _MotivoEstornoDialogState extends State<_MotivoEstornoDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Motivo da correção/devolução'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motivo do estorno',
            alignLabelWithHint: true,
          ),
          validator: (valor) {
            final texto = valor?.trim() ?? '';
            if (texto.length < 5) {
              return 'Informe pelo menos 5 caracteres.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _ResumoPagamentos extends StatelessWidget {
  const _ResumoPagamentos({
    required this.aReceber,
    required this.vencido,
    required this.recebido,
    required this.taxas,
    required this.liquido,
    required this.moeda,
  });

  final double aReceber;
  final double vencido;
  final double recebido;
  final double taxas;
  final double liquido;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ResumoGrande(
          titulo: 'Total a receber',
          valor: moeda.format(aReceber),
          icone: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ResumoPequeno(
                titulo: 'Vencido',
                valor: moeda.format(vencido),
                icone: Icons.warning_amber_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResumoPequeno(
                titulo: 'Recebido bruto',
                valor: moeda.format(recebido),
                icone: Icons.check_circle_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ResumoPequeno(
                titulo: 'Taxas',
                valor: moeda.format(taxas),
                icone: Icons.credit_card_off_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ResumoPequeno(
                titulo: 'Recebido líquido',
                valor: moeda.format(liquido),
                icone: Icons.savings_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResumoGrande extends StatelessWidget {
  const _ResumoGrande({
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
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(icone, color: const Color(0xFFD6A84B), size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 3),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoPequeno extends StatelessWidget {
  const _ResumoPequeno({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: const Color(0xFFD6A84B)),
            const SizedBox(height: 8),
            Text(titulo, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 2),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardContaReceber extends StatelessWidget {
  const _CardContaReceber({
    required this.ordem,
    required this.moeda,
    required this.data,
    required this.onTap,
  });

  final Map<String, dynamic> ordem;
  final NumberFormat moeda;
  final DateFormat data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _texto(ordem['status_pagamento'], padrao: 'Pendente');
    final total = _double(ordem['valor_final']);
    final recebido = _double(ordem['valor_recebido']);
    final pendente = _double(ordem['valor_pendente']);
    final vencimento = _texto(ordem['vencimento_pagamento']);
    final placa = _texto(ordem['veiculo_placa']);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _texto(ordem['numero'], padrao: 'OS'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _texto(ordem['cliente_nome'], padrao: 'Cliente'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _ChipStatusPagamento(status: status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (placa.isNotEmpty) ...[
                    const Icon(
                      Icons.directions_car_outlined,
                      size: 17,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 5),
                    Text(placa.toUpperCase()),
                  ],
                  const Spacer(),
                  Text(
                    moeda.format(pendente),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    'Total: ${moeda.format(total)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  Text(
                    'Recebido: ${moeda.format(recebido)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  if (vencimento.isNotEmpty)
                    Text(
                      'Vence: ${_formatarData(vencimento, data)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumoOrdemPagamento extends StatelessWidget {
  const _ResumoOrdemPagamento({
    required this.valorOriginal,
    required this.descontoOs,
    required this.valorBase,
    required this.descontoNegociacao,
    required this.acrescimoNegociacao,
    required this.jurosParcelamento,
    required this.total,
    required this.recebido,
    required this.taxas,
    required this.liquidoRecebido,
    required this.pendente,
    required this.custoProdutos,
    required this.resultadoAposTaxasProdutos,
    required this.moeda,
  });

  final double valorOriginal;
  final double descontoOs;
  final double valorBase;
  final double descontoNegociacao;
  final double acrescimoNegociacao;
  final double jurosParcelamento;
  final double total;
  final double recebido;
  final double taxas;
  final double liquidoRecebido;
  final double pendente;
  final double custoProdutos;
  final double resultadoAposTaxasProdutos;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LinhaValor(
              titulo: 'Valor original',
              valor: moeda.format(valorOriginal),
            ),
            if (descontoOs > 0.000001)
              _LinhaValor(
                titulo: 'Desconto da OS',
                valor: '- ${moeda.format(descontoOs)}',
              ),
            _LinhaValor(
              titulo: 'Base financeira',
              valor: moeda.format(valorBase),
            ),
            if (descontoNegociacao > 0.000001)
              _LinhaValor(
                titulo: 'Desconto negociado',
                valor: '- ${moeda.format(descontoNegociacao)}',
              ),
            if (acrescimoNegociacao > 0.000001)
              _LinhaValor(
                titulo: 'Acréscimo',
                valor: '+ ${moeda.format(acrescimoNegociacao)}',
              ),
            if (jurosParcelamento > 0.000001)
              _LinhaValor(
                titulo: 'Juros / parcelamento',
                valor: '+ ${moeda.format(jurosParcelamento)}',
              ),
            const Divider(),
            _LinhaValor(
              titulo: 'Valor negociado',
              valor: moeda.format(total),
              destaque: true,
            ),
            const Divider(),
            _LinhaValor(
              titulo: 'Recebido bruto',
              valor: moeda.format(recebido),
            ),
            if (taxas > 0.000001)
              _LinhaValor(
                titulo: 'Taxas da maquininha',
                valor: '- ${moeda.format(taxas)}',
              ),
            _LinhaValor(
              titulo: 'Recebido líquido',
              valor: moeda.format(liquidoRecebido),
            ),
            _LinhaValor(
              titulo: 'Saldo pendente',
              valor: moeda.format(pendente),
              destaque: true,
            ),
            if (custoProdutos > 0.000001) ...[
              const Divider(),
              _LinhaValor(
                titulo: 'Custo dos produtos',
                valor: '- ${moeda.format(custoProdutos)}',
              ),
              _LinhaValor(
                titulo: 'Resultado parcial',
                valor: moeda.format(resultadoAposTaxasProdutos),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaValor extends StatelessWidget {
  const _LinhaValor({
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontSize: destaque ? 18 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAjusteFinanceiro extends StatelessWidget {
  const _CardAjusteFinanceiro({
    required this.ajuste,
    required this.moeda,
    required this.data,
    this.onEstornar,
  });

  final AjusteFinanceiroOrdemServico ajuste;
  final NumberFormat moeda;
  final DateFormat data;
  final VoidCallback? onEstornar;

  @override
  Widget build(BuildContext context) {
    final sinal = ajuste.ehDesconto ? '-' : '+';
    final criado = _formatarData(ajuste.criadoEm, data);

    return ListTile(
      leading: Icon(
        ajuste.ehDesconto
            ? Icons.remove_circle_outline
            : Icons.add_circle_outline,
      ),
      title: Text('${ajuste.tipo}: $sinal ${moeda.format(ajuste.valor)}'),
      subtitle: Text(
        [
          ajuste.motivo,
          criado,
          if (ajuste.estaCancelado) 'Estornado',
        ].join(' • '),
      ),
      trailing: onEstornar == null
          ? null
          : IconButton(
              tooltip: 'Estornar ajuste',
              onPressed: onEstornar,
              icon: const Icon(Icons.undo_rounded),
            ),
    );
  }
}

class _CardPagamento extends StatelessWidget {
  const _CardPagamento({
    required this.pagamento,
    required this.moeda,
    required this.data,
    this.onReceber,
    this.onEstornar,
  });

  final PagamentoOrdemServico pagamento;
  final NumberFormat moeda;
  final DateFormat data;
  final VoidCallback? onReceber;
  final VoidCallback? onEstornar;

  @override
  Widget build(BuildContext context) {
    final parcela = pagamento.parcelaNumero == null
        ? ''
        : 'Parcela ${pagamento.parcelaNumero}/${pagamento.totalParcelas}';
    final percentualTaxa = pagamento.taxaPercentual == null
        ? ''
        : ' (${pagamento.taxaPercentual!.toStringAsFixed(2).replaceAll('.', ',')}%)';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    parcela.isEmpty ? 'Pagamento' : parcela,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _ChipStatusPagamento(
                  status: pagamento.estaVencido ? 'Vencido' : pagamento.status,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              moeda.format(pagamento.valor),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            if (pagamento.taxaOperacao > 0.000001) ...[
              const SizedBox(height: 5),
              Text(
                'Taxa: - ${moeda.format(pagamento.taxaOperacao)}$percentualTaxa',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
              Text(
                'Líquido: ${moeda.format(pagamento.valorLiquido)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                if (pagamento.formaPagamento.isNotEmpty)
                  Text(
                    pagamento.formaPagamento,
                    style: const TextStyle(color: Colors.white60),
                  ),
                if (pagamento.dataPagamento != null)
                  Text(
                    _formatarData(pagamento.dataPagamento!, data),
                    style: const TextStyle(color: Colors.white60),
                  ),
                if (pagamento.vencimento != null)
                  Text(
                    'Venc.: ${_formatarData(pagamento.vencimento!, data)}',
                    style: const TextStyle(color: Colors.white60),
                  ),
              ],
            ),
            if (pagamento.comprovanteCaminho != null) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(Icons.attach_file_rounded, size: 16),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      path.basename(pagamento.comprovanteCaminho!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (pagamento.motivoEstorno.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                'Motivo: ${pagamento.motivoEstorno}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            if (onReceber != null || onEstornar != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onEstornar != null)
                    TextButton.icon(
                      onPressed: onEstornar,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Ajustar'),
                    ),
                  if (onReceber != null)
                    FilledButton.icon(
                      onPressed: onReceber,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Receber'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipStatusPagamento extends StatelessWidget {
  const _ChipStatusPagamento({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cor = _corStatusPagamento(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EstadoVazioPagamentos extends StatelessWidget {
  const _EstadoVazioPagamentos();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 70, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 68, color: Colors.white30),
          SizedBox(height: 14),
          Text(
            'Nenhuma conta encontrada',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            'As Ordens de Serviço finalizadas aparecerão aqui para controle de recebimentos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

Color _corStatusPagamento(String status) {
  switch (status) {
    case 'Pago':
      return Colors.green;
    case 'Parcialmente pago':
      return Colors.blue;
    case 'Vencido':
      return Colors.red;
    case 'Estornado':
      return Colors.orange;
    case 'Cancelado':
      return Colors.grey;
    case 'Pendente':
    default:
      return Colors.amber;
  }
}

String _formatarData(String valor, DateFormat formato) {
  final data = DateTime.tryParse(valor);
  return data == null ? valor : formato.format(data);
}

String _texto(dynamic valor, {String padrao = ''}) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? padrao : texto;
}

int? _int(dynamic valor) {
  if (valor is int) {
    return valor;
  }

  if (valor is num) {
    return valor.toInt();
  }

  return int.tryParse(valor?.toString().trim() ?? '');
}

double _double(dynamic valor) {
  if (valor is num) {
    return valor.toDouble();
  }

  return double.tryParse(valor?.toString().trim().replaceAll(',', '.') ?? '') ??
      0;
}
