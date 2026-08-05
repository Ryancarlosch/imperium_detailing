import 'package:flutter/material.dart';

import '../repositories/veiculo_repository.dart';
import 'novo_veiculo_page.dart';
import 'veiculo_detalhes_page.dart';

class VeiculosPage extends StatefulWidget {
  const VeiculosPage({super.key});

  @override
  State<VeiculosPage> createState() => _VeiculosPageState();
}

class _VeiculosPageState extends State<VeiculosPage> {
  final VeiculoRepository _repository = VeiculoRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  List<Map<String, dynamic>> _veiculos = [];
  bool _carregando = true;
  String _pesquisa = '';

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
    try {
      final veiculos = await _repository.listarVeiculosComCliente();

      if (!mounted) return;

      setState(() {
        _veiculos = veiculos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      _mensagem('Não foi possível carregar os veículos: $erro', erro: true);
    }
  }

  List<Map<String, dynamic>> get _veiculosFiltrados {
    final termo = _pesquisa.trim().toLowerCase();

    if (termo.isEmpty) {
      return _veiculos;
    }

    return _veiculos.where((veiculo) {
      final texto = [
        veiculo['marca'],
        veiculo['modelo'],
        veiculo['placa'],
        veiculo['cor'],
        veiculo['ano'],
        veiculo['cliente_nome'],
      ].join(' ').toLowerCase();

      return texto.contains(termo);
    }).toList();
  }

  Future<void> _adicionar() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovoVeiculoPage()),
    );

    if (salvou == true) {
      setState(() {
        _carregando = true;
      });

      await _carregar();

      if (!mounted) return;

      _mensagem('Veículo cadastrado com sucesso.');
    }
  }

  Future<void> _abrirDetalhes(int veiculoId) async {
    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VeiculoDetalhesPage(veiculoId: veiculoId),
      ),
    );

    if (alterou == true) {
      _mensagem('Veículo excluído com sucesso.');
    }

    setState(() {
      _carregando = true;
    });

    await _carregar();
  }

  void _mensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _veiculosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Veículos'),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregar,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  TextField(
                    controller: _pesquisaController,
                    onChanged: (valor) {
                      setState(() {
                        _pesquisa = valor;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Pesquisar veículo, placa ou cliente',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _pesquisa.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _pesquisaController.clear();

                                setState(() {
                                  _pesquisa = '';
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Veículos cadastrados',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${filtrados.length}',
                        style: const TextStyle(
                          color: Color(0xFFD6A84B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filtrados.isEmpty)
                    _EstadoVazio(
                      pesquisando: _pesquisa.isNotEmpty,
                      aoAdicionar: _adicionar,
                    )
                  else
                    ...filtrados.map((veiculo) {
                      final id = veiculo['id'] as int;

                      final marca = (veiculo['marca'] ?? '').toString();

                      final modelo = (veiculo['modelo'] ?? '').toString();

                      final placa = (veiculo['placa'] ?? '').toString().trim();

                      final cliente = (veiculo['cliente_nome'] ?? '')
                          .toString();

                      final cor = (veiculo['cor'] ?? '').toString().trim();

                      final ano = (veiculo['ano'] ?? '').toString().trim();

                      final detalhes = [
                        if (placa.isNotEmpty) placa,
                        if (cor.isNotEmpty) cor,
                        if (ano.isNotEmpty) ano,
                      ].join(' • ');

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            onTap: () {
                              _abrirDetalhes(id);
                            },
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            leading: CircleAvatar(
                              radius: 25,
                              backgroundColor: const Color(
                                0xFFD6A84B,
                              ).withValues(alpha: 0.14),
                              child: const Icon(
                                Icons.directions_car_outlined,
                                color: Color(0xFFD6A84B),
                              ),
                            ),
                            title: Text(
                              '$marca $modelo',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 3),
                                Text(
                                  cliente,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (detalhes.isNotEmpty)
                                  Text(
                                    detalhes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionar,
        icon: const Icon(Icons.add),
        label: const Text('Novo veículo'),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.pesquisando, required this.aoAdicionar});

  final bool pesquisando;
  final VoidCallback aoAdicionar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(
        children: [
          Icon(
            pesquisando
                ? Icons.search_off_rounded
                : Icons.directions_car_outlined,
            size: 76,
            color: Colors.white30,
          ),
          const SizedBox(height: 16),
          Text(
            pesquisando
                ? 'Nenhum veículo encontrado'
                : 'Nenhum veículo cadastrado',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            pesquisando
                ? 'Tente pesquisar usando outro termo.'
                : 'Cadastre os veículos dos seus clientes.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          if (!pesquisando) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: aoAdicionar,
              icon: const Icon(Icons.add),
              label: const Text('Cadastrar veículo'),
            ),
          ],
        ],
      ),
    );
  }
}
