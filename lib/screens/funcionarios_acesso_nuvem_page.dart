import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';
import '../services/funcionario_acesso_service.dart';
import '../services/ponto_nuvem_service.dart';

class FuncionariosAcessoNuvemPage extends StatefulWidget {
  const FuncionariosAcessoNuvemPage({super.key, required this.empresaId});

  final String empresaId;

  @override
  State<FuncionariosAcessoNuvemPage> createState() =>
      _FuncionariosAcessoNuvemPageState();
}

class _FuncionariosAcessoNuvemPageState
    extends State<FuncionariosAcessoNuvemPage> {
  final FuncionarioAcessoService _service = FuncionarioAcessoService.instance;
  final PontoNuvemService _ponto = PontoNuvemService.instance;
  final UsuarioRepository _usuariosRepository = UsuarioRepository();

  bool _carregando = true;
  String? _processandoId;
  String? _erro;

  List<Map<String, dynamic>> _colaboradores = const [];
  List<Map<String, dynamic>> _acessos = const [];
  List<Map<String, dynamic>> _usuarios = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      await _usuariosRepository.garantirEstrutura();

      final resultados = await Future.wait<dynamic>([
        _ponto.listarColaboradoresRemotos(),
        _service.listarAcessosAdmin(widget.empresaId),
        _usuariosRepository.listarUsuarios(incluirInativos: true),
      ]);

      if (!mounted) return;

      setState(() {
        _colaboradores = (resultados[0] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _acessos = (resultados[1] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _usuarios = (resultados[2] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = FuncionarioAcessoService.textoErro(erro);
      });
    }
  }

  Map<String, dynamic>? _acessoDo(String colaboradorRemotoId) {
    for (final item in _acessos) {
      if ((item['colaborador_id'] ?? '').toString() == colaboradorRemotoId) {
        return item;
      }
    }
    return null;
  }

  Map<String, dynamic>? _usuarioLocalDo(Map<String, dynamic> colaborador) {
    final localId = _intNulo(colaborador['origem_local_id']);
    if (localId == null) return null;

    for (final usuario in _usuarios) {
      if ((usuario['perfil'] ?? '').toString() !=
          UsuarioRepository.perfilFuncionario) {
        continue;
      }

      if (_intNulo(usuario['colaborador_id']) == localId) {
        return usuario;
      }
    }

    return null;
  }

  Future<void> _liberarCelular(Map<String, dynamic> colaborador) async {
    final remotoId = (colaborador['id'] ?? '').toString().trim();
    if (remotoId.isEmpty) return;

    final usuario = _usuarioLocalDo(colaborador);

    if (usuario == null) {
      _mensagem(
        'Antes de liberar outro celular, crie um usuário do tipo Funcionário '
        'e vincule-o a ${colaborador['nome'] ?? 'este funcionário'}.',
        erro: true,
      );
      return;
    }

    final acesso = _acessoDo(remotoId);
    final emailController = TextEditingController(
      text: (acesso?['email'] ?? '').toString(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Liberar celular • ${colaborador['nome'] ?? 'Funcionário'}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informe o e-mail que o funcionário usará no Magic Link. '
              'Depois do primeiro acesso, ele usará o PIN criado no próprio '
              'celular.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail do funcionário',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Módulo 1, apenas Ponto, Clientes e Agenda são '
              'sincronizados para outro aparelho. As áreas administrativas '
              'continuam bloqueadas.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
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
              final valor = emailController.text.trim().toLowerCase();
              if (valor.contains('@')) {
                Navigator.of(dialogContext).pop(valor);
              }
            },
            child: const Text('Liberar'),
          ),
        ],
      ),
    );

    emailController.dispose();
    if (email == null) return;

    final usuarioId = _intNulo(usuario['id']);
    if (usuarioId == null) return;

    setState(() => _processandoId = remotoId);

    try {
      final permissoes = await _usuariosRepository.obterPermissoes(usuarioId);

      final resultado = await _service.prepararAcessoAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: remotoId,
        email: email,
        login: (usuario['login'] ?? '').toString(),
        permissoes: permissoes,
      );

      await _carregar();

      if (!mounted) return;
      _mensagem(
        '${resultado['status'] ?? 'Acesso preparado'}. '
        'O funcionário já pode usar esse e-mail no primeiro acesso.',
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem(FuncionarioAcessoService.textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  Future<void> _sincronizarPermissoes(Map<String, dynamic> colaborador) async {
    final remotoId = (colaborador['id'] ?? '').toString().trim();
    final usuario = _usuarioLocalDo(colaborador);
    final usuarioId = _intNulo(usuario?['id']);

    if (usuarioId == null) {
      _mensagem('Usuário local do funcionário não encontrado.', erro: true);
      return;
    }

    setState(() => _processandoId = remotoId);

    try {
      final sincronizou = await _service.sincronizarPermissoesUsuarioLocal(
        usuarioId,
      );

      if (!sincronizou) {
        throw StateError(
          'O acesso remoto ainda não foi preparado. Use “Liberar celular” '
          'primeiro.',
        );
      }

      await _carregar();
      if (mounted) _mensagem('Permissões enviadas para o funcionário.');
    } catch (erro) {
      if (mounted) {
        _mensagem(FuncionarioAcessoService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  Future<void> _alterarAtivo(
    Map<String, dynamic> colaborador,
    bool ativo,
  ) async {
    final remotoId = (colaborador['id'] ?? '').toString().trim();
    if (remotoId.isEmpty) return;

    setState(() => _processandoId = remotoId);

    try {
      await _service.definirAtivoAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: remotoId,
        ativo: ativo,
      );

      await _carregar();
      if (!mounted) return;

      _mensagem(
        ativo
            ? 'Acesso reativado. Use “Liberar celular” para autorizar um '
                  'aparelho novamente.'
            : 'Acesso desativado. O app do funcionário será bloqueado quando '
                  'conseguir consultar a nuvem.',
      );
    } catch (erro) {
      if (mounted) {
        _mensagem(FuncionarioAcessoService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  Future<void> _revogarCelulares(Map<String, dynamic> colaborador) async {
    final remotoId = (colaborador['id'] ?? '').toString().trim();
    if (remotoId.isEmpty) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revogar celulares'),
        content: Text(
          'Os aparelhos vinculados de ${colaborador['nome'] ?? 'este funcionário'} serão bloqueados. O histórico do Ponto e os dados '
          'da empresa não serão apagados. Para liberar novamente, será '
          'necessário usar “Liberar celular”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _processandoId = remotoId);

    try {
      await _service.revogarDispositivosAdmin(
        empresaId: widget.empresaId,
        colaboradorRemotoId: remotoId,
      );

      await _carregar();
      if (mounted) {
        _mensagem(
          'Celulares revogados. Os dados e o histórico foram mantidos.',
        );
      }
    } catch (erro) {
      if (mounted) {
        _mensagem(FuncionarioAcessoService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  String _status(
    Map<String, dynamic> colaborador,
    Map<String, dynamic>? acesso,
  ) {
    if (acesso == null) return 'Não liberado';
    if (acesso['ativo'] != true) return 'Desativado';

    final dispositivos = _intNulo(acesso['dispositivos_ativos']) ?? 0;
    final podeNovo = acesso['permitir_novo_dispositivo'] == true;

    if (dispositivos > 0 && podeNovo) {
      return 'Celular vinculado • nova liberação aberta';
    }

    if (dispositivos > 0) return 'Celular vinculado';
    return 'Aguardando primeiro acesso';
  }

  Color? _statusCor(String status) {
    if (status.startsWith('Celular vinculado')) return Colors.greenAccent;
    if (status == 'Aguardando primeiro acesso') return Colors.orangeAccent;
    if (status == 'Desativado') return Colors.redAccent;
    return Colors.white60;
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  int? _intNulo(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acessos em outros celulares'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Funcionários em outro aparelho',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'O PIN continua local de cada celular. A nuvem transporta '
                      'somente o vínculo do funcionário, permissões e os dados '
                      'operacionais preparados neste Módulo 1: Ponto, Clientes, '
                      'Veículos e Agenda.',
                    ),
                  ],
                ),
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _erro!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_colaboradores.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Nenhum funcionário foi importado para o Ponto na nuvem. '
                    'Volte e use “Importar/atualizar funcionários”.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              for (final colaborador in _colaboradores) ...[
                Builder(
                  builder: (context) {
                    final remotoId = (colaborador['id'] ?? '').toString();
                    final acesso = _acessoDo(remotoId);
                    final usuario = _usuarioLocalDo(colaborador);
                    final status = _status(colaborador, acesso);
                    final processando = _processandoId == remotoId;
                    final ativo = acesso?['ativo'] == true;
                    final dispositivos =
                        _intNulo(acesso?['dispositivos_ativos']) ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  child: Icon(
                                    dispositivos > 0
                                        ? Icons.phone_android_rounded
                                        : Icons.badge_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (colaborador['nome'] ?? 'Funcionário')
                                            .toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          color: _statusCor(status),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (processando)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              usuario == null
                                  ? 'Sem usuário local vinculado.'
                                  : '@${usuario['login'] ?? ''} • '
                                        '${(acesso?['email'] ?? 'e-mail não liberado')}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (usuario == null) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'Crie o usuário em Usuários e permissões e '
                                'vincule-o a este funcionário.',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: processando || usuario == null
                                      ? null
                                      : () => _liberarCelular(colaborador),
                                  icon: const Icon(Icons.phone_android_rounded),
                                  label: Text(
                                    acesso == null
                                        ? 'Liberar celular'
                                        : 'Liberar/Atualizar celular',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      processando ||
                                          usuario == null ||
                                          acesso == null
                                      ? null
                                      : () =>
                                            _sincronizarPermissoes(colaborador),
                                  icon: const Icon(Icons.sync_rounded),
                                  label: const Text('Enviar permissões'),
                                ),
                                if (acesso != null)
                                  OutlinedButton.icon(
                                    onPressed: processando
                                        ? null
                                        : () => _alterarAtivo(
                                            colaborador,
                                            !ativo,
                                          ),
                                    icon: Icon(
                                      ativo
                                          ? Icons.block_outlined
                                          : Icons.check_circle_outline,
                                    ),
                                    label: Text(
                                      ativo ? 'Desativar' : 'Reativar',
                                    ),
                                  ),
                                if (dispositivos > 0)
                                  OutlinedButton.icon(
                                    onPressed: processando
                                        ? null
                                        : () => _revogarCelulares(colaborador),
                                    icon: const Icon(Icons.phonelink_erase),
                                    label: const Text('Revogar celulares'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }
}
