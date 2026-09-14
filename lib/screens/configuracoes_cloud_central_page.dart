import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/usuario_repository.dart';
import '../services/configuracao_cloud_service.dart';
import '../services/crm_orcamentos_cloud_v2_service.dart';
import '../services/empresa_cloud_service.dart';
import '../services/funcionario_acesso_service.dart';
import '../services/operacional_sync_service.dart';
import '../services/tenant_runtime_service.dart';
import '../services/sync_motor_service.dart';
import '../services/os_arquivos_cloud_v2_service.dart';
import '../services/os_cloud_v3_service.dart';

class ConfiguracoesCloudCentralPage extends StatefulWidget {
  const ConfiguracoesCloudCentralPage({super.key});

  @override
  State<ConfiguracoesCloudCentralPage> createState() =>
      _ConfiguracoesCloudCentralPageState();
}

class _ConfiguracoesCloudCentralPageState
    extends State<ConfiguracoesCloudCentralPage> {
  final ConfiguracaoCloudService _configCloud =
      ConfiguracaoCloudService.instance;
  final EmpresaCloudService _empresaCloud = EmpresaCloudService.instance;
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _sincronizando = false;
  bool _trocandoEmpresa = false;
  String? _empresaAtualId;
  List<Map<String, dynamic>> _empresas = const [];
  List<Map<String, Object?>> _conflitos = const [];
  List<Map<String, Object?>> _conflitosCrmOrcamentos = const [];
  Map<String, Object?> _diagnosticoCrmOrcamentos = const {};
  Map<String, Object?> _diagnosticoArquivosOs = const {};
  List<Map<String, Object?>> _conflitosArquivosOs = const [];
  Map<String, Object?> _diagnosticoOrdensServico = const {};
  List<Map<String, Object?>> _conflitosOrdensServico = const [];
  Map<String, Object?> _diagnosticoConfig = const {};
  Map<String, Object?> _diagnosticoMultiempresa = const {};
  Map<String, Object?> _diagnosticoSync = const {};
  List<Map<String, Object?>> _filaSync = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);

    try {
      final empresaAtualId = await OperacionalSyncService.instance
          .empresaAtualId();
      final empresas = await _empresaCloud.listarEmpresasVinculadas();
      final multi = await _empresaCloud.diagnosticarMultiempresa();

      Map<String, Object?> config = const {};
      List<Map<String, Object?>> conflitos = const [];

      Map<String, Object?> crmOrcamentos = const {};
      List<Map<String, Object?>> conflitosCrmOrcamentos = const [];
      Map<String, Object?> arquivosOs = const {};
      List<Map<String, Object?>> conflitosArquivosOs = const [];
      Map<String, Object?> ordensServico = const {};
      List<Map<String, Object?>> conflitosOrdensServico = const [];
      Map<String, Object?> syncDiagnostico = const {};
      List<Map<String, Object?>> filaSync = const [];
      if (empresaAtualId != null && empresaAtualId.isNotEmpty) {
        config = await _configCloud.diagnosticar(empresaAtualId);
        conflitos = await _configCloud.listarConflitosPendentes(
          empresaId: empresaAtualId,
        );
        crmOrcamentos = await CrmOrcamentosCloudV2Service.instance.diagnosticar(
          empresaAtualId,
        );
        conflitosCrmOrcamentos = await CrmOrcamentosCloudV2Service.instance
            .listarConflitosPendentes(empresaId: empresaAtualId);
        arquivosOs = await OsArquivosCloudV2Service.instance.diagnosticar(
          empresaAtualId,
        );
        conflitosArquivosOs = await OsArquivosCloudV2Service.instance
            .listarConflitosPendentes(empresaId: empresaAtualId);
        ordensServico = await OsCloudV3Service.instance.diagnosticar(
          empresaAtualId,
        );
        conflitosOrdensServico = await OsCloudV3Service.instance
            .listarConflitosPendentes(empresaId: empresaAtualId);
        syncDiagnostico = await SyncMotorService.instance.diagnosticar(
          empresaAtualId,
        );
        filaSync = await SyncMotorService.instance.listarFila(empresaAtualId);
      }

      if (!mounted) return;

      setState(() {
        _empresaAtualId = empresaAtualId;
        _empresas = empresas;
        _diagnosticoConfig = config;
        _diagnosticoMultiempresa = multi;
        _conflitos = conflitos;
        _diagnosticoCrmOrcamentos = crmOrcamentos;
        _conflitosCrmOrcamentos = conflitosCrmOrcamentos;
        _diagnosticoArquivosOs = arquivosOs;
        _conflitosArquivosOs = conflitosArquivosOs;
        _diagnosticoOrdensServico = ordensServico;
        _conflitosOrdensServico = conflitosOrdensServico;
        _diagnosticoSync = syncDiagnostico;
        _filaSync = filaSync;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem(
        'Não foi possível carregar a Central Cloud.\n$erro',
        erro: true,
      );
    }
  }

  Future<void> _trocarEmpresa(Map<String, dynamic> empresa) async {
    if (_trocandoEmpresa) return;

    final empresaId = (empresa['empresa_id'] ?? '').toString().trim();
    final nome = (empresa['nome'] ?? 'Empresa').toString().trim();

    if (empresaId.isEmpty || empresa['atual'] == true) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trocar de empresa?'),
        content: Text(
          'O Imperium vai fechar as telas atuais e abrir a base local '
          'isolada de "$nome".\n\n'
          'Dados ainda não sincronizados da empresa atual permanecem '
          'salvos no banco local dela.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Trocar empresa'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _trocandoEmpresa = true);

    try {
      // Best-effort: tenta esvaziar a fila da empresa atual, mas a troca
      // continua segura offline porque cada tenant possui seu próprio banco.
      await OperacionalSyncService.instance.tentarSincronizarTudo();

      await _empresaCloud.trocarEmpresa(empresaId);

      TenantRuntimeService.instance.reiniciarAplicacao();
    } catch (erro) {
      if (mounted) {
        setState(() => _trocandoEmpresa = false);
        _mensagem('$erro', erro: true);
      }
    }
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    try {
      await OperacionalSyncService.instance.sincronizarTudo(
        origem: 'manual',
        ignorarBackoff: true,
      );
      await _carregar();
      if (mounted) _mensagem('Sincronização concluída.');
    } catch (erro) {
      await _carregar();
      if (mounted) {
        _mensagem(
          'Sincronização parcial. Consulte a Saúde da sincronização.\n$erro',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _resolver(
    Map<String, Object?> conflito, {
    required bool local,
  }) async {
    final id = _int(conflito['id']);
    if (id <= 0) return;

    final escolha = local ? 'deste aparelho' : 'da nuvem';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver conflito?'),
        content: Text(
          'A configuração $escolha será mantida.\n\n'
          'A outra versão será substituída.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      if (local) {
        await _configCloud.resolverUsandoLocal(id);
      } else {
        await _configCloud.resolverUsandoNuvem(id);
      }

      await _sincronizar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    }
  }

  Future<void> _resolverCrmOrcamento(
    Map<String, Object?> conflito, {
    required bool local,
  }) async {
    final id = _int(conflito['id']);
    if (id <= 0) return;

    final escolha = local ? 'deste aparelho' : 'da nuvem';
    final entidade = (conflito['entidade'] ?? 'registro').toString().replaceAll(
      '_',
      ' ',
    );

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver conflito CRM/Orçamento?'),
        content: Text(
          'Será mantida a versão $escolha para $entidade.\n\n'
          'A outra versão será substituída.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      if (local) {
        await CrmOrcamentosCloudV2Service.instance.resolverUsandoLocal(id);
      } else {
        await CrmOrcamentosCloudV2Service.instance.resolverUsandoNuvem(id);
      }

      await _sincronizar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    }
  }

  Future<void> _resolverArquivoOs(
    Map<String, Object?> conflito, {
    required bool local,
  }) async {
    final id = _int(conflito['id']);
    if (id <= 0) return;

    final entidade = (conflito['entidade'] ?? 'arquivo').toString().replaceAll(
      '_',
      ' ',
    );
    final escolha = local ? 'deste aparelho' : 'da nuvem';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver conflito de arquivo?'),
        content: Text(
          'Será mantida a versão $escolha para $entidade.\n\n'
          'A outra versão será substituída.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      if (local) {
        await OsArquivosCloudV2Service.instance.resolverUsandoLocal(id);
      } else {
        await OsArquivosCloudV2Service.instance.resolverUsandoNuvem(id);
      }
      await _sincronizar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    }
  }

  Future<void> _resolverOsCloud(
    Map<String, Object?> conflito, {
    required bool local,
  }) async {
    final id = _int(conflito['id']);
    if (id <= 0) return;

    final escolha = local ? 'deste aparelho' : 'da nuvem';
    final entidade = (conflito['entidade'] ?? 'registro').toString();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver conflito da OS?'),
        content: Text(
          'Será mantida a versão $escolha para $entidade.\n\n'
          'A outra versão será substituída no próximo ciclo seguro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      if (local) {
        await OsCloudV3Service.instance.resolverUsandoLocal(id);
      } else {
        await OsCloudV3Service.instance.resolverUsandoNuvem(id);
      }

      await _sincronizar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    }
  }

  Widget _ordensServicoCloudCard() {
    final conflitos = _conflitosOrdensServico.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.car_repair_outlined),
                SizedBox(width: 8),
                Text(
                  'Ordens de Serviço Cloud V3',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _linha(
              'OS mapeadas',
              '${_int(_diagnosticoOrdensServico['ordens_mapeadas'])}',
            ),
            _linha(
              'Itens mapeados',
              '${_int(_diagnosticoOrdensServico['itens_mapeados'])}',
            ),
            _linha('Conflitos pendentes', '$conflitos'),
            if (_conflitosOrdensServico.isNotEmpty) ...[
              const Divider(),
              ..._conflitosOrdensServico.map(
                (conflito) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.compare_arrows_rounded),
                  title: Text(
                    '${conflito['entidade']} #${conflito['local_id']}',
                  ),
                  subtitle: Text('${conflito['motivo']}'),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _resolverOsCloud(conflito, local: true),
                        child: const Text('Este aparelho'),
                      ),
                      FilledButton.tonal(
                        onPressed: () =>
                            _resolverOsCloud(conflito, local: false),
                        child: const Text('Nuvem'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Text(
                'Nenhum conflito de OS. Alterações Web e Android podem ser '
                'reconciliadas com CAS.',
              ),
          ],
        ),
      ),
    );
  }

  void _mensagem(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações Cloud'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar agora',
            onPressed: _sincronizando ? null : _sincronizar,
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
                children: [
                  _statusCard(),
                  const SizedBox(height: 12),
                  _syncSaudeCard(),
                  const SizedBox(height: 12),
                  _empresasCard(),
                  const SizedBox(height: 12),
                  _modulosCard(),
                  const SizedBox(height: 12),
                  _conflitosCard(),
                  const SizedBox(height: 12),
                  _crmOrcamentosCard(),
                  const SizedBox(height: 12),
                  _arquivosOsCard(),
                  const SizedBox(height: 12),
                  _ordensServicoCloudCard(),
                ],
              ),
            ),
    );
  }

  Widget _syncSaudeCard() {
    final status =
        (_diagnosticoSync['ultimo_ciclo_status'] ?? 'Nunca executado')
            .toString();
    final erros = _int(_diagnosticoSync['modulos_erro']);
    final bloqueados = _int(_diagnosticoSync['modulos_bloqueados']);
    final aguardando = _int(_diagnosticoSync['modulos_aguardando']);
    final ultimoSucesso = DateTime.tryParse(
      (_diagnosticoSync['ultimo_sucesso_em'] ?? '').toString(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.monitor_heart_outlined),
                SizedBox(width: 8),
                Text(
                  'Saúde da sincronização',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _linha('Último ciclo', status),
            _linha('Módulos com erro', '$erros'),
            _linha('Módulos bloqueados', '$bloqueados'),
            _linha('Aguardando retry', '$aguardando'),
            if (ultimoSucesso != null)
              _linha(
                'Último sucesso',
                _dataHora.format(ultimoSucesso.toLocal()),
              ),
            const Divider(),
            if (_filaSync.isEmpty)
              const Text(
                'A fila será criada na primeira sincronização com o novo motor.',
              )
            else
              ..._filaSync.map(_syncModuloLinha),
            const SizedBox(height: 8),
            const Text(
              'O botão de sincronizar no topo força nova tentativa imediata, '
              'ignorando o backoff. Conflitos continuam exigindo resolução.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncModuloLinha(Map<String, Object?> item) {
    final modulo = (item['modulo'] ?? '-').toString();
    final status = (item['status'] ?? 'Pendente').toString();
    final tentativas = _int(item['tentativas_consecutivas']);
    final proxima = DateTime.tryParse(
      (item['proxima_tentativa_em'] ?? '').toString(),
    );
    final erro = (item['ultimo_erro'] ?? '').toString().trim();

    final nome =
        <String, String>{
          'configuracoes': 'Configurações',
          'operacional': 'Clientes / Veículos / Agenda',
          'ordens_servico': 'Ordens de Serviço',
          'arquivos_os': 'Arquivos da OS',
          'crm_orcamentos': 'CRM / Orçamentos',
          'estoque': 'Estoque',
          'financeiro': 'Financeiro',
          'precificacao': 'Precificação',
          'ponto': 'Ponto',
        }[modulo] ??
        modulo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status == 'Sucesso'
                ? Icons.check_circle_outline_rounded
                : status == 'Erro'
                ? Icons.error_outline_rounded
                : status == 'Bloqueado'
                ? Icons.block_rounded
                : status == 'Aguardando'
                ? Icons.schedule_rounded
                : Icons.sync_rounded,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$nome — $status',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (tentativas > 0)
                  Text(
                    'Tentativas consecutivas: $tentativas',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (proxima != null)
                  Text(
                    'Próximo retry: ${_dataHora.format(proxima.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (erro.isNotEmpty)
                  Text(
                    erro,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final mapeada = _diagnosticoConfig['mapeada'] == true;
    final conflitos = _int(_diagnosticoConfig['conflitos_pendentes']);
    final remotoEm = DateTime.tryParse(
      (_diagnosticoConfig['remoto_atualizado_em'] ?? '').toString(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings_suggest_outlined),
                SizedBox(width: 8),
                Text(
                  'Configuração compartilhada',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _linha('Empresa atual', _empresaAtualId ?? 'Não identificada'),
            _linha('Mapeada na nuvem', mapeada ? 'Sim' : 'Ainda não'),
            _linha('Conflitos pendentes', '$conflitos'),
            if (remotoEm != null)
              _linha('Última versão remota', _dataHora.format(remotoEm)),
            const Divider(),
            const Text(
              'Logo, assinatura e caminhos de backup continuam locais. '
              'Esses arquivos irão para Storage em uma etapa separada.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _empresasCard() {
    final multi = _diagnosticoMultiempresa['multiempresa_detectada'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.domain_outlined),
                SizedBox(width: 8),
                Text(
                  'Empresas vinculadas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
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
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                  ),
                  title: Text((empresa['nome'] ?? 'Empresa').toString()),
                  subtitle: Text(
                    'Papel: ${(empresa['papel'] ?? '-').toString()}',
                  ),
                  trailing: empresa['atual'] == true
                      ? const Chip(label: Text('Atual'))
                      : OutlinedButton.icon(
                          onPressed: _trocandoEmpresa
                              ? null
                              : () => _trocarEmpresa(empresa),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Trocar'),
                        ),
                ),
              ),
            if (multi) ...[
              const Divider(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mais de uma empresa foi detectada. A troca de empresa '
                        'ainda fica bloqueada porque o SQLite local precisa ser '
                        'isolado por empresa antes de alternar tenants com segurança.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modulosCard() {
    final prontos = FuncionarioAcessoService.modulosRemotosProntos.toList()
      ..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.security_outlined),
                SizedBox(width: 8),
                Text(
                  'Permissões Cloud ativas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Estes módulos já podem receber as permissões do acesso '
              'funcionário sem cair no bloqueio de módulo ainda não homologado.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: prontos
                  .map(
                    (modulo) => Chip(
                      avatar: const Icon(Icons.cloud_done_outlined, size: 17),
                      label: Text(
                        UsuarioRepository.nomesModulos[modulo] ?? modulo,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            const Text(
              'Precificação permanece protegida pela permissão Financeiro '
              'na nuvem e por isso ainda não entra como permissão Cloud independente.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _conflitosCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.sync_problem_rounded),
                SizedBox(width: 8),
                Text(
                  'Conflitos de configuração',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_conflitos.isEmpty)
              const Text('Nenhum conflito pendente.')
            else
              ..._conflitos.map(
                (conflito) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _conflitoItem(conflito),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conflitoItem(Map<String, Object?> conflito) {
    final motivo = (conflito['motivo'] ?? '').toString().replaceAll('_', ' ');
    final detectado = DateTime.tryParse(
      (conflito['detectado_em'] ?? '').toString(),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            motivo.isEmpty ? 'Alteração concorrente' : motivo,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (detectado != null)
            Text(
              'Detectado em ${_dataHora.format(detectado)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resolver(conflito, local: false),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Usar nuvem'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _resolver(conflito, local: true),
                  icon: const Icon(Icons.phone_android_rounded),
                  label: const Text('Usar local'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _crmOrcamentosCard() {
    final conflitos = _int(_diagnosticoCrmOrcamentos['conflitos_pendentes']);
    final orcamentos = _int(_diagnosticoCrmOrcamentos['orcamentos_mapeados']);
    final leads = _int(_diagnosticoCrmOrcamentos['crm_leads_mapeados']);
    final campanhas = _int(_diagnosticoCrmOrcamentos['crm_campanhas_mapeadas']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_outlined),
                SizedBox(width: 8),
                Text(
                  'CRM e Orçamentos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _linha('Orçamentos mapeados', '$orcamentos'),
            _linha('Leads mapeados', '$leads'),
            _linha('Campanhas mapeadas', '$campanhas'),
            _linha('Conflitos pendentes', '$conflitos'),
            const SizedBox(height: 10),
            if (_conflitosCrmOrcamentos.isEmpty)
              const Text('Nenhum conflito CRM/Orçamentos pendente.')
            else
              ..._conflitosCrmOrcamentos.map(
                (conflito) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _crmOrcamentoConflitoItem(conflito),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _crmOrcamentoConflitoItem(Map<String, Object?> conflito) {
    final entidade = (conflito['entidade'] ?? 'registro').toString().replaceAll(
      '_',
      ' ',
    );
    final motivo = (conflito['motivo'] ?? 'alteracao_concorrente')
        .toString()
        .replaceAll('_', ' ');
    final localId = _int(conflito['local_id']);
    final detectado = DateTime.tryParse(
      (conflito['detectado_em'] ?? '').toString(),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$entidade #$localId',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(motivo),
          if (detectado != null)
            Text(
              'Detectado em ${_dataHora.format(detectado)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _resolverCrmOrcamento(conflito, local: false),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Usar nuvem'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _resolverCrmOrcamento(conflito, local: true),
                  icon: const Icon(Icons.phone_android_rounded),
                  label: const Text('Usar local'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _arquivosOsCard() {
    final fotos = _int(_diagnosticoArquivosOs['fotos_mapeadas']);
    final checklist = _int(_diagnosticoArquivosOs['checklist_mapeado']);
    final assinaturas = _int(_diagnosticoArquivosOs['assinaturas_mapeadas']);
    final conflitos = _int(_diagnosticoArquivosOs['conflitos_pendentes']);
    final erros =
        _int(_diagnosticoArquivosOs['fotos_com_erro']) +
        _int(_diagnosticoArquivosOs['checklist_com_erro']) +
        _int(_diagnosticoArquivosOs['assinaturas_com_erro']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.folder_copy_outlined),
                SizedBox(width: 8),
                Text(
                  'Arquivos da OS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _linha('Fotos mapeadas', '$fotos'),
            _linha('Itens de checklist', '$checklist'),
            _linha('Assinaturas mapeadas', '$assinaturas'),
            _linha('Erros de arquivo', '$erros'),
            _linha('Conflitos pendentes', '$conflitos'),
            const SizedBox(height: 10),
            if (_conflitosArquivosOs.isEmpty)
              const Text('Nenhum conflito de arquivo pendente.')
            else
              ..._conflitosArquivosOs.map(
                (conflito) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _arquivoOsConflitoItem(conflito),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _arquivoOsConflitoItem(Map<String, Object?> conflito) {
    final entidade = (conflito['entidade'] ?? 'arquivo').toString().replaceAll(
      '_',
      ' ',
    );
    final motivo = (conflito['motivo'] ?? 'alteracao_concorrente')
        .toString()
        .replaceAll('_', ' ');
    final localId = _int(conflito['local_id']);
    final detectado = DateTime.tryParse(
      (conflito['detectado_em'] ?? '').toString(),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$entidade #$localId',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(motivo),
          if (detectado != null)
            Text(
              'Detectado em ${_dataHora.format(detectado)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resolverArquivoOs(conflito, local: false),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Usar nuvem'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _resolverArquivoOs(conflito, local: true),
                  icon: const Icon(Icons.phone_android_rounded),
                  label: const Text('Usar local'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }
}
