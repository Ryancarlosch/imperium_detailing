import 'package:flutter/material.dart';

import '../services/ponto_nuvem_diagnostico_service.dart';
import '../services/ponto_nuvem_importacao_service.dart';
import '../services/ponto_nuvem_service.dart';
import 'funcionarios_acesso_nuvem_page.dart';
import 'ponto_etapa1_validacao_page.dart';

class PontoNuvemImportacaoPage extends StatefulWidget {
  const PontoNuvemImportacaoPage({super.key, required this.empresaId});

  final String empresaId;

  @override
  State<PontoNuvemImportacaoPage> createState() =>
      _PontoNuvemImportacaoPageState();
}

class _PontoNuvemImportacaoPageState extends State<PontoNuvemImportacaoPage> {
  final PontoNuvemImportacaoService _importacao =
      PontoNuvemImportacaoService.instance;
  final PontoNuvemService _nuvem = PontoNuvemService.instance;
  final PontoNuvemDiagnosticoService _diagnosticoService =
      PontoNuvemDiagnosticoService.instance;

  bool _carregando = true;
  bool _importando = false;

  Map<String, dynamic> _resumo = const {};
  List<Map<String, dynamic>> _remotos = const [];
  List<String> _ultimasFalhas = const [];
  Map<String, dynamic> _estadoMigracao = const {};
  Map<String, dynamic> _diagnostico = const {};
  bool _migrandoHistorico = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _importacao.obterResumo(empresaId: widget.empresaId),
        _nuvem.listarColaboradoresRemotos(),
        _nuvem.obterEstadoMigracao(),
        _diagnosticoService.diagnosticar(empresaEsperadaId: widget.empresaId),
      ]);

      if (!mounted) return;

      setState(() {
        _resumo = Map<String, dynamic>.from(resultados[0] as Map);
        _remotos = (resultados[1] as List)
            .map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList();
        _estadoMigracao = Map<String, dynamic>.from(resultados[2] as Map);
        _diagnostico = Map<String, dynamic>.from(resultados[3] as Map);
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);
      _mensagem('Falha ao consultar a nuvem: $erro', erro: true);
    }
  }

  Future<void> _importar() async {
    if (_importando) return;

    setState(() {
      _importando = true;
      _ultimasFalhas = const [];
    });

    try {
      final resultado = await _importacao.importarColaboradores(
        empresaId: widget.empresaId,
      );

      if (!mounted) return;

      setState(() {
        _ultimasFalhas = List<String>.from(resultado.falhas);
      });

      await _carregar();

      if (!mounted) return;

      _mensagem(
        resultado.falhas.isEmpty
            ? '${resultado.sucesso} funcionário(s) preparado(s) na nuvem.'
            : '${resultado.sucesso} concluído(s) e '
                  '${resultado.falhas.length} falha(s).',
        erro: resultado.falhas.isNotEmpty,
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem('Não foi possível importar: $erro', erro: true);
    } finally {
      if (mounted) {
        setState(() => _importando = false);
      }
    }
  }

  Future<void> _abrirHomologacaoEtapa1() async {
    // ponto-etapa1-homologacao-v7
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PontoEtapa1ValidacaoPage(empresaId: widget.empresaId),
      ),
    );

    await _carregar();
  }

  Future<void> _abrirAcessosFuncionarios() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            FuncionariosAcessoNuvemPage(empresaId: widget.empresaId),
      ),
    );

    await _carregar();
  }

  Future<void> _migrarHistorico() async {
    if (_migrandoHistorico) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Migrar histórico do Ponto'),
        content: const Text(
          'Esta operação envia o histórico atual do SQLite para a nuvem. '
          'O modo compartilhado só será ativado depois que toda a migração '
          'terminar com sucesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Migrar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _migrandoHistorico = true);

    try {
      final resultado = await _nuvem.migrarHistoricoLocalCompleto();
      await _carregar();

      if (!mounted) return;

      _mensagem(
        'Migração concluída: '
        '${resultado['colaboradores']} funcionário(s), '
        '${resultado['registros']} registro(s), '
        '${resultado['ajustes']} ajuste(s) e '
        '${resultado['fechamentos']} fechamento(s).',
      );
    } catch (erro) {
      if (!mounted) return;

      _mensagem(
        'A migração não foi ativada porque ocorreu uma falha: $erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => _migrandoHistorico = false);
      }
    }
  }

  Future<void> _vincular(Map<String, dynamic> colaborador) async {
    final controller = TextEditingController();

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vincular funcionário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(colaborador['nome']?.toString() ?? 'Funcionário'),
            const SizedBox(height: 12),
            const Text(
              'Primeiro envie o convite em Supabase > Authentication > Users. '
              'Depois que o funcionário aceitar, informe o mesmo e-mail aqui.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail confirmado no Supabase',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = controller.text.trim();
              if (valor.contains('@')) {
                Navigator.of(dialogContext).pop(valor);
              }
            },
            child: const Text('Vincular'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (email == null) return;

    try {
      await _nuvem.vincularUsuario(
        colaboradorRemotoId: colaborador['id'].toString(),
        email: email,
      );

      await _carregar();

      if (!mounted) return;
      _mensagem('Funcionário vinculado à conta Supabase.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem('$erro', erro: true);
    }
  }

  int _numero(String chave) {
    final valor = _resumo[chave];
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro
              ? const Color(0xFFB00020)
              : const Color(0xFF1B5E20),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ponto na nuvem'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando || _importando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A nuvem do Ponto não recebe salário, encargos, '
                        'remuneração ou custo/hora. O vínculo contém somente '
                        'identidade operacional do funcionário.',
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
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _SaudeNuvemCard(diagnostico: _diagnostico),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ResumoCard(
                      titulo: 'Locais',
                      valor: _numero('total_local'),
                      icone: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ResumoCard(
                      titulo: 'Vinculados',
                      valor: _numero('vinculados'),
                      icone: Icons.link,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ResumoCard(
                      titulo: 'Na nuvem',
                      valor: _numero('remoto'),
                      icone: Icons.cloud_done,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _importando ? null : _importar,
                icon: _importando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  _importando
                      ? 'Sincronizando...'
                      : 'Importar/atualizar funcionários',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _importando || _migrandoHistorico
                    ? null
                    : _abrirAcessosFuncionarios,
                icon: const Icon(Icons.phonelink_outlined),
                label: const Text('Acessos em outros celulares'),
              ),
              OutlinedButton.icon(
                onPressed: _importando || _migrandoHistorico
                    ? null
                    : _abrirHomologacaoEtapa1,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Homologar Etapa 1'),
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _estadoMigracao['migracao_concluida'] == true
                                ? Icons.cloud_done
                                : Icons.cloud_sync,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _estadoMigracao['migracao_concluida'] == true
                                  ? 'Ponto compartilhado ativado'
                                  : 'Migração inicial pendente',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _estadoMigracao['migracao_concluida'] == true
                            ? 'A nuvem já é a origem compartilhada do Ponto e '
                                  'o SQLite funciona como espelho local.'
                            : 'Migre o histórico antes de ativar batidas e '
                                  'correções compartilhadas entre aparelhos.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (_estadoMigracao['migracao_concluida'] != true) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _migrandoHistorico
                              ? null
                              : _migrarHistorico,
                          icon: _migrandoHistorico
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_sync),
                          label: Text(
                            _migrandoHistorico
                                ? 'Migrando histórico...'
                                : 'Migrar histórico e ativar',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Contas dos funcionários',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final colaborador in _remotos)
                Card(
                  child: ListTile(
                    leading: Icon(
                      (colaborador['auth_user_id']?.toString() ?? '').isEmpty
                          ? Icons.person_outline
                          : Icons.verified_user,
                    ),
                    title: Text(
                      colaborador['nome']?.toString() ?? 'Funcionário',
                    ),
                    subtitle: Text(
                      (colaborador['auth_user_id']?.toString() ?? '').isEmpty
                          ? 'Conta Supabase ainda não vinculada'
                          : 'Conta Supabase vinculada',
                    ),
                    trailing:
                        (colaborador['auth_user_id']?.toString() ?? '').isEmpty
                        ? TextButton(
                            onPressed: () => _vincular(colaborador),
                            child: const Text('Vincular'),
                          )
                        : const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                          ),
                  ),
                ),
            ],
            if (_ultimasFalhas.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Falhas da última sincronização',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final falha in _ultimasFalhas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            '• $falha',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaudeNuvemCard extends StatelessWidget {
  const _SaudeNuvemCard({required this.diagnostico});

  final Map<String, dynamic> diagnostico;

  bool _ok(String chave) => diagnostico[chave] == true;

  @override
  Widget build(BuildContext context) {
    final saudavel = _ok('saudavel');
    final disponivel = _ok('diagnostico_disponivel');
    final versao = diagnostico['backend_version'] ?? 0;
    final mensagem = (diagnostico['mensagem'] ?? 'Diagnóstico não executado.')
        .toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  saudavel
                      ? Icons.health_and_safety
                      : Icons.warning_amber_rounded,
                  color: saudavel ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    saudavel
                        ? 'Saúde da nuvem: pronta'
                        : 'Saúde da nuvem: atenção',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  disponivel ? 'Backend V$versao' : 'Não verificado',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(mensagem, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            _SaudeLinha(titulo: 'Empresa correta', ok: _ok('empresa_confere')),
            _SaudeLinha(titulo: 'Backend V6', ok: _ok('backend_atualizado')),
            _SaudeLinha(titulo: 'Batida online', ok: _ok('rpc_batida_online')),
            _SaudeLinha(
              titulo: 'Batida offline idempotente',
              ok: _ok('rpc_batida_offline'),
            ),
            _SaudeLinha(
              titulo: 'Tabela de idempotência',
              ok: _ok('tabela_idempotencia'),
            ),
            _SaudeLinha(
              titulo: 'Realtime do Ponto',
              ok: _ok('realtime_ponto_registros'),
            ),
            _SaudeLinha(
              titulo: 'Estado de sincronização',
              ok: _ok('sync_estado_disponivel'),
            ),
            _SaudeLinha(
              titulo: 'Migração concluída',
              ok: _ok('migracao_concluida'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaudeLinha extends StatelessWidget {
  const _SaudeLinha({required this.titulo, required this.ok});

  final String titulo;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel_outlined,
            size: 17,
            color: ok ? Colors.greenAccent : Colors.orangeAccent,
          ),
          const SizedBox(width: 7),
          Expanded(child: Text(titulo)),
        ],
      ),
    );
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final int valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            Icon(icone),
            const SizedBox(height: 6),
            Text(
              '$valor',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
