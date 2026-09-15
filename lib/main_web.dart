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
  final TextEditingController confirmarCadastro = TextEditingController();
  final TextEditingController novaSenha = TextEditingController();
  final TextEditingController confirmarNovaSenha = TextEditingController();

  final EmpresaCloudService empresaService = EmpresaCloudService.instance;
  final ImperiumAuthService auth = ImperiumAuthService.instance;

  StreamSubscription<AuthState>? _authSubscription;

  bool carregando = true;
  bool processando = false;
  bool enviandoRecuperacao = false;
  bool definindoSenha = false;
  bool salvandoNovaSenha = false;
  bool modoPrimeiroAcesso = false;
  bool ocultarSenha = true;
  bool ocultarConfirmacao = true;
  bool ocultarNovaSenha = true;
  bool ocultarConfirmacaoNova = true;

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
    confirmarCadastro.dispose();
    novaSenha.dispose();
    confirmarNovaSenha.dispose();
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
    if (processando || enviandoRecuperacao) return;

    setState(() {
      processando = true;
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
      confirmarCadastro.clear();
      await _carregarContexto();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => processando = false);
    }
  }

  Future<void> _criarContaEmpresa() async {
    if (processando || enviandoRecuperacao) return;

    final senhaDigitada = senha.text.trim();
    final confirmacao = confirmarCadastro.text.trim();

    if (senhaDigitada.length < 8) {
      setState(() {
        erro = 'A senha deve ter pelo menos 8 caracteres.';
        mensagem = null;
      });
      return;
    }

    if (senhaDigitada != confirmacao) {
      setState(() {
        erro = 'As senhas informadas são diferentes.';
        mensagem = null;
      });
      return;
    }

    setState(() {
      processando = true;
      erro = null;
      mensagem = null;
    });

    try {
      final resposta = await auth.criarContaComEmailSenha(
        email: email.text,
        senha: senhaDigitada,
      );

      usuario = resposta.user ?? client?.auth.currentUser;
      final possuiSessao = resposta.session != null || auth.autenticado;

      if (!possuiSessao) {
        if (!mounted) return;
        setState(() {
          mensagem =
              'Conta criada. Confirme o e-mail recebido e depois entre com '
              'o mesmo e-mail e senha para ativar sua empresa.';
          modoPrimeiroAcesso = false;
          confirmarCadastro.clear();
        });
        return;
      }

      await _carregarContexto();
    } catch (e) {
      if (!mounted) return;
      setState(() => erro = auth.textoErro(e));
    } finally {
      if (mounted) setState(() => processando = false);
    }
  }

  Future<void> _enviarRecuperacaoSenha() async {
    if (processando || enviandoRecuperacao) return;

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
    final confirmacao = confirmarNovaSenha.text.trim();

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
        confirmarNovaSenha.clear();
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

    Object? erroResgate;
    try {
      await c.rpc('imperium_resgatar_convite');
    } catch (e) {
      erroResgate = e;
    }

    final vinculadas = await empresaService.listarEmpresasVinculadas();
    var atual = (await AppDatabase.instance.empresaAtivaId ?? '').trim();

    final atualValida = vinculadas.any(
      (empresa) => (empresa['empresa_id'] ?? '').toString() == atual,
    );

    if (!atualValida) atual = '';

    if (vinculadas.isEmpty) {
      if (erroResgate != null) {
        throw StateError(
          'Não foi possível ativar sua empresa agora. Confira se está usando '
          'o mesmo e-mail da assinatura ou do convite e tente novamente.',
        );
      }

      throw StateError(
        'Nenhuma empresa ativa foi encontrada para este e-mail. Use o mesmo '
        'e-mail informado na assinatura ou no convite do Imperium e confirme '
        'se a licença da empresa está ativa.',
      );
    }

    if (atual.isEmpty && vinculadas.length == 1) {
      atual = (vinculadas.first['empresa_id'] ?? '').toString();
      if (atual.isNotEmpty) {
        await empresaService.trocarEmpresa(atual);
      }
    }

    if (!mounted) return;
    setState(() {
      usuario = user;
      empresas = vinculadas;
      empresaAtual = atual;
      erro = null;
      mensagem = null;
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
          modoPrimeiroAcesso = false;
          senha.clear();
          confirmarCadastro.clear();
        });
      }
    }
  }

  void _alternarPrimeiroAcesso(bool valor) {
    if (processando || enviandoRecuperacao) return;
    setState(() {
      modoPrimeiroAcesso = valor;
      erro = null;
      mensagem = null;
      senha.clear();
      confirmarCadastro.clear();
    });
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

  Widget _fundoAutenticacao(Widget child) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.72, -0.68),
            radius: 1.18,
            colors: [Color(0xFF242014), ImperiumWebTheme.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _login() {
    return _fundoAutenticacao(
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = MediaQuery.sizeOf(context).width >= 900;

            if (!desktop) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _loginCard(),
              );
            }

            return Row(
              children: [
                const Expanded(child: _LoginHero()),
                const SizedBox(width: 64),
                SizedBox(width: 430, child: _loginCard()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _loginCard() {
    final titulo = modoPrimeiroAcesso
        ? 'Ative sua empresa'
        : 'Acesse sua operação';
    final subtitulo = modoPrimeiroAcesso
        ? 'Use o e-mail informado na assinatura ou no convite e crie a senha que será usada no Web e no aplicativo.'
        : 'Use o mesmo e-mail e senha no Imperium Web e no aplicativo.';

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
              titulo,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
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
              enabled: !processando && !enviandoRecuperacao,
              decoration: const InputDecoration(
                labelText: 'E-mail da empresa',
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
              textInputAction: modoPrimeiroAcesso
                  ? TextInputAction.next
                  : TextInputAction.done,
              enabled: !processando && !enviandoRecuperacao,
              onSubmitted: modoPrimeiroAcesso ? null : (_) => _entrar(),
              decoration: InputDecoration(
                labelText: modoPrimeiroAcesso ? 'Criar senha' : 'Senha',
                helperText: modoPrimeiroAcesso ? 'Mínimo de 8 caracteres' : null,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: processando
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
            if (modoPrimeiroAcesso) ...[
              const SizedBox(height: 14),
              TextField(
                controller: confirmarCadastro,
                obscureText: ocultarConfirmacao,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                enabled: !processando,
                onSubmitted: (_) => _criarContaEmpresa(),
                decoration: InputDecoration(
                  labelText: 'Confirmar senha',
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  suffixIcon: IconButton(
                    tooltip: ocultarConfirmacao
                        ? 'Mostrar confirmação'
                        : 'Ocultar confirmação',
                    onPressed: processando
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
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: processando || enviandoRecuperacao
                      ? null
                      : _enviarRecuperacaoSenha,
                  child: Text(
                    enviandoRecuperacao
                        ? 'Enviando...'
                        : 'Esqueci minha senha',
                  ),
                ),
              ),
            if (mensagem != null) ...[
              const SizedBox(height: 10),
              _AvisoLogin(
                icon: Icons.check_circle_outline_rounded,
                texto: mensagem!,
                destaque: true,
              ),
            ],
            if (erro != null) ...[
              const SizedBox(height: 10),
              _AvisoLogin(
                icon: Icons.error_outline_rounded,
                texto: erro!,
                erro: true,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: processando || enviandoRecuperacao
                  ? null
                  : modoPrimeiroAcesso
                  ? _criarContaEmpresa
                  : _entrar,
              icon: processando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      modoPrimeiroAcesso
                          ? Icons.business_center_outlined
                          : Icons.login_rounded,
                    ),
              label: Text(
                processando
                    ? 'Aguarde...'
                    : modoPrimeiroAcesso
                    ? 'Criar conta e ativar empresa'
                    : 'Entrar na empresa',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: processando
                  ? null
                  : () => _alternarPrimeiroAcesso(!modoPrimeiroAcesso),
              icon: Icon(
                modoPrimeiroAcesso
                    ? Icons.login_rounded
                    : Icons.add_business_outlined,
              ),
              label: Text(
                modoPrimeiroAcesso
                    ? 'Já tenho acesso'
                    : 'Primeiro acesso da empresa',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Funcionários são cadastrados dentro da empresa pelo administrador; não precisam criar outra conta de empresa.',
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
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
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
                  controller: confirmarNovaSenha,
                  obscureText: ocultarConfirmacaoNova,
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
                              () => ocultarConfirmacaoNova =
                                  !ocultarConfirmacaoNova,
                            ),
                      icon: Icon(
                        ocultarConfirmacaoNova
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
                'Cada ambiente permanece isolado por empresa. Somente empresas em que você é administrador ou proprietário aparecem aqui.',
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

  @override
  Widget build(BuildContext context) {
    if (carregando) return _carregando();
    if (definindoSenha) return _redefinirSenha();
    if (usuario == null) return _login();
    if (empresaAtual.isEmpty) return _seletorEmpresa();

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          const SizedBox(height: 38),
          Text(
            'Sua empresa inteira,\nem um só lugar.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.04,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Operação, clientes, agenda, financeiro, equipe e indicadores conectados ao mesmo ambiente da sua empresa.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFADB6C0),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroChip(icon: Icons.cloud_done_outlined, texto: 'Web + App'),
              _HeroChip(
                icon: Icons.business_outlined,
                texto: 'Multiempresa',
              ),
              _HeroChip(
                icon: Icons.lock_outline_rounded,
                texto: 'Acesso seguro',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: ImperiumWebTheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ImperiumWebTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: ImperiumWebTheme.accentStrong),
          const SizedBox(width: 7),
          Text(texto, style: const TextStyle(fontWeight: FontWeight.w700)),
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
        ? const Color(0xFFFFB4AB)
        : destaque
        ? const Color(0xFFC8E6C9)
        : const Color(0xFFADB6C0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: cor, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
