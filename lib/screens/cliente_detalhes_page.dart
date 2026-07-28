import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import 'veiculos_cliente_page.dart';

class ClienteDetalhesPage extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetalhesPage({
    super.key,
    required this.cliente,
  });

  @override
  State<ClienteDetalhesPage> createState() =>
      _ClienteDetalhesPageState();
}

class _ClienteDetalhesPageState
    extends State<ClienteDetalhesPage> {
  late Cliente cliente;

  final ClienteRepository _repository =
  ClienteRepository();

  @override
  void initState() {
    super.initState();
    cliente = widget.cliente;
  }

  Future<void> editarCliente() async {
    final nomeController =
    TextEditingController(text: cliente.nome);

    final telefoneController =
    TextEditingController(text: cliente.telefone);

    final emailController =
    TextEditingController(text: cliente.email);

    final enderecoController =
    TextEditingController(text: cliente.endereco);

    final observacoesController =
    TextEditingController(text: cliente.observacoes);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Editar cliente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeController,
                  textCapitalization:
                  TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    prefixIcon:
                    Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon:
                    Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType:
                  TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon:
                    Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: enderecoController,
                  textCapitalization:
                  TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Endereço',
                    prefixIcon:
                    Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacoesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    prefixIcon:
                    Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final nome =
                nomeController.text.trim();

                if (nome.isEmpty) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Informe o nome do cliente.',
                      ),
                    ),
                  );
                  return;
                }

                final clienteAtualizado = Cliente(
                  id: cliente.id,
                  nome: nome,
                  telefone:
                  telefoneController.text.trim(),
                  email: emailController.text.trim(),
                  endereco:
                  enderecoController.text.trim(),
                  observacoes:
                  observacoesController.text.trim(),
                );

                await _repository.atualizarCliente(
                  clienteAtualizado,
                );

                if (!dialogContext.mounted) return;

                Navigator.pop(dialogContext);

                setState(() {
                  cliente = clienteAtualizado;
                });

                ScaffoldMessenger.of(context)
                    .showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Cliente atualizado com sucesso.',
                    ),
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Widget criarInformacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    final texto = valor.trim().isEmpty
        ? 'Não informado'
        : valor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icone),
        title: Text(titulo),
        subtitle: Text(texto),
      ),
    );
  }

  void abrirVeiculos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return VeiculosClientePage(
            cliente: cliente,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do cliente'),
        actions: [
          IconButton(
            onPressed: editarCliente,
            tooltip: 'Editar cliente',
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 46,
            child: Icon(
              Icons.person,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            cliente.nome,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: abrirVeiculos,
            icon: const Icon(
              Icons.directions_car_outlined,
            ),
            label: const Text(
              'Ver veículos do cliente',
            ),
          ),
          const SizedBox(height: 24),
          criarInformacao(
            icone: Icons.phone_outlined,
            titulo: 'Telefone',
            valor: cliente.telefone,
          ),
          criarInformacao(
            icone: Icons.email_outlined,
            titulo: 'E-mail',
            valor: cliente.email,
          ),
          criarInformacao(
            icone: Icons.location_on_outlined,
            titulo: 'Endereço',
            valor: cliente.endereco,
          ),
          criarInformacao(
            icone: Icons.notes_outlined,
            titulo: 'Observações',
            valor: cliente.observacoes,
          ),
        ],
      ),
    );
  }
}