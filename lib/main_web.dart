import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'screens/login_email_senha_page.dart';
import 'services/cloud_session_service.dart';
import 'services/empresa_cloud_service.dart';
import 'services/imperium_auth_service.dart';
import 'services/supabase_bootstrap.dart';
import 'web/imperium_web_theme.dart';
import 'web/web_workspace_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.inicializar();
  runApp(const ImperiumWebApp());
}

class ImperiumWebApp extends StatelessWidget {
  const ImperiumWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imperium Manager Web',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ImperiumWebTheme.dark(),
      home: const _WebSessaoGate(),
    );
  }
}

class _WebSessaoGate extends StatefulWidget {
  const _WebSessaoGate();

  @override
  State<_WebSessaoGate> createState() => _WebSessaoGateState();
}

class _WebSessaoGateState extends State<_WebSessaoGate> {
  final CloudSessionService _cloudSession = CloudSessionService.instance;
  final EmpresaCloudService _empresaService = EmpresaCloudService.instance;
  final ImperiumAuthService _auth = ImperiumAuthService.instance;

  final TextEditingController _novaSenha = TextEditingController();
  final TextEditingController _confirmarNovaSenha = TextEditingController();

  StreamSubscription<AuthState>? _authSubscription;

  bool _carregando = true;
  bool _definindoSenha = false;
  bool _salvandoSenha = false;
  bool _ocultarNovaSenha = true;
  bool _ocultarConfirmacao = true;

  String? _erro;
  String? _mensagem;
  Map<String, dynamic>? _sessao;
  List<Map<String, dynamic>> _empresas = const [];
  String _empresaAtualId = '';

  SupabaseClient? get _client => SupabaseBootstrap.client;

  bool get _urlRecuperacao {
    final uri = Uri.base;
    final fragmento = uri.fragment.toLowerCase();
    final tipo = (uri.queryParameters['type'] ?? '').toLowerCase();
    return tipo == 'recovery' || fragmento.contains('type=recovery');
  }

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _novaSenha.dispose();
    _confirmarNovaSenha.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    try {
      final client = _client;
      if (client == null) {
        throw StateError(
          SupabaseBootstrap.ultimoErro ?? 'Supabase indisponível.',
        );
      }

      await _authSubscription?.cancel();
      _authSubscription = client.auth.onAuthStateChange.listen(
        (estado) {
          if (!mounted) return;

          if (estado.event == AuthChangeEvent.passwordRecovery &&
              (estado.session?.user ?? client.auth.currentUser) != null) {
            setState(() {
              _definindoSenha = true;
              _sessao = null;
              _empresas = const [];
              _empresaAtualId = '';
              _erro = null;
              _mensagem = 'Crie uma nova senha para concluir o acesso.';
              _carregando = false;
            });
            return;
          }

          if ((estado.session?.user ?? client.auth.currentUser) == null) {
            setState(() {
              _sessao = null;
              _empresas = const [];
              _empresaAtualId = '';
              _definindoSenha = false;
              _erro = null;
              _mensagem = null;
              _carregando = false;
            });
          }
        },
        onError: (Object erro) {
          if (!mounted) return;
          setState(() {
            _erro = _auth.textoErro(erro);
            _carregando = false;
          });
        },
      );

      final usuario = client.auth.currentUser;
      if (usuario == null) return;

      if (_urlRecuperacao) {
        _definindoSenha = true;
        _mensagem = 'Crie uma nova senha para concluir o acesso.';
        return;
      }

      try {
        final sessao = await _cloudSession.prepararSessao();
        await _aceitarSessao(sessao);
      } on SelecaoEmpresaNecessaria {
        // A tela compartilhada de login detecta a sessão Supabase existente
        // e apresenta o mesmo seletor multiempresa usado no aplicativo.
        _sessao = null;
      }
    } catch (erro) {
      _erro = _auth.textoErro(erro);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _aceitarSessao(Map<String, dynamic> sessao) async {
    final vinculadas = await _empresaService.listarEmpresasVinculadas();
    final atual = (await AppDatabase.instance.empresaAtivaId ?? '').trim();

    if (atual.isEmpty ||
        !vinculadas.any(
          (empresa) => (empresa['empresa_id'] ?? '').toString() == atual,
        )) {
      throw StateError(
        'Não foi possível identificar a empresa ativa desta sessão.',
      );
    }

    if (!mounted) return;
    setState(() {
      _sessao = Map<String, dynamic>.from(sessao);
      _empresas = vinculadas;
      _empresaAtualId = atual;
      _erro = null;
      _mensagem = null;
    });
  }

  void _aoEntrar(Map<String, dynamic> sessao) {
    _concluirLogin(sessao);
  }

  Future<void> _concluirLogin(Map<String, dynamic> sessao) async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      await _aceitarSessao(sessao);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _trocarEmpresa(String empresaId) async {
    final destino = empresaId.trim();
    if (destino.isEmpty || destino == _empresaAtualId || _carregando) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final sessao = await _cloudSession.prepararSessao(empresaId: destino);
      await _aceitarSessao(sessao);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _sair() async {
    await _cloudSession.sair();
    if (!mounted) return;

    setState(() {
      _sessao = null;
      _empresas = const [];
      _empresaAtualId = '';
      _definindoSenha = false;
      _erro = null;
      _mensagem = null;
    });
  }

  Future<void> _salvarNovaSenha() async {
    if (_salvandoSenha) return;

    final novaSenha = _novaSenha.text.trim();
    final confirmar = _confirmarNovaSenha.text.trim();

    if (novaSenha.length < 8) {
      setState(() => _erro = 'A senha deve ter pelo menos 8 caracteres.');
      return;
    }

    if (novaSenha != confirmar) {
      setState(() => _erro = 'As senhas informadas são diferentes.');
      return;
    }

    setState(() {
      _salvandoSenha = true;
      _erro = null;
      _mensagem = null;
    });

    try {
      await _auth.definirNovaSenha(novaSenha);
      _novaSenha.clear();
      _confirmarNovaSenha.clear();

      try {
        final sessao = await _cloudSession.prepararSessao();
        if (!mounted) return;
        setState(() {
          _definindoSenha = false;
          _mensagem = 'Senha atualizada com sucesso.';
        });
        await _aceitarSessao(sessao);
      } on SelecaoEmpresaNecessaria {
        if (!mounted) return;
        setState(() {
          _definindoSenha = false;
          _sessao = null;
          _mensagem = 'Senha atualizada. Escolha a empresa para continuar.';
        });
      }
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _salvandoSenha = false);
    }
  }

  Widget _carregandoTela() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Preparando seu ambiente...'),
          ],
        ),
      ),
    );
  }

  Widget _erroTela() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 52),
                      const SizedBox(height: 16),
                      const Text(
                        'Não foi possível abrir o Imperium',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(_erro ?? '', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _inicializar,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _sair,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Entrar com outra conta'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _redefinirSenha() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 52),
                      const SizedBox(height: 16),
                      Text(
                        'Defina sua nova senha',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Essa senha será a mesma no Imperium Web e no aplicativo.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _novaSenha,
                        obscureText: _ocultarNovaSenha,
                        enabled: !_salvandoSenha,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Nova senha',
                          helperText: 'Mínimo de 8 caracteres',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _salvandoSenha
                                ? null
                                : () => setState(
                                    () =>
                                        _ocultarNovaSenha = !_ocultarNovaSenha,
                                  ),
                            icon: Icon(
                              _ocultarNovaSenha
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmarNovaSenha,
                        obscureText: _ocultarConfirmacao,
                        enabled: !_salvandoSenha,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _salvarNovaSenha(),
                        decoration: InputDecoration(
                          labelText: 'Confirmar nova senha',
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _salvandoSenha
                                ? null
                                : () => setState(
                                    () => _ocultarConfirmacao =
                                        !_ocultarConfirmacao,
                                  ),
                            icon: Icon(
                              _ocultarConfirmacao
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_mensagem != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _mensagem!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.greenAccent),
                        ),
                      ],
                      if (_erro != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _erro!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _salvandoSenha ? null : _salvarNovaSenha,
                          icon: _salvandoSenha
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(
                            _salvandoSenha
                                ? 'Salvando...'
                                : 'Salvar nova senha',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return _carregandoTela();
    if (_definindoSenha) return _redefinirSenha();

    final sessao = _sessao;
    if (sessao == null) {
      if (_erro != null && _client?.auth.currentUser != null) {
        return _erroTela();
      }
      return LoginEmailSenhaPage(onLogin: _aoEntrar);
    }

    return WebWorkspaceShell(
      usuarioEmail: (_client?.auth.currentUser?.email ?? '').trim(),
      empresas: _empresas,
      empresaAtualId: _empresaAtualId,
      onTrocarEmpresa: _trocarEmpresa,
      onSair: _sair,
    );
  }
}
