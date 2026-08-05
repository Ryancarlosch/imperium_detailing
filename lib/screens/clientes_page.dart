import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import 'cliente_detalhes_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final ClienteRepository _repository = ClienteRepository();

  List<Cliente> clientes = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarClientes();
  }

  Future<void> carregarClientes() async {
    try {
      final lista = await _repository.listarClientes();

      if (!mounted) return;

      setState(() {
        clientes = lista;
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar clientes: $erro')),
      );
    }
  }

  Future<void> abrirCadastro() async {
    final cliente = await showDialog<Cliente>(
      context: context,
      builder: (context) {
        return const _NovoClienteDialog();
      },
    );

    if (cliente == null || !mounted) {
      return;
    }

    try {
      await _repository.inserirCliente(cliente);

      if (!mounted) {
        return;
      }

      await carregarClientes();
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao cadastrar cliente: $erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : clientes.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 72, color: Colors.white38),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum cliente cadastrado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Toque no botão + para cadastrar',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: carregarClientes,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: clientes.length,
                separatorBuilder: (_, __) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (context, index) {
                  final cliente = clientes[index];

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(cliente.nome),
                      subtitle: Text(
                        cliente.telefone.isNotEmpty
                            ? cliente.telefone
                            : 'Telefone não informado',
                      ),
                      onTap: () async {
                        final resultado = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ClienteDetalhesPage(cliente: cliente),
                          ),
                        );

                        if (resultado == true) {
                          carregarClientes();
                        }
                      },
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: abrirCadastro,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NovoClienteDialog extends StatefulWidget {
  const _NovoClienteDialog();

  @override
  State<_NovoClienteDialog> createState() => _NovoClienteDialogState();
}

class _NovoClienteDialogState extends State<_NovoClienteDialog> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _enderecoController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _enderecoController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  void _salvar() {
    final nome = _nomeController.text.trim();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do cliente.')),
      );
      return;
    }

    final cliente = Cliente(
      nome: nome,
      telefone: _telefoneController.text.trim(),
      email: _emailController.text.trim(),
      endereco: _enderecoController.text.trim(),
      observacoes: _observacoesController.text.trim(),
    );

    Navigator.pop(context, cliente);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo cliente'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do cliente',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _enderecoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Endereço',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacoesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
