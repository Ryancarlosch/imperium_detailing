import 'package:flutter/material.dart';

import '../services/cloud_session_service.dart';
import '../services/imperium_auth_service.dart';
import '../services/supabase_bootstrap.dart';
import 'empresa_primeiro_acesso_page.dart';

class LoginEmailSenhaPage extends StatefulWidget {
  const LoginEmailSenhaPage({super.key, required this.onLogin});

  final ValueChanged<Map<String, dynamic>> onLogin;

  @override
  State<LoginEmailSenhaPage> createState() => _LoginEmailSenhaPageState();
}

class _LoginEmailSenhaPageState extends State<LoginEmailSenhaPage> {
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

  Future<void> _recuperarSenha() async {
    if (_carregando || _enviandoRecuperacao) return;

    setState(() {
      _enviandoRecuperacao = true;
      _erro = null;
      _mensagem = null;
    });

    try {
      await _auth.enviarRecuperacaoSenha(email: _email.text);

      if (!mounted) return;
      setState(() {
        _mensagem =
            'Enviamos um e-mail para você definir uma nova senha. Abra o link, escolha a senha e depois volte para entrar no aplicativo.';
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

  Widget _seletorEmpresa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.business_rounded, size: 52),
        const SizedBox(height: 18),
        Text(
          'Escolha a empresa',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sua conta possui acesso a mais de uma empresa.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        ..._empresasParaEscolher.map((empresa) {
          final id = (empresa['empresa_id'] ?? '').toString();
          final nome = (empresa['nome'] ?? 'Empresa').toString();
          final papel = (empresa['papel'] ?? '').toString();

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: _carregando ? null : () => _selecionarEmpresa(id),
              icon: const Icon(Icons.domain_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome),
                    if (papel.isNotEmpty)
                      Text(
                        papel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (_erro != null) ...[
          const SizedBox(height: 8),
          Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _carregando ? null : _trocarConta,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Entrar com outra conta'),
        ),
      ],
    );
  }

  Widget _formularioLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.directions_car_filled_rounded, size: 72),
        const SizedBox(height: 18),
        Text(
          'Imperium Manager',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Use o mesmo e-mail e senha no aplicativo e na Web.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _email,
          enabled: !_carregando && !_enviandoRecuperacao,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.alternate_email_rounded),
            border: OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: 'Senha',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: _carregando
                  ? null
                  : () => setState(() => _ocultarSenha = !_ocultarSenha),
              icon: Icon(
                _ocultarSenha
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
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
            child: Text(
              _enviandoRecuperacao ? 'Enviando...' : 'Esqueci minha senha',
            ),
          ),
        ),
        if (_mensagem != null) ...[
          const SizedBox(height: 6),
          Text(
            _mensagem!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.greenAccent),
          ),
        ],
        if (_erro != null) ...[
          const SizedBox(height: 6),
          Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _carregando || _enviandoRecuperacao ? null : _entrar,
            icon: _carregando
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_carregando ? 'Entrando...' : 'Entrar'),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Acesso da empresa',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _carregando ? null : _abrirPrimeiroAcessoEmpresa,
          icon: const Icon(Icons.business_outlined),
          label: const Text('Ativar empresa existente'),
        ),
        const SizedBox(height: 14),
        Text(
          'Funcionário: seu acesso é criado pelo administrador da empresa. Depois de definir sua senha pelo e-mail recebido, entre normalmente acima.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restaurando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Verificando sua conta...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _empresasParaEscolher.isNotEmpty
                      ? _seletorEmpresa()
                      : _formularioLogin(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
