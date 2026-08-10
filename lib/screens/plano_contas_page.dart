import 'package:flutter/material.dart';

import '../models/plano_conta_financeiro.dart';
import '../repositories/plano_contas_repository.dart';

class PlanoContasPage extends StatefulWidget {
  const PlanoContasPage({super.key});

  @override
  State<PlanoContasPage> createState() => _PlanoContasPageState();
}

class _PlanoContasPageState extends State<PlanoContasPage> {
  final PlanoContasRepository _repository = PlanoContasRepository();

  bool _carregando = true;
  bool _mostrarInativas = false;
  List<PlanoContaFinanceiro> _contas = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final contas = await _repository.listar(
        incluirInativos: _mostrarInativas,
      );

      if (!mounted) return;
      setState(() {
        _contas = contas;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar o plano de contas.\n$erro',
          erro: true);
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

  List<PlanoContaFinanceiro> get _folhas {
    // Subcategorias inativas não impedem que a categoria geral ativa
    // seja usada no dia a dia (ex.: Serviços).
    final idsPais = _contas
        .where((e) => e.ativo)
        .map((e) => e.parentId)
        .whereType<int>()
        .toSet();

    return _contas.where((conta) {
      if (conta.id == null) return false;
      if (idsPais.contains(conta.id)) return false;
      return true;
    }).toList();
  }

  Map<String, List<PlanoContaFinanceiro>> get _porSecao {
    final mapa = <String, List<PlanoContaFinanceiro>>{
      'Receitas e deduções': [],
      'Custos das vendas': [],
      'Despesas da empresa': [],
      'Não afeta o resultado': [],
    };

    for (final conta in _folhas) {
      final titulo = _repository.tituloSecao(conta);
      mapa.putIfAbsent(titulo, () => <PlanoContaFinanceiro>[]).add(conta);
    }

    return mapa;
  }

  Future<void> _novaCategoria() async {
    final resultado = await showModalBottomSheet<_NovaCategoriaData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _NovaCategoriaSheet(),
    );

    if (resultado == null) return;

    try {
      await _repository.criarCategoriaSimplificada(
        nome: resultado.nome,
        secao: resultado.secao,
      );
      await _carregar();
      _mensagem('Categoria criada.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _editar(PlanoContaFinanceiro conta) async {
    final nomeAtualExibido = _repository.nomeExibicao(conta);
    final controller = TextEditingController(text: nomeAtualExibido);

    final novoNome = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Editar categoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome exibido',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _repository.ehProtegida(conta)
                    ? 'Esta categoria participa de automações do Imperium. '
                        'Você pode alterar o nome exibido, mas a função interna '
                        'continua protegida.'
                    : 'O nome pode ser alterado sem modificar o histórico dos lançamentos.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (novoNome == null || novoNome == nomeAtualExibido) return;

    try {
      await _repository.renomear(id: conta.id!, nome: novoNome);
      await _carregar();
      _mensagem('Categoria atualizada.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _alternarAtivo(PlanoContaFinanceiro conta) async {
    final novoAtivo = !conta.ativo;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(novoAtivo ? 'Ativar categoria' : 'Desativar categoria'),
        content: Text(
          novoAtivo
              ? 'Deseja voltar a exibir "${_repository.nomeExibicao(conta)}" nos lançamentos?'
              : 'Deseja ocultar "${_repository.nomeExibicao(conta)}" dos novos lançamentos?\n\n'
                  'O histórico existente não será apagado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(novoAtivo ? 'Ativar' : 'Desativar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _repository.alterarAtivo(id: conta.id!, ativo: novoAtivo);
      await _carregar();
      _mensagem(novoAtivo ? 'Categoria ativada.' : 'Categoria desativada.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Widget _cabecalho() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'O Imperium já vem pronto para usar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha a categoria pelo nome que faz sentido no dia a dia. '
              'Códigos e regras contábeis ficam nos bastidores. '
              'Categorias marcadas como Automático são preenchidas pelo próprio sistema.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _novaCategoria,
                    icon: const Icon(Icons.add),
                    label: const Text('Nova categoria'),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('Mostrar inativas'),
                  selected: _mostrarInativas,
                  onSelected: (valor) {
                    setState(() => _mostrarInativas = valor);
                    _carregar();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secao(String titulo, List<PlanoContaFinanceiro> contas) {
    if (contas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ...contas.map(_cardConta),
      ],
    );
  }

  Widget _cardConta(PlanoContaFinanceiro conta) {
    final automatica = _repository.ehAutomatica(conta);
    final protegida = _repository.ehProtegida(conta);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
        leading: CircleAvatar(
          child: Icon(
            conta.grupoDre == 'Não DRE'
                ? Icons.swap_horiz_rounded
                : conta.tipo == 'Entrada'
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _repository.nomeExibicao(conta),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: conta.ativo ? null : Colors.grey,
                ),
              ),
            ),
            if (automatica)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text('Automático'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _repository.descricaoUso(conta),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (valor) {
            if (valor == 'editar') {
              _editar(conta);
            } else if (valor == 'ativo') {
              _alternarAtivo(conta);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'editar',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.edit_outlined),
                title: Text('Editar nome'),
              ),
            ),
            if (!protegida)
              PopupMenuItem(
                value: 'ativo',
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    conta.ativo
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(conta.ativo ? 'Desativar' : 'Ativar'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secoes = _porSecao;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias financeiras'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaCategoria,
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  _cabecalho(),
                  for (final entrada in secoes.entries)
                    _secao(entrada.key, entrada.value),
                ],
              ),
      ),
    );
  }
}

class _NovaCategoriaData {
  const _NovaCategoriaData({
    required this.nome,
    required this.secao,
  });

  final String nome;
  final PlanoContaSecao secao;
}

class _NovaCategoriaSheet extends StatefulWidget {
  const _NovaCategoriaSheet();

  @override
  State<_NovaCategoriaSheet> createState() => _NovaCategoriaSheetState();
}

class _NovaCategoriaSheetState extends State<_NovaCategoriaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  PlanoContaSecao _secao = PlanoContaSecao.despesaEmpresa;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _NovaCategoriaData(nome: _nome.text.trim(), secao: _secao),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        8,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nova categoria',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'O Imperium configura automaticamente a classificação interna.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nome,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Uniformes',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                if ((valor?.trim().length ?? 0) < 3) {
                  return 'Informe um nome com pelo menos 3 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PlanoContaSecao>(
              initialValue: _secao,
              decoration: const InputDecoration(
                labelText: 'Onde entra?',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: PlanoContaSecao.receita,
                  child: Text('Receitas'),
                ),
                DropdownMenuItem(
                  value: PlanoContaSecao.custoVenda,
                  child: Text('Custos das vendas'),
                ),
                DropdownMenuItem(
                  value: PlanoContaSecao.despesaEmpresa,
                  child: Text('Despesas da empresa'),
                ),
                DropdownMenuItem(
                  value: PlanoContaSecao.naoAfetaResultado,
                  child: Text('Não afeta o resultado'),
                ),
              ],
              onChanged: (valor) {
                if (valor != null) {
                  setState(() => _secao = valor);
                }
              },
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: const Text('Salvar categoria'),
            ),
          ],
        ),
      ),
    );
  }
}
