import 'package:flutter/material.dart';

import '../services/operacional_cloud_v2_service.dart';
import '../services/operacional_sync_service.dart';

class OperacionalConflitosCard extends StatefulWidget {
  const OperacionalConflitosCard({
    super.key,
    this.onSincronizar,
  });

  final Future<void> Function()? onSincronizar;

  @override
  State<OperacionalConflitosCard> createState() =>
      _OperacionalConflitosCardState();
}

class _OperacionalConflitosCardState extends State<OperacionalConflitosCard> {
  final OperacionalCloudV2Service _cloud = OperacionalCloudV2Service.instance;

  bool _carregando = true;
  bool _resolvendo = false;
  Map<String, Object?> _diagnostico = const {};
  List<Map<String, Object?>> _conflitos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);

    try {
      final empresaId = await OperacionalSyncService.instance.empresaAtualId();
      if (empresaId == null || empresaId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _diagnostico = const {};
          _conflitos = const [];
          _carregando = false;
        });
        return;
      }

      final diagnostico = await _cloud.diagnosticar(empresaId);
      final conflitos = await _cloud.listarConflitosPendentes(
        empresaId: empresaId,
      );

      if (!mounted) return;
      setState(() {
        _diagnostico = diagnostico;
        _conflitos = conflitos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar conflitos operacionais.\n$erro', erro: true);
    }
  }

  Future<void> _resolver(
    Map<String, Object?> conflito, {
    required bool local,
  }) async {
    if (_resolvendo) return;

    final id = _int(conflito['id']);
    if (id <= 0) return;

    final entidade = _nomeEntidade(conflito['entidade']);
    final escolha = local ? 'deste aparelho' : 'da nuvem';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver conflito operacional?'),
        content: Text(
          'Será mantida a versão $escolha para $entidade.\n\n'
          'A outra versão será substituída. Se a nuvem mudar novamente durante '
          'a resolução, o Imperium recusará a gravação e pedirá nova revisão.',
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

    if (confirmar != true || !mounted) return;
    setState(() => _resolvendo = true);

    try {
      if (local) {
        await _cloud.resolverUsandoLocal(id);
      } else {
        await _cloud.resolverUsandoNuvem(id);
      }

      final sincronizar = widget.onSincronizar;
      if (sincronizar != null) {
        await sincronizar();
      } else {
        await OperacionalSyncService.instance.sincronizarTudo(
          origem: 'resolucao_conflito_operacional',
          ignorarBackoff: true,
        );
      }

      await _carregar();
      if (mounted) _mensagem('Conflito operacional resolvido.');
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    } finally {
      if (mounted) setState(() => _resolvendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _int(_diagnostico['conflitos_pendentes']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Clientes, Veículos e Agenda',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar conflitos operacionais',
                  onPressed: _carregando || _resolvendo ? null : _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_carregando)
              const LinearProgressIndicator()
            else ...[
              _linha(
                'Clientes mapeados',
                '${_int(_diagnostico['clientes_mapeados'])}',
              ),
              _linha(
                'Veículos mapeados',
                '${_int(_diagnostico['veiculos_mapeados'])}',
              ),
              _linha(
                'Agendamentos mapeados',
                '${_int(_diagnostico['agendamentos_mapeados'])}',
              ),
              _linha('Conflitos pendentes', '$pendentes'),
              if (_conflitos.isEmpty) ...[
                const Divider(),
                const Text(
                  'Nenhum conflito operacional pendente. O motor usa a versão '
                  'remota como atualização quando somente a nuvem mudou e bloqueia '
                  'a sincronização quando os dois lados foram alterados.',
                ),
              ] else ...[
                const Divider(),
                ..._conflitos.map(_conflitoItem),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _conflitoItem(Map<String, Object?> conflito) {
    final entidade = _nomeEntidade(conflito['entidade']);
    final motivo = (conflito['motivo'] ?? 'alteracao_concorrente')
        .toString()
        .replaceAll('_', ' ');
    final localId = _int(conflito['local_id']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resolvendo
                        ? null
                        : () => _resolver(conflito, local: false),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Usar nuvem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _resolvendo
                        ? null
                        : () => _resolver(conflito, local: true),
                    icon: const Icon(Icons.phone_android_rounded),
                    label: const Text('Este aparelho'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _nomeEntidade(Object? valor) {
    switch ((valor ?? '').toString()) {
      case 'cliente':
        return 'Cliente';
      case 'veiculo':
        return 'Veículo';
      case 'agendamento':
        return 'Agendamento';
      default:
        return 'Registro operacional';
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

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }
}
