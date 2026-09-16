import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories/usuario_repository.dart';
import 'screens/login_email_senha_page.dart';
import 'screens/nova_senha_page.dart';
import 'services/backup_automatico_service.dart';
import 'services/cloud_session_service.dart';
import 'services/funcionario_acesso_service.dart';
import 'services/operacional_sync_service.dart';
import 'services/supabase_bootstrap.dart';
import 'services/tenant_runtime_service.dart';
import 'widgets/licenca_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseBootstrap.inicializar();

  try {
    await OperacionalSyncService.instance.prepararTenantInicial();
  } catch (_) {
    // Offline ou primeiro uso: o AppDatabase usa o último tenant marcado
    // ou o banco legado até a empresa ser confirmada.
  }

  runApp(const ImperiumApp());
}

class ImperiumApp extends StatelessWidget {
  const ImperiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TenantRuntimeService.instance.revisao,
      builder: (context, revisao, _) {
        return MaterialApp(
          key: ValueKey<String>('tenant-runtime-$revisao'),
          title: 'Imperium Manager',
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
      },
    );
  }
}

class _SessaoGate extends StatefulWidget {
  const _SessaoGate();

  @override
  State<_SessaoGate> createState() => _SessaoGateState();
}

class _SessaoGateState extends State<_SessaoGate> with WidgetsBindingObserver {
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  StreamSubscription<AuthState>? _authSubscription;
  bool _carregando = true;
  bool _definindoSenha = false;
  Map<String, dynamic>? _sessao;
  String? _erroInicializacao;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ouvirAutenticacao();
    _inicializar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sessao != null) {
      unawaited(_sincronizarSessao('mobile_resume'));
    }
  }

  void _ouvirAutenticacao() {
    final client = SupabaseBootstrap.client;
    if (client == null) return;

    _authSubscription?.cancel();
    _authSubscription = client.auth.onAuthStateChange.listen((estado) {
      if (!mounted) return;

      if (estado.event == AuthChangeEvent.passwordRecovery &&
          (estado.session?.user ?? client.auth.currentUser) != null) {
        setState(() {
          _definindoSenha = true;
          _sessao = null;
          _carregando = false;
          _erroInicializacao = null;
        });
        return;
      }

      if (estado.event == AuthChangeEvent.signedOut ||
          (estado.session?.user ?? client.auth.currentUser) == null) {
        setState(() {
          _definindoSenha = false;
          _sessao = null;
          _carregando = false;
        });
      }
    });
  }

  void _agendarBackupAutomatico() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackupAutomaticoService.instance.verificarEExecutar();
    });
  }

  Future<void> _sincronizarSessao(
    String origem, {
    bool ignorarBackoff = false,
  }) async {
    if (_sessao == null || SupabaseBootstrap.client?.auth.currentUser == null) {
      return;
    }

    try {
      await OperacionalSyncService.instance.sincronizarTudo(
        origem: origem,
        ignorarBackoff: ignorarBackoff,
      );
    } catch (_) {
      // O mobile continua offline-first. Uma falha de rede nunca impede o uso
      // da sessão já autorizada; a próxima retomada tentará novamente.
    }
  }

  Future<Map<String, dynamic>?> _validarFuncionarioAntesDeAbrir(
    Map<String, dynamic>? sessao,
  ) async {
    if (sessao == null) return null;

    final perfil = (sessao['perfil'] ?? '').toString();
    if (perfil != UsuarioRepository.perfilFuncionario) {
      return sessao;
    }

    final acesso = FuncionarioAcessoService.instance;

    try {
      final remoto = await acesso.sincronizarPermissoesLocais();

      if (remoto['consultado'] == true && remoto['ativo'] != true) {
        await acesso.sairSupabase();
        return null;
      }

      final atualizada = await _usuarioRepository.restaurarSessaoPersistida();
      return atualizada ?? sessao;
    } catch (_) {
      return sessao;
    }
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

      Map<String, dynamic>? sessao;
      final usuarioCloud = SupabaseBootstrap.client?.auth.currentUser;

      if (usuarioCloud == null) {
        await _usuarioRepository.sair();
      } else {
        sessao = await _usuarioRepository.restaurarSessaoPersistida();
        sessao = await _validarFuncionarioAntesDeAbrir(sessao);
      }

      if (!mounted) return;

      setState(() {
        _sessao = sessao;
        _carregando = false;
      });

      if (sessao != null) {
        _agendarBackupAutomatico();
        unawaited(_sincronizarSessao('mobile_startup'));
      }
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _sessao = null;
        _carregando = false;
        _erroInicializacao = _textoErro(erro);
      });
    }
  }

  void _aoEntrar(Map<String, dynamic> sessao) {
    if (!mounted) return;

    setState(() {
      _sessao = Map<String, dynamic>.from(sessao);
      _erroInicializacao = null;
      _definindoSenha = false;
    });
    _agendarBackupAutomatico();
    unawaited(_sincronizarSessao('mobile_login', ignorarBackoff: true));
  }

  Future<void> _concluirRecuperacaoSenha() async {
    if (!mounted) return;
    setState(() {
      _definindoSenha = false;
      _carregando = true;
      _erroInicializacao = null;
    });
    await _inicializar();
  }

  Future<void> _sair() async {
    try {
      await CloudSessionService.instance.sair();
    } finally {
      if (mounted) {
        setState(() {
          _sessao = null;
          _definindoSenha = false;
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
    if (_definindoSenha) {
      return NovaSenhaPage(onConcluido: _concluirRecuperacaoSenha);
    }

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
      return LoginEmailSenhaPage(onLogin: _aoEntrar);
    }

    return LicencaGate(sessao: sessao, onLogout: _sair);
  }
}
