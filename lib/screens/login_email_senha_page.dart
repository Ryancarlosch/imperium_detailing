import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/imperium_app_links.dart';
import '../services/cloud_session_service.dart';
import '../services/imperium_auth_service.dart';
import '../services/supabase_bootstrap.dart';
import '../web/imperium_web_theme.dart';
import 'empresa_primeiro_acesso_page.dart';

class LoginEmailSenhaPage extends StatefulWidget {
  const LoginEmailSenhaPage({super.key, required this.onLogin});

  final ValueChanged<Map<String, dynamic>> onLogin;

  @override
  State<LoginEmailSenhaPage> createState() => _LoginEmailSenhaPageState();
}

class _LoginEmailSenhaPageState extends State<LoginEmailSenhaPage> {
  static const _gold = Color(0xFFFFC857);
  static const _goldSoft = Color(0xFFF2B84B);
  static const _background = Color(0xFF07090C);
  static const _surface = Color(0xFF101419);
  static const _surfaceRaised = Color(0xFF171C22);
  static const _border = Color(0xFF2A313A);
  static const _text = Color(0xFFF5F6F8);
  static const _muted = Color(0xFF9CA5AF);

  final TextEditingController _email = TextEditingController();
  final TextEditingController _senha = TextEditingController();

  final ImperiumAuthService _auth = ImperiumAuthService.instance;
  final CloudSessionService _cloudSession = CloudSessionService.instance;

  bool _carregando = false;
  bool _restaurando = true;
  bool _enviandoRecuperacao = false;
  bool _ocultarSenha = true;
  String? _erro;
  String? _mensagem;
  List<Map<String, dynamic>> _empresasParaEscolher = const [];

  @override
  void initState() {
    super.initState();
    _restaurarContaConectada();
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _restaurarContaConectada() async {
    try {
      final usuario = SupabaseBootstrap.client?.auth.currentUser;
      final email = (usuario?.email ?? '').trim().toLowerCase();
      if (email.isNotEmpty) {
        _email.text = email;
        await _abrirContexto();
      }
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _restaurando = false);
    }
  }

  Future<void> _entrar() async {
    if (_carregando || _enviandoRecuperacao) return;

    final email = _email.text.trim().toLowerCase();
    final senha = _senha.text;

    setState(() {
      _carregando = true;
      _erro = null;
      _mensagem = null;
      _empresasParaEscolher = const [];
    });

    try {
      await _auth.entrarComEmailSenha(email: email, senha: senha);
      await _abrirContexto();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String get _redirectRecuperacaoSenha {
    if (kIsWeb) {
      final base = Uri.base;
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/',
      ).toString();
    }

    return ImperiumAppLinks.loginCallback;
  }

  Future<void> _recuperarSenha() async {
    if (_carregando || _enviandoRecuperacao) return;

    setState(() {
      _enviandoRecuperacao = true;
      _erro = null;
      _mensagem = null;
    });

    try {
      await _auth.enviarRecuperacaoSenha(
        email: _email.text,
        redirectTo: _redirectRecuperacaoSenha,
      );

      if (!mounted) return;
      setState(() {
        _mensagem = kIsWeb
            ? 'Enviamos um e-mail para você definir uma nova senha. Abra o link e conclua a troca no Imperium.'
            : 'Enviamos um e-mail para você definir uma nova senha. Abra o link neste celular; o Imperium será aberto para concluir a troca.';
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _enviandoRecuperacao = false);
    }
  }

  Future<void> _abrirContexto({String? empresaId}) async {
    try {
      final sessao = await _cloudSession.prepararSessao(empresaId: empresaId);
      if (!mounted) return;
      widget.onLogin(Map<String, dynamic>.from(sessao));
    } on SelecaoEmpresaNecessaria catch (selecao) {
      if (!mounted) return;
      setState(() {
        _empresasParaEscolher = selecao.empresas;
        _erro = null;
      });
    }
  }

  Future<void> _selecionarEmpresa(String empresaId) async {
    if (_carregando || empresaId.isEmpty) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      await _abrirContexto(empresaId: empresaId);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _trocarConta() async {
    if (_carregando) return;

    setState(() => _carregando = true);
    try {
      await _cloudSession.sair();
      if (!mounted) return;
      setState(() {
        _empresasParaEscolher = const [];
        _erro = null;
        _mensagem = null;
        _senha.clear();
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirPrimeiroAcessoEmpresa() async {
    final sessao = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const EmpresaPrimeiroAcessoPage()),
    );
    if (!mounted || sessao == null) return;
    widget.onLogin(Map<String, dynamic>.from(sessao));
  }

  Widget _logoImperium() {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F13),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _goldSoft, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.16),
            blurRadius: 28,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'M',
          style: TextStyle(
            color: _gold,
            fontSize: 40,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return SizedBox(
      height: 245,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF19150D),
                  Color(0xFF0B0E12),
                  Color(0xFF050608),
                ],
              ),
            ),
          ),
          Positioned(
            left: -70,
            top: -90,
            child: Transform.rotate(
              angle: 0.63,
              child: Container(
                width: 210,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.035),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -38,
            top: 26,
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 190,
              color: _gold.withValues(alpha: 0.055),
            ),
          ),
          Positioned(
            right: 28,
            top: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'GESTÃO',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.72),
                    fontSize: 9,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'QUE MOVE',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.72),
                    fontSize: 9,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'RESULTADOS',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.72),
                    fontSize: 9,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(width: 38, height: 2, color: _goldSoft),
              ],
            ),
          ),
          Positioned(
            left: 28,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VEÍCULOS  •  PESSOAS  •  PROCESSOS',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.62),
                    fontSize: 8,
                    letterSpacing: 2.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(width: 34, height: 2, color: _goldSoft),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.08),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _logoImperium(),
                const SizedBox(height: 16),
                const Text(
                  'IMPERIUM',
                  style: TextStyle(
                    color: _text,
                    fontSize: 25,
                    letterSpacing: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'MANAGER',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    letterSpacing: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF101419)],
                ),
              ),
              child: SizedBox(height: 42),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _goldSoft, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _border.withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _mensagens() {
    return Column(
      children: [
        if (_mensagem != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF153022),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF23553A)),
            ),
            child: Text(
              _mensagem!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9DDEB4)),
            ),
          ),
        ],
        if (_erro != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF311619),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF65262D)),
            ),
            child: Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFA3AD)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _divisorOu() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: _border)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OU',
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: _border)),
      ],
    );
  }

  Widget _seletorEmpresa(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _goldSoft.withValues(alpha: 0.55)),
              ),
              child: const Icon(Icons.business_rounded, color: _gold, size: 30),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Escolha a empresa',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seu e-mail possui acesso a mais de uma empresa.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 24),
          ..._empresasParaEscolher.map((empresa) {
            final id = (empresa['empresa_id'] ?? '').toString();
            final nome = (empresa['nome'] ?? 'Empresa').toString();
            final papel = (empresa['papel'] ?? '').toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: _carregando ? null : () => _selecionarEmpresa(id),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 62),
                  foregroundColor: _text,
                  side: const BorderSide(color: _border),
                  backgroundColor: _surfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.domain_outlined, color: _goldSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (papel.isNotEmpty)
                            Text(
                              papel,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ],
                ),
              ),
            );
          }),
          _mensagens(),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _carregando ? null : _trocarConta,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Entrar com outra conta'),
          ),
        ],
      ),
    );
  }

  Widget _formularioLogin(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Login',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Acesse sua empresa com seu e-mail e senha',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: _email,
            enabled: !_carregando && !_enviandoRecuperacao,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(color: _text),
            decoration: _inputDecoration(
              label: 'E-mail',
              icon: Icons.mail_outline_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _senha,
            enabled: !_carregando && !_enviandoRecuperacao,
            obscureText: _ocultarSenha,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _entrar(),
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            style: const TextStyle(color: _text),
            decoration: _inputDecoration(
              label: 'Senha',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                onPressed: _carregando
                    ? null
                    : () => setState(() => _ocultarSenha = !_ocultarSenha),
                icon: Icon(
                  _ocultarSenha
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _muted,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _carregando || _enviandoRecuperacao
                  ? null
                  : _recuperarSenha,
              style: TextButton.styleFrom(foregroundColor: _gold),
              child: Text(
                _enviandoRecuperacao ? 'Enviando...' : 'Esqueci minha senha',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          _mensagens(),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _carregando || _enviandoRecuperacao ? null : _entrar,
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF1B1300),
                disabledBackgroundColor: _gold.withValues(alpha: 0.35),
                disabledForegroundColor: const Color(0xFF1B1300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_carregando)
                    const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1B1300),
                      ),
                    )
                  else
                    const Icon(Icons.login_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(_carregando ? 'Entrando...' : 'Entrar na empresa'),
                  if (!_carregando) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _divisorOu(),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _carregando ? null : _abrirPrimeiroAcessoEmpresa,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _goldSoft, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.rocket_launch_outlined, size: 20),
              label: const Text(
                'Começar 30 dias grátis',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'Ainda não tem conta? ',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: _carregando ? null : _abrirPrimeiroAcessoEmpresa,
                child: const Text(
                  'Criar conta',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Container(width: 38, height: 2, color: _goldSoft),
                const SizedBox(height: 10),
                Text(
                  'MAIS QUE GESTÃO  •  MOVEMOS O SEU FUTURO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.58),
                    fontSize: 8.5,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartao(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: _gold.withValues(alpha: 0.045),
            blurRadius: 38,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _hero(),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: _empresasParaEscolher.isNotEmpty
                  ? _seletorEmpresa(context)
                  : _formularioLogin(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conteudo(BuildContext context) {
    if (_restaurando) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _gold),
              SizedBox(height: 14),
              Text('Verificando sua conta...', style: TextStyle(color: _muted)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          Positioned(
            top: -170,
            right: -120,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold.withValues(alpha: 0.035),
              ),
            ),
          ),
          Positioned(
            bottom: -210,
            left: -160,
            child: Container(
              width: 390,
              height: 390,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.018),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _cartao(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ImperiumWebTheme.dark(),
      child: Builder(builder: _conteudo),
    );
  }
}
