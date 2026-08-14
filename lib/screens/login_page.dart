import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';
import '../services/funcionario_acesso_service.dart';
import 'funcionario_primeiro_acesso_page.dart';
import 'dashboard_page.dart';
import 'empresa_primeiro_acesso_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLogin});

  final ValueChanged<Map<String, dynamic>>? onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmarPinController = TextEditingController();

  bool _ocultarPin = true;
  bool _ocultarConfirmacao = true;
  bool _carregando = false;
  bool _verificandoPrimeiroAcesso = true;
  bool _primeiroAcesso = false;
  bool _manterConectado = true;

  @override
  void initState() {
    super.initState();
    _prepararLogin();
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _pinController.dispose();
    _confirmarPinController.dispose();
    super.dispose();
  }

  Future<void> _prepararLogin() async {
    try {
      await _usuarioRepository.garantirEstrutura();

      final funcionarioService = FuncionarioAcessoService.instance;

      await funcionarioService.garantirEstruturaLocal();

      final dispositivoFuncionario =
          await funcionarioService.dispositivoFuncionario;

      final loginFuncionario = await funcionarioService.loginLocal;

      final possuiAdminComPin = await _usuarioRepository
          .possuiAdministradorComPin();

      if (!mounted) {
        return;
      }

      setState(() {
        _primeiroAcesso = !dispositivoFuncionario && !possuiAdminComPin;
        _verificandoPrimeiroAcesso = false;

        if (dispositivoFuncionario &&
            (loginFuncionario?.trim().isNotEmpty ?? false)) {
          _usuarioController.text = loginFuncionario!.trim();
        } else if (_primeiroAcesso && _usuarioController.text.trim().isEmpty) {
          _usuarioController.text = 'admin';
        }
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _verificandoPrimeiroAcesso = false;
      });

      _mostrarMensagem(
        'Não foi possível preparar o login: ${_textoErro(erro)}',
        erro: true,
      );
    }
  }

  Future<void> _abrirPrimeiroAcessoFuncionario() async {
    final sessao = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const FuncionarioPrimeiroAcessoPage()),
    );

    if (!mounted || sessao == null) return;

    if (widget.onLogin != null) {
      widget.onLogin!(Map<String, dynamic>.from(sessao));
      return;
    }

    _usuarioController.text = (sessao['login'] ?? '').toString();

    _pinController.clear();
    _confirmarPinController.clear();

    _mostrarMensagem(
      'Acesso de funcionário configurado. '
      'Use seu PIN nos próximos acessos.',
    );

    await _prepararLogin();
  }

  Future<void> _abrirPrimeiroAcessoEmpresa() async {
    if (_carregando) return;

    final sessao = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const EmpresaPrimeiroAcessoPage()),
    );

    if (sessao == null || !mounted) return;

    if (widget.onLogin != null) {
      widget.onLogin!(Map<String, dynamic>.from(sessao));
      return;
    }

    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => DashboardPage(sessao: sessao)),
    );
  }

  Future<void> _entrar() async {
    if (_carregando || _verificandoPrimeiroAcesso) {
      return;
    }

    final usuario = _usuarioController.text.trim().toLowerCase();
    final pin = _pinController.text.trim();
    final confirmarPin = _confirmarPinController.text.trim();

    if (usuario.isEmpty || pin.isEmpty) {
      _mostrarMensagem(
        _primeiroAcesso
            ? 'Informe o usuário e crie um PIN.'
            : 'Informe o usuário e o PIN.',
        erro: true,
      );
      return;
    }

    if (_primeiroAcesso) {
      if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
        _mostrarMensagem('O PIN deve ter entre 4 e 8 números.', erro: true);
        return;
      }

      if (pin != confirmarPin) {
        _mostrarMensagem('A confirmação do PIN está diferente.', erro: true);
        return;
      }
    }

    setState(() {
      _carregando = true;
    });

    try {
      if (_primeiroAcesso) {
        await _configurarPrimeiroAcesso(usuario: usuario, pin: pin);
      }

      final sessao = await _usuarioRepository.autenticar(
        login: usuario,
        pin: pin,
        manterConectado: _manterConectado,
      );

      if (!mounted) {
        return;
      }

      if (widget.onLogin != null) {
        widget.onLogin!(Map<String, dynamic>.from(sessao));
        return;
      }

      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => DashboardPage(sessao: sessao)),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  Future<void> _configurarPrimeiroAcesso({
    required String usuario,
    required String pin,
  }) async {
    final usuarios = await _usuarioRepository.listarUsuarios(
      incluirInativos: false,
    );

    Map<String, dynamic>? administrador;

    for (final item in usuarios) {
      final login = (item['login'] ?? '').toString().trim().toLowerCase();
      final perfil = (item['perfil'] ?? '').toString().trim();

      if (login == usuario && perfil == UsuarioRepository.perfilAdministrador) {
        administrador = item;
        break;
      }
    }

    if (administrador == null) {
      throw StateError(
        'No primeiro acesso, use o login do Administrador. '
        'O login padrão é admin.',
      );
    }

    final usuarioId = _int(administrador['id']);

    if (usuarioId <= 0) {
      throw StateError('Não foi possível identificar o usuário Administrador.');
    }

    await _usuarioRepository.definirPin(usuarioId: usuarioId, pin: pin);

    if (mounted) {
      setState(() {
        _primeiroAcesso = false;
      });
    }
  }

  int _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    const prefixos = <String>[
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ];

    for (final prefixo in prefixos) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto;
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final primeiroAcesso = _primeiroAcesso;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.directions_car_filled_rounded, size: 76),
                  const SizedBox(height: 22),
                  Text(
                    'Imperium Detailing',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    primeiroAcesso
                        ? 'Configuração do primeiro acesso'
                        : 'Acesso ao sistema',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  if (_verificandoPrimeiroAcesso) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    const Text('Preparando acesso...'),
                  ] else ...[
                    if (primeiroAcesso) ...[
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.admin_panel_settings_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Primeiro acesso: use o login admin '
                                  'e escolha um PIN de 4 a 8 números. '
                                  'Depois disso, o mesmo PIN será usado '
                                  'nos próximos acessos.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextField(
                      controller: _usuarioController,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !_carregando,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinController,
                      obscureText: _ocultarPin,
                      keyboardType: TextInputType.number,
                      textInputAction: primeiroAcesso
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onSubmitted: primeiroAcesso ? null : (_) => _entrar(),
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !_carregando,
                      maxLength: 8,
                      decoration: InputDecoration(
                        labelText: primeiroAcesso ? 'Criar PIN' : 'PIN',
                        counterText: '',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _ocultarPin ? 'Mostrar PIN' : 'Ocultar PIN',
                          onPressed: _carregando
                              ? null
                              : () {
                                  setState(() {
                                    _ocultarPin = !_ocultarPin;
                                  });
                                },
                          icon: Icon(
                            _ocultarPin
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (primeiroAcesso) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmarPinController,
                        obscureText: _ocultarConfirmacao,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _entrar(),
                        autocorrect: false,
                        enableSuggestions: false,
                        enabled: !_carregando,
                        maxLength: 8,
                        decoration: InputDecoration(
                          labelText: 'Confirmar PIN',
                          counterText: '',
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
                    ],
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: _manterConectado,
                      onChanged: _carregando
                          ? null
                          : (valor) {
                              setState(() {
                                _manterConectado = valor ?? true;
                              });
                            },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Manter conectado'),
                      subtitle: const Text(
                        'Abrir direto no Dashboard '
                        'neste aparelho.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _carregando
                            ? null
                            : _abrirPrimeiroAcessoEmpresa,
                        icon: const Icon(Icons.business_outlined),
                        label: const Text('Sou empresa • primeiro acesso'),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                            : Icon(
                                primeiroAcesso
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.login_rounded,
                              ),
                        label: Text(
                          _carregando
                              ? 'Aguarde...'
                              : primeiroAcesso
                              ? 'Configurar e entrar'
                              : 'Entrar',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _carregando
                            ? null
                            : _abrirPrimeiroAcessoFuncionario,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text(
                          'Sou funcionário • primeiro acesso neste celular',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
