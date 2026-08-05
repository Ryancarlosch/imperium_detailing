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

  List<Cliente> _clientes = [];
  bool _carregando = true;
  bool _mostrarArquivados = false;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
  }

  Future<void> _carregarClientes({bool exibirCarregamento = true}) async {
    final filtroArquivadosConsultado = _mostrarArquivados;

    if (exibirCarregamento && mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final lista = filtroArquivadosConsultado
          ? await _repository.listarClientesArquivados()
          : await _repository.listarClientesAtivos();

      if (!mounted || filtroArquivadosConsultado != _mostrarArquivados) {
        return;
      }

      setState(() {
        _clientes = lista;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted || filtroArquivadosConsultado != _mostrarArquivados) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem('Erro ao carregar clientes: $erro', erro: true);
    }
  }

  void _alterarFiltro(bool mostrarArquivados) {
    if (_mostrarArquivados == mostrarArquivados) {
      return;
    }

    setState(() {
      _mostrarArquivados = mostrarArquivados;
      _clientes = [];
      _carregando = true;
    });

    _carregarClientes(exibirCarregamento: false);
  }

  Future<void> _abrirCadastro() async {
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

      await _carregarClientes();

      if (!mounted) {
        return;
      }

      _mostrarMensagem('Cliente cadastrado com sucesso.');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem('Erro ao cadastrar cliente: $erro', erro: true);
    }
  }

  Future<void> _abrirDetalhes(Cliente cliente) async {
    final resultado = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) {
          return ClienteDetalhesPage(cliente: cliente);
        },
      ),
    );

    if (!mounted || resultado == null) {
      return;
    }

    await _carregarClientes();

    if (!mounted) {
      return;
    }

    if (resultado == 'arquivado') {
      _mostrarMensagem('Cliente arquivado. Todo o histórico foi preservado.');
    } else if (resultado == 'reativado') {
      _mostrarMensagem('Cliente reativado com sucesso.');
    }
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  String _dataArquivamento(Cliente cliente) {
    final valor = cliente.arquivadoEm;

    if (valor == null || valor.trim().isEmpty) {
      return '';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return '';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString().padLeft(4, '0');

    return '$dia/$mes/$ano';
  }

  Widget _construirFiltro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.people_outline),
              label: Text('Ativos'),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.archive_outlined),
              label: Text('Arquivados'),
            ),
          ],
          selected: {_mostrarArquivados},
          onSelectionChanged: (selecao) {
            _alterarFiltro(selecao.first);
          },
        ),
      ),
    );
  }

  Widget _construirEstadoVazio() {
    final titulo = _mostrarArquivados
        ? 'Nenhum cliente arquivado'
        : 'Nenhum cliente cadastrado';

    final descricao = _mostrarArquivados
        ? 'Clientes arquivados aparecerão aqui.'
        : 'Toque no botão + para cadastrar.';

    return RefreshIndicator(
      onRefresh: _carregarClientes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          Icon(
            _mostrarArquivados
                ? Icons.inventory_2_outlined
                : Icons.people_outline,
            size: 72,
            color: Colors.white38,
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _construirLista() {
    return RefreshIndicator(
      onRefresh: _carregarClientes,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _clientes.length,
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final cliente = _clientes[index];
          final dataArquivamento = _dataArquivamento(cliente);

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  cliente.ativo ? Icons.person : Icons.archive_outlined,
                ),
              ),
              title: Text(cliente.nome),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cliente.telefone.isNotEmpty
                        ? cliente.telefone
                        : 'Telefone não informado',
                  ),
                  if (!cliente.ativo) ...[
                    const SizedBox(height: 3),
                    Text(
                      dataArquivamento.isEmpty
                          ? 'Cliente arquivado'
                          : 'Arquivado em $dataArquivamento',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              isThreeLine: !cliente.ativo,
              onTap: () {
                _abrirDetalhes(cliente);
              },
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: Column(
        children: [
          _construirFiltro(),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _clientes.isEmpty
                ? _construirEstadoVazio()
                : _construirLista(),
          ),
        ],
      ),
      floatingActionButton: _mostrarArquivados
          ? null
          : FloatingActionButton(
              onPressed: _abrirCadastro,
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cliente = Cliente(
      nome: _nomeController.text.trim(),
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomeController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do cliente',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (valor) {
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Informe o nome do cliente.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _enderecoController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
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
