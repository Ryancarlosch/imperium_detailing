import 'package:flutter/material.dart';
import 'package:imperium_detailing/screens/dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  bool _ocultarSenha = true;
  bool _carregando = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final usuario = _usuarioController.text.trim().toLowerCase();
    final senha = _senhaController.text.trim();

    if (usuario.isEmpty || senha.isEmpty) {
      _mostrarMensagem('Informe o usuário e a senha.');
      return;
    }

    setState(() {
      _carregando = true;
    });

    await Future<void>.delayed(
      const Duration(milliseconds: 250),
    );

    if (!mounted) {
      return;
    }

    final loginValido = usuario == 'admin' && senha == '1234';

    setState(() {
      _carregando = false;
    });

    if (!loginValido) {
      _mostrarMensagem('Usuário ou senha incorretos.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DashboardPage(),
      ),
    );
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.directions_car_filled_rounded,
                    size: 76,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Imperium Detailing',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Acesso ao sistema',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _usuarioController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      prefixIcon: Icon(
                        Icons.person_outline_rounded,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _senhaController,
                    obscureText: _ocultarSenha,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _entrar(),
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _ocultarSenha
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                        onPressed: () {
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _carregando ? null : _entrar,
                      icon: _carregando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.login_rounded,
                            ),
                      label: Text(
                        _carregando ? 'Entrando...' : 'Entrar',
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Acesso de teste',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'Usuário: admin\nSenha: 1234',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
