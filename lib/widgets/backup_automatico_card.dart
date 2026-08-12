import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backup_automatico_service.dart';
import '../services/google_drive_backup_service.dart';

class BackupAutomaticoCard extends StatefulWidget {
  const BackupAutomaticoCard({super.key});

  @override
  State<BackupAutomaticoCard> createState() => _BackupAutomaticoCardState();
}

class _BackupAutomaticoCardState extends State<BackupAutomaticoCard> {
  final BackupAutomaticoService _service = BackupAutomaticoService.instance;
  final GoogleDriveBackupService _drive = GoogleDriveBackupService.instance;
  final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _processando = false;
  bool _processandoDrive = false;

  BackupAutomaticoConfiguracao? _configuracao;
  GoogleDriveEstado? _estadoDrive;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _service.carregarConfiguracao(),
        _drive.obterEstado(),
      ]);

      if (!mounted) return;

      setState(() {
        _configuracao = resultados[0] as BackupAutomaticoConfiguracao;
        _estadoDrive = resultados[1] as GoogleDriveEstado;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
      });
    }
  }

  Future<void> _recarregarDrive() async {
    try {
      final estado = await _drive.obterEstado();

      if (!mounted) return;

      setState(() {
        _estadoDrive = estado;
      });
    } catch (_) {
      // Estado visual best-effort.
    }
  }

  Future<void> _alterarAtivo(bool valor) async {
    final atual = _configuracao;
    if (atual == null || _processando) return;

    setState(() {
      _configuracao = atual.copyWith(ativo: valor);
    });

    try {
      final salva = await _service.salvarConfiguracao(
        atual.copyWith(ativo: valor),
      );

      if (!mounted) return;

      setState(() {
        _configuracao = salva;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _configuracao = atual;
      });

      _mensagem('Não foi possível alterar o backup automático: $erro', true);
    }
  }

  Future<void> _alterarIntervalo(int? horas) async {
    final atual = _configuracao;
    if (atual == null || horas == null || _processando) return;

    setState(() {
      _configuracao = atual.copyWith(intervaloHoras: horas);
    });

    try {
      final salva = await _service.salvarConfiguracao(
        atual.copyWith(intervaloHoras: horas),
      );

      if (!mounted) return;

      setState(() {
        _configuracao = salva;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _configuracao = atual;
      });

      _mensagem('Não foi possível salvar a frequência: $erro', true);
    }
  }

  Future<void> _alterarRetencao(int? quantidade) async {
    final atual = _configuracao;
    if (atual == null || quantidade == null || _processando) return;

    setState(() {
      _configuracao = atual.copyWith(manterCopias: quantidade);
    });

    try {
      final salva = await _service.salvarConfiguracao(
        atual.copyWith(manterCopias: quantidade),
      );

      if (!mounted) return;

      setState(() {
        _configuracao = salva;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _configuracao = atual;
      });

      _mensagem('Não foi possível salvar a retenção: $erro', true);
    }
  }

  Future<void> _executarAgora() async {
    if (_processando) return;

    setState(() {
      _processando = true;
    });

    final resultado = await _service.verificarEExecutar(forcar: true);
    await _carregar();

    if (!mounted) return;

    setState(() {
      _processando = false;
    });

    _mensagem(
      resultado.sucesso
          ? resultado.mensagem
          : 'Falha no backup automático: ${resultado.mensagem}',
      !resultado.sucesso,
    );
  }

  Future<void> _conectarDrive() async {
    if (_processandoDrive) return;

    setState(() {
      _processandoDrive = true;
    });

    try {
      final estado = await _drive.conectar();

      if (!mounted) return;

      setState(() {
        _estadoDrive = estado;
      });

      _mensagem('Google Drive conectado com sucesso.', false);
    } catch (erro) {
      if (!mounted) return;

      _mensagem('Não foi possível conectar o Google Drive: $erro', true);
    } finally {
      if (mounted) {
        setState(() {
          _processandoDrive = false;
        });
      }
    }
  }

  Future<void> _desconectarDrive() async {
    if (_processandoDrive) return;

    setState(() {
      _processandoDrive = true;
    });

    try {
      final estado = await _drive.desconectar();

      if (!mounted) return;

      setState(() {
        _estadoDrive = estado;
      });

      _mensagem('Google Drive desconectado.', false);
    } catch (erro) {
      if (!mounted) return;

      _mensagem('Não foi possível desconectar: $erro', true);
    } finally {
      if (mounted) {
        setState(() {
          _processandoDrive = false;
        });
      }
    }
  }

  String _data(String? valor) {
    final data = DateTime.tryParse(valor?.trim() ?? '');
    if (data == null) return 'Ainda não executado';

    return _formatoData.format(data.toLocal());
  }

  String _frequencia(int horas) {
    switch (horas) {
      case 12:
        return 'A cada 12 horas';
      case 24:
        return 'Diariamente';
      case 72:
        return 'A cada 3 dias';
      case 168:
        return 'Semanalmente';
      default:
        return 'A cada $horas horas';
    }
  }

  void _mensagem(String texto, bool erro) {
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
    if (_carregando) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Carregando backup automático...')),
            ],
          ),
        ),
      );
    }

    final configuracao = _configuracao;

    if (configuracao == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Não foi possível carregar a configuração do backup automático.',
                ),
              ),
              TextButton(onPressed: _carregar, child: const Text('Tentar')),
            ],
          ),
        ),
      );
    }

    final possuiErro = (configuracao.ultimoErro ?? '').trim().isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: configuracao.ativo,
              onChanged: _processando ? null : _alterarAtivo,
              secondary: Icon(
                configuracao.ativo ? Icons.backup_outlined : Icons.cloud_off,
              ),
              title: const Text(
                'Backup automático',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Ao entrar no Imperium, cria uma cópia quando a frequência estiver vencida.',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: configuracao.intervaloHoras,
                    decoration: const InputDecoration(
                      labelText: 'Frequência',
                      prefixIcon: Icon(Icons.schedule),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 12,
                        child: Text('A cada 12 horas'),
                      ),
                      DropdownMenuItem(value: 24, child: Text('Diariamente')),
                      DropdownMenuItem(value: 72, child: Text('A cada 3 dias')),
                      DropdownMenuItem(value: 168, child: Text('Semanalmente')),
                    ],
                    onChanged: _processando ? null : _alterarIntervalo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: configuracao.manterCopias,
                    decoration: const InputDecoration(
                      labelText: 'Manter cópias',
                      prefixIcon: Icon(Icons.layers),
                    ),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3 cópias')),
                      DropdownMenuItem(value: 7, child: Text('7 cópias')),
                      DropdownMenuItem(value: 15, child: Text('15 cópias')),
                      DropdownMenuItem(value: 30, child: Text('30 cópias')),
                    ],
                    onChanged: _processando ? null : _alterarRetencao,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (possuiErro ? Colors.redAccent : Colors.white)
                      .withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    possuiErro
                        ? 'Última tentativa encontrou uma falha'
                        : 'Último backup automático local',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _data(configuracao.ultimoSucessoEm),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (possuiErro) ...[
                    const SizedBox(height: 5),
                    Text(
                      configuracao.ultimoErro!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    '${_frequencia(configuracao.intervaloHoras)} • '
                    '${configuracao.manterCopias} cópia(s) automáticas',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _GoogleDriveCard(
              estado: _estadoDrive,
              processando: _processandoDrive,
              onConectar: _conectarDrive,
              onDesconectar: _desconectarDrive,
              onAtualizar: _recarregarDrive,
              formatarData: _data,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _processando ? null : _executarAgora,
              icon: _processando
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _processando ? 'Criando backup...' : 'Criar backup agora',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleDriveCard extends StatelessWidget {
  const _GoogleDriveCard({
    required this.estado,
    required this.processando,
    required this.onConectar,
    required this.onDesconectar,
    required this.onAtualizar,
    required this.formatarData,
  });

  final GoogleDriveEstado? estado;
  final bool processando;
  final VoidCallback onConectar;
  final VoidCallback onDesconectar;
  final VoidCallback onAtualizar;
  final String Function(String?) formatarData;

  @override
  Widget build(BuildContext context) {
    final atual = estado;

    if (atual == null) {
      return const SizedBox.shrink();
    }

    if (!atual.configurado) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.orangeAccent.withValues(alpha: 0.30),
          ),
          color: Colors.orangeAccent.withValues(alpha: 0.06),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Google Drive preparado, mas o Client ID ainda não foi '
                'configurado. O backup local continua funcionando normalmente.',
              ),
            ),
          ],
        ),
      );
    }

    final erro = (atual.ultimoErro ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (atual.conectado ? Colors.greenAccent : Colors.white)
              .withValues(alpha: 0.18),
        ),
        color: const Color(0xFF121212),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(atual.conectado ? Icons.cloud_done : Icons.cloud),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  atual.conectado
                      ? 'Google Drive conectado'
                      : 'Google Drive disponível',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: processando ? null : onAtualizar,
                tooltip: 'Atualizar estado',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (atual.conectado) ...[
            if ((atual.nome ?? '').trim().isNotEmpty)
              Text(atual.nome!, style: const TextStyle(color: Colors.white70)),
            if ((atual.email ?? '').trim().isNotEmpty)
              Text(
                atual.email!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            const SizedBox(height: 10),
            Text(
              'Último envio: ${formatarData(atual.ultimoEnvioEm)}',
              style: const TextStyle(color: Colors.white70),
            ),
            if ((atual.ultimoArquivoNome ?? '').trim().isNotEmpty)
              Text(
                atual.ultimoArquivoNome!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ] else
            const Text(
              'Conecte a conta que receberá os backups do Imperium.',
              style: TextStyle(color: Colors.white70),
            ),
          if (erro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              erro,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (atual.conectado)
            OutlinedButton.icon(
              onPressed: processando ? null : onDesconectar,
              icon: processando
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_off),
              label: const Text('Desconectar Google Drive'),
            )
          else
            FilledButton.icon(
              onPressed: processando ? null : onConectar,
              icon: processando
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Conectar Google Drive'),
            ),
        ],
      ),
    );
  }
}
