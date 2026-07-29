import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_orcamento.dart';
import '../repositories/orcamento_repository.dart';
import '../repositories/ordem_servico_repository.dart';
import '../services/pdf/orcamento_pdf_service.dart';
import 'novo_orcamento_page.dart';
import 'nova_ordem_servico_page.dart';

class OrcamentoDetalhesPage extends StatefulWidget {
  const OrcamentoDetalhesPage({
    super.key,
    required this.orcamentoId,
  });

  final int orcamentoId;

  @override
  State<OrcamentoDetalhesPage> createState() =>
      _OrcamentoDetalhesPageState();
}

class _OrcamentoDetalhesPageState
    extends State<OrcamentoDetalhesPage> {
  final _repository = OrcamentoRepository();
  final _ordemRepository = OrdemServicoRepository();
  final _pdfService = OrcamentoPdfService();

  final _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final _data = DateFormat('dd/MM/yyyy');

  Map<String, dynamic>? _dados;
  List<ItemOrcamento> _itens = [];

  bool _carregando = true;
  bool _gerandoPdf = false;
  bool _alterandoStatus = false;
  bool _excluindo = false;
  bool _verificandoOrdem = true;
  bool _abrindoOrdem = false;
  bool _existeOrdemServico = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final dados =
      await _repository.buscarOrcamentoComDetalhes(
        widget.orcamentoId,
      );

      if (!mounted) {
        return;
      }

      final itens = _extrairItens(
        dados?['itens'],
      );

      final existeOrdem = await _ordemRepository
          .existeOrdemParaOrcamento(
        widget.orcamentoId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _dados = dados;
        _itens = itens;
        _existeOrdemServico = existeOrdem;
        _verificandoOrdem = false;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _verificandoOrdem = false;
      });

      _mensagem(
        'Não foi possível carregar o orçamento: $erro',
        erro: true,
      );
    }
  }

  List<ItemOrcamento> _extrairItens(
      dynamic valor,
      ) {
    if (valor is! List) {
      return [];
    }

    return valor
        .whereType<Map>()
        .map(
          (item) => ItemOrcamento.fromMap(
        Map<String, dynamic>.from(item),
      ),
    )
        .toList();
  }

  Future<void> _editar() async {
    final orcamento = await _repository.buscarPorId(
      widget.orcamentoId,
    );

    if (orcamento == null || !mounted) {
      return;
    }

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoOrcamentoPage(
          orcamento: orcamento,
        ),
      ),
    );

    if (alterou == true && mounted) {
      setState(() {
        _carregando = true;
      });

      await _carregar();
    }
  }

  Future<void> _alterarStatus(
      String novoStatus,
      ) async {
    if (_alterandoStatus) {
      return;
    }

    setState(() {
      _alterandoStatus = true;
    });

    try {
      await _repository.atualizarStatus(
        widget.orcamentoId,
        novoStatus,
      );

      await _carregar();

      if (!mounted) {
        return;
      }

      _mensagem(
        'Status atualizado para $novoStatus.',
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mensagem(
        'Não foi possível alterar o status: $erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _alterandoStatus = false;
        });
      }
    }
  }

  Future<void> _gerarOrdemServico() async {
    if (_abrindoOrdem || _existeOrdemServico) {
      return;
    }

    setState(() {
      _abrindoOrdem = true;
    });

    try {
      final criou = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NovaOrdemServicoPage(
            orcamentoId: widget.orcamentoId,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      if (criou == true) {
        setState(() {
          _existeOrdemServico = true;
        });

        _mensagem(
          'Ordem de Serviço vinculada ao orçamento.',
        );
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mensagem(
        'Não foi possível abrir a Ordem de Serviço: $erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _abrindoOrdem = false;
        });
      }
    }
  }

  Future<void> _pdf({
    required bool recibo,
    required bool compartilhar,
  }) async {
    final dados = _dados;

    if (dados == null || _gerandoPdf) {
      return;
    }

    setState(() {
      _gerandoPdf = true;
    });

    try {
      if (compartilhar) {
        await _pdfService.compartilhar(
          dados,
          recibo: recibo,
        );
      } else {
        await _pdfService.visualizar(
          dados,
          recibo: recibo,
        );
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mensagem(
        'Não foi possível gerar o PDF: $erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _gerandoPdf = false;
        });
      }
    }
  }

  Future<void> _excluir() async {
    if (_excluindo) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Excluir orçamento?',
          ),
          content: const Text(
            'O orçamento e todos os seus serviços serão '
                'apagados permanentemente. Esta ação não pode '
                'ser desfeita.',
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
                'Cancelar',
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              icon: const Icon(
                Icons.delete_outline,
              ),
              label: const Text(
                'Excluir',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _excluindo = true;
    });

    try {
      await _repository.excluirOrcamento(
        widget.orcamentoId,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        true,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _excluindo = false;
      });

      _mensagem(
        'Não foi possível excluir o orçamento: $erro',
        erro: true,
      );
    }
  }

  void _mensagem(
      String mensagem, {
        bool erro = false,
      }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor:
          erro ? Colors.red.shade700 : null,
        ),
      );
  }

  String _texto(
      String chave,
      ) {
    return (_dados?[chave] ?? '')
        .toString()
        .trim();
  }

  double _numero(
      String chave,
      ) {
    final valor = _dados?[chave];

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
      valor?.toString() ?? '',
    ) ??
        0;
  }

  String _dataTexto(
      String chave,
      ) {
    final valor = DateTime.tryParse(
      _texto(chave),
    );

    if (valor == null) {
      return 'Não informada';
    }

    return _data.format(valor);
  }

  String _formatarQuantidade(
      double quantidade,
      ) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(
      RegExp(r'0+$'),
      '',
    )
        .replaceAll(
      RegExp(r',$'),
      '',
    );
  }

  Color _corStatus(
      String status,
      ) {
    switch (status) {
      case 'Aprovado':
        return Colors.green;
      case 'Recusado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _iconeStatus(
      String status,
      ) {
    switch (status) {
      case 'Aprovado':
        return Icons.check_circle_outline;
      case 'Recusado':
        return Icons.cancel_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final status = _texto('status').isEmpty
        ? 'Pendente'
        : _texto('status');

    final subtotal = _numero('subtotal_itens') > 0
        ? _numero('subtotal_itens')
        : _itens.fold<double>(
      0,
          (total, item) => total + item.subtotal,
    );

    final desconto = _numero('desconto');

    final totalBanco = _numero('valor_total');

    final total = totalBanco > 0
        ? totalBanco
        : (subtotal - desconto).clamp(
      0,
      double.infinity,
    );

    final veiculo = [
      _texto('veiculo_marca'),
      _texto('veiculo_modelo'),
      _texto('veiculo_placa'),
    ].where(
          (item) => item.isNotEmpty,
    ).join(' • ');

    return PopScope(
      canPop: !_excluindo,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Detalhes do orçamento',
          ),
          actions: [
            IconButton(
              tooltip: 'Editar orçamento',
              onPressed:
              dados == null || _excluindo
                  ? null
                  : _editar,
              icon: const Icon(
                Icons.edit_outlined,
              ),
            ),
            PopupMenuButton<String>(
              enabled:
              dados != null && !_excluindo,
              onSelected: (opcao) {
                if (opcao == 'excluir') {
                  _excluir();
                }
              },
              itemBuilder: (_) {
                return const [
                  PopupMenuItem(
                    value: 'excluir',
                    child: ListTile(
                      contentPadding:
                      EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      title: Text(
                        'Excluir orçamento',
                      ),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: _carregando
            ? const Center(
          child: CircularProgressIndicator(),
        )
            : dados == null
            ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Orçamento não encontrado.',
              textAlign: TextAlign.center,
            ),
          ),
        )
            : RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding:
            const EdgeInsets.all(16),
            children: [
              _CabecalhoOrcamento(
                numero: widget.orcamentoId,
                status: status,
                corStatus:
                _corStatus(status),
                iconeStatus:
                _iconeStatus(status),
                total: _moeda.format(total),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Cliente e veículo',
                icone: Icons.person_outline,
                child: Column(
                  children: [
                    _LinhaInformacao(
                      titulo: 'Cliente',
                      valor:
                      _texto('cliente_nome')
                          .isEmpty
                          ? 'Não informado'
                          : _texto(
                        'cliente_nome',
                      ),
                      icone:
                      Icons.person_outline,
                    ),
                    const Divider(height: 24),
                    _LinhaInformacao(
                      titulo: 'Telefone',
                      valor: _texto(
                        'cliente_telefone',
                      ).isEmpty
                          ? 'Não informado'
                          : _texto(
                        'cliente_telefone',
                      ),
                      icone:
                      Icons.phone_outlined,
                    ),
                    const Divider(height: 24),
                    _LinhaInformacao(
                      titulo: 'Veículo',
                      valor: veiculo.isEmpty
                          ? 'Não vinculado'
                          : veiculo,
                      icone: Icons
                          .directions_car_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Serviços',
                icone: Icons
                    .design_services_outlined,
                child: _itens.isEmpty
                    ? const Padding(
                  padding:
                  EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                  child: Text(
                    'Nenhum serviço encontrado.',
                    textAlign:
                    TextAlign.center,
                  ),
                )
                    : Column(
                  children: List.generate(
                    _itens.length,
                        (indice) {
                      final item =
                      _itens[indice];

                      return Padding(
                        padding:
                        EdgeInsets.only(
                          bottom: indice ==
                              _itens.length -
                                  1
                              ? 0
                              : 12,
                        ),
                        child:
                        _CardServico(
                          numero:
                          indice + 1,
                          item: item,
                          quantidade:
                          _formatarQuantidade(
                            item.quantidade,
                          ),
                          valorUnitario:
                          _moeda.format(
                            item.valorUnitario,
                          ),
                          subtotal:
                          _moeda.format(
                            item.subtotal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Resumo financeiro',
                icone:
                Icons.payments_outlined,
                child: Column(
                  children: [
                    _LinhaValor(
                      titulo: 'Subtotal',
                      valor:
                      _moeda.format(subtotal),
                    ),
                    const SizedBox(height: 10),
                    _LinhaValor(
                      titulo: 'Desconto',
                      valor:
                      _moeda.format(desconto),
                    ),
                    const Divider(height: 26),
                    _LinhaValor(
                      titulo: 'Total',
                      valor:
                      _moeda.format(total),
                      destaque: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Informações',
                icone:
                Icons.info_outline,
                child: Column(
                  children: [
                    _LinhaInformacao(
                      titulo: 'Emissão',
                      valor: _dataTexto(
                        'data_emissao',
                      ),
                      icone: Icons
                          .calendar_today_outlined,
                    ),
                    const Divider(height: 24),
                    _LinhaInformacao(
                      titulo: 'Validade',
                      valor: _dataTexto(
                        'validade',
                      ),
                      icone: Icons
                          .event_available_outlined,
                    ),
                    if (_texto('observacoes')
                        .isNotEmpty) ...[
                      const Divider(height: 24),
                      _TextoLongo(
                        titulo: 'Observações',
                        valor:
                        _texto('observacoes'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Situação do orçamento',
                icone: Icons
                    .assignment_turned_in_outlined,
                child:
                DropdownButtonFormField<
                    String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Alterar status',
                    prefixIcon: Icon(
                      Icons
                          .assignment_turned_in_outlined,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Pendente',
                      child: Text(
                        'Pendente',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Aprovado',
                      child: Text(
                        'Aprovado',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Recusado',
                      child: Text(
                        'Recusado',
                      ),
                    ),
                  ],
                  onChanged:
                  _alterandoStatus
                      ? null
                      : (novoStatus) {
                    if (novoStatus ==
                        null ||
                        novoStatus ==
                            status) {
                      return;
                    }

                    _alterarStatus(
                      novoStatus,
                    );
                  },
                ),
              ),
              if (status == 'Aprovado') ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _verificandoOrdem ||
                          _abrindoOrdem ||
                          _existeOrdemServico
                      ? null
                      : _gerarOrdemServico,
                  icon: _abrindoOrdem || _verificandoOrdem
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _existeOrdemServico
                              ? Icons.check_circle_outline
                              : Icons.assignment_add,
                        ),
                  label: Text(
                    _verificandoOrdem
                        ? 'Verificando Ordem de Serviço...'
                        : _abrindoOrdem
                            ? 'Abrindo...'
                            : _existeOrdemServico
                                ? 'Ordem de Serviço já criada'
                                : 'Gerar Ordem de Serviço',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _gerandoPdf
                    ? null
                    : () {
                  _pdf(
                    recibo: false,
                    compartilhar:
                    false,
                  );
                },
                icon: _gerandoPdf
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(
                  Icons
                      .picture_as_pdf_outlined,
                ),
                label: Text(
                  _gerandoPdf
                      ? 'Gerando PDF...'
                      : 'Visualizar orçamento em PDF',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _gerandoPdf
                    ? null
                    : () {
                  _pdf(
                    recibo: false,
                    compartilhar:
                    true,
                  );
                },
                icon: const Icon(
                  Icons.share_outlined,
                ),
                label: const Text(
                  'Compartilhar orçamento',
                ),
              ),
              if (status == 'Aprovado') ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _gerandoPdf
                      ? null
                      : () {
                    _pdf(
                      recibo: true,
                      compartilhar:
                      true,
                    );
                  },
                  icon: const Icon(
                    Icons
                        .receipt_long_outlined,
                  ),
                  label: const Text(
                    'Gerar e compartilhar recibo',
                  ),
                ),
              ],
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _CabecalhoOrcamento
    extends StatelessWidget {
  const _CabecalhoOrcamento({
    required this.numero,
    required this.status,
    required this.corStatus,
    required this.iconeStatus,
    required this.total,
  });

  final int numero;
  final String status;
  final Color corStatus;
  final IconData iconeStatus;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(
                  0xFFD6A84B,
                ).withValues(
                  alpha: 0.14,
                ),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 34,
                color: Color(0xFFD6A84B),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Orçamento #$numero',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              total,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(
                color:
                const Color(0xFFD6A84B),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                borderRadius:
                BorderRadius.circular(30),
                color: corStatus.withValues(
                  alpha: 0.14,
                ),
                border: Border.all(
                  color: corStatus,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconeStatus,
                    size: 18,
                    color: corStatus,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    status,
                    style: TextStyle(
                      color: corStatus,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.icone,
    required this.child,
  });

  final String titulo;
  final IconData icone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icone,
                  size: 21,
                  color:
                  const Color(0xFFD6A84B),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _CardServico extends StatelessWidget {
  const _CardServico({
    required this.numero,
    required this.item,
    required this.quantidade,
    required this.valorUnitario,
    required this.subtotal,
  });

  final int numero;
  final ItemOrcamento item;
  final String quantidade;
  final String valorUnitario;
  final String subtotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius:
                  BorderRadius.circular(9),
                  color: const Color(
                    0xFFD6A84B,
                  ).withValues(
                    alpha: 0.15,
                  ),
                ),
                child: Text(
                  numero.toString(),
                  style: const TextStyle(
                    color:
                    Color(0xFFD6A84B),
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.servico,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                    if (item.descricao
                        .trim()
                        .isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.descricao,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InformacaoServico(
                titulo: 'Quantidade',
                valor: quantidade,
              ),
              _InformacaoServico(
                titulo: 'Valor unitário',
                valor: valorUnitario,
              ),
              _InformacaoServico(
                titulo: 'Subtotal',
                valor: subtotal,
                destaque: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InformacaoServico
    extends StatelessWidget {
  const _InformacaoServico({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style:
            Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              color: destaque
                  ? const Color(0xFFD6A84B)
                  : null,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaInformacao
    extends StatelessWidget {
  const _LinhaInformacao({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Icon(
          icone,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
              const SizedBox(height: 3),
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
    final estilo = destaque
        ? Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(
      fontWeight: FontWeight.bold,
      color: const Color(0xFFD6A84B),
    )
        : Theme.of(context)
        .textTheme
        .bodyLarge
        ?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: estilo,
          ),
        ),
        Text(
          valor,
          style: estilo,
        ),
      ],
    );
  }
}

class _TextoLongo extends StatelessWidget {
  const _TextoLongo({
    required this.titulo,
    required this.valor,
  });

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context)
              .textTheme
              .bodySmall,
        ),
        const SizedBox(height: 5),
        Text(
          valor,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}