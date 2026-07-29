import 'package:flutter/material.dart';

import '../models/veiculo.dart';
import '../repositories/veiculo_repository.dart';
import 'novo_veiculo_page.dart';

class VeiculoDetalhesPage extends StatefulWidget {
  const VeiculoDetalhesPage({
    super.key,
    required this.veiculoId,
  });

  final int veiculoId;

  @override
  State<VeiculoDetalhesPage> createState() =>
      _VeiculoDetalhesPageState();
}

class _VeiculoDetalhesPageState
    extends State<VeiculoDetalhesPage> {
  final VeiculoRepository _repository = VeiculoRepository();

  Map<String, dynamic>? _veiculo;
  bool _carregando = true;
  bool _executandoAcao = false;

  @override
  void initState() {
    super.initState();
    _carregarVeiculo();
  }

  Future<void> _carregarVeiculo() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final veiculo = await _repository
          .buscarVeiculoComClientePorId(widget.veiculoId);

      if (!mounted) return;

      setState(() {
        _veiculo = veiculo;
        _carregando = false;
      });

      if (veiculo == null) {
        _mostrarMensagem(
          'Veículo não encontrado.',
          erro: true,
        );
      }
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar o veículo: $erro',
        erro: true,
      );
    }
  }

  String _obterTexto(
    String campo, {
    String padrao = '',
  }) {
    final valor = _veiculo?[campo];

    if (valor == null) {
      return padrao;
    }

    final texto = valor.toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  int _obterInt(String campo) {
    final valor = _veiculo?[campo];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Veiculo? _montarVeiculoParaEdicao() {
    if (_veiculo == null) {
      return null;
    }

    final id = _obterInt('id');
    final clienteId = _obterInt('cliente_id');

    if (id <= 0 || clienteId <= 0) {
      return null;
    }

    return Veiculo(
      id: id,
      clienteId: clienteId,
      marca: _obterTexto('marca'),
      modelo: _obterTexto('modelo'),
      placa: _obterTexto('placa'),
      cor: _obterTexto('cor'),
      ano: _obterTexto('ano'),
      observacoes: _obterTexto('observacoes'),
    );
  }

  Future<void> _editarVeiculo() async {
    if (_executandoAcao) return;

    final veiculo = _montarVeiculoParaEdicao();

    if (veiculo == null) {
      _mostrarMensagem(
        'Não foi possível preparar o veículo para edição.',
        erro: true,
      );
      return;
    }

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoVeiculoPage(
          veiculo: veiculo,
        ),
      ),
    );

    if (alterou == true) {
      await _carregarVeiculo();

      if (!mounted) return;

      _mostrarMensagem(
        'Veículo atualizado com sucesso.',
      );
    }
  }

  Future<void> _excluirVeiculo() async {
    if (_executandoAcao) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir veículo'),
          content: const Text(
            'Deseja excluir este veículo permanentemente?\n\n'
            'Agendamentos, fotos e outros registros vinculados '
            'também podem ser afetados.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _repository.excluirVeiculo(widget.veiculoId);

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) return;

      _mostrarMensagem(
        'Não foi possível excluir o veículo: $erro',
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

  void _mostrarMensagem(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do veículo'),
        actions: [
          IconButton(
            onPressed: _carregando || _executandoAcao
                ? null
                : _editarVeiculo,
            tooltip: 'Editar veículo',
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            enabled: !_carregando && !_executandoAcao,
            onSelected: (valor) {
              if (valor == 'excluir') {
                _excluirVeiculo();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'excluir',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    SizedBox(width: 10),
                    Text('Excluir veículo'),
                  ],
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
          : _veiculo == null
              ? _VeiculoNaoEncontrado(
                  aoTentarNovamente: _carregarVeiculo,
                )
              : RefreshIndicator(
                  onRefresh: _carregarVeiculo,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      32,
                    ),
                    children: [
                      _CabecalhoVeiculo(
                        marca: _obterTexto(
                          'marca',
                          padrao: 'Marca não informada',
                        ),
                        modelo: _obterTexto(
                          'modelo',
                          padrao: 'Modelo não informado',
                        ),
                        placa: _obterTexto(
                          'placa',
                          padrao: 'Sem placa',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SecaoDetalhes(
                        titulo: 'Proprietário',
                        icone: Icons.person_outline,
                        itens: [
                          _ItemDetalhe(
                            rotulo: 'Nome',
                            valor: _obterTexto(
                              'cliente_nome',
                              padrao: 'Não informado',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'Telefone',
                            valor: _obterTexto(
                              'cliente_telefone',
                              padrao: 'Não informado',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'E-mail',
                            valor: _obterTexto(
                              'cliente_email',
                              padrao: 'Não informado',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SecaoDetalhes(
                        titulo: 'Dados do veículo',
                        icone: Icons.directions_car_outlined,
                        itens: [
                          _ItemDetalhe(
                            rotulo: 'Marca',
                            valor: _obterTexto(
                              'marca',
                              padrao: 'Não informada',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'Modelo',
                            valor: _obterTexto(
                              'modelo',
                              padrao: 'Não informado',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'Placa',
                            valor: _obterTexto(
                              'placa',
                              padrao: 'Não informada',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'Cor',
                            valor: _obterTexto(
                              'cor',
                              padrao: 'Não informada',
                            ),
                          ),
                          _ItemDetalhe(
                            rotulo: 'Ano',
                            valor: _obterTexto(
                              'ano',
                              padrao: 'Não informado',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SecaoDetalhes(
                        titulo: 'Observações',
                        icone: Icons.notes_outlined,
                        itens: [
                          _ItemDetalhe(
                            rotulo: 'Informações',
                            valor: _obterTexto(
                              'observacoes',
                              padrao: 'Nenhuma observação registrada.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _executandoAcao
                            ? null
                            : _editarVeiculo,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar veículo'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _executandoAcao
                            ? null
                            : _excluirVeiculo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                          ),
                        ),
                        icon: _executandoAcao
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline),
                        label: Text(
                          _executandoAcao
                              ? 'Excluindo...'
                              : 'Excluir veículo',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CabecalhoVeiculo extends StatelessWidget {
  const _CabecalhoVeiculo({
    required this.marca,
    required this.modelo,
    required this.placa,
  });

  final String marca;
  final String modelo;
  final String placa;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6A84B)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFD6A84B)
                  .withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 36,
              color: Color(0xFFD6A84B),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$marca $modelo'.trim(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    placa,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
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

class _SecaoDetalhes extends StatelessWidget {
  const _SecaoDetalhes({
    required this.titulo,
    required this.icone,
    required this.itens,
  });

  final String titulo;
  final IconData icone;
  final List<_ItemDetalhe> itens;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icone,
                  color: const Color(0xFFD6A84B),
                ),
                const SizedBox(width: 9),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...itens.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: item,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemDetalhe extends StatelessWidget {
  const _ItemDetalhe({
    required this.rotulo,
    required this.valor,
  });

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _VeiculoNaoEncontrado extends StatelessWidget {
  const _VeiculoNaoEncontrado({
    required this.aoTentarNovamente,
  });

  final VoidCallback aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.directions_car_filled_outlined,
              size: 76,
              color: Colors.white30,
            ),
            const SizedBox(height: 16),
            const Text(
              'Veículo não encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O veículo pode ter sido excluído ou não está mais disponível.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: aoTentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
