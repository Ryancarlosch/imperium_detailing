import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'services/empresa_cloud_service.dart';
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
          if (!mounted) return;
          setState(() {
            erro = _textoErro(e);
            carregando = false;
          });
        },
      );
    } catch (e) {
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
    } catch (e) {
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

      if (!mounted) return;

      setState(() {
        linkEnviado = true;
        mensagem =
            'Link enviado para $destino. Abra somente o link mais recente. '
            'Depois da confirmação você voltará automaticamente para o '
            'Imperium Manager Web.';
      });
    } catch (e) {
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
  }

  Future<void> _trocarEmpresa(String id) async {
    if (id.isEmpty || id == empresaAtual) return;

    setState(() => carregando = true);
    try {
      await empresaService.trocarEmpresa(id);
      await _carregarContexto();
    } catch (e) {
      erro = _textoErro(e);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _sair() async {
    await client?.auth.signOut();
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

  Widget _carregando() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(compacto: true),
            SizedBox(height: 22),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Preparando seu ambiente...'),
          ],
        ),
      ),
    );
  }

  Widget _login() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.70, -0.65),
            radius: 1.15,
            colors: [Color(0xFF242014), ImperiumWebTheme.background],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 56 : 22,
                    vertical: 30,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: desktop
                        ? Row(
                            children: [
                              const Expanded(child: _LoginHero()),
                              const SizedBox(width: 64),
                              SizedBox(width: 430, child: _loginCard()),
                            ],
                          )
                        : _loginCard(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: ImperiumWebTheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _BrandMark(compacto: true),
            ),
            const SizedBox(height: 28),
            Text(
              'Acesse sua operação',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Use o mesmo e-mail da sua conta Imperium. Enviaremos um link seguro, sem senha.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFADB6C0),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _enviarMagicLink(),
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'voce@empresa.com.br',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            if (mensagem != null) ...[
              const SizedBox(height: 14),
              _AvisoLogin(
                icon: Icons.mark_email_read_outlined,
                texto: mensagem!,
                destaque: true,
              ),
            ],
            if (erro != null) ...[
              const SizedBox(height: 14),
              _AvisoLogin(
                icon: Icons.error_outline_rounded,
                texto: erro!,
                erro: true,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: enviandoLink ? null : _enviarMagicLink,
              icon: enviandoLink
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(
                enviandoLink
                    ? 'Enviando...'
                    : linkEnviado
                    ? 'Enviar novo link'
                    : 'Entrar com link seguro',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Supabase Auth · empresa e permissões preservadas',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8F9AA5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seletorEmpresa() {
    return Scaffold(
      appBar: AppBar(
        title: const _BrandMark(compacto: true),
        actions: [
          TextButton.icon(
            onPressed: _sair,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sair'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
            children: [
              Text(
                'Qual empresa você quer abrir?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cada ambiente permanece isolado por empresa. Você pode trocar novamente pelo menu superior.',
              ),
              const SizedBox(height: 24),
              if (erro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AvisoLogin(
                    icon: Icons.error_outline_rounded,
                    texto: erro!,
                    erro: true,
                  ),
                ),
              ...empresas.map((e) {
                final nome = '${e['nome'] ?? 'Empresa'}';
                final papel = '${e['papel'] ?? '-'}';
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _trocarEmpresa('${e['empresa_id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: ImperiumWebTheme.accentStrong.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.business_rounded),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Perfil de acesso: $papel'),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 17),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) return _carregando();
    if (usuario == null) return _login();
    if (empresaAtual.isEmpty) return _seletorEmpresa();

    return WebWorkspaceShell(
      key: ValueKey('tenant-$empresaAtual'),
      usuarioEmail: usuario?.email ?? usuario?.id ?? '',
      empresas: empresas,
      empresaAtualId: empresaAtual,
      onTrocarEmpresa: _trocarEmpresa,
      onSair: _sair,
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compacto ? 40 : 52,
          height: compacto ? 40 : 52,
          decoration: BoxDecoration(
            color: ImperiumWebTheme.accentStrong,
            borderRadius: BorderRadius.circular(compacto ? 12 : 16),
          ),
          child: Icon(
            Icons.auto_awesome_mosaic_rounded,
            color: const Color(0xFF241900),
            size: compacto ? 23 : 30,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IMPERIUM',
              style: TextStyle(
                fontSize: compacto ? 15 : 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'MANAGER',
              style: TextStyle(
                fontSize: compacto ? 10 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
                color: ImperiumWebTheme.accentStrong,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w900,
      height: 1.08,
      letterSpacing: -1.2,
    );

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(compacto: false),
          const SizedBox(height: 52),
          Text('Sua empresa inteira,\nem um único painel.', style: title),
          const SizedBox(height: 18),
          Text(
            'Operação, clientes, ordens de serviço, estoque, financeiro, CRM e gestão conectados à mesma nuvem do aplicativo.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFB7C0CA),
              height: 1.55,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 34),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeatureChip(icon: Icons.sync_rounded, label: 'Android + Web'),
              _FeatureChip(icon: Icons.security_rounded, label: 'Multiempresa'),
              _FeatureChip(
                icon: Icons.cloud_done_rounded,
                label: 'Supabase Cloud',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ImperiumWebTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ImperiumWebTheme.accentStrong),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AvisoLogin extends StatelessWidget {
  const _AvisoLogin({
    required this.icon,
    required this.texto,
    this.erro = false,
    this.destaque = false,
  });

  final IconData icon;
  final String texto;
  final bool erro;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final cor = erro
        ? Theme.of(context).colorScheme.error
        : destaque
        ? ImperiumWebTheme.accentStrong
        : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
