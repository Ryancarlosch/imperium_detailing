import 'package:flutter/material.dart';

import '../services/configuracao_arquivos_cloud_service.dart';
import '../services/operacional_cloud_v2_service.dart';
import '../services/operacional_sync_service.dart';

class SyncConflitosPage extends StatefulWidget {
  const SyncConflitosPage({super.key, required this.empresaId});

  final String empresaId;

  @override
  State<SyncConflitosPage> createState() => _SyncConflitosPageState();
}

class _SyncConflitosPageState extends State<SyncConflitosPage> {
  final OperacionalCloudV2Service _operacional =
      OperacionalCloudV2Service.instance;
  final ConfiguracaoArquivosCloudService _arquivos =
      ConfiguracaoArquivosCloudService.instance;

  bool _carregando = true;
  int? _resolvendoId;
  String? _erro;
  List<_ConflitoUi> _conflitos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final operacional = await _operacional.listarConflitosPendentes(
        empresaId: widget.empresaId,
      );
      final arquivos = await _arquivos.listarConflitosPendentes(
        empresaId: widget.empresaId,
      );

      final itens = <_ConflitoUi>[
        ...operacional.map(
          (item) => _ConflitoUi(
            origem: _OrigemConflito.operacional,
            id: _int(item['id']),
            titulo: _tituloOperacional(_texto(item['entidade'])),
            detalhe: _motivo(_texto(item['motivo'])),
            identificador:
                'Registro local #${_int(item['local_id'])} • nuvem ${_curto(_texto(item['remoto_id']))}',
          ),
        ),
        ...arquivos.map(
          (item) => _ConflitoUi(
            origem: _OrigemConflito.arquivoConfiguracao,
            id: _int(item['id']),
            titulo: _tituloArquivo(_texto(item['tipo'])),
            detalhe: _motivo(_texto(item['motivo'])),
            identificador: 'Arquivo da identidade da empresa',
          ),
        ),
      ];

      if (!mounted) return;
      setState(() {
        _conflitos = itens;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  Future<void> _resolver(_ConflitoUi conflito, {required bool usarLocal}) async {
    if (_resolvendoId != null) return;

    final escolha = usarLocal ? 'este aparelho' : 'a nuvem';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(usarLocal ? 'Manter este aparelho?' : 'Usar versão da nuvem?'),
        content: Text(
          'Você escolheu $escolha para “${conflito.titulo}”. '
          'A decisão será registrada e a sincronização continuará a partir dessa versão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    setState(() => _resolvendoId = conflito.id);

    try {
      if (conflito.origem == _OrigemConflito.operacional) {
        if (usarLocal) {
          await _operacional.resolverUsandoLocal(conflito.id);
        } else {
          await _operacional.resolverUsandoNuvem(conflito.id);
        }
      } else {
        if (usarLocal) {
          await _arquivos.resolverUsandoLocal(conflito.id);
        } else {
          await _arquivos.resolverUsandoNuvem(conflito.id);
        }
      }

      await OperacionalSyncService.instance.sincronizarTudo(
        origem: 'resolucao_conflito',
        ignorarBackoff: true,
      );
      await _arquivos.sincronizar(widget.empresaId);

      if (!mounted) return;
      _mensagem('Conflito resolvido.');
      await _carregar();
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _resolvendoId = null);
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
        title: const Text('Revisar conflitos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? _Erro(mensagem: _erro!, onRetry: _carregar)
          : _conflitos.isEmpty
          ? const _SemConflitos()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _conflitos.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.compare_arrows_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'O Imperium detectou alterações diferentes no aparelho e na nuvem. '
                              'Nada será sobrescrito até você escolher qual versão deve prevalecer.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final conflito = _conflitos[index - 1];
                final resolvendo = _resolvendoId == conflito.id;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              conflito.origem == _OrigemConflito.operacional
                                  ? Icons.sync_problem_rounded
                                  : Icons.image_outlined,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                conflito.titulo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(conflito.detalhe),
                        const SizedBox(height: 4),
                        Text(
                          conflito.identificador,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _resolvendoId == null
                                  ? () => _resolver(conflito, usarLocal: true)
                                  : null,
                              icon: resolvendo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.phone_android_rounded),
                              label: const Text('Usar este aparelho'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _resolvendoId == null
                                  ? () => _resolver(conflito, usarLocal: false)
                                  : null,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Usar nuvem'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static String _texto(Object? value) => (value ?? '').toString();

  static String _curto(String value) {
    final texto = value.trim();
    if (texto.length <= 12) return texto;
    return '${texto.substring(0, 6)}…${texto.substring(texto.length - 4)}';
  }

  static String _tituloOperacional(String entidade) {
    return switch (entidade) {
      'cliente' => 'Cliente alterado em dois aparelhos',
      'veiculo' => 'Veículo alterado em dois aparelhos',
      'agendamento' => 'Agendamento alterado em dois aparelhos',
      _ => 'Registro operacional em conflito',
    };
  }

  static String _tituloArquivo(String tipo) {
    return switch (tipo) {
      'logo' => 'Logo da empresa em conflito',
      'assinatura_empresa' => 'Assinatura da empresa em conflito',
      _ => 'Arquivo da empresa em conflito',
    };
  }

  static String _motivo(String motivo) {
    return switch (motivo) {
      'alteracao_concorrente' =>
        'A versão local e a versão da nuvem foram modificadas desde a última sincronização.',
      'alteracao_local_e_exclusao_remota' =>
        'Este aparelho alterou o registro enquanto ele foi removido em outro aparelho.',
      'registro_remoto_ausente' || 'remoto_ausente' =>
        'O vínculo existia localmente, mas o registro remoto não foi encontrado.',
      'primeira_sincronizacao_divergente' =>
        'Já existem versões diferentes antes do primeiro vínculo entre este aparelho e a nuvem.',
      'primeira_sincronizacao_remoto_excluido' =>
        'Este aparelho possui o arquivo, mas a nuvem registra que ele foi removido.',
      _ => motivo.isEmpty ? 'Alterações concorrentes detectadas.' : motivo,
    };
  }

  static String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'PostgrestException: ',
      'StorageException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto.isEmpty ? 'Não foi possível resolver o conflito.' : texto;
  }
}

enum _OrigemConflito { operacional, arquivoConfiguracao }

class _ConflitoUi {
  const _ConflitoUi({
    required this.origem,
    required this.id,
    required this.titulo,
    required this.detalhe,
    required this.identificador,
  });

  final _OrigemConflito origem;
  final int id;
  final String titulo;
  final String detalhe;
  final String identificador;
}

class _SemConflitos extends StatelessWidget {
  const _SemConflitos();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_outlined, size: 64),
            SizedBox(height: 14),
            Text(
              'Nenhum conflito pendente',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Clientes, veículos, agenda e arquivos da empresa estão livres para sincronizar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.mensagem, required this.onRetry});

  final String mensagem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 54),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
