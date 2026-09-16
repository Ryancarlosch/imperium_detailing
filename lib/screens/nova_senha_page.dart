import 'package:flutter/material.dart';

import '../services/imperium_auth_service.dart';

class NovaSenhaPage extends StatefulWidget {
  const NovaSenhaPage({super.key, required this.onConcluido});

  final Future<void> Function() onConcluido;

  @override
  State<NovaSenhaPage> createState() => _NovaSenhaPageState();
}

class _NovaSenhaPageState extends State<NovaSenhaPage> {
  final ImperiumAuthService _auth = ImperiumAuthService.instance;
  final TextEditingController _senha = TextEditingController();
  final TextEditingController _confirmacao = TextEditingController();

  bool _salvando = false;
  bool _ocultarSenha = true;
  bool _ocultarConfirmacao = true;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    final senha = _senha.text;
    final confirmacao = _confirmacao.text;

    if (senha.length < 8) {
      setState(() => _erro = 'A nova senha precisa ter pelo menos 8 caracteres.');
      return;
    }

    if (senha != confirmacao) {
      setState(() => _erro = 'As senhas não conferem.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      await _auth.definirNovaSenha(senha);
      await widget.onConcluido();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _auth.textoErro(erro));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 56),
                      const SizedBox(height: 16),
                      const Text(
                        'Crie uma nova senha',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use a mesma senha para entrar no aplicativo e no Imperium Web.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _senha,
                        obscureText: _ocultarSenha,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Nova senha',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _ocultarSenha = !_ocultarSenha,
                            ),
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
                        controller: _confirmacao,
                        obscureText: _ocultarConfirmacao,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _salvar(),
                        decoration: InputDecoration(
                          labelText: 'Confirmar nova senha',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _ocultarConfirmacao = !_ocultarConfirmacao,
                            ),
                            icon: Icon(
                              _ocultarConfirmacao
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_erro != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _erro!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _salvando ? null : _salvar,
                          icon: _salvando
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                            _salvando ? 'Salvando...' : 'Salvar nova senha',
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
}
