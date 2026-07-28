import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/orcamento.dart';
import '../repositories/orcamento_repository.dart';
import '../services/orcamento_pdf_service.dart';
import 'novo_orcamento_page.dart';

class OrcamentoDetalhesPage
    extends StatefulWidget {
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
  final _pdfService = OrcamentoPdfService();

  final _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final _data = DateFormat('dd/MM/yyyy');

  Map<String, dynamic>? _dados;
  bool _carregando = true;
  bool _gerandoPdf = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final dados = await _repository
          .buscarOrcamentoComDetalhes(
        widget.orcamentoId,
      );

      if (!mounted) return;

      setState(() {
        _dados = dados;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem(
        'Não foi possível carregar: $erro',
        erro: true,
      );
    }
  }

  Future<void> _editar() async {
    final orcamento =
        await _repository.buscarPorId(
      widget.orcamentoId,
    );

    if (orcamento == null || !mounted) return;

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoOrcamentoPage(
          orcamento: orcamento,
        ),
      ),
    );

    if (alterou == true) {
      setState(() {
        _carregando = true;
      });
      await _carregar();
    }
  }

  Future<void> _alterarStatus(
    String status,
  ) async {
    await _repository.atualizarStatus(
      widget.orcamentoId,
      status,
    );

    await _carregar();
  }

  Future<void> _pdf({
    required bool recibo,
    required bool compartilhar,
  }) async {
    final dados = _dados;

    if (dados == null || _gerandoPdf) return;

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
      if (!mounted) return;

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
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Excluir orçamento?',
          ),
          content: const Text(
            'Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _repository.excluirOrcamento(
      widget.orcamentoId,
    );

    if (!mounted) return;

    Navigator.pop(context, true);
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

  String _texto(String chave) {
    return (_dados?[chave] ?? '')
        .toString()
        .trim();
  }

  String _dataTexto(String chave) {
    final valor =
        DateTime.tryParse(_texto(chave));

    return valor == null
        ? 'Não informada'
        : _data.format(valor);
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Aprovado':
        return Colors.green;
      case 'Recusado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dados = _dados;
    final status = _texto('status');
    final valor =
        (dados?['valor'] as num?)?.toDouble() ?? 0;

    final veiculo = [
      _texto('veiculo_marca'),
      _texto('veiculo_modelo'),
      _texto('veiculo_placa'),
    ].where((item) => item.isNotEmpty).join(' • ');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Detalhes do orçamento',
        ),
        actions: [
          IconButton(
            onPressed:
                dados == null ? null : _editar,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (valor) {
              if (valor == 'excluir') {
                _excluir();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'excluir',
                child: Text(
                  'Excluir orçamento',
                ),
              ),
            ],
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : dados == null
              ? const Center(
                  child: Text(
                    'Orçamento não encontrado.',
                  ),
                )
              : ListView(
                  padding:
                      const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Icon(
                              Icons
                                  .description_outlined,
                              size: 58,
                              color:
                                  Color(0xFFD6A84B),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _texto('servico'),
                              textAlign:
                                  TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _moeda.format(valor),
                              style: const TextStyle(
                                color:
                                    Color(0xFFD6A84B),
                                fontSize: 27,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Chip(
                              label: Text(status),
                              backgroundColor:
                                  _corStatus(status)
                                      .withValues(
                                alpha: 0.16,
                              ),
                              side: BorderSide(
                                color:
                                    _corStatus(status),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Secao(
                      titulo: 'Cliente e veículo',
                      filhos: [
                        _Linha(
                          titulo: 'Cliente',
                          valor:
                              _texto('cliente_nome'),
                        ),
                        _Linha(
                          titulo: 'Telefone',
                          valor: _texto(
                            'cliente_telefone',
                          ).isEmpty
                              ? 'Não informado'
                              : _texto(
                                  'cliente_telefone',
                                ),
                        ),
                        _Linha(
                          titulo: 'Veículo',
                          valor: veiculo.isEmpty
                              ? 'Não vinculado'
                              : veiculo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Secao(
                      titulo: 'Informações',
                      filhos: [
                        _Linha(
                          titulo: 'Emissão',
                          valor:
                              _dataTexto('data_emissao'),
                        ),
                        _Linha(
                          titulo: 'Validade',
                          valor:
                              _dataTexto('validade'),
                        ),
                        if (_texto('descricao')
                            .isNotEmpty)
                          _TextoLongo(
                            titulo: 'Descrição',
                            valor:
                                _texto('descricao'),
                          ),
                        if (_texto('observacoes')
                            .isNotEmpty)
                          _TextoLongo(
                            titulo: 'Observações',
                            valor:
                                _texto('observacoes'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: status,
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
                          child: Text('Pendente'),
                        ),
                        DropdownMenuItem(
                          value: 'Aprovado',
                          child: Text('Aprovado'),
                        ),
                        DropdownMenuItem(
                          value: 'Recusado',
                          child: Text('Recusado'),
                        ),
                      ],
                      onChanged: (novoStatus) {
                        if (novoStatus != null) {
                          _alterarStatus(
                            novoStatus,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _gerandoPdf
                          ? null
                          : () {
                              _pdf(
                                recibo: false,
                                compartilhar: false,
                              );
                            },
                      icon: const Icon(
                        Icons.picture_as_pdf_outlined,
                      ),
                      label: const Text(
                        'Visualizar orçamento em PDF',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _gerandoPdf
                          ? null
                          : () {
                              _pdf(
                                recibo: false,
                                compartilhar: true,
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
                                  compartilhar: true,
                                );
                              },
                        icon: const Icon(
                          Icons.receipt_long_outlined,
                        ),
                        label: const Text(
                          'Gerar e compartilhar recibo',
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.filhos,
  });

  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...filhos,
          ],
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.titulo,
    required this.valor,
  });

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                color: Colors.white60,
              ),
            ),
          ),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 4),
          Text(valor),
        ],
      ),
    );
  }
}
