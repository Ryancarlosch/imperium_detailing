import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'services/empresa_cloud_service.dart';
import 'services/supabase_bootstrap.dart';
import 'web/web_operacional_shell.dart';

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
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
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
  final email = TextEditingController();
  final senha = TextEditingController();
  final empresaService = EmpresaCloudService.instance;

  bool carregando = true;
  String? erro;
  User? usuario;
  List<Map<String, dynamic>> empresas = const [];
  String empresaAtual = '';

  SupabaseClient? get client => SupabaseBootstrap.client;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    email.dispose();
    senha.dispose();
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
      if (usuario != null) await _carregarContexto();
    } catch (e) {
      erro = e.toString();
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _entrar() async {
    final c = client;
    if (c == null) return;

    setState(() {
      carregando = true;
      erro = null;
    });

    try {
      final r = await c.auth.signInWithPassword(
        email: email.text.trim(),
        password: senha.text,
      );
      usuario = r.user;
      await _carregarContexto();
    } catch (e) {
      erro = e.toString();
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _carregarContexto() async {
    empresas = await empresaService.listarEmpresasVinculadas();
    empresaAtual = (await AppDatabase.instance.empresaAtivaId) ?? '';

    if (empresaAtual.isEmpty && empresas.length == 1) {
      empresaAtual = '${empresas.first['empresa_id']}';
      await empresaService.trocarEmpresa(empresaAtual);
      empresas = await empresaService.listarEmpresasVinculadas();
    }
  }

  Future<void> _trocarEmpresa(String id) async {
    if (id.isEmpty || id == empresaAtual) return;

    setState(() => carregando = true);
    try {
      await empresaService.trocarEmpresa(id);
      await _carregarContexto();
    } finally {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _sair() async {
    await client?.auth.signOut();
    if (!mounted) return;
    setState(() {
      usuario = null;
      empresas = const [];
      empresaAtual = '';
      senha.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (usuario == null) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Imperium Manager Web',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: email,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: senha,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _entrar(),
                    ),
                    if (erro != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        erro!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _entrar,
                      icon: const Icon(Icons.login),
                      label: const Text('Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (empresaAtual.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Selecione a empresa')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: empresas
              .map(
                (e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.business),
                    title: Text('${e['nome'] ?? 'Empresa'}'),
                    subtitle: Text('Papel: ${e['papel'] ?? '-'}'),
                    trailing: FilledButton(
                      onPressed: () => _trocarEmpresa('${e['empresa_id']}'),
                      child: const Text('Abrir'),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    return WebOperacionalShell(
      key: ValueKey('tenant-$empresaAtual'),
      usuarioEmail: usuario?.email ?? usuario?.id ?? '',
      empresas: empresas,
      empresaAtualId: empresaAtual,
      onTrocarEmpresa: _trocarEmpresa,
      onSair: _sair,
    );
  }
}
