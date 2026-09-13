import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/usuario_repository.dart';
import '../services/configuracao_cloud_service.dart';
import '../services/crm_orcamentos_cloud_v2_service.dart';
import '../services/empresa_cloud_service.dart';
import '../services/funcionario_acesso_service.dart';
import '../services/operacional_sync_service.dart';

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
  String? _empresaAtualId;
  List<Map<String, dynamic>> _empresas = const [];
  List<Map<String, Object?>> _conflitos = const [];
  List<Map<String, Object?>> _conflitosCrmOrcamentos = const [];
  Map<String, Object?> _diagnosticoCrmOrcamentos = const {};
  Map<String, Object?> _diagnosticoConfig = const {};
  Map<String, Object?> _diagnosticoMultiempresa = const {};

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

  Future<void> _sincronizar() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    try {
      await OperacionalSyncService.instance.tentarSincronizarTudo();
      await _carregar();
      if (mounted) _mensagem('Configurações sincronizadas.');
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
                  _empresasCard(),
                  const SizedBox(height: 12),
                  _modulosCard(),
                  const SizedBox(height: 12),
                  _conflitosCard(),
                  const SizedBox(height: 12),
                  _crmOrcamentosCard(),
                ],
              ),
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
                      : null,
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
