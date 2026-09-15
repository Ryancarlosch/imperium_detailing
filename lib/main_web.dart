import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
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
  final TextEditingController email = TextEditingController();
  final TextEditingController senha = TextEditingController();
  final TextEditingController novaSenha = TextEditingController();
  final TextEditingController confirmarSenha = TextEditingController();

  final EmpresaCloudService empresaService = EmpresaCloudService.instance;
  final ImperiumAuthService auth = ImperiumAuthService.instance;

  StreamSubscription<AuthState>? _authSubscription;

  bool carregando = true;
  bool entrando = false;
  bool enviandoRecuperacao = false;
  bool definindoSenha = false;
  bool salvandoNovaSenha = false;
  bool ocultarSenha = true;
  bool ocultarNovaSenha = true;
  bool ocultarConfirmacao = true;
  String? erro;
  String? mensagem;
  User? usuario;
  List<Map<String, dynamic>> empresas = const [];
  String empresaAtual = '';

  SupabaseClient? get client => SupabaseBootstrap.client;

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
    email.dispose();
    senha.dispose();
    novaSenha.dispose();
    confirmarSenha.dispose();
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
      final emailAtual = (usuario?.email ?? '').trim().toLowerCase();
      if (emailAtual.isNotEmpty) email.text = emailAtual;

      if (usuario != null && _urlRecuperacao) {
        definindoSenha = true;
        mensagem = 'Crie uma nova senha para concluir o acesso.';
      } else if (usuario != null) {
        await _carregarContexto();
      }

      _authSubscription = c.auth.onAuthStateChange.listen(
        (estado) {
          if (!mounted) return;

          final novoUsuario = estado.session?.user ?? c.auth.currentUser;

          if (estado.event == AuthChangeEvent.passwordRecovery &&
              novoUsuario != null) {
            setState(() {
              usuario = novoUsuario;
              definindoSenha = true;
              empresas = const [];
              empresaAtual = '';
              erro = null;
              mensagem = 'Crie uma nova senha para concluir o acesso.';
              carregando = false;
            });
            return;
          }

          if (novoUsuario == null) {
            setState(() {
              usuario = null;
              empresas = const [];
              empresaAtual = '';
              definindoSenha = false;
              erro = null;
              mensagem = null;
              carregando = false;
            });
            return;
          }

          usuario = novoUsuario;
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            erro = auth.textoErro(e);
            carregando = false;
          });
        },
      );
    } catch (e) {
      erro = auth.textoErro(e);
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _entrar() async {
    if (entrando) return;

    setState(() {
      entrando = true;
      erro = null;
      mensagem = null;
    });

    try {
      final user = await auth.entrarComEmailSenha(
        email: email.text,
        senha: senha.text,
      );

      usuario = user;
      senha.clear();
      await _carregarContexto();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => entrando = false);
    }
  }

  Future<void> _enviarRecuperacaoSenha() async {
    if (enviandoRecuperacao) return;

    setState(() {
      enviandoRecuperacao = true;
      erro = null;
      mensagem = null;
    });

    try {
      await auth.enviarRecuperacaoSenha(
        email: email.text,
        redirectTo: '${Uri.base.origin}/',
      );

      if (!mounted) return;
      setState(() {
        mensagem =
            'Enviamos um e-mail para você definir uma nova senha. Abra somente o link mais recente.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => enviandoRecuperacao = false);
    }
  }

  Future<void> _salvarNovaSenha() async {
    if (salvandoNovaSenha) return;

    final senhaNova = novaSenha.text.trim();
    final confirmacao = confirmarSenha.text.trim();

    if (senhaNova.length < 8) {
      setState(() {
        erro = 'A senha deve ter pelo menos 8 caracteres.';
        mensagem = null;
      });
      return;
    }

    if (senhaNova != confirmacao) {
      setState(() {
        erro = 'As senhas informadas são diferentes.';
        mensagem = null;
      });
      return;
    }

    setState(() {
      salvandoNovaSenha = true;
      erro = null;
      mensagem = null;
    });

    try {
      final user = await auth.definirNovaSenha(senhaNova);

      if (!mounted) return;
      setState(() {
        usuario = user;
        definindoSenha = false;
        novaSenha.clear();
        confirmarSenha.clear();
        mensagem = 'Senha definida com sucesso.';
      });

      await _carregarContexto();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => salvandoNovaSenha = false);
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
      // Sem convite pendente: usa os vínculos já existentes.
    }

    final vinculadas = await empresaService.listarEmpresasVinculadas();
    var atual = (await AppDatabase.instance.empresaAtivaId ?? '').trim();

    final atualValida = vinculadas.any(
      (empresa) => (empresa['empresa_id'] ?? '').toString() == atual,
    );

    if (!atualValida) atual = '';

    if (atual.isEmpty && vinculadas.length == 1) {
      atual = (vinculadas.first['empresa_id'] ?? '').toString();
      if (atual.isNotEmpty) {
        await empresaService.trocarEmpresa(atual);
      }
    }

    if (vinculadas.isEmpty) {
      throw StateError(
        'Esta conta entrou no Imperium, mas ainda não possui uma empresa ativa vinculada.',
      );
    }

    if (!mounted) return;
    setState(() {
      usuario = user;
      empresas = vinculadas;
      empresaAtual = atual;
      erro = null;
    });
  }

  Future<void> _trocarEmpresa(String id) async {
    if (id.isEmpty || id == empresaAtual) return;

    setState(() {
      carregando = true;
      erro = null;
    });

    try {
      await empresaService.trocarEmpresa(id);
      await _carregarContexto();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _sair() async {
    try {
      await auth.sair();
    } finally {
      if (mounted) {
        setState(() {
          usuario = null;
          empresas = const [];
          empresaAtual = '';
          erro = null;
          mensagem = null;
          senha.clear();
        });
      }
    }
  }

  String get _papelAtual {
    for (final empresa in empresas) {
      if ((empresa['empresa_id'] ?? '').toString() == empresaAtual) {
        return (empresa['papel'] ?? '').toString().trim().toLowerCase();
      }
    }
    return '';
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

  Widget _fundoAutenticacao(Widget card) {
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: card,
              ),
            ),
          ),
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
                    constraints: const BoxConstraints(maxWidth: 1120),
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
      color: ImperiumWebTheme.surface.withValues(alpha: 0.96),
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
              'Use o mesmo e-mail e senha no Imperium Web e no aplicativo.',
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
              textInputAction: TextInputAction.next,
              enabled: !entrando && !enviandoRecuperacao,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'voce@empresa.com.br',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: senha,
              obscureText: ocultarSenha,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              enabled: !entrando && !enviandoRecuperacao,
              onSubmitted: (_) => _entrar(),
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: entrando
                      ? null
                      : () => setState(() => ocultarSenha = !ocultarSenha),
                  icon: Icon(
                    ocultarSenha
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: entrando || enviandoRecuperacao
                    ? null
                    : _enviarRecuperacaoSenha,
                child: Text(
                  enviandoRecuperacao ? 'Enviando...' : 'Esqueci minha senha',
                ),
              ),
            ),
            if (mensagem != null) ...[
              const SizedBox(height: 6),
              _AvisoLogin(
                icon: Icons.check_circle_outline_rounded,
                texto: mensagem!,
                destaque: true,
              ),
            ],
            if (erro != null) ...[
              const SizedBox(height: 6),
              _AvisoLogin(
                icon: Icons.error_outline_rounded,
                texto: erro!,
                erro: true,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: entrando || enviandoRecuperacao ? null : _entrar,
              icon: entrando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(entrando ? 'Entrando...' : 'Entrar'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Supabase Auth · empresa, licença e permissões preservadas',
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

  Widget _redefinirSenha() {
    return _fundoAutenticacao(
      Card(
        margin: EdgeInsets.zero,
        color: ImperiumWebTheme.surface.withValues(alpha: 0.96),
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
              const SizedBox(height: 26),
              Text(
                'Defina sua senha',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use pelo menos 8 caracteres. Essa senha será a mesma no Web e no aplicativo.',
              ),
              const SizedBox(height: 22),
              TextField(
                controller: novaSenha,
                obscureText: ocultarNovaSenha,
                enabled: !salvandoNovaSenha,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nova senha',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    onPressed: salvandoNovaSenha
                        ? null
                        : () => setState(
                            () => ocultarNovaSenha = !ocultarNovaSenha,
                          ),
                    icon: Icon(
                      ocultarNovaSenha
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmarSenha,
                obscureText: ocultarConfirmacao,
                enabled: !salvandoNovaSenha,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _salvarNovaSenha(),
                decoration: InputDecoration(
                  labelText: 'Confirmar nova senha',
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  suffixIcon: IconButton(
                    onPressed: salvandoNovaSenha
                        ? null
                        : () => setState(
                            () => ocultarConfirmacao = !ocultarConfirmacao,
                          ),
                    icon: Icon(
                      ocultarConfirmacao
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (mensagem != null) ...[
                const SizedBox(height: 14),
                _AvisoLogin(
                  icon: Icons.info_outline_rounded,
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
                onPressed: salvandoNovaSenha ? null : _salvarNovaSenha,
                icon: salvandoNovaSenha
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  salvandoNovaSenha ? 'Salvando...' : 'Salvar nova senha',
                ),
              ),
            ],
          ),
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
                'Cada ambiente permanece isolado por empresa. Seu perfil é aplicado automaticamente.',
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
              ...empresas.map((empresa) {
                final nome = (empresa['nome'] ?? 'Empresa').toString();
                final papel = (empresa['papel'] ?? '-').toString();
                final id = (empresa['empresa_id'] ?? '').toString();

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: id.isEmpty ? null : () => _trocarEmpresa(id),
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
                                Text('Perfil: $papel'),
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

  Widget _funcionarioWebBloqueado() {
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined, size: 54),
                    const SizedBox(height: 18),
                    Text(
                      'Acesso de funcionário',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sua conta pertence à equipe desta empresa. Nesta etapa, o acesso operacional do funcionário continua no aplicativo móvel, com as permissões definidas pelo administrador.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (empresas.length > 1)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => empresaAtual = ''),
                        icon: const Icon(Icons.business_outlined),
                        label: const Text('Trocar empresa'),
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

  @override
  Widget build(BuildContext context) {
    if (carregando) return _carregando();
    if (definindoSenha) return _redefinirSenha();
    if (usuario == null) return _login();
    if (empresaAtual.isEmpty) return _seletorEmpresa();
    if (_papelAtual == 'funcionario') return _funcionarioWebBloqueado();

    return WebWorkspaceShell(
      usuarioEmail: (usuario?.email ?? '').trim(),
      empresas: empresas,
      empresaAtualId: empresaAtual,
      onTrocarEmpresa: _trocarEmpresa,
      onSair: _sair,
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compacto = false});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compacto ? 38 : 48,
          height: compacto ? 38 : 48,
          decoration: BoxDecoration(
            color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compacto ? 12 : 15),
            border: Border.all(color: ImperiumWebTheme.border),
          ),
          child: const Icon(
            Icons.auto_awesome_mosaic_outlined,
            color: ImperiumWebTheme.accentStrong,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compacto ? 'Imperium' : 'Imperium Manager',
              style: TextStyle(
                fontSize: compacto ? 16 : 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            if (!compacto)
              const Text(
                'Gestão automotiva',
                style: TextStyle(
                  color: Color(0xFF8F9AA5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BrandMark(),
        SizedBox(height: 34),
        Text(
          'Sua operação inteira,\nem um único acesso.',
          style: TextStyle(
            fontSize: 42,
            height: 1.08,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.3,
          ),
        ),
        SizedBox(height: 18),
        SizedBox(
          width: 540,
          child: Text(
            'Entre com e-mail e senha no navegador ou no celular. A empresa, o plano e as permissões são resolvidos automaticamente.',
            style: TextStyle(
              color: Color(0xFFADB6C0),
              fontSize: 17,
              height: 1.55,
            ),
          ),
        ),
      ],
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
        ? const Color(0xFFFF8C8C)
        : destaque
        ? ImperiumWebTheme.accentStrong
        : const Color(0xFFADB6C0);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cor, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: TextStyle(color: cor, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
