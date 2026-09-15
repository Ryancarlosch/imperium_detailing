import 'package:flutter/material.dart';

import '../services/cloud_session_service.dart';
import '../services/imperium_auth_service.dart';

class EmpresaPrimeiroAcessoPage extends StatefulWidget {
  const EmpresaPrimeiroAcessoPage({super.key});

  @override
  State<EmpresaPrimeiroAcessoPage> createState() =>
      _EmpresaPrimeiroAcessoPageState();
}

class _EmpresaPrimeiroAcessoPageState extends State<EmpresaPrimeiroAcessoPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _senha = TextEditingController();
  final TextEditingController _confirmarSenha = TextEditingController();

  final ImperiumAuthService _auth = ImperiumAuthService.instance;
  final CloudSessionService _cloudSession = CloudSessionService.instance;

  bool _carregando = false;
  bool _ocultarSenha = true;
  bool _ocultarConfirmacao = true;
  String? _erro;
  String? _mensagem;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _confirmarSenha.dispose();
    super.dispose();
  }

  Future<void> _criarContaEAtivar() async {
    if (_carregando) return;

    final email = _email.text.trim().toLowerCase();
    final senha = _senha.text.trim();
    final confirmar = _confirmarSenha.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _mostrarErro('Informe o mesmo e-mail usado na assinatura do Imperium.');
      return;
    }

    if (senha.length < 8) {
      _mostrarErro('A senha deve ter pelo menos 8 caracteres.');
      return;
    }

    if (senha != confirmar) {
      _mostrarErro('As senhas informadas são diferentes.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
      _mensagem = null;
    });

    try {
      final resposta = await _auth.criarContaComEmailSenha(
        email: email,
        senha: senha,
      );

      final possuiSessao = resposta.session != null || _auth.autenticado;
      if (!possuiSessao) {
        if (!mounted) return;
        setState(() {
          _mensagem =
              'Conta criada. Confirme o e-mail recebido. Depois volte e toque '
              'em “Já tenho senha • ativar minha assinatura”. O vínculo com '
              'a empresa será feito automaticamente.';
        });
        return;
      }

      await _abrirEmpresa();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _entrarEAtivar() async {
    if (_carregando) return;

    final email = _email.text.trim().toLowerCase();
    final senha = _senha.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _mostrarErro('Informe o mesmo e-mail usado na assinatura do Imperium.');
      return;
    }

    if (senha.isEmpty) {
      _mostrarErro('Informe sua senha.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
      _mensagem = null;
    });

    try {
      await _auth.entrarComEmailSenha(email: email, senha: senha);
      await _abrirEmpresa();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirEmpresa() async {
    try {
      final sessao = await _cloudSession.prepararSessao();
      if (!mounted) return;
      Navigator.of(context).pop<Map<String, dynamic>>(sessao);
    } on SelecaoEmpresaNecessaria {
      throw StateError(
        'Sua conta possui mais de uma empresa. Volte para a tela de login e '
        'escolha qual empresa deseja abrir.',
      );
    }
  }

  void _mostrarErro(String texto) {
    if (!mounted) return;
    setState(() {
      _erro = texto;
      _mensagem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ativar assinatura')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.workspace_premium_rounded, size: 58),
                      const SizedBox(height: 18),
                      Text(
                        'Ative sua assinatura do Imperium',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use exatamente o e-mail informado ao assinar o plano. '
                        'Depois da autenticação, sua empresa e sua licença são '
                        'vinculadas automaticamente. A mesma senha funciona no '
                        'aplicativo e na Web.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _email,
                        enabled: !_carregando,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'E-mail da assinatura',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _senha,
                        enabled: !_carregando,
                        obscureText: _ocultarSenha,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Criar senha',
                          helperText: 'Mínimo de 8 caracteres',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _ocultarSenha
                                ? 'Mostrar senha'
                                : 'Ocultar senha',
                            onPressed: _carregando
                                ? null
                                : () {
                                    setState(() {
                                      _ocultarSenha = !_ocultarSenha;
                                    });
                                  },
                            icon: Icon(
                              _ocultarSenha
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmarSenha,
                        enabled: !_carregando,
                        obscureText: _ocultarConfirmacao,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _criarContaEAtivar(),
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Confirmar senha',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _ocultarConfirmacao
                                ? 'Mostrar confirmação'
                                : 'Ocultar confirmação',
                            onPressed: _carregando
                                ? null
                                : () {
                                    setState(() {
                                      _ocultarConfirmacao =
                                          !_ocultarConfirmacao;
                                    });
                                  },
                            icon: Icon(
                              _ocultarConfirmacao
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_mensagem != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _mensagem!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.greenAccent),
                        ),
                      ],
                      if (_erro != null) ...[
                        const SizedBox(height: 16),
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
                          onPressed: _carregando ? null : _criarContaEAtivar,
                          icon: _carregando
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.workspace_premium_rounded),
                          label: Text(
                            _carregando
                                ? 'Ativando...'
                                : 'Criar senha e ativar assinatura',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _carregando ? null : _entrarEAtivar,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text(
                          'Já tenho senha • ativar minha assinatura',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text(
                        'Funcionários não assinam um plano separado. O acesso '
                        'deles é criado e administrado dentro da empresa pelo '
                        'administrador.',
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
      ),
    );
  }
}
