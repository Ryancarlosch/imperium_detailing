import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/usuario_repository.dart';
import '../services/licenca_service.dart';
import '../services/supabase_bootstrap.dart';

class EmpresaPrimeiroAcessoPage extends StatefulWidget {
  const EmpresaPrimeiroAcessoPage({super.key});

  @override
  State<EmpresaPrimeiroAcessoPage> createState() =>
      _EmpresaPrimeiroAcessoPageState();
}

class _EmpresaPrimeiroAcessoPageState extends State<EmpresaPrimeiroAcessoPage> {
  static const String _redirectUrl = 'imperiumdetailing://login-callback/';

  final TextEditingController _email = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirmarPin = TextEditingController();

  final UsuarioRepository _usuarios = UsuarioRepository();
  final LicencaService _licenca = const LicencaService();

  bool _enviando = false;
  bool _verificando = false;
  bool _concluindo = false;
  bool _ocultarPin = true;
  bool _ocultarConfirmacao = true;

  Map<String, dynamic>? _empresa;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    _confirmarPin.dispose();
    super.dispose();
  }

  Future<void> _validarAparelhoLimpo() async {
    await _usuarios.garantirEstrutura();

    if (await _usuarios.possuiAdministradorComPin()) {
      throw StateError(
        'Este aparelho já possui uma empresa configurada. '
        'No beta, use uma instalação limpa do Imperium para outra empresa.',
      );
    }

    final vinculada = await _licenca.empresaVinculadaAoDispositivo();
    if (vinculada != null) {
      throw StateError('Este aparelho já está vinculado a uma empresa.');
    }
  }

  Future<void> _enviarMagicLink() async {
    if (_enviando) return;

    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      _mensagem('Informe o e-mail liberado pelo Imperium.', erro: true);
      return;
    }

    final client = _client;
    if (client == null) {
      _mensagem('Supabase não está disponível.', erro: true);
      return;
    }

    setState(() => _enviando = true);

    try {
      await _validarAparelhoLimpo();

      final atual = client.auth.currentUser;
      if (atual != null && (atual.email ?? '').trim().toLowerCase() != email) {
        await client.auth.signOut();
      }

      await client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: _redirectUrl,
        shouldCreateUser: true,
      );

      if (!mounted) return;

      _mensagem(
        'Magic Link enviado. Abra somente o link mais recente '
        'neste mesmo celular.',
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _verificarAcesso() async {
    if (_verificando) return;

    final client = _client;
    if (client == null) {
      _mensagem('Supabase não está disponível.', erro: true);
      return;
    }

    setState(() => _verificando = true);

    try {
      await _validarAparelhoLimpo();

      final usuario = client.auth.currentUser;
      if (usuario == null) {
        throw StateError('Abra primeiro o Magic Link enviado ao e-mail.');
      }

      final emailDigitado = _email.text.trim().toLowerCase();
      final emailAutenticado = (usuario.email ?? '').trim().toLowerCase();

      if (emailDigitado.isNotEmpty && emailAutenticado != emailDigitado) {
        throw StateError(
          'O link foi aberto com $emailAutenticado, mas o acesso '
          'foi solicitado para $emailDigitado. Use Trocar conta.',
        );
      }

      final resposta = await client.rpc('imperium_resgatar_convite');
      final mapa = _primeiroMapa(resposta);

      if (mapa['resgatado'] != true) {
        throw StateError('Não foi possível ativar o convite desta empresa.');
      }

      final empresaId = (mapa['empresa_id'] ?? '').toString().trim();

      if (empresaId.isEmpty) {
        throw StateError('Empresa não identificada.');
      }

      if (mapa['acesso_liberado'] != true) {
        throw StateError(
          'O convite foi encontrado, mas a licença desta empresa '
          'não está liberada.',
        );
      }

      await _licenca.vincularDispositivoSeNecessario(
        empresaId: empresaId,
        userId: usuario.id,
        email: emailAutenticado,
      );

      if (!mounted) return;

      setState(() {
        _empresa = mapa;
      });

      _mensagem('Empresa validada. Agora crie o PIN do administrador.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _trocarConta() async {
    final client = _client;
    if (client != null) {
      await client.auth.signOut();
    }

    if (!mounted) return;

    setState(() {
      _empresa = null;
      _pin.clear();
      _confirmarPin.clear();
    });

    _mensagem('Conta da nuvem desconectada. Envie um novo Magic Link.');
  }

  Future<void> _concluir() async {
    if (_concluindo || _empresa == null) return;

    final pin = _pin.text.trim();
    final confirmar = _confirmarPin.text.trim();

    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      _mensagem('O PIN deve ter entre 4 e 8 números.', erro: true);
      return;
    }

    if (pin != confirmar) {
      _mensagem('Os PINs informados são diferentes.', erro: true);
      return;
    }

    setState(() => _concluindo = true);

    try {
      final usuarios = await _usuarios.listarUsuarios(incluirInativos: false);

      Map<String, dynamic>? administrador;

      for (final item in usuarios) {
        if ((item['perfil'] ?? '').toString() ==
            UsuarioRepository.perfilAdministrador) {
          administrador = item;
          break;
        }
      }

      if (administrador == null) {
        throw StateError('Administrador local não encontrado.');
      }

      final id = _int(administrador['id']);
      if (id <= 0) {
        throw StateError('Administrador local inválido.');
      }

      await _usuarios.definirPin(usuarioId: id, pin: pin);

      final sessao = await _usuarios.autenticar(
        login: (administrador['login'] ?? 'admin').toString(),
        pin: pin,
        manterConectado: true,
      );

      try {
        await _licenca.consultarComCacheOffline();
      } catch (_) {
        // O gate fará uma nova validação ao abrir o sistema.
      }

      if (!mounted) return;
      Navigator.of(context).pop<Map<String, dynamic>>(sessao);
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _concluindo = false);
    }
  }

  Map<String, dynamic> _primeiroMapa(dynamic resposta) {
    if (resposta is List && resposta.isNotEmpty && resposta.first is Map) {
      return Map<String, dynamic>.from(resposta.first as Map);
    }

    if (resposta is Map) {
      return Map<String, dynamic>.from(resposta);
    }

    throw StateError('Resposta de convite inválida.');
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'AuthException: ',
      'PostgrestException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    final lower = texto.toLowerCase();

    if (lower.contains('email rate limit') ||
        lower.contains('over_email_send_rate_limit') ||
        lower.contains('429')) {
      return 'Muitos links foram solicitados. Aguarde alguns minutos '
          'e tente enviar somente uma vez.';
    }

    return texto.isEmpty ? 'Falha no primeiro acesso.' : texto;
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

  @override
  Widget build(BuildContext context) {
    final empresa = _empresa;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Primeiro acesso da empresa'),
        actions: [
          TextButton(
            onPressed: _trocarConta,
            child: const Text('Trocar conta'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Use o e-mail que foi liberado no Painel de Empresas. '
                'Nesta fase do beta, cada instalação do Imperium pertence '
                'a uma única empresa.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            enabled: empresa == null && !_enviando && !_verificando,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'E-mail do proprietário',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (empresa == null) ...[
            FilledButton.icon(
              onPressed: _enviando ? null : _enviarMagicLink,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(_enviando ? 'Enviando...' : 'Enviar Magic Link'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _verificando ? null : _verificarAcesso,
              icon: _verificando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(
                _verificando ? 'Verificando...' : 'Já abri o link • verificar',
              ),
            ),
          ] else ...[
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.business_outlined,
                  color: Colors.greenAccent,
                ),
                title: Text((empresa['empresa_nome'] ?? 'Empresa').toString()),
                subtitle: Text(
                  'Plano ${empresa['plano'] ?? ''} • '
                  '${empresa['status_efetivo'] ?? ''}',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              obscureText: _ocultarPin,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: 'Criar PIN do administrador',
                counterText: '',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _ocultarPin = !_ocultarPin);
                  },
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
                  onPressed: () {
                    setState(() => _ocultarConfirmacao = !_ocultarConfirmacao);
                  },
                  icon: Icon(
                    _ocultarConfirmacao
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _concluindo ? null : _concluir,
              icon: _concluindo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                _concluindo ? 'Ativando...' : 'Ativar empresa e entrar',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
