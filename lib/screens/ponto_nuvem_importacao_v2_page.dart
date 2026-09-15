import 'package:flutter/material.dart';

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

  bool _carregando = true;
  bool _importando = false;
  bool _migrandoHistorico = false;

  Map<String, dynamic> _resumo = const {};
  Map<String, dynamic> _estadoMigracao = const {};
  List<Map<String, dynamic>> _remotos = const [];
  List<String> _ultimasFalhas = const [];

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
            ? '${resultado.sucesso} funcionário(s) sincronizado(s).'
            : '${resultado.sucesso} concluído(s) e '
                  '${resultado.falhas.length} falha(s).',
        erro: resultado.falhas.isNotEmpty,
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem('Não foi possível sincronizar: $erro', erro: true);
    } finally {
      if (mounted) {
        setState(() => _importando = false);
      }
    }
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

  Future<void> _abrirHomologacaoEtapa1() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PontoEtapa1ValidacaoPage(empresaId: widget.empresaId),
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
          'Esta operação envia o histórico atual do aparelho para a nuvem. '
          'O modo compartilhado só será ativado depois que a migração terminar '
          'com sucesso.',
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

  Widget _resumoCard({
    required String titulo,
    required int valor,
    required IconData icone,
  }) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            children: [
              Icon(icone),
              const SizedBox(height: 6),
              Text(
                '$valor',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardMigracao() {
    final concluida = _estadoMigracao['migracao_concluida'] == true;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(concluida ? Icons.cloud_done : Icons.cloud_sync),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    concluida
                        ? 'Ponto compartilhado ativado'
                        : 'Migração inicial pendente',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              concluida
                  ? 'A nuvem já é a origem compartilhada do Ponto entre os '
                        'aparelhos autorizados da empresa.'
                  : 'Migre o histórico antes de ativar batidas e correções '
                        'compartilhadas entre aparelhos.',
              style: const TextStyle(color: Colors.white70),
            ),
            if (!concluida) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _migrandoHistorico ? null : _migrarHistorico,
                  icon: _migrandoHistorico
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync),
                  label: Text(
                    _migrandoHistorico
                        ? 'Migrando histórico...'
                        : 'Migrar histórico e ativar',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _listaFuncionarios() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.groups_2_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Funcionários sincronizados',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Os funcionários pertencem à empresa e são gerenciados pelo '
              'administrador dentro do Imperium. Nenhuma configuração manual '
              'no Supabase é necessária.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            if (_remotos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhum funcionário sincronizado ainda.'),
              )
            else
              ..._remotos.map(
                (colaborador) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.badge_outlined),
                  ),
                  title: Text(
                    colaborador['nome']?.toString() ?? 'Funcionário',
                  ),
                  subtitle: const Text(
                    'Cadastro operacional vinculado à empresa',
                  ),
                  trailing: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _importando || _migrandoHistorico
                    ? null
                    : _abrirAcessosFuncionarios,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gerenciar funcionários e permissões'),
              ),
            ),
          ],
        ),
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
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'O Ponto sincroniza somente a identidade operacional '
                        'e os registros necessários. Salário, encargos e '
                        'custos continuam protegidos na gestão da empresa.',
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
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Row(
                children: [
                  _resumoCard(
                    titulo: 'Locais',
                    valor: _numero('total_local'),
                    icone: Icons.badge_outlined,
                  ),
                  const SizedBox(width: 8),
                  _resumoCard(
                    titulo: 'Vinculados',
                    valor: _numero('vinculados'),
                    icone: Icons.link_rounded,
                  ),
                  const SizedBox(width: 8),
                  _resumoCard(
                    titulo: 'Na nuvem',
                    valor: _numero('remoto'),
                    icone: Icons.cloud_done_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _importando ? null : _importar,
                  icon: _importando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _importando
                        ? 'Sincronizando...'
                        : 'Sincronizar funcionários',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _importando || _migrandoHistorico
                      ? null
                      : _abrirHomologacaoEtapa1,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Homologar Etapa 1'),
                ),
              ),
              const SizedBox(height: 14),
              _cardMigracao(),
              const SizedBox(height: 14),
              _listaFuncionarios(),
            ],
            if (_ultimasFalhas.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Falhas da última sincronização',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._ultimasFalhas.map(
                        (falha) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '• $falha',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
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
