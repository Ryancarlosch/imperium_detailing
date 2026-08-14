import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/funcionario_acesso_service.dart';
import '../services/operacional_sync_service.dart';
import '../services/ponto_offline_sync_service.dart';
import '../services/supabase_bootstrap.dart';

class FuncionarioPrimeiroAcessoPage extends StatefulWidget {
  const FuncionarioPrimeiroAcessoPage({super.key});

  @override
  State<FuncionarioPrimeiroAcessoPage> createState() =>
      _FuncionarioPrimeiroAcessoPageState();
}

class _FuncionarioPrimeiroAcessoPageState
    extends State<FuncionarioPrimeiroAcessoPage> {
  final FuncionarioAcessoService _service = FuncionarioAcessoService.instance;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirmarPin = TextEditingController();

  StreamSubscription<dynamic>? _authSubscription;
  Timer? _cooldownTimer;

  bool _enviando = false;
  bool _verificando = false;
  bool _concluindo = false;
  bool _trocandoConta = false;
  bool _ocultarPin = true;
  bool _ocultarConfirmacao = true;
  int _cooldownRestante = 0;

  Map<String, dynamic>? _acesso;
  String? _erro;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  User? get _usuarioSupabase => _client?.auth.currentUser;

  String get _emailAutenticado =>
      (_usuarioSupabase?.email ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();

    final client = _client;

    if (client != null) {
      _authSubscription = client.auth.onAuthStateChange.listen((_) {
        _verificarSessao(silencioso: true);
      });
    }

    _preencherEmailConhecido();
    _verificarSessao(silencioso: true);
  }

  Future<void> _preencherEmailConhecido() async {
    final local = await _service.emailLocal;
    if (!mounted || _email.text.trim().isNotEmpty) return;

    final valor = local ?? _emailAutenticado;
    if (valor.trim().isNotEmpty) {
      _email.text = valor.trim().toLowerCase();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cooldownTimer?.cancel();
    _email.dispose();
    _pin.dispose();
    _confirmarPin.dispose();
    super.dispose();
  }

  void _iniciarCooldown() {
    _cooldownTimer?.cancel();

    setState(() => _cooldownRestante = 60);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldownRestante <= 1) {
        timer.cancel();
        setState(() => _cooldownRestante = 0);
      } else {
        setState(() => _cooldownRestante--);
      }
    });
  }

  Future<void> _enviarMagicLink() async {
    if (_enviando || _cooldownRestante > 0) return;

    final email = _email.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains('@')) {
      _mensagem(
        'Informe exatamente o e-mail liberado pelo administrador.',
        erro: true,
      );
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
      _acesso = null;
    });

    try {
      await _service.enviarMagicLink(email);

      if (!mounted) return;

      _iniciarCooldown();
      _mensagem(
        'Link enviado. Abra somente o link mais recente neste mesmo celular.',
      );
    } catch (erro) {
      if (!mounted) return;

      final texto = FuncionarioAcessoService.textoErro(erro);
      setState(() => _erro = texto);

      if (erro is AuthException &&
          ((erro.code ?? '').toLowerCase() == 'over_email_send_rate_limit' ||
              (erro.statusCode ?? '') == '429')) {
        _iniciarCooldown();
      }

      _mensagem(texto, erro: true);
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
      }
    }
  }

  Future<void> _verificarSessao({bool silencioso = false}) async {
    if (_verificando) return;

    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      if (!silencioso) {
        _mensagem(
          'Ainda não há uma conta autenticada. Abra o Magic Link primeiro.',
          erro: true,
        );
      }
      return;
    }

    final digitado = _email.text.trim().toLowerCase();
    final autenticado = (user.email ?? '').trim().toLowerCase();

    if (digitado.isNotEmpty &&
        autenticado.isNotEmpty &&
        digitado != autenticado) {
      final texto =
          'Este aparelho está autenticado como $autenticado, mas você informou '
          '$digitado. Toque em “Trocar conta” e abra o Magic Link do e-mail '
          'correto.';

      if (mounted) setState(() => _erro = texto);
      if (!silencioso) _mensagem(texto, erro: true);
      return;
    }

    if (mounted) {
      setState(() {
        _verificando = true;
        _erro = null;
      });
    }

    try {
      final acesso = await _service.resgatarAcessoAtual();

      if (!mounted) return;

      _email.text = (acesso['email'] ?? user.email ?? '')
          .toString()
          .trim()
          .toLowerCase();

      setState(() => _acesso = acesso);

      if (!silencioso) {
        _mensagem('Conta confirmada. Agora crie o PIN deste celular.');
      }
    } catch (erro) {
      if (!mounted) return;

      var texto = FuncionarioAcessoService.textoErro(erro);

      try {
        final diagnostico = await _service.diagnosticarAcessoAtual();
        final emailAuth = (diagnostico['email_autenticado'] ?? '')
            .toString()
            .trim();
        final liberado = diagnostico['liberado'] == true;

        if (emailAuth.isNotEmpty && !liberado) {
          texto =
              'O Magic Link autenticou $emailAuth, mas esse e-mail não está '
              'liberado para um funcionário ativo. No celular do administrador, '
              'abra “Acessos em outros celulares” e confira se o e-mail é '
              'exatamente $emailAuth.';
        }
      } catch (_) {
        // Mantém a mensagem original se o diagnóstico não estiver disponível.
      }

      if (!mounted) return;
      setState(() => _erro = texto);

      if (!silencioso) {
        _mensagem(texto, erro: true);
      }
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _trocarConta() async {
    if (_trocandoConta) return;

    setState(() => _trocandoConta = true);

    try {
      await _service.sairSupabase();

      if (!mounted) return;

      setState(() {
        _acesso = null;
        _erro = null;
      });

      _mensagem(
        'Conta anterior desconectada. Informe o e-mail liberado e solicite um '
        'novo Magic Link.',
      );
    } finally {
      if (mounted) setState(() => _trocandoConta = false);
    }
  }

  Future<void> _concluir() async {
    if (_concluindo) return;

    final acesso = _acesso;

    if (acesso == null) {
      _mensagem('Valide primeiro o Magic Link.', erro: true);
      return;
    }

    final pin = _pin.text.trim();
    final confirmar = _confirmarPin.text.trim();

    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      _mensagem('O PIN deve ter entre 4 e 8 números.', erro: true);
      return;
    }

    if (pin != confirmar) {
      _mensagem('A confirmação do PIN está diferente.', erro: true);
      return;
    }

    setState(() => _concluindo = true);

    try {
      final sessao = await _service.provisionarLocal(acesso: acesso, pin: pin);

      try {
        await OperacionalSyncService.instance.sincronizarTudo();
        await PontoOfflineSyncService.instance.sincronizarPendentes();
      } catch (_) {
        // O primeiro acesso continua válido mesmo sem baixar dados agora.
      }

      if (!mounted) return;
      Navigator.of(context).pop<Map<String, dynamic>>(sessao);
    } catch (erro) {
      if (!mounted) return;
      _mensagem(FuncionarioAcessoService.textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _concluindo = false);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  Widget _info(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acesso = _acesso;
    final emailAutenticado = _emailAutenticado;

    return Scaffold(
      appBar: AppBar(title: const Text('Acesso do funcionário')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.phone_android_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Use o e-mail liberado pelo administrador. O Magic Link '
                        'é necessário apenas para autorizar este aparelho. O PIN '
                        'fica somente neste celular.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (emailAutenticado.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Conta autenticada neste aparelho'),
                  subtitle: Text(emailAutenticado),
                  trailing: TextButton(
                    onPressed: _trocandoConta ? null : _trocarConta,
                    child: Text(_trocandoConta ? 'Saindo...' : 'Trocar conta'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (acesso == null) ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_enviando && !_verificando,
                decoration: const InputDecoration(
                  labelText: 'E-mail liberado pelo administrador',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _enviando || _cooldownRestante > 0
                    ? null
                    : _enviarMagicLink,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mark_email_read_outlined),
                label: Text(
                  _enviando
                      ? 'Enviando...'
                      : _cooldownRestante > 0
                      ? 'Aguarde $_cooldownRestante s'
                      : 'Enviar Magic Link',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _verificando
                    ? null
                    : () => _verificarSessao(silencioso: false),
                icon: _verificando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: const Text('Já abri o link • verificar'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 14),
                Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ] else ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: Colors.greenAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Acesso confirmado',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _info(
                        'Empresa',
                        (acesso['empresa_nome'] ?? '').toString(),
                      ),
                      _info(
                        'Funcionário',
                        (acesso['colaborador_nome'] ?? '').toString(),
                      ),
                      _info('Login', (acesso['login'] ?? '').toString()),
                      _info('E-mail', (acesso['email'] ?? '').toString()),
                      const SizedBox(height: 10),
                      Text(
                        acesso['ponto_migracao_ativa'] == true
                            ? 'Ponto compartilhado está ativo.'
                            : 'O Ponto ainda não foi ativado na nuvem pelo '
                                  'administrador.',
                        style: TextStyle(
                          color: acesso['ponto_migracao_ativa'] == true
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pin,
                obscureText: _ocultarPin,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'Criar PIN deste celular',
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _ocultarPin ? 'Mostrar PIN' : 'Ocultar PIN',
                    onPressed: () => setState(() => _ocultarPin = !_ocultarPin),
                    icon: Icon(
                      _ocultarPin
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmarPin,
                obscureText: _ocultarConfirmacao,
                keyboardType: TextInputType.number,
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
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _concluindo ? null : _concluir,
                icon: _concluindo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _concluindo ? 'Ativando aparelho...' : 'Criar PIN e entrar',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'O PIN nunca é enviado ao Supabase e pode ser diferente do PIN '
                'configurado em outro aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
