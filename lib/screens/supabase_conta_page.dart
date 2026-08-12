import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_bootstrap.dart';
import 'ponto_nuvem_importacao_page.dart';

class SupabaseContaPage extends StatefulWidget {
  const SupabaseContaPage({super.key, this.emailInicial});

  final String? emailInicial;

  @override
  State<SupabaseContaPage> createState() => _SupabaseContaPageState();
}

class _SupabaseContaPageState extends State<SupabaseContaPage> {
  static const String _redirectUrl = 'imperiumdetailing://login-callback/';

  final TextEditingController _emailController = TextEditingController();

  StreamSubscription<dynamic>? _authSubscription;

  bool _carregando = true;
  bool _enviandoLink = false;
  bool _saindo = false;

  String? _erro;
  String? _empresaId;
  String? _empresaNome;
  String? _papel;
  bool _empresaAtiva = false;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  User? get _usuario => _client?.auth.currentUser;

  bool get _rlsValidado {
    return _usuario != null &&
        (_empresaId?.isNotEmpty ?? false) &&
        (_empresaNome?.isNotEmpty ?? false) &&
        (_papel?.isNotEmpty ?? false) &&
        _empresaAtiva;
  }

  @override
  void initState() {
    super.initState();

    _emailController.text = widget.emailInicial?.trim() ?? '';

    final client = _client;
    if (client != null) {
      _authSubscription = client.auth.onAuthStateChange.listen(
        (_) {
          _carregarEstado();
        },
        onError: (Object erro) {
          if (!mounted) return;
          setState(() {
            _erro = 'Falha ao atualizar a sessão: $erro';
          });
        },
      );
    }

    _carregarEstado();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _carregarEstado() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    final client = _client;

    if (client == null) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _erro =
            'A infraestrutura do Supabase não está disponível. '
            'O banco local continua funcionando normalmente.';
        _limparEmpresa();
      });
      return;
    }

    final usuario = client.auth.currentUser;

    if (usuario == null) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _limparEmpresa();
      });
      return;
    }

    try {
      final vinculo = await client
          .from('empresa_usuarios')
          .select('empresa_id,papel,ativo')
          .eq('user_id', usuario.id)
          .eq('ativo', true)
          .limit(1)
          .maybeSingle();

      final empresaId = vinculo?['empresa_id']?.toString().trim() ?? '';
      final papel = vinculo?['papel']?.toString().trim() ?? '';

      if (empresaId.isEmpty) {
        throw StateError('Esta conta não possui empresa ativa autorizada.');
      }

      final empresa = await client
          .from('empresas')
          .select('id,nome,ativo')
          .eq('id', empresaId)
          .eq('ativo', true)
          .limit(1)
          .maybeSingle();

      if (empresa == null) {
        throw StateError('A empresa vinculada não está disponível.');
      }

      if (!mounted) return;

      setState(() {
        _empresaId = empresaId;
        _empresaNome = empresa['nome']?.toString().trim() ?? '';
        _papel = papel;
        _empresaAtiva = empresa['ativo'] == true;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _limparEmpresa();
        _carregando = false;
        _erro = _textoErro(erro);
      });
    }
  }

  void _limparEmpresa() {
    _empresaId = null;
    _empresaNome = null;
    _papel = null;
    _empresaAtiva = false;
  }

  Future<void> _enviarMagicLink() async {
    final client = _client;
    final email = _emailController.text.trim();

    if (client == null) {
      _mensagem('O Supabase não está disponível neste momento.', erro: true);
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      _mensagem('Informe um e-mail válido.', erro: true);
      return;
    }

    setState(() => _enviandoLink = true);

    try {
      await client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: _redirectUrl,
        shouldCreateUser: false,
      );

      if (!mounted) return;

      _mensagem('Link enviado. Abra o e-mail neste aparelho e toque no link.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) {
        setState(() => _enviandoLink = false);
      }
    }
  }

  Future<void> _sair() async {
    final client = _client;
    if (client == null || _saindo) return;

    setState(() => _saindo = true);

    try {
      await client.auth.signOut();
      await _carregarEstado();

      if (!mounted) return;
      _mensagem('Conta da nuvem desconectada.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) {
        setState(() => _saindo = false);
      }
    }
  }

  Future<void> _abrirPontoNuvem() async {
    final empresaId = _empresaId;

    if (!_rlsValidado || empresaId == null) {
      _mensagem('Valide primeiro a conta e a empresa na nuvem.', erro: true);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PontoNuvemImportacaoPage(empresaId: empresaId),
      ),
    );

    await _carregarEstado();
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    const prefixos = <String>[
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ];

    for (final prefixo in prefixos) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida.' : texto;
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

  Widget _linha({required String titulo, required String valor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: SelectableText(
              valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = _usuario;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta na nuvem'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarEstado,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _rlsValidado
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _rlsValidado
                          ? 'Conta conectada. A empresa e as permissões '
                                'foram validadas pelo RLS do Supabase.'
                          : 'Conecte uma conta autorizada do Supabase para '
                                'usar a sincronização entre aparelhos.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (_carregando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            )
          else if (usuario == null) ...[
            const Text(
              'Conectar conta',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enviandoLink ? null : _enviarMagicLink,
              icon: _enviandoLink
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(_enviandoLink ? 'Enviando...' : 'Enviar Magic Link'),
            ),
          ] else ...[
            if (_rlsValidado)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: Colors.greenAccent,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'RLS validado com sucesso',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _linha(titulo: 'E-mail', valor: usuario.email ?? ''),
                      _linha(titulo: 'Empresa', valor: _empresaNome ?? ''),
                      _linha(titulo: 'Papel', valor: _papel ?? ''),
                      _linha(titulo: 'Empresa ID', valor: _empresaId ?? ''),
                      const SizedBox(height: 14),

                      // Entrada que estava faltando no APK.
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _abrirPontoNuvem,
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('Preparar Ponto na nuvem'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Aqui você importa os funcionários, migra o '
                        'histórico e ativa o Ponto compartilhado.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _erro ??
                        'A sessão existe, mas a empresa ainda não '
                            'foi validada pelo RLS.',
                  ),
                ),
              ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saindo ? null : _sair,
              icon: const Icon(Icons.logout),
              label: Text(_saindo ? 'Desconectando...' : 'Desconectar'),
            ),
          ],

          if (_erro != null && usuario == null) ...[
            const SizedBox(height: 14),
            Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 18),
          const Text(
            'O login local do Imperium continua separado. '
            'A conta Supabase identifica o usuário na nuvem e permite '
            'aplicar as políticas de acesso da empresa.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
