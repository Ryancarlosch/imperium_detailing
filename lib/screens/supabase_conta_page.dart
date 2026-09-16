import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_bootstrap.dart';
import 'imperium_clientes_page.dart';
import 'imperium_empresas_page.dart';
import 'imperium_planos_page.dart';
import 'licenca_status_page.dart';
import 'ponto_nuvem_importacao_page.dart';

class SupabaseContaPage extends StatefulWidget {
  const SupabaseContaPage({super.key, this.emailInicial});

  final String? emailInicial;

  @override
  State<SupabaseContaPage> createState() => _SupabaseContaPageState();
}

class _SupabaseContaPageState extends State<SupabaseContaPage> {
  StreamSubscription<dynamic>? _authSubscription;

  bool _carregando = true;
  bool _saindo = false;

  String? _erro;
  String? _empresaId;
  String? _empresaNome;
  String? _papel;
  bool _empresaAtiva = false;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  User? get _usuario => _client?.auth.currentUser;

  bool get _rlsValidado {
    return _usuario != null &&
        (_empresaId?.isNotEmpty ?? false) &&
        (_empresaNome?.isNotEmpty ?? false) &&
        (_papel?.isNotEmpty ?? false) &&
        _empresaAtiva;
  }

  @override
  void initState() {
    super.initState();

    final client = _client;
    if (client != null) {
      _authSubscription = client.auth.onAuthStateChange.listen(
        (_) {
          _carregarEstado();
        },
        onError: (Object erro) {
          if (!mounted) return;
          setState(() {
            _erro = 'Falha ao atualizar a sessão: ${_textoErro(erro)}';
          });
        },
      );
    }

    _carregarEstado();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _carregarEstado() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    final client = _client;

    if (client == null) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _erro =
            'A infraestrutura do Supabase não está disponível. '
            'O banco local continua funcionando normalmente.';
        _limparEmpresa();
      });
      return;
    }

    final usuario = client.auth.currentUser;

    if (usuario == null) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _limparEmpresa();
      });
      return;
    }

    try {
      // Compatibilidade com clientes antigos que foram criados pelo painel
      // comercial antes do autocadastro livre.
      try {
        await client.rpc('imperium_resgatar_convite');
      } catch (_) {
        // Sem convite pendente: continua normalmente.
      }

      var vinculo = await client
          .from('empresa_usuarios')
          .select('empresa_id,papel,ativo')
          .eq('user_id', usuario.id)
          .eq('ativo', true)
          .limit(1)
          .maybeSingle();

      if (vinculo == null) {
        // Cadastro livre: se o e-mail já estiver confirmado, a primeira
        // empresa e o teste de 30 dias são criados automaticamente.
        try {
          await client.rpc('imperium_autocadastro_empresa');
        } catch (_) {
          // O erro amigável é produzido abaixo caso o vínculo siga ausente.
        }

        vinculo = await client
            .from('empresa_usuarios')
            .select('empresa_id,papel,ativo')
            .eq('user_id', usuario.id)
            .eq('ativo', true)
            .limit(1)
            .maybeSingle();
      }

      final empresaId = vinculo?['empresa_id']?.toString().trim() ?? '';
      final papel = vinculo?['papel']?.toString().trim() ?? '';

      if (empresaId.isEmpty) {
        throw StateError(
          'Não foi possível localizar sua empresa. Confirme seu e-mail e '
          'entre novamente para liberar os 30 dias grátis.',
        );
      }

      final empresa = await client
          .from('empresas')
          .select('id,nome,ativo')
          .eq('id', empresaId)
          .eq('ativo', true)
          .limit(1)
          .maybeSingle();

      if (empresa == null) {
        throw StateError('A empresa vinculada não está disponível.');
      }

      if (!mounted) return;

      setState(() {
        _empresaId = empresaId;
        _empresaNome = empresa['nome']?.toString().trim() ?? '';
        _papel = papel;
        _empresaAtiva = empresa['ativo'] == true;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _limparEmpresa();
        _carregando = false;
        _erro = _textoErro(erro);
      });
    }
  }

  void _limparEmpresa() {
    _empresaId = null;
    _empresaNome = null;
    _papel = null;
    _empresaAtiva = false;
  }

  Future<void> _abrirPainelEmpresas() async {
    if (!_adminComercial) {
      _mensagem(
        'Painel restrito à empresa proprietária do Imperium.',
        erro: true,
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ImperiumEmpresasPage()),
    );

    if (!mounted) return;
    await _carregarEstado();
  }

  Future<void> _sair() async {
    final client = _client;
    if (client == null || _saindo) return;

    setState(() => _saindo = true);

    try {
      await client.auth.signOut();
      await _carregarEstado();

      if (!mounted) return;
      _mensagem(
        'Conta desconectada. Use a tela principal para entrar novamente.',
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) {
        setState(() => _saindo = false);
      }
    }
  }

  Future<void> _abrirLicenca() async {
    if (!_rlsValidado) {
      _mensagem('Valide primeiro a conta e a empresa na nuvem.', erro: true);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LicencaStatusPage(empresaId: _empresaId),
      ),
    );
  }

  bool get _adminComercial {
    const empresaImperium = 'dbbf4114-06fa-46b8-a2f6-50b3f3ead436';
    final papel = (_papel ?? '').trim().toLowerCase();

    return _empresaId == empresaImperium &&
        const {
          'admin',
          'administrador',
          'proprietario',
          'proprietário',
          'dono',
          'owner',
        }.contains(papel);
  }

  Future<void> _abrirPainelClientes() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ImperiumClientesPage()),
    );

    await _carregarEstado();
  }

  Future<void> _abrirPainelPlanos() async {
    if (!_adminComercial) {
      _mensagem(
        'Painel restrito à empresa proprietária do Imperium.',
        erro: true,
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ImperiumPlanosPage()),
    );

    if (!mounted) return;
    await _carregarEstado();
  }

  Future<void> _abrirPontoNuvem() async {
    final empresaId = _empresaId;

    if (!_rlsValidado || empresaId == null) {
      _mensagem('Valide primeiro a conta e a empresa na nuvem.', erro: true);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PontoNuvemImportacaoPage(empresaId: empresaId),
      ),
    );

    await _carregarEstado();
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    const prefixos = <String>[
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ];

    for (final prefixo in prefixos) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida.' : texto;
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

  Widget _linha({required String titulo, required String valor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: SelectableText(
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
    final usuario = _usuario;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta na nuvem'),
        actions: [
          if (_adminComercial)
            IconButton(
              tooltip: 'Painel de empresas',
              onPressed: _carregando ? null : _abrirPainelEmpresas,
              icon: const Icon(Icons.business_center_outlined),
            ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarEstado,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _rlsValidado
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _rlsValidado
                          ? 'Conta conectada. A empresa e as permissões estão sincronizadas com a nuvem.'
                          : 'A sessão da empresa não está conectada. Use o login principal do Imperium com e-mail e senha.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_carregando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ),
            )
          else if (usuario == null) ...[
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  children: [
                    Icon(Icons.login_rounded, size: 42),
                    SizedBox(height: 12),
                    Text(
                      'Conta desconectada',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Volte para a tela principal e entre com o mesmo e-mail e senha usados no Imperium Web. Não usamos mais Magic Link para o login da empresa.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            if (_rlsValidado)
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
                          Expanded(
                            child: Text(
                              'Conta da empresa validada',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _linha(titulo: 'E-mail', valor: usuario.email ?? ''),
                      _linha(titulo: 'Empresa', valor: _empresaNome ?? ''),
                      _linha(titulo: 'Papel', valor: _papel ?? ''),
                      _linha(titulo: 'Empresa ID', valor: _empresaId ?? ''),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _abrirLicenca,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Plano e assinatura'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_adminComercial) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _abrirPainelClientes,
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            label: const Text('Painel de clientes'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _abrirPainelPlanos,
                            icon: const Icon(Icons.sell_outlined),
                            label: const Text('Planos de assinatura'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _abrirPontoNuvem,
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('Preparar Ponto na nuvem'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Aqui você importa os funcionários, migra o histórico e ativa o Ponto compartilhado.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _erro ??
                        'A sessão existe, mas a empresa ainda não foi validada.',
                  ),
                ),
              ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _saindo ? null : _sair,
              icon: const Icon(Icons.logout),
              label: Text(_saindo ? 'Saindo...' : 'Sair da conta'),
            ),
          ],
          if (_erro != null && usuario == null) ...[
            const SizedBox(height: 14),
            Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 18),
          const Text(
            'A mesma conta de e-mail e senha identifica a empresa no aplicativo e na Web. O cadastro de empresa é automático após a confirmação do e-mail.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
