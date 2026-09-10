import 'dart:async';

import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';
import '../services/funcionario_acesso_service.dart';
import '../services/operacional_sync_service.dart';
import '../services/ponto_offline_sync_service.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'configuracoes_page.dart';
import 'custo_servicos_page.dart';
import 'dre_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'meu_ponto_page.dart';
import 'meu_perfil_page.dart';
import 'orcamentos_page.dart';
import 'ordens_servico_page.dart';
import 'pagamentos_funcionarios_page.dart';

class UsuarioInicioPage extends StatefulWidget {
  const UsuarioInicioPage({
    super.key,
    required this.sessao,
    required this.onLogout,
  });

  final Map<String, dynamic> sessao;
  final VoidCallback onLogout;

  @override
  State<UsuarioInicioPage> createState() => _UsuarioInicioPageState();
}

class _UsuarioInicioPageState extends State<UsuarioInicioPage>
    with WidgetsBindingObserver {
  final UsuarioRepository _usuarios = UsuarioRepository();
  final FuncionarioAcessoService _acesso = FuncionarioAcessoService.instance;
  final OperacionalSyncService _operacional = OperacionalSyncService.instance;
  final PontoOfflineSyncService _pontoOffline =
      PontoOfflineSyncService.instance;

  late Map<String, dynamic> _sessao;
  Timer? _timer;
  bool _sincronizando = false;
  int _pontoPendente = 0;
  DateTime? _ultimoSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessao = Map<String, dynamic>.from(widget.sessao);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizar(silencioso: true);
    });

    _timer = Timer.periodic(const Duration(seconds: 90), (_) {
      _sincronizar(silencioso: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sincronizar(silencioso: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _sincronizar({bool silencioso = false}) async {
    if (_sincronizando) return;

    if (mounted) setState(() => _sincronizando = true);

    try {
      final remoto = await _acesso.sincronizarPermissoesLocais();

      if (remoto['consultado'] == true && remoto['ativo'] != true) {
        await _acesso.sairSupabase();

        if (!mounted) return;

        _mensagem(
          remoto['motivo'] == 'dispositivo_revogado'
              ? 'Este celular foi revogado pelo administrador.'
              : 'Seu acesso foi desativado pelo administrador.',
          erro: true,
        );

        widget.onLogout();
        return;
      }

      final usuarioId = _intNulo(_sessao['id']);

      if (usuarioId != null && usuarioId > 0) {
        final permissoes = await _usuarios.obterPermissoes(usuarioId);
        final usuario = await _usuarios.buscarUsuarioPorId(usuarioId);

        if (usuario != null && mounted) {
          setState(() {
            _sessao = <String, dynamic>{
              ..._sessao,
              ...usuario,
              'permissoes': permissoes,
            };
          });
        }
      }

      await _operacional.tentarSincronizarTudo();
      await _pontoOffline.sincronizarPendentes(
        colaboradorLocalId: _colaboradorId,
      );

      final pendentes = await _pontoOffline.contarPendentes(
        colaboradorLocalId: _colaboradorId,
      );

      if (mounted) {
        setState(() {
          _pontoPendente = pendentes;
          _ultimoSync = DateTime.now();
        });
      }

      if (!silencioso && mounted) {
        _mensagem(
          pendentes > 0
              ? 'Dados atualizados. $pendentes batida(s) de Ponto ainda '
                    'aguardam internet.'
              : 'Dados e permissões atualizados.',
        );
      }
    } catch (erro) {
      if (!silencioso && mounted) {
        _mensagem(
          'Não foi possível consultar a nuvem agora. Os dados locais continuam '
          'disponíveis.\n${FuncionarioAcessoService.textoErro(erro)}',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  bool _pode(String modulo) {
    if ((_sessao['perfil'] ?? '').toString() ==
        UsuarioRepository.perfilAdministrador) {
      return true;
    }

    final bruto = _sessao['permissoes'];
    if (bruto is Map) return bruto[modulo] == true;
    return false;
  }

  int? get _colaboradorId => _intNulo(_sessao['colaborador_id']);

  int? _intNulo(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  Future<void> _abrir(BuildContext context, Widget pagina) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina));

    if (mounted) {
      await _sincronizar(silencioso: true);
    }
  }

  List<_ModuloUsuario> _modulos(BuildContext context) {
    final itens = <_ModuloUsuario>[];

    void adicionar(
      String modulo,
      String titulo,
      IconData icone,
      Widget pagina,
    ) {
      if (_pode(modulo)) {
        itens.add(
          _ModuloUsuario(
            titulo: titulo,
            icone: icone,
            onTap: () => _abrir(context, pagina),
          ),
        );
      }
    }

    if (_pode('ponto') && _colaboradorId != null) {
      itens.add(
        _ModuloUsuario(
          titulo: 'Meu ponto',
          icone: Icons.fingerprint_rounded,
          aviso: _pontoPendente > 0 ? '$_pontoPendente pendente(s)' : null,
          onTap: () => _abrir(
            context,
            MeuPontoPage(
              colaboradorId: _colaboradorId!,
              nome:
                  (_sessao['colaborador_nome'] ??
                          _sessao['nome'] ??
                          'Funcionário')
                      .toString(),
            ),
          ),
        ),
      );
    }

    adicionar(
      'clientes',
      'Clientes',
      Icons.people_outline_rounded,
      const ClientesPage(),
    );
    adicionar(
      'agenda',
      'Agenda',
      Icons.calendar_month_outlined,
      const AgendaPage(),
    );
    adicionar(
      'orcamentos',
      'Orçamentos',
      Icons.request_quote_outlined,
      const OrcamentosPage(),
    );
    adicionar(
      'ordens_servico',
      'Ordens de Serviço',
      Icons.car_repair_outlined,
      const OrdensServicoPage(statusInicial: 'Todos'),
    );
    adicionar(
      'estoque',
      'Estoque',
      Icons.inventory_2_outlined,
      const EstoquePage(),
    );
    adicionar(
      'financeiro',
      'Financeiro',
      Icons.account_balance_wallet_outlined,
      const FinanceiroPage(),
    );
    adicionar('dre', 'DRE', Icons.analytics_outlined, const DrePage());
    adicionar(
      'precificacao',
      'Precificação',
      Icons.price_check_outlined,
      const CustoServicosPage(),
    );
    adicionar(
      'funcionarios',
      'Funcionários',
      Icons.badge_outlined,
      const PagamentosFuncionariosPage(),
    );
    adicionar(
      'configuracoes',
      'Configurações',
      Icons.settings_outlined,
      const ConfiguracoesPage(),
    );

    return itens;
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  String _horaUltimoSync() {
    final data = _ultimoSync;
    if (data == null) return 'Sincronização automática ativa';

    return 'Última atualização: '
        '${data.hour.toString().padLeft(2, '0')}:'
        '${data.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final modulos = _modulos(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imperium'),
        actions: [
          IconButton(
            tooltip: 'Meu perfil e segurança',
            onPressed: () => _abrir(
              context,
              MeuPerfilPage(sessao: Map<String, dynamic>.from(_sessao)),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar dados e permissões',
            onPressed: _sincronizando
                ? null
                : () => _sincronizar(silencioso: false),
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _sincronizar(silencioso: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.person_outline_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_sessao['nome'] ?? 'Usuário').toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text((_sessao['perfil'] ?? '').toString()),
                          const SizedBox(height: 3),
                          Text(
                            _horaUltimoSync(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_pontoPendente > 0) ...[
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(
                    Icons.cloud_off_outlined,
                    color: Colors.orangeAccent,
                  ),
                  title: Text(
                    '$_pontoPendente batida(s) aguardando sincronização',
                  ),
                  subtitle: const Text(
                    'O registro ficou salvo neste celular e será enviado '
                    'quando a conexão voltar.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (modulos.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Nenhum módulo foi liberado para este usuário.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: modulos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                ),
                itemBuilder: (_, index) {
                  final item = modulos[index];

                  return Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item.onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icone, size: 30),
                            const SizedBox(height: 9),
                            Text(
                              item.titulo,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.aviso != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                item.aviso!,
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ModuloUsuario {
  const _ModuloUsuario({
    required this.titulo,
    required this.icone,
    required this.onTap,
    this.aviso,
  });

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;
  final String? aviso;
}
