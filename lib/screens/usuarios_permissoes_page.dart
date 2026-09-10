import 'package:flutter/material.dart';

import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/usuario_repository.dart';
import '../services/funcionario_acesso_service.dart';

class UsuariosPermissoesPage extends StatefulWidget {
  const UsuariosPermissoesPage({super.key});

  @override
  State<UsuariosPermissoesPage> createState() => _UsuariosPermissoesPageState();
}

class _UsuariosPermissoesPageState extends State<UsuariosPermissoesPage> {
  final UsuarioRepository _repository = UsuarioRepository();
  final CustosRepository _custosRepository = CustosRepository();

  bool _carregando = true;
  List<Map<String, dynamic>> _usuarios = const [];
  List<ColaboradorCusto> _colaboradores = const [];

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
      await _repository.garantirEstrutura();

      final resultados = await Future.wait<dynamic>([
        _repository.listarUsuarios(),
        _custosRepository.listarColaboradores(),
      ]);

      if (!mounted) return;

      setState(() {
        _usuarios = List<Map<String, dynamic>>.from(
          resultados[0] as List<dynamic>,
        );
        _colaboradores = resultados[1] as List<ColaboradorCusto>;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _editarUsuario([Map<String, dynamic>? usuario]) async {
    final salvou = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UsuarioFormSheet(
        repository: _repository,
        colaboradores: _colaboradores,
        usuario: usuario,
      ),
    );

    if (salvou == true) {
      await _carregar();
    }
  }

  Future<void> _configurarPin(Map<String, dynamic> usuario) async {
    final id = _int(usuario['id']);
    if (id == null) return;

    final pin = TextEditingController();
    final confirmar = TextEditingController();

    final salvou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Configurar PIN • ${usuario['nome'] ?? ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Novo PIN',
                helperText: 'Use de 4 a 8 números.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmar,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Confirmar PIN',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (pin.text.trim() != confirmar.text.trim()) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Os PINs informados são diferentes.'),
                  ),
                );
                return;
              }

              try {
                await _repository.definirPin(usuarioId: id, pin: pin.text);

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (erro) {
                if (!dialogContext.mounted) return;

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('$erro'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: const Text('Salvar PIN'),
          ),
        ],
      ),
    );

    pin.dispose();
    confirmar.dispose();

    if (salvou == true) {
      await _carregar();
      _mensagem('PIN atualizado.');
    }
  }

  Future<void> _liberarBloqueio(Map<String, dynamic> usuario) async {
    final id = _int(usuario['id']);
    if (id == null) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Liberar tentativas de PIN?'),
        content: Text(
          'O bloqueio temporário de @${usuario['login'] ?? ''} será zerado. '
          'A liberação ficará registrada na auditoria de segurança.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Liberar'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    try {
      await _repository.liberarBloqueioUsuario(id);
      _mensagem('Tentativas de PIN liberadas.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _abrirAuditoria() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _HistoricoSegurancaPage(repository: _repository),
      ),
    );
  }

  Future<void> _abrirAcessos() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _HistoricoAcessosPage(repository: _repository),
      ),
    );
  }

  Future<void> _permissoes(Map<String, dynamic> usuario) async {
    final id = _int(usuario['id']);
    if (id == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PermissoesUsuarioPage(
          repository: _repository,
          usuarioId: id,
          nome: (usuario['nome'] ?? '').toString(),
          perfil: (usuario['perfil'] ?? '').toString(),
        ),
      ),
    );

    await _carregar();
  }

  int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
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
        title: const Text('Usuários e permissões'),
        actions: [
          IconButton(
            tooltip: 'Auditoria de segurança',
            onPressed: _carregando ? null : _abrirAuditoria,
            icon: const Icon(Icons.security_outlined),
          ),
          IconButton(
            tooltip: 'Histórico de acessos',
            onPressed: _carregando ? null : _abrirAcessos,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _carregando ? null : () => _editarUsuario(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Usuário'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(13),
                      child: Text(
                        'Cadastre os usuários, configure o PIN '
                        'e defina quais módulos cada pessoa poderá '
                        'acessar. O PIN é armazenado somente como '
                        'hash com salt; o número original não fica salvo.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._usuarios.map((usuario) {
                    final perfil = (usuario['perfil'] ?? '').toString();
                    final ativo = _int(usuario['ativo']) == 1;
                    final colaborador = (usuario['colaborador_nome'] ?? '')
                        .toString();
                    final temPin =
                        (usuario['pin_hash'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty &&
                        (usuario['pin_salt'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            perfil == UsuarioRepository.perfilAdministrador
                                ? Icons.admin_panel_settings_outlined
                                : Icons.badge_outlined,
                          ),
                        ),
                        title: Text(
                          (usuario['nome'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          [
                            '@${usuario['login'] ?? ''}',
                            perfil,
                            if (colaborador.isNotEmpty)
                              'Funcionário: $colaborador',
                            ativo ? 'Ativo' : 'Inativo',
                            temPin ? 'PIN configurado' : 'Sem PIN',
                          ].join(' • '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (valor) {
                            if (valor == 'editar') {
                              _editarUsuario(usuario);
                            } else if (valor == 'pin') {
                              _configurarPin(usuario);
                            } else if (valor == 'permissoes') {
                              _permissoes(usuario);
                            } else if (valor == 'liberar_bloqueio') {
                              _liberarBloqueio(usuario);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'editar',
                              child: Text('Editar usuário'),
                            ),
                            PopupMenuItem(
                              value: 'pin',
                              child: Text('Configurar PIN'),
                            ),
                            PopupMenuItem(
                              value: 'permissoes',
                              child: Text('Permissões'),
                            ),
                            PopupMenuItem(
                              value: 'liberar_bloqueio',
                              child: Text('Liberar tentativas de PIN'),
                            ),
                          ],
                        ),
                        onTap: () => _permissoes(usuario),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

class _UsuarioFormSheet extends StatefulWidget {
  const _UsuarioFormSheet({
    required this.repository,
    required this.colaboradores,
    this.usuario,
  });

  final UsuarioRepository repository;
  final List<ColaboradorCusto> colaboradores;
  final Map<String, dynamic>? usuario;

  @override
  State<_UsuarioFormSheet> createState() => _UsuarioFormSheetState();
}

class _UsuarioFormSheetState extends State<_UsuarioFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _login = TextEditingController();

  String _perfil = UsuarioRepository.perfilFuncionario;
  int? _colaboradorId;
  bool _ativo = true;
  bool _salvando = false;

  bool get _editando => widget.usuario != null;

  @override
  void initState() {
    super.initState();

    final usuario = widget.usuario;
    if (usuario != null) {
      _nome.text = (usuario['nome'] ?? '').toString();
      _login.text = (usuario['login'] ?? '').toString();
      _perfil = (usuario['perfil'] ?? UsuarioRepository.perfilFuncionario)
          .toString();
      _colaboradorId = _int(usuario['colaborador_id']);
      _ativo = _int(usuario['ativo']) == 1;
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    _login.dispose();
    super.dispose();
  }

  int? _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _salvando = true);

    try {
      await widget.repository.salvarUsuario(
        id: _int(widget.usuario?['id']),
        nome: _nome.text,
        login: _login.text,
        perfil: _perfil,
        colaboradorId: _perfil == UsuarioRepository.perfilFuncionario
            ? _colaboradorId
            : null,
        ativo: _ativo,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, teclado + 18),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editando ? 'Editar usuário' : 'Novo usuário',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) =>
                    (valor ?? '').trim().length < 2 ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _login,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Login *',
                  prefixText: '@',
                  helperText: 'Ex.: joao, maria.silva, admin',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) =>
                    (valor ?? '').trim().length < 3 ? 'Informe um login' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _perfil,
                decoration: const InputDecoration(
                  labelText: 'Perfil',
                  border: OutlineInputBorder(),
                ),
                items: UsuarioRepository.perfis
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor != null) {
                          setState(() {
                            _perfil = valor;
                            if (_perfil ==
                                UsuarioRepository.perfilAdministrador) {
                              _colaboradorId = null;
                            }
                          });
                        }
                      },
              ),
              if (_perfil == UsuarioRepository.perfilFuncionario) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _colaboradorId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vincular ao funcionário *',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.colaboradores
                      .where((item) => item.id != null)
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.id!,
                          child: Text(
                            item.nome,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _salvando
                      ? null
                      : (valor) => setState(() => _colaboradorId = valor),
                  validator: (valor) =>
                      _perfil == UsuarioRepository.perfilFuncionario &&
                          valor == null
                      ? 'Selecione o funcionário'
                      : null,
                ),
              ],
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usuário ativo'),
                subtitle: const Text(
                  'Usuários inativos não poderão entrar '
                  'quando o login for ativado.',
                ),
                value: _ativo,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _ativo = valor),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_salvando ? 'Salvando...' : 'Salvar usuário'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissoesUsuarioPage extends StatefulWidget {
  const _PermissoesUsuarioPage({
    required this.repository,
    required this.usuarioId,
    required this.nome,
    required this.perfil,
  });

  final UsuarioRepository repository;
  final int usuarioId;
  final String nome;
  final String perfil;

  @override
  State<_PermissoesUsuarioPage> createState() => _PermissoesUsuarioPageState();
}

class _PermissoesUsuarioPageState extends State<_PermissoesUsuarioPage> {
  bool _carregando = true;
  Map<String, bool> _permissoes = const {};

  bool get _administrador =>
      widget.perfil == UsuarioRepository.perfilAdministrador;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final permissoes = await widget.repository.obterPermissoes(
      widget.usuarioId,
    );

    if (!mounted) return;

    setState(() {
      _permissoes = permissoes;
      _carregando = false;
    });
  }

  Future<void> _alterar(String modulo, bool permitido) async {
    try {
      await widget.repository.salvarPermissao(
        usuarioId: widget.usuarioId,
        modulo: modulo,
        permitido: permitido,
      );

      // modulo1-sync-permissao
      try {
        await FuncionarioAcessoService.instance
            .sincronizarPermissoesUsuarioLocal(widget.usuarioId);
      } catch (erro) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Permissão salva neste aparelho, mas a nuvem ainda não '
                'atualizou: ${FuncionarioAcessoService.textoErro(erro)}',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }

      await _carregar();
    } catch (erro) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Permissões • ${widget.nome}')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      _administrador
                          ? 'Administrador possui acesso completo.'
                          : 'Por padrão, Funcionário acessa somente o próprio ponto. Você pode liberar outros módulos aqui.',
                    ),
                  ),
                ),
                ...UsuarioRepository.modulos.map(
                  (modulo) => SwitchListTile(
                    title: Text(
                      UsuarioRepository.nomesModulos[modulo] ?? modulo,
                    ),
                    subtitle: Text(
                      modulo == 'financeiro' ||
                              modulo == 'dre' ||
                              modulo == 'precificacao'
                          ? 'Área financeira/gerencial'
                          : 'Módulo do Imperium',
                    ),
                    value: _permissoes[modulo] ?? false,
                    onChanged: _administrador
                        ? null
                        : (valor) => _alterar(modulo, valor),
                  ),
                ),
              ],
            ),
    );
  }
}

class _HistoricoSegurancaPage extends StatefulWidget {
  const _HistoricoSegurancaPage({required this.repository});

  final UsuarioRepository repository;

  @override
  State<_HistoricoSegurancaPage> createState() =>
      _HistoricoSegurancaPageState();
}

class _HistoricoSegurancaPageState extends State<_HistoricoSegurancaPage> {
  bool _carregando = true;
  List<Map<String, dynamic>> _itens = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final itens = await widget.repository.listarAuditoriaUsuario();

    if (!mounted) {
      return;
    }

    setState(() {
      _itens = itens;
      _carregando = false;
    });
  }

  String _data(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    if (data == null) {
      return '';
    }

    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoria de segurança')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                children: [
                  const Card(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: EdgeInsets.all(13),
                      child: Text(
                        'Alterações de PIN, permissões e liberações de bloqueio '
                        'ficam registradas aqui. O PIN original nunca é gravado.',
                      ),
                    ),
                  ),
                  if (_itens.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhuma alteração de segurança registrada.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._itens.map((item) {
                      final usuario = (item['usuario_nome'] ?? '')
                          .toString()
                          .trim();
                      final ator = (item['ator_nome'] ?? '').toString().trim();
                      final acao = (item['acao'] ?? '').toString();
                      final detalhe = (item['detalhe'] ?? '').toString();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.shield_outlined),
                          title: Text(
                            usuario.isEmpty ? acao : '$usuario • $acao',
                          ),
                          subtitle: Text(
                            [
                              if (detalhe.trim().isNotEmpty) detalhe,
                              if (ator.isNotEmpty) 'Por: $ator',
                              _data(item['criado_em']),
                            ].where((e) => e.trim().isNotEmpty).join(' • '),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _HistoricoAcessosPage extends StatefulWidget {
  const _HistoricoAcessosPage({required this.repository});

  final UsuarioRepository repository;

  @override
  State<_HistoricoAcessosPage> createState() => _HistoricoAcessosPageState();
}

class _HistoricoAcessosPageState extends State<_HistoricoAcessosPage> {
  bool _carregando = true;
  List<Map<String, dynamic>> _acessos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final acessos = await widget.repository.listarAcessos();

    if (!mounted) return;

    setState(() {
      _acessos = acessos;
      _carregando = false;
    });
  }

  String _data(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');

    if (data == null) {
      return '';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano $hora:$minuto';
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de acessos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                children: [
                  if (_acessos.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhuma tentativa de acesso registrada.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._acessos.map((item) {
                      final sucesso = _int(item['sucesso']) == 1;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            sucesso
                                ? Icons.login_rounded
                                : Icons.lock_outline_rounded,
                          ),
                          title: Text(
                            (item['usuario_nome'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty
                                ? (item['usuario_nome'] ?? '').toString()
                                : '@${item['login'] ?? ''}',
                          ),
                          subtitle: Text(
                            [
                              _data(item['criado_em']),
                              (item['motivo'] ?? '').toString(),
                            ].where((e) => e.trim().isNotEmpty).join(' • '),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
