import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/veiculo.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/veiculo_repository.dart';

class ClienteOperacionalPage extends StatefulWidget {
  const ClienteOperacionalPage({super.key, required this.cliente});

  final Cliente cliente;

  @override
  State<ClienteOperacionalPage> createState() => _ClienteOperacionalPageState();
}

class _ClienteOperacionalPageState extends State<ClienteOperacionalPage> {
  final ClienteRepository _clientes = ClienteRepository();
  final VeiculoRepository _veiculos = VeiculoRepository();

  late Cliente _cliente;
  List<Veiculo> _lista = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _carregar();
  }

  Future<void> _carregar() async {
    final id = _cliente.id;
    if (id == null) return;

    if (mounted) setState(() => _carregando = true);

    try {
      final atual = await _clientes.buscarClientePorId(id);
      final veiculos = await _veiculos.listarVeiculosDoCliente(id);

      if (!mounted) return;

      setState(() {
        if (atual != null) _cliente = atual;
        _lista = veiculos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível atualizar o cliente: $erro', erro: true);
    }
  }

  Future<void> _editarCliente() async {
    final nome = TextEditingController(text: _cliente.nome);
    final telefone = TextEditingController(text: _cliente.telefone);
    final email = TextEditingController(text: _cliente.email);
    final endereco = TextEditingController(text: _cliente.endereco);
    final observacoes = TextEditingController(text: _cliente.observacoes);

    final atualizado = await showDialog<Cliente>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar cliente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: telefone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: endereco,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: observacoes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final nomeLimpo = nome.text.trim();
              if (nomeLimpo.isEmpty) return;

              Navigator.of(dialogContext).pop(
                _cliente.copyWith(
                  nome: nomeLimpo,
                  telefone: telefone.text.trim(),
                  email: email.text.trim(),
                  endereco: endereco.text.trim(),
                  observacoes: observacoes.text.trim(),
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    nome.dispose();
    telefone.dispose();
    email.dispose();
    endereco.dispose();
    observacoes.dispose();

    if (atualizado == null) return;

    try {
      await _clientes.atualizarCliente(atualizado);
      if (!mounted) return;
      setState(() => _cliente = atualizado);
      _mensagem('Cliente atualizado.');
    } catch (erro) {
      _mensagem('Não foi possível salvar: $erro', erro: true);
    }
  }

  Future<void> _editarVeiculo([Veiculo? atual]) async {
    final marca = TextEditingController(text: atual?.marca ?? '');
    final modelo = TextEditingController(text: atual?.modelo ?? '');
    final placa = TextEditingController(text: atual?.placa ?? '');
    final cor = TextEditingController(text: atual?.cor ?? '');
    final ano = TextEditingController(text: atual?.ano ?? '');
    final observacoes = TextEditingController(text: atual?.observacoes ?? '');

    final veiculo = await showDialog<Veiculo>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(atual == null ? 'Novo veículo' : 'Editar veículo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: marca,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelo,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: placa,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Placa'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cor,
                decoration: const InputDecoration(labelText: 'Cor'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ano,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ano'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: observacoes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (marca.text.trim().isEmpty || modelo.text.trim().isEmpty) {
                return;
              }

              Navigator.of(dialogContext).pop(
                Veiculo(
                  id: atual?.id,
                  clienteId: _cliente.id!,
                  marca: marca.text.trim(),
                  modelo: modelo.text.trim(),
                  placa: placa.text.trim().toUpperCase(),
                  cor: cor.text.trim(),
                  ano: ano.text.trim(),
                  observacoes: observacoes.text.trim(),
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    marca.dispose();
    modelo.dispose();
    placa.dispose();
    cor.dispose();
    ano.dispose();
    observacoes.dispose();

    if (veiculo == null) return;

    try {
      if (veiculo.id == null) {
        await _veiculos.inserirVeiculo(veiculo);
      } else {
        await _veiculos.atualizarVeiculo(veiculo);
      }
      await _carregar();
      if (mounted) _mensagem('Veículo salvo.');
    } catch (erro) {
      _mensagem('Não foi possível salvar o veículo: $erro', erro: true);
    }
  }

  Future<void> _excluirVeiculo(Veiculo veiculo) async {
    final id = veiculo.id;
    if (id == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover veículo'),
        content: Text('Remover ${veiculo.marca} ${veiculo.modelo}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await _veiculos.excluirVeiculo(id);
      await _carregar();
    } catch (erro) {
      _mensagem('Não foi possível remover: $erro', erro: true);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar cliente',
            onPressed: _editarCliente,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarVeiculo(),
        icon: const Icon(Icons.add),
        label: const Text('Veículo'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _cliente.nome,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_cliente.telefone.isNotEmpty)
                      Text('Telefone: ${_cliente.telefone}'),
                    if (_cliente.email.isNotEmpty)
                      Text('E-mail: ${_cliente.email}'),
                    if (_cliente.endereco.isNotEmpty)
                      Text('Endereço: ${_cliente.endereco}'),
                    if (_cliente.observacoes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_cliente.observacoes),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Visão operacional: histórico de ordens, valores, ticket '
                      'médio e dados financeiros não são exibidos no celular '
                      'do funcionário.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Veículos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_lista.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Nenhum veículo cadastrado.'),
                ),
              )
            else
              for (final veiculo in _lista)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.directions_car_outlined),
                    ),
                    title: Text('${veiculo.marca} ${veiculo.modelo}'),
                    subtitle: Text(
                      [
                        if (veiculo.placa.isNotEmpty) veiculo.placa,
                        if (veiculo.cor.isNotEmpty) veiculo.cor,
                        if (veiculo.ano.isNotEmpty) veiculo.ano,
                      ].join(' • '),
                    ),
                    onTap: () => _editarVeiculo(veiculo),
                    trailing: IconButton(
                      tooltip: 'Remover',
                      onPressed: () => _excluirVeiculo(veiculo),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
