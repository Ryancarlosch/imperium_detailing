import 'package:flutter/material.dart';

import '../models/fornecedor.dart';
import '../repositories/fornecedor_repository.dart';

class FornecedoresPage extends StatefulWidget {
  const FornecedoresPage({super.key});

  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage> {
  final FornecedorRepository _repository = FornecedorRepository();
  final TextEditingController _pesquisa = TextEditingController();

  bool _carregando = true;
  bool _mostrarInativos = false;
  String _termo = '';
  List<Fornecedor> _fornecedores = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _pesquisa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final dados = await _repository.listar(incluirInativos: _mostrarInativos);
      if (!mounted) return;
      setState(() {
        _fornecedores = dados;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  List<Fornecedor> get _filtrados {
    final termo = _termo.trim().toLowerCase();
    if (termo.isEmpty) return _fornecedores;
    return _fornecedores.where((item) {
      return item.nome.toLowerCase().contains(termo) ||
          item.documento.toLowerCase().contains(termo) ||
          item.categoria.toLowerCase().contains(termo);
    }).toList();
  }

  Future<void> _abrir({Fornecedor? fornecedor}) async {
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _FornecedorForm(repository: _repository, fornecedor: fornecedor),
    );
    if (resultado == true) await _carregar();
  }

  Future<void> _alternar(Fornecedor fornecedor) async {
    if (fornecedor.id == null) return;
    try {
      await _repository.alterarAtivo(fornecedor.id!, !fornecedor.ativo);
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fornecedores = _filtrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fornecedores'),
        actions: [
          IconButton(
            tooltip: _mostrarInativos ? 'Ocultar inativos' : 'Mostrar inativos',
            onPressed: () {
              setState(() => _mostrarInativos = !_mostrarInativos);
              _carregar();
            },
            icon: Icon(
              _mostrarInativos
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Fornecedor'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                TextField(
                  controller: _pesquisa,
                  onChanged: (valor) => setState(() => _termo = valor),
                  decoration: const InputDecoration(
                    hintText: 'Pesquisar nome, documento ou categoria',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                if (fornecedores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 50),
                    child: Text(
                      'Nenhum fornecedor encontrado.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...fornecedores.map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        enabled: item.ativo,
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(
                          item.nome,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          [
                            if (item.categoria.isNotEmpty) item.categoria,
                            if (item.telefone.isNotEmpty) item.telefone,
                            if (!item.ativo) 'Inativo',
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (valor) {
                            if (valor == 'editar') {
                              _abrir(fornecedor: item);
                            } else {
                              _alternar(item);
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
                                item.ativo ? 'Desativar' : 'Reativar',
                              ),
                            ),
                          ],
                        ),
                        onTap: item.ativo
                            ? () => _abrir(fornecedor: item)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FornecedorForm extends StatefulWidget {
  const _FornecedorForm({required this.repository, this.fornecedor});

  final FornecedorRepository repository;
  final Fornecedor? fornecedor;

  @override
  State<_FornecedorForm> createState() => _FornecedorFormState();
}

class _FornecedorFormState extends State<_FornecedorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _documento;
  late final TextEditingController _telefone;
  late final TextEditingController _email;
  late final TextEditingController _endereco;
  late final TextEditingController _cidade;
  late final TextEditingController _estado;
  late final TextEditingController _categoria;
  late final TextEditingController _observacoes;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final f = widget.fornecedor;
    _nome = TextEditingController(text: f?.nome ?? '');
    _documento = TextEditingController(text: f?.documento ?? '');
    _telefone = TextEditingController(text: f?.telefone ?? '');
    _email = TextEditingController(text: f?.email ?? '');
    _endereco = TextEditingController(text: f?.endereco ?? '');
    _cidade = TextEditingController(text: f?.cidade ?? '');
    _estado = TextEditingController(text: f?.estado ?? '');
    _categoria = TextEditingController(text: f?.categoria ?? '');
    _observacoes = TextEditingController(text: f?.observacoes ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _nome,
      _documento,
      _telefone,
      _email,
      _endereco,
      _cidade,
      _estado,
      _categoria,
      _observacoes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      final anterior = widget.fornecedor;
      final fornecedor = Fornecedor(
        id: anterior?.id,
        nome: _nome.text.trim(),
        documento: _documento.text.trim(),
        telefone: _telefone.text.trim(),
        email: _email.text.trim(),
        endereco: _endereco.text.trim(),
        cidade: _cidade.text.trim(),
        estado: _estado.text.trim().toUpperCase(),
        categoria: _categoria.text.trim(),
        observacoes: _observacoes.text.trim(),
        ativo: anterior?.ativo ?? true,
        criadoEm: anterior?.criadoEm ?? agora,
        atualizadoEm: agora,
      );

      if (anterior == null) {
        await widget.repository.inserir(fornecedor);
      } else {
        await widget.repository.atualizar(fornecedor);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fornecedor == null
                    ? 'Novo fornecedor'
                    : 'Editar fornecedor',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (valor) =>
                    (valor?.trim().length ?? 0) < 2 ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _documento,
                decoration: const InputDecoration(labelText: 'CNPJ / CPF'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _categoria,
                decoration: const InputDecoration(labelText: 'Categoria'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _telefone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _endereco,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cidade,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _estado,
                      maxLength: 2,
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _observacoes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
