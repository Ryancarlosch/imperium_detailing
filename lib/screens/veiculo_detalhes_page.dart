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
  final VeiculoRepository _repository =
      VeiculoRepository();

  Map<String, dynamic>? _dados;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final dados =
          await _repository.buscarVeiculoComClientePorId(
        widget.veiculoId,
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
        'Não foi possível carregar o veículo: $erro',
        erro: true,
      );
    }
  }

  Future<void> _editar() async {
    final dados = _dados;

    if (dados == null) return;

    final veiculo = Veiculo.fromMap(dados);

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoVeiculoPage(
          veiculo: veiculo,
        ),
      ),
    );

    if (alterou == true) {
      setState(() {
        _carregando = true;
      });

      await _carregar();

      if (!mounted) return;

      _mensagem(
        'Veículo atualizado com sucesso.',
      );
    }
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir veículo?'),
          content: const Text(
            'Esta ação não pode ser desfeita. '
            'Agendamentos e fotos vinculados também '
            'podem ser removidos.',
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

    try {
      await _repository.excluirVeiculo(
        widget.veiculoId,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) return;

      _mensagem(
        'Não foi possível excluir o veículo: $erro',
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
    String chave, {
    String vazio = 'Não informado',
  }) {
    final valor =
        (_dados?[chave] ?? '').toString().trim();

    return valor.isEmpty ? vazio : valor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do veículo'),
        actions: [
          IconButton(
            onPressed:
                _carregando ? null : _editar,
            tooltip: 'Editar',
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
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Excluir',
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
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
          : _dados == null
              ? const Center(
                  child: Text(
                    'Veículo não encontrado.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF1A1A1A),
                        borderRadius:
                            BorderRadius.circular(22),
                        border: Border.all(
                          color:
                              const Color(0xFFD6A84B)
                                  .withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFD6A84B,
                              ).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius:
                                  BorderRadius.circular(
                                24,
                              ),
                            ),
                            child: const Icon(
                              Icons
                                  .directions_car_outlined,
                              size: 46,
                              color:
                                  Color(0xFFD6A84B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${_texto('marca')} '
                            '${_texto('modelo')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _texto(
                              'placa',
                              vazio: 'Sem placa',
                            ),
                            style: const TextStyle(
                              color:
                                  Color(0xFFD6A84B),
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Informações',
                      filhos: [
                        _Linha(
                          icone:
                              Icons.person_outline,
                          titulo: 'Proprietário',
                          valor:
                              _texto('cliente_nome'),
                        ),
                        _Linha(
                          icone:
                              Icons.phone_outlined,
                          titulo: 'Telefone',
                          valor: _texto(
                            'cliente_telefone',
                          ),
                        ),
                        _Linha(
                          icone:
                              Icons.palette_outlined,
                          titulo: 'Cor',
                          valor: _texto('cor'),
                        ),
                        _Linha(
                          icone: Icons
                              .calendar_today_outlined,
                          titulo: 'Ano',
                          valor: _texto('ano'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Observações',
                      filhos: [
                        Text(
                          _texto(
                            'observacoes',
                            vazio:
                                'Nenhuma observação cadastrada.',
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
      ),
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
          const SizedBox(height: 14),
          ...filhos,
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.icone,
    required this.titulo,
    required this.valor,
  });

  final IconData icone;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icone,
            color: const Color(0xFFD6A84B),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
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
      ),
    );
  }
}
