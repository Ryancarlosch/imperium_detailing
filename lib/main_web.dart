import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'services/empresa_cloud_service.dart';
import 'services/supabase_bootstrap.dart';
import 'services/web_analytics_service.dart';
import 'web/web_operacional_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = WebAnalyticsService.instance;
  await analytics.inicializar();

  final flutterOnErrorAnterior = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(
      analytics.registrarErro(
        area: 'flutter_framework',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );

    if (flutterOnErrorAnterior != null) {
      flutterOnErrorAnterior(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final platformOnErrorAnterior = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      analytics.registrarErro(
        area: 'dart_runtime',
        error: error,
        stackTrace: stack,
      ),
    );
    return platformOnErrorAnterior?.call(error, stack) ?? false;
  };

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
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _WebGate(),
    );
  }
}

class _WebGate extends StatefulWidget {
  const _WebGate();

  @override
  State<_WebGate> createState() => _WebGateState();
}

class _WebGateState extends State<_WebGate> {
  final email = TextEditingController();
  final empresaService = EmpresaCloudService.instance;
  final analytics = WebAnalyticsService.instance;

  StreamSubscription<AuthState>? _authSubscription;

  bool carregando = true;
  bool enviandoLink = false;
  bool linkEnviado = false;
  String? erro;
  String? mensagem;
  User? usuario;
  List<Map<String, dynamic>> empresas = const [];
  String empresaAtual = '';

  SupabaseClient? get client => SupabaseBootstrap.client;

  String get _redirectUrl => '${Uri.base.origin}/';

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    email.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    try {
      final c = client;
      if (c == null) {
        throw StateError(
          SupabaseBootstrap.ultimoErro ?? 'Supabase indisponível.',
        );
      }

      usuario = c.auth.currentUser;

      if (usuario != null) {
        await _carregarContexto();
      }

      _authSubscription = c.auth.onAuthStateChange.listen(
        (authState) {
          _tratarMudancaAuth(authState);
        },
        onError: (Object e) {
          unawaited(
            analytics.registrarErro(
              area: 'auth_stream',
              error: e,
              stackTrace: StackTrace.current,
            ),
          );
          if (!mounted) return;
          setState(() {
            erro = _textoErro(e);
            carregando = false;
          });
        },
      );
    } catch (e, stack) {
      unawaited(
        analytics.registrarErro(
          area: 'auth_init',
          error: e,
          stackTrace: stack,
        ),
      );
      erro = _textoErro(e);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _tratarMudancaAuth(AuthState authState) async {
    if (!mounted) return;

    final novoUsuario = authState.session?.user ?? client?.auth.currentUser;

    if (novoUsuario == null) {
      setState(() {
        usuario = null;
        empresas = const [];
        empresaAtual = '';
        carregando = false;
      });
      return;
    }

    setState(() {
      carregando = true;
      erro = null;
      mensagem = null;
      usuario = novoUsuario;
    });

    try {
      await _carregarContexto();
    } catch (e, stack) {
      unawaited(
        analytics.registrarErro(
          area: 'auth_state_change',
          error: e,
          stackTrace: stack,
        ),
      );
      erro = _textoErro(e);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _enviarMagicLink() async {
    final c = client;
    if (c == null || enviandoLink) return;

    final destino = email.text.trim().toLowerCase();

    if (destino.isEmpty || !destino.contains('@')) {
      setState(() {
        erro = 'Informe um e-mail válido.';
        mensagem = null;
      });
      return;
    }

    setState(() {
      enviandoLink = true;
      linkEnviado = false;
      erro = null;
      mensagem = null;
    });

    try {
      await c.auth.signInWithOtp(
        email: destino,
        emailRedirectTo: _redirectUrl,
        shouldCreateUser: false,
      );

      await analytics.evento(
        'auth_magic_link_requested',
        propriedades: const {'channel': 'email'},
      );

      if (!mounted) return;

      setState(() {
        linkEnviado = true;
        mensagem =
            'Link enviado para $destino. Abra somente o link mais recente. '
            'Depois da confirmação você voltará automaticamente para o '
            'Imperium Manager Web.';
      });
    } catch (e, stack) {
      await analytics.evento(
        'auth_magic_link_failed',
        propriedades: {'error_type': e.runtimeType.toString()},
      );
      unawaited(
        analytics.registrarErro(
          area: 'magic_link',
          error: e,
          stackTrace: stack,
        ),
      );

      if (!mounted) return;
      setState(() {
        erro = _textoErro(e);
        mensagem = null;
      });
    } finally {
      if (mounted) setState(() => enviandoLink = false);
    }
  }

  Future<void> _carregarContexto() async {
    final c = client;
    final user = c?.auth.currentUser;

    if (c == null || user == null) {
      empresas = const [];
      empresaAtual = '';
      return;
    }

    try {
      await c.rpc('imperium_resgatar_convite');
    } catch (_) {
      // Sem convite pendente: segue usando os vínculos existentes.
    }

    empresas = await empresaService.listarEmpresasVinculadas();
    empresaAtual = (await AppDatabase.instance.empresaAtivaId) ?? '';

    final empresaAtualValida = empresas.any(
      (empresa) => '${empresa['empresa_id']}' == empresaAtual,
    );

    if (!empresaAtualValida) {
      empresaAtual = '';
    }

    if (empresaAtual.isEmpty && empresas.length == 1) {
      empresaAtual = '${empresas.first['empresa_id']}';
      await empresaService.trocarEmpresa(empresaAtual);
      empresas = await empresaService.listarEmpresasVinculadas();
    }

    if (empresas.isEmpty) {
      throw StateError(
        'Esta conta entrou no Supabase, mas não possui empresa ativa '
        'vinculada ao Imperium.',
      );
    }

    await analytics.identificar(user.id);
    await analytics.evento(
      'auth_context_ready',
      propriedades: {
        'company_count': empresas.length,
        'role': _papelEmpresaAtual(),
      },
    );
  }

  String _papelEmpresaAtual() {
    for (final empresa in empresas) {
      if ('${empresa['empresa_id']}' == empresaAtual) {
        return '${empresa['papel'] ?? 'desconhecido'}';
      }
    }
    return 'desconhecido';
  }

  Future<void> _trocarEmpresa(String id) async {
    if (id.isEmpty || id == empresaAtual) return;

    setState(() => carregando = true);
    try {
      await empresaService.trocarEmpresa(id);
      await _carregarContexto();
      await analytics.evento(
        'company_switched',
        propriedades: {'role': _papelEmpresaAtual()},
      );
    } catch (e, stack) {
      unawaited(
        analytics.registrarErro(
          area: 'company_switch',
          error: e,
          stackTrace: stack,
        ),
      );
      erro = _textoErro(e);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _sair() async {
    await analytics.evento('auth_signed_out');
    await client?.auth.signOut();
    await analytics.limparIdentidade();
    if (!mounted) return;

    setState(() {
      usuario = null;
      empresas = const [];
      empresaAtual = '';
      linkEnviado = false;
      mensagem = null;
      erro = null;
    });
  }

  String _textoErro(Object e) {
    var texto = e.toString().trim();

    for (final prefixo in const [
      'AuthException: ',
      'PostgrestException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    final lower = texto.toLowerCase();

    if (lower.contains('email rate limit') ||
        lower.contains('over_email_send_rate_limit') ||
        lower.contains('429')) {
      return 'Muitos links foram solicitados. Aguarde alguns minutos e '
          'envie somente um novo Magic Link.';
    }

    if (lower.contains('user not found') ||
        lower.contains('signups not allowed') ||
        lower.contains('invalid login credentials')) {
      return 'Este e-mail ainda não está liberado para entrar no Imperium.';
    }

    return texto.isEmpty ? 'Falha ao acessar o Imperium.' : texto;
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (usuario == null) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_done_outlined, size: 58),
                      const SizedBox(height: 16),
                      const Text(
                        'Imperium Manager Web',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Entre com o mesmo e-mail da sua conta na nuvem. '
                        'Não é necessária senha.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _enviarMagicLink(),
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (mensagem != null) ...[
                        const SizedBox(height: 14),
                        Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.mark_email_read_outlined),
                                const SizedBox(width: 10),
                                Expanded(child: Text(mensagem!)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (erro != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          erro!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: enviandoLink ? null : _enviarMagicLink,
                          icon: enviandoLink
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.mark_email_read_outlined),
                          label: Text(
                            enviandoLink
                                ? 'Enviando...'
                                : linkEnviado
                                    ? 'Enviar novo link'
                                    : 'Enviar link de acesso',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Retorno seguro: $_redirectUrl',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (empresaAtual.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Selecione a empresa'),
          actions: [
            TextButton.icon(
              onPressed: _sair,
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (erro != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ...empresas.map(
              (e) => Card(
                child: ListTile(
                  leading: const Icon(Icons.business),
                  title: Text('${e['nome'] ?? 'Empresa'}'),
                  subtitle: Text('Papel: ${e['papel'] ?? '-'}'),
                  trailing: FilledButton(
                    onPressed: () => _trocarEmpresa('${e['empresa_id']}'),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return WebOperacionalShell(
      key: ValueKey('tenant-$empresaAtual'),
      usuarioEmail: usuario?.email ?? usuario?.id ?? '',
      empresas: empresas,
      empresaAtualId: empresaAtual,
      onTrocarEmpresa: _trocarEmpresa,
      onSair: _sair,
    );
  }
}
