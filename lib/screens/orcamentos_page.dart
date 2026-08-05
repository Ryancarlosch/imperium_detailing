import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/orcamento_repository.dart';
import 'novo_orcamento_page.dart';
import 'orcamento_detalhes_page.dart';

class OrcamentosPage extends StatefulWidget {
  const OrcamentosPage({super.key});

  @override
  State<OrcamentosPage> createState() => _OrcamentosPageState();
}

class _OrcamentosPageState extends State<OrcamentosPage> {
  final _repository = OrcamentoRepository();
  final _pesquisaController = TextEditingController();

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Map<String, dynamic>> _orcamentos = [];
  bool _carregando = true;
  String _pesquisa = '';
  String _status = 'Todos';

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
      final orcamentos = await _repository.listarOrcamentosComDetalhes();

      if (!mounted) return;

      setState(() {
        _orcamentos = orcamentos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar os orçamentos: $erro'),
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _orcamentosFiltrados {
    final termo = _pesquisa.trim().toLowerCase();

    return _orcamentos.where((orcamento) {
      final correspondeTexto =
          termo.isEmpty ||
          [
            orcamento['cliente_nome'],
            orcamento['servico'],
            orcamento['veiculo_marca'],
            orcamento['veiculo_modelo'],
            orcamento['veiculo_placa'],
          ].join(' ').toLowerCase().contains(termo);

      final correspondeStatus =
          _status == 'Todos' || orcamento['status'] == _status;

      return correspondeTexto && correspondeStatus;
    }).toList();
  }

  Future<void> _novo() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovoOrcamentoPage()),
    );

    if (salvou == true) {
      setState(() {
        _carregando = true;
      });
      await _carregar();
    }
  }

  Future<void> _abrir(int id) async {
    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => OrcamentoDetalhesPage(orcamentoId: id)),
    );

    if (alterou == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orçamento excluído com sucesso.')),
      );
    }

    setState(() {
      _carregando = true;
    });
    await _carregar();
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
    final filtrados = _orcamentosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamentos'),
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregar,
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
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar cliente, serviço ou veículo',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por status',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Todos', child: Text('Todos')),
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
                    onChanged: (valor) {
                      if (valor == null) return;

                      setState(() {
                        _status = valor;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Orçamentos cadastrados',
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 72,
                            color: Colors.white30,
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Nenhum orçamento encontrado',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtrados.map((orcamento) {
                      final id = orcamento['id'] as int;
                      final status = (orcamento['status'] ?? 'Pendente')
                          .toString();
                      final valor =
                          (orcamento['valor'] as num?)?.toDouble() ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            onTap: () => _abrir(id),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: _corStatus(
                                status,
                              ).withValues(alpha: 0.15),
                              child: Icon(
                                Icons.description_outlined,
                                color: _corStatus(status),
                              ),
                            ),
                            title: Text(
                              (orcamento['servico'] ?? '').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${orcamento['cliente_nome']}\n$status',
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _moeda.format(valor),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD6A84B),
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 19),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novo,
        icon: const Icon(Icons.add),
        label: const Text('Novo orçamento'),
      ),
    );
  }
}
