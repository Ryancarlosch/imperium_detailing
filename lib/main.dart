import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'repositories/usuario_repository.dart';
import 'services/backup_automatico_service.dart';
import 'screens/dashboard_page.dart';
import 'screens/login_page.dart';
import 'screens/usuario_inicio_page.dart';

import 'services/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseBootstrap.inicializar();

  runApp(const ImperiumApp());
}

class ImperiumApp extends StatelessWidget {
  const ImperiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imperium Detailing',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _SessaoGate(),
    );
  }
}

class _SessaoGate extends StatefulWidget {
  const _SessaoGate();

  @override
  State<_SessaoGate> createState() => _SessaoGateState();
}

class _SessaoGateState extends State<_SessaoGate> {
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  bool _carregando = true;
  Map<String, dynamic>? _sessao;
  String? _erroInicializacao;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  void _agendarBackupAutomatico() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackupAutomaticoService.instance.verificarEExecutar();
    });
  }

  Future<void> _inicializar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erroInicializacao = null;
      });
    }

    try {
      await _usuarioRepository.garantirEstrutura();

      final sessao = await _usuarioRepository.restaurarSessaoPersistida();

      if (!mounted) {
        return;
      }

      setState(() {
        _sessao = sessao;
        _carregando = false;
      });
      // backup-auto: sessao-restaurada
      if (sessao != null) {
        _agendarBackupAutomatico();
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sessao = null;
        _carregando = false;
        _erroInicializacao = _textoErro(erro);
      });
    }
  }

  void _aoEntrar(Map<String, dynamic> sessao) {
    if (!mounted) {
      return;
    }

    setState(() {
      _sessao = Map<String, dynamic>.from(sessao);
      _erroInicializacao = null;
    });
    // backup-auto: login-manual
    _agendarBackupAutomatico();
  }

  Future<void> _sair() async {
    try {
      await _usuarioRepository.sair();
    } finally {
      if (mounted) {
        setState(() {
          _sessao = null;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Abrindo o Imperium...'),
            ],
          ),
        ),
      );
    }

    if (_erroInicializacao != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 52),
                        const SizedBox(height: 16),
                        const Text(
                          'Não foi possível iniciar o sistema',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(_erroInicializacao!, textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _inicializar,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
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

    final sessao = _sessao;

    if (sessao == null) {
      return LoginPage(onLogin: _aoEntrar);
    }

    final perfil = (sessao['perfil'] ?? '').toString().trim();

    if (perfil == UsuarioRepository.perfilFuncionario) {
      return UsuarioInicioPage(
        sessao: sessao,
        onLogout: () {
          _sair();
        },
      );
    }

    return DashboardPage(
      sessao: sessao,
      onLogout: () {
        _sair();
      },
    );
  }
}
