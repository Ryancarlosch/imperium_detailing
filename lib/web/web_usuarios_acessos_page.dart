import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';
import '../services/funcionario_acesso_service.dart';
import '../services/web_cloud_ponto_service.dart';
import 'imperium_web_theme.dart';

class WebUsuariosAcessosPage extends StatefulWidget {
  const WebUsuariosAcessosPage({required this.empresaId, super.key});

  final String empresaId;

  @override
  State<WebUsuariosAcessosPage> createState() => _WebUsuariosAcessosPageState();
}

class _WebUsuariosAcessosPageState extends State<WebUsuariosAcessosPage> {
  final _acesso = FuncionarioAcessoService.instance;
  final _ponto = WebCloudPontoService.instance;
  final _busca = TextEditingController();

  bool _carregando = true;
  String? _erro;
  String _filtro = 'Todos';
  List<Map<String, dynamic>> _colaboradores = const [];
  List<Map<String, dynamic>> _acessos = const [];

  static const _modulos = <String>[
    'ponto',
    'clientes',
    'crm',
    'agenda',
    'orcamentos',
    'ordens_servico',
    'estoque',
    'financeiro',
    'configuracoes',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final dados = await Future.wait<dynamic>([
        _ponto.listarColaboradores(),
        _acesso.listarAcessosAdmin(widget.empresaId),
      ]);

      if (!mounted) return;
      setState(() {
        _colaboradores = dados[0] as List<Map<String, dynamic>>;
        _acessos = dados[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Map<String, dynamic>? _acessoDo(String colaboradorId) {
    for (final acesso in _acessos) {
      if ((acesso['colaborador_id'] ?? '').toString() == colaboradorId) {
        return acesso;
      }
    }
    return null;
  }

  Map<String, bool> _permissoes(dynamic raw) {
    final resultado = <String, bool>{
      for (final modulo in _modulos) modulo: false,
    };

    if (raw is Map) {
      for (final entry in raw.entries) {
        final modulo = entry.key.toString();
        if (resultado.containsKey(modulo)) {
          resultado[modulo] = entry.value == true;
        }
      }
    }

    return resultado;
  }

  int _quantidadePermissoes(Map<String, dynamic>? acesso) {
    if (acesso == null) return 0;
    return _permissoes(
      acesso['permissoes'],
    ).values.where((permitido) => permitido).length;
  }

  Future<void> _configurar(
    Map<String, dynamic> colaborador,
    Map<String, dynamic>? atual,
  ) async {
    final email = TextEditingController(
      text: (atual?['email'] ?? '').toString(),
    );
    final login = TextEditingController(
      text: (atual?['login'] ?? '').toString(),
    );
    final permissoes = _permissoes(atual?['permissoes']);

    if (login.text.trim().isEmpty) {
      final nome = (colaborador['nome'] ?? '').toString().trim().toLowerCase();
      login.text = nome
          .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
          .replaceAll(RegExp(r'^\.+|\.+$'), '');
    }

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          return AlertDialog(
            title: Text(atual == null ? 'Configurar acesso' : 'Editar acesso'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.badge_outlined),
                        ),
                        title: Text(
                          (colaborador['nome'] ?? 'Funcionário').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          (colaborador['funcao'] ?? '').toString(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail de acesso *',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                        helperText:
                            'O funcionário entra com a conta vinculada a este e-mail.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: login,
                      decoration: const InputDecoration(
                        labelText: 'Login interno *',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Permissões',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Libere apenas os módulos necessários para este funcionário.',
                      style: TextStyle(color: Color(0xFF89939E), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ..._modulos.map((modulo) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          UsuarioRepository.nomesModulos[modulo] ?? modulo,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        value: permissoes[modulo] ?? false,
                        onChanged: (valor) {
                          setLocal(() => permissoes[modulo] = valor);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 19),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Precificação não é uma permissão Cloud independente; '
                                'continua protegida pelo acesso ao Financeiro.',
                                style: TextStyle(
                                  color: Color(0xFF89939E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final emailLimpo = email.text.trim().toLowerCase();
                  final loginLimpo = login.text.trim().toLowerCase();
                  if (!emailLimpo.contains('@') || loginLimpo.length < 3) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Informe um e-mail válido e um login com pelo menos 3 caracteres.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Salvar acesso'),
              ),
            ],
          );
        },
      ),
    );

    if (salvar != true) return;

    try {
      await _acesso.prepararAcessoAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: colaborador['id'].toString(),
        email: email.text,
        login: login.text,
        permissoes: permissoes,
      );
      await _carregar();
      _mensagem('Acesso atualizado com sucesso.');
    } catch (e) {
      _mensagem(_textoErro(e), erro: true);
    }
  }

  Future<void> _alterarAtivo(
    Map<String, dynamic> colaborador,
    Map<String, dynamic> acesso,
  ) async {
    final ativo = acesso['ativo'] == true;
    final nome = (colaborador['nome'] ?? 'Funcionário').toString();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ativo ? 'Desativar acesso?' : 'Ativar acesso?'),
        content: Text(
          ativo
              ? '$nome deixará de acessar os módulos Cloud desta empresa.'
              : '$nome voltará a acessar os módulos permitidos desta empresa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ativo ? 'Desativar' : 'Ativar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _acesso.definirAtivoAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: colaborador['id'].toString(),
        ativo: !ativo,
      );
      await _carregar();
      _mensagem(ativo ? 'Acesso desativado.' : 'Acesso ativado.');
    } catch (e) {
      _mensagem(_textoErro(e), erro: true);
    }
  }

  Future<void> _revogarDispositivos(
    Map<String, dynamic> colaborador,
    Map<String, dynamic> acesso,
  ) async {
    final dispositivos = _int(acesso['dispositivos_ativos']);
    final nome = (colaborador['nome'] ?? 'Funcionário').toString();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar dispositivos?'),
        content: Text(
          dispositivos <= 0
              ? 'Não há dispositivo ativo registrado para $nome. '
                    'Mesmo assim, você pode revogar vínculos existentes.'
              : '$nome possui $dispositivos dispositivo(s) ativo(s). '
                    'Eles precisarão refazer o vínculo de acesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phonelink_erase_outlined),
            label: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _acesso.revogarDispositivosAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: colaborador['id'].toString(),
      );
      await _carregar();
      _mensagem('Dispositivos revogados.');
    } catch (e) {
      _mensagem(_textoErro(e), erro: true);
    }
  }

  List<Map<String, dynamic>> _filtrados() {
    final termo = _busca.text.trim().toLowerCase();

    return _colaboradores.where((colaborador) {
      final id = colaborador['id'].toString();
      final acesso = _acessoDo(id);
      final configurado = acesso != null;
      final ativo = acesso?['ativo'] == true;

      if (_filtro == 'Configurados' && !configurado) return false;
      if (_filtro == 'Sem acesso' && configurado) return false;
      if (_filtro == 'Ativos' && !ativo) return false;
      if (_filtro == 'Inativos' && (!configurado || ativo)) return false;

      if (termo.isEmpty) return true;

      return [
        colaborador['nome'],
        colaborador['funcao'],
        acesso?['email'],
        acesso?['login'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();
  }

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusAcesso(Map<String, dynamic>? acesso) {
    if (acesso == null) {
      return const Chip(
        avatar: Icon(Icons.person_off_outlined, size: 16),
        label: Text('Sem acesso'),
        visualDensity: VisualDensity.compact,
      );
    }

    final ativo = acesso['ativo'] == true;
    final vinculado = (acesso['auth_user_id'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    return Chip(
      avatar: Icon(
        !ativo
            ? Icons.block_outlined
            : vinculado
            ? Icons.verified_user_outlined
            : Icons.hourglass_top_rounded,
        size: 16,
      ),
      label: Text(
        !ativo
            ? 'Inativo'
            : vinculado
            ? 'Vinculado'
            : 'Aguardando vínculo',
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _acoes(
    Map<String, dynamic> colaborador,
    Map<String, dynamic>? acesso,
  ) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: acesso == null ? 'Configurar acesso' : 'Editar acesso',
          onPressed: () => _configurar(colaborador, acesso),
          icon: Icon(
            acesso == null
                ? Icons.person_add_alt_1_outlined
                : Icons.manage_accounts_outlined,
          ),
        ),
        if (acesso != null) ...[
          IconButton(
            tooltip: acesso['ativo'] == true
                ? 'Desativar acesso'
                : 'Ativar acesso',
            onPressed: () => _alterarAtivo(colaborador, acesso),
            icon: Icon(
              acesso['ativo'] == true
                  ? Icons.block_outlined
                  : Icons.check_circle_outline_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Revogar dispositivos',
            onPressed: () => _revogarDispositivos(colaborador, acesso),
            icon: const Icon(Icons.phonelink_erase_outlined),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando && _colaboradores.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null && _colaboradores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 12),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final filtrados = _filtrados();
    final configurados = _colaboradores
        .where((c) => _acessoDo(c['id'].toString()) != null)
        .length;
    final ativos = _acessos.where((a) => a['ativo'] == true).length;
    final vinculados = _acessos
        .where((a) => (a['auth_user_id'] ?? '').toString().trim().isNotEmpty)
        .length;
    final dispositivos = _acessos.fold<int>(
      0,
      (total, item) => total + _int(item['dispositivos_ativos']),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 1050;
        final larguraDisponivel = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final larguraResumo =
            (larguraDisponivel - (12 * (colunas - 1))) / colunas;

        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compacto ? 16 : 24,
              compacto ? 18 : 24,
              compacto ? 16 : 24,
              40,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Usuários e acessos',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Controle quais funcionários podem acessar a empresa e quais módulos ficam disponíveis.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _carregando ? null : _carregar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: ImperiumWebTheme.accentStrong,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Funcionários permanecem dentro da empresa. '
                          'Eles não criam outra empresa nem outro plano; o administrador controla vínculo e permissões.',
                          style: TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Funcionários',
                    valor: '${_colaboradores.length}',
                    detalhe: 'Colaboradores cadastrados na empresa',
                    icone: Icons.groups_2_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Acessos configurados',
                    valor: '$configurados',
                    detalhe: 'Funcionários com credencial preparada',
                    icone: Icons.manage_accounts_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Contas vinculadas',
                    valor: '$vinculados',
                    detalhe: '$ativos acesso(s) atualmente ativo(s)',
                    icone: Icons.verified_user_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Dispositivos ativos',
                    valor: '$dispositivos',
                    detalhe: 'Dispositivos vinculados aos funcionários',
                    icone: Icons.devices_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: compacto ? larguraDisponivel - 28 : 410,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText:
                                'Buscar funcionário, função, e-mail ou login',
                            suffixIcon: _busca.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpar busca',
                                    onPressed: () {
                                      _busca.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filtro,
                          decoration: const InputDecoration(
                            labelText: 'Situação',
                          ),
                          items:
                              const [
                                    'Todos',
                                    'Configurados',
                                    'Sem acesso',
                                    'Ativos',
                                    'Inativos',
                                  ]
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (valor) =>
                              setState(() => _filtro = valor ?? 'Todos'),
                        ),
                      ),
                      Text(
                        '${filtrados.length} resultado(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (filtrados.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.manage_accounts_outlined,
                          size: 42,
                          color: Color(0xFF89939E),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nenhum funcionário encontrado',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (tabela)
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 52,
                      dataRowMinHeight: 64,
                      dataRowMaxHeight: 82,
                      columns: const [
                        DataColumn(label: Text('FUNCIONÁRIO')),
                        DataColumn(label: Text('ACESSO')),
                        DataColumn(label: Text('E-MAIL / LOGIN')),
                        DataColumn(label: Text('PERMISSÕES')),
                        DataColumn(label: Text('DISPOSITIVOS')),
                        DataColumn(label: Text('ÚLTIMO ACESSO')),
                        DataColumn(label: Text('AÇÕES')),
                      ],
                      rows: filtrados.map((colaborador) {
                        final acesso = _acessoDo(colaborador['id'].toString());
                        final ultimo = (acesso?['ultimo_acesso_em'] ?? '')
                            .toString();

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 230,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (colaborador['nome'] ?? 'Funcionário')
                                          .toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      (colaborador['funcao'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFAAB3BD),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(_statusAcesso(acesso)),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  acesso == null
                                      ? '—'
                                      : [
                                          (acesso['email'] ?? '').toString(),
                                          if ((acesso['login'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                            '@${acesso['login']}',
                                        ].join('\n'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                acesso == null
                                    ? '—'
                                    : '${_quantidadePermissoes(acesso)} de ${_modulos.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                acesso == null
                                    ? '—'
                                    : '${_int(acesso['dispositivos_ativos'])}',
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(
                                  ultimo.trim().isEmpty ? 'Nunca' : ultimo,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(_acoes(colaborador, acesso)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                ...filtrados.map((colaborador) {
                  final acesso = _acessoDo(colaborador['id'].toString());

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.badge_outlined),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (colaborador['nome'] ?? 'Funcionário')
                                        .toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      (colaborador['funcao'] ?? '').toString(),
                                      if (acesso != null)
                                        (acesso['email'] ?? '').toString(),
                                      if (acesso != null)
                                        '${_quantidadePermissoes(acesso)} permissões',
                                    ].where((e) => e.trim().isNotEmpty).join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFAAB3BD),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _statusAcesso(acesso),
                                ],
                              ),
                            ),
                            _acoes(colaborador, acesso),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  void _mensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Bad state: ', '');
  }
}
