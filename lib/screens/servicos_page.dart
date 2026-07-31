import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/servico_catalogo.dart';
import '../repositories/servico_repository.dart';
import 'novo_servico_page.dart';

class ServicosPage extends StatefulWidget {
  const ServicosPage({super.key});

  @override
  State<ServicosPage> createState() =>
      _ServicosPageState();
}

class _ServicosPageState extends State<ServicosPage> {
  final _repository = ServicoRepository();
  final _pesquisaController = TextEditingController();
  final _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String _pesquisa = '';
  List<ServicoCatalogo> _servicos = [];

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
    setState(() => _carregando = true);

    try {
      final lista = await _repository.listarServicos(
        pesquisa: _pesquisa,
      );

      if (!mounted) return;

      setState(() {
        _servicos = lista;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar serviços: $erro',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrir({
    ServicoCatalogo? servico,
  }) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoServicoPage(
          servico: servico,
        ),
      ),
    );

    if (salvou == true) {
      await _carregar();
    }
  }

  Future<void> _alterarAtivo(
    ServicoCatalogo servico,
  ) async {
    if (servico.id == null) return;

    await _repository.alterarAtivo(
      servico.id!,
      !servico.ativo,
    );

    await _carregar();
  }

  Future<void> _excluir(
    ServicoCatalogo servico,
  ) async {
    if (servico.id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir serviço'),
        content: Text(
          'Deseja excluir "${servico.nome}"?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await _repository.excluirServico(
      servico.id!,
    );

    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Catálogo de serviços',
        ),
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () => _abrir(),
        icon: const Icon(Icons.add),
        label: const Text('Novo serviço'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            100,
          ),
          children: [
            TextField(
              controller: _pesquisaController,
              onChanged: (valor) {
                setState(() => _pesquisa = valor);
              },
              onSubmitted: (_) => _carregar(),
              decoration: InputDecoration(
                hintText:
                    'Pesquisar serviço ou categoria',
                prefixIcon: const Icon(
                  Icons.search,
                ),
                suffixIcon: _pesquisa.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _pesquisaController.clear();
                          setState(() => _pesquisa = '');
                          _carregar();
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_servicos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 70),
                child: Column(
                  children: [
                    Icon(
                      Icons.design_services_outlined,
                      size: 72,
                      color: Colors.white30,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Nenhum serviço cadastrado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._servicos.map(
                (servico) => Card(
                  margin:
                      const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _abrir(
                      servico: servico,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(
                        Icons.cleaning_services_outlined,
                      ),
                    ),
                    title: Text(
                      servico.nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${servico.categoria.isEmpty ? "Sem categoria" : servico.categoria}'
                      ' • ${_moeda.format(servico.precoPadrao)}'
                      ' • ${servico.duracaoFormatada}',
                    ),
                    trailing:
                        PopupMenuButton<String>(
                      onSelected: (opcao) {
                        if (opcao == 'editar') {
                          _abrir(servico: servico);
                        } else if (opcao == 'ativo') {
                          _alterarAtivo(servico);
                        } else if (opcao ==
                            'excluir') {
                          _excluir(servico);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'editar',
                          child: Text('Editar'),
                        ),
                        PopupMenuItem(
                          value: 'ativo',
                          child: Text(
                            servico.ativo
                                ? 'Desativar'
                                : 'Ativar',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'excluir',
                          child: Text(
                            'Excluir',
                            style: TextStyle(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
