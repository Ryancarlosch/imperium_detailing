import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'services/empresa_cloud_service.dart';
import 'services/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.inicializar();
  runApp(const ImperiumWebFoundationApp());
}

class ImperiumWebFoundationApp extends StatelessWidget {
  const ImperiumWebFoundationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imperium Manager Web',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _WebFoundationPage(),
    );
  }
}

class _WebFoundationPage extends StatefulWidget {
  const _WebFoundationPage();

  @override
  State<_WebFoundationPage> createState() => _WebFoundationPageState();
}

class _WebFoundationPageState extends State<_WebFoundationPage> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _empresaCloud = EmpresaCloudService.instance;

  bool _carregando = true;
  bool _autenticando = false;
  String? _erro;
  User? _usuario;
  List<Map<String, dynamic>> _empresas = const [];
  Map<String, Object?> _diagnosticoLocal = const {};

  SupabaseClient? get _client => SupabaseBootstrap.client;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    if (!mounted) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final client = _client;

      if (client == null) {
        throw StateError(
          SupabaseBootstrap.ultimoErro ??
              'Supabase não está configurado para o ambiente Web.',
        );
      }

      _usuario = client.auth.currentUser;

      if (_usuario != null) {
        await _carregarContexto();
      }
    } catch (erro) {
      _erro = _textoErro(erro);
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _entrar() async {
    final client = _client;
    if (client == null || _autenticando) return;

    final email = _email.text.trim();
    final senha = _senha.text;

    if (email.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe e-mail e senha.');
      return;
    }

    setState(() {
      _autenticando = true;
      _erro = null;
    });

    try {
      final resposta = await client.auth.signInWithPassword(
        email: email,
        password: senha,
      );

      _usuario = resposta.user;

      if (_usuario == null) {
        throw StateError('O login não retornou um usuário válido.');
      }

      await _carregarContexto();
    } catch (erro) {
      _erro = _textoErro(erro);
    } finally {
      if (mounted) {
        setState(() => _autenticando = false);
      }
    }
  }

  Future<void> _sair() async {
    final client = _client;
    if (client == null) return;

    await client.auth.signOut();

    if (!mounted) return;

    setState(() {
      _usuario = null;
      _empresas = const [];
      _diagnosticoLocal = const {};
      _erro = null;
      _senha.clear();
    });
  }

  Future<void> _carregarContexto() async {
    final empresas = await _empresaCloud.listarEmpresasVinculadas();
    final diagnostico = await AppDatabase.instance.diagnosticarTenantLocal();

    if (!mounted) return;

    setState(() {
      _empresas = empresas;
      _diagnosticoLocal = diagnostico;
    });
  }

  Future<void> _ativarEmpresa(Map<String, dynamic> empresa) async {
    final empresaId = (empresa['empresa_id'] ?? '').toString().trim();
    if (empresaId.isEmpty) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      await _empresaCloud.trocarEmpresa(empresaId);
      await _carregarContexto();
    } catch (erro) {
      _erro = _textoErro(erro);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const <String>[
      'Bad state: ',
      'AuthException: ',
      'PostgrestException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto;
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imperium Manager — Web Foundation'),
        actions: [
          if (_usuario != null)
            IconButton(
              tooltip: 'Atualizar contexto',
              onPressed: _carregarContexto,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (_usuario != null)
            IconButton(
              tooltip: 'Sair',
              onPressed: _sair,
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: _usuario == null ? _loginCard() : _contextoCard(),
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Entrar no Imperium',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Fundação Web V1: autenticação Supabase, empresa/tenant e '
              'SQLite WASM no navegador.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'E-mail',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _entrar(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _senha,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _entrar(),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(
                _erro!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _autenticando ? null : _entrar,
              icon: _autenticando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextoCard() {
    final empresaAtual = (_diagnosticoLocal['empresa_ativa_id'] ?? '')
        .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fundação Web ativa',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _linha('Usuário', _usuario?.email ?? _usuario?.id ?? '-'),
                _linha(
                  'Tenant ativo',
                  empresaAtual.isEmpty ? 'Selecione uma empresa' : empresaAtual,
                ),
                _linha(
                  'Banco local',
                  (_diagnosticoLocal['plataforma_banco'] ??
                          'sqlite-wasm-indexeddb')
                      .toString(),
                ),
                _linha(
                  'Schema',
                  (_diagnosticoLocal['schema_version'] ?? '-').toString(),
                ),
                _linha(
                  'Banco criado',
                  _diagnosticoLocal['banco_ativo_existe'] == true
                      ? 'Sim'
                      : 'Ainda não',
                ),
                if (_erro != null) ...[
                  const Divider(),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Empresas vinculadas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (_empresas.isEmpty)
                  const Text('Nenhuma empresa ativa encontrada.')
                else
                  ..._empresas.map(
                    (empresa) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        empresa['atual'] == true
                            ? Icons.check_circle_rounded
                            : Icons.business_outlined,
                      ),
                      title: Text((empresa['nome'] ?? 'Empresa').toString()),
                      subtitle: Text(
                        'Papel: ${(empresa['papel'] ?? '-').toString()}',
                      ),
                      trailing: empresa['atual'] == true
                          ? const Chip(label: Text('Ativa'))
                          : FilledButton.tonal(
                              onPressed: () => _ativarEmpresa(empresa),
                              child: const Text('Ativar'),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Próxima etapa: portar Dashboard e módulos operacionais para '
              'usar fontes Cloud/Web sem dependência direta de File/Image.file.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
