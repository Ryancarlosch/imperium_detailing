import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/ponto_repository.dart';
import '../repositories/ponto_sincronizado_repository.dart';
import '../services/ponto_solicitacao_ajuste_service.dart';

class PontoSolicitacoesAjustePage extends StatefulWidget {
  const PontoSolicitacoesAjustePage.admin({super.key})
    : administrador = true,
      colaboradorLocalId = null,
      colaboradorNome = '';

  const PontoSolicitacoesAjustePage.minhas({
    super.key,
    required this.colaboradorLocalId,
    required this.colaboradorNome,
  }) : administrador = false,
       assert(colaboradorLocalId != null);

  final bool administrador;
  final int? colaboradorLocalId;
  final String colaboradorNome;

  @override
  State<PontoSolicitacoesAjustePage> createState() =>
      _PontoSolicitacoesAjustePageState();
}

class _PontoSolicitacoesAjustePageState
    extends State<PontoSolicitacoesAjustePage> {
  final PontoSolicitacaoAjusteService _service =
      PontoSolicitacaoAjusteService.instance;

  bool _carregando = true;
  bool _processando = false;
  String _statusAdmin = 'Pendente';
  List<Map<String, dynamic>> _solicitacoes = const [];

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
      final dados = widget.administrador
          ? await _service.listarAdmin(status: _statusAdmin)
          : await _service.listarMinhas(
              colaboradorLocalId: widget.colaboradorLocalId!,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _solicitacoes = dados;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() => _carregando = false);
      _mensagem(PontoSolicitacaoAjusteService.textoErro(erro), erro: true);
    }
  }

  Future<void> _novaSolicitacao() async {
    final colaboradorId = widget.colaboradorLocalId;
    if (colaboradorId == null) {
      return;
    }

    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PontoSolicitarAjustePage(
          colaboradorLocalId: colaboradorId,
          colaboradorNome: widget.colaboradorNome.isEmpty
              ? 'Funcionário'
              : widget.colaboradorNome,
        ),
      ),
    );

    if (salvou == true) {
      await _carregar();
    }
  }

  Future<String?> _motivoDecisao({required bool aprovar}) async {
    final controller = TextEditingController();

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(aprovar ? 'Aprovar solicitação?' : 'Rejeitar solicitação?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: aprovar
                ? 'Observação da aprovação'
                : 'Motivo da rejeição *',
            helperText: aprovar
                ? 'Opcional. O motivo informado pelo funcionário continuará no histórico.'
                : 'Obrigatório, com pelo menos 5 caracteres.',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (!aprovar && texto.length < 5) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o motivo da rejeição.'),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(texto);
            },
            child: Text(aprovar ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );

    controller.dispose();
    return resultado;
  }

  Future<void> _decidir(Map<String, dynamic> item, bool aprovar) async {
    if (_processando) {
      return;
    }

    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      return;
    }

    final motivo = await _motivoDecisao(aprovar: aprovar);
    if (motivo == null) {
      return;
    }

    setState(() => _processando = true);

    try {
      await _service.decidir(
        solicitacaoId: id,
        aprovar: aprovar,
        motivo: motivo,
      );

      if (!mounted) {
        return;
      }

      _mensagem(
        aprovar
            ? 'Solicitação aprovada e ponto atualizado.'
            : 'Solicitação rejeitada.',
      );
      await _carregar();
    } catch (erro) {
      if (mounted) {
        _mensagem(PontoSolicitacaoAjusteService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  Future<void> _cancelar(Map<String, dynamic> item) async {
    if (_processando) {
      return;
    }

    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar solicitação?'),
        content: const Text(
          'A solicitação continuará no histórico como cancelada, mas não poderá mais ser aprovada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar solicitação'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    setState(() => _processando = true);

    try {
      await _service.cancelar(id);
      if (mounted) {
        _mensagem('Solicitação cancelada.');
        await _carregar();
      }
    } catch (erro) {
      if (mounted) {
        _mensagem(PontoSolicitacaoAjusteService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }

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
        title: Text(
          widget.administrador
              ? 'Solicitações de ajuste'
              : 'Minhas solicitações',
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: widget.administrador
          ? null
          : FloatingActionButton.extended(
              onPressed: _processando ? null : _novaSolicitacao,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Solicitar correção'),
            ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  14,
                  14,
                  14,
                  widget.administrador ? 30 : 100,
                ),
                children: [
                  if (widget.administrador) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _statusAdmin,
                      decoration: const InputDecoration(
                        labelText: 'Exibir',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Pendente',
                          child: Text('Pendentes'),
                        ),
                        DropdownMenuItem(
                          value: 'Aprovada',
                          child: Text('Aprovadas'),
                        ),
                        DropdownMenuItem(
                          value: 'Rejeitada',
                          child: Text('Rejeitadas'),
                        ),
                        DropdownMenuItem(
                          value: 'Cancelada',
                          child: Text('Canceladas'),
                        ),
                        DropdownMenuItem(value: 'Todos', child: Text('Todas')),
                      ],
                      onChanged: _processando
                          ? null
                          : (valor) {
                              if (valor == null || valor == _statusAdmin) {
                                return;
                              }
                              setState(() => _statusAdmin = valor);
                              _carregar();
                            },
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Card(
                      margin: EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: EdgeInsets.all(13),
                        child: Text(
                          'Quando uma batida ficar errada, envie uma solicitação. O administrador revisa e, ao aprovar, o ponto é corrigido com histórico de auditoria.',
                        ),
                      ),
                    ),
                  ],
                  if (_solicitacoes.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          widget.administrador
                              ? 'Nenhuma solicitação neste filtro.'
                              : 'Você ainda não enviou solicitação de correção.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._solicitacoes.map(
                      (item) => _SolicitacaoCard(
                        item: item,
                        administrador: widget.administrador,
                        processando: _processando,
                        onAprovar: () => _decidir(item, true),
                        onRejeitar: () => _decidir(item, false),
                        onCancelar: () => _cancelar(item),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class PontoSolicitarAjustePage extends StatefulWidget {
  const PontoSolicitarAjustePage({
    super.key,
    required this.colaboradorLocalId,
    required this.colaboradorNome,
    this.dataInicial,
  });

  final int colaboradorLocalId;
  final String colaboradorNome;
  final DateTime? dataInicial;

  @override
  State<PontoSolicitarAjustePage> createState() =>
      _PontoSolicitarAjustePageState();
}

class _PontoSolicitarAjustePageState extends State<PontoSolicitarAjustePage> {
  final PontoRepository _ponto = PontoSincronizadoRepository();
  final PontoSolicitacaoAjusteService _service =
      PontoSolicitacaoAjusteService.instance;
  final TextEditingController _motivo = TextEditingController();
  final TextEditingController _observacoes = TextEditingController();

  late DateTime _data;
  String _situacao = 'Trabalhado';
  String? _entrada;
  String? _intervaloInicio;
  String? _intervaloFim;
  String? _saida;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    final inicial = widget.dataInicial ?? agora;
    _data = DateTime(inicial.year, inicial.month, inicial.day);
    _carregarRegistro();
  }

  @override
  void dispose() {
    _motivo.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregarRegistro() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final registro = await _ponto.buscarRegistro(
        colaboradorId: widget.colaboradorLocalId,
        data: _data,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (registro != null) {
          _situacao = (registro['situacao'] ?? 'Trabalhado').toString();
          _entrada = _hora(registro['entrada']);
          _intervaloInicio = _hora(registro['intervalo_inicio']);
          _intervaloFim = _hora(registro['intervalo_fim']);
          _saida = _hora(registro['saida']);
          _observacoes.text = (registro['observacoes'] ?? '').toString();
        } else {
          _situacao = 'Trabalhado';
          _entrada = null;
          _intervaloInicio = null;
          _intervaloFim = null;
          _saida = null;
          _observacoes.clear();
        }
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  String? _hora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) {
      return null;
    }
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }

  Future<void> _selecionarData() async {
    final agora = DateTime.now();
    final selecionada = await showDatePicker(
      context: context,
      initialDate: _data.isAfter(agora) ? agora : _data,
      firstDate: DateTime(2020),
      lastDate: agora,
    );

    if (selecionada == null) {
      return;
    }

    setState(() => _data = selecionada);
    await _carregarRegistro();
  }

  Future<String?> _selecionarHora(String? atual) async {
    final partes = atual?.split(':') ?? const <String>[];
    final hora = partes.length >= 2
        ? TimeOfDay(
            hour: int.tryParse(partes[0]) ?? 8,
            minute: int.tryParse(partes[1]) ?? 0,
          )
        : TimeOfDay.now();

    final selecionada = await showTimePicker(
      context: context,
      initialTime: hora,
    );

    if (selecionada == null) {
      return atual;
    }

    return '${selecionada.hour.toString().padLeft(2, '0')}:${selecionada.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _salvar() async {
    if (_salvando) {
      return;
    }

    if (_motivo.text.trim().length < 5) {
      _mensagem(
        'Informe o motivo da correção com pelo menos 5 caracteres.',
        erro: true,
      );
      return;
    }

    if (_situacao == 'Trabalhado' && (_entrada == null || _saida == null)) {
      _mensagem('Informe pelo menos entrada e saída.', erro: true);
      return;
    }

    setState(() => _salvando = true);

    try {
      await _service.solicitar(
        colaboradorLocalId: widget.colaboradorLocalId,
        data: _data,
        situacao: _situacao,
        entrada: _entrada,
        intervaloInicio: _intervaloInicio,
        intervaloFim: _intervaloFim,
        saida: _saida,
        observacoes: _observacoes.text,
        motivo: _motivo.text,
      );

      if (!mounted) {
        return;
      }

      _mensagem('Solicitação enviada para aprovação.');
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (mounted) {
        _mensagem(PontoSolicitacaoAjusteService.textoErro(erro), erro: true);
      }
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }

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
      appBar: AppBar(title: const Text('Solicitar correção do ponto')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.badge_outlined),
                    ),
                    title: Text(widget.colaboradorNome),
                    subtitle: const Text(
                      'A alteração só será aplicada depois da aprovação do administrador.',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _salvando ? null : _selecionarData,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(DateFormat('dd/MM/yyyy').format(_data)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _situacao,
                  decoration: const InputDecoration(
                    labelText: 'Situação solicitada',
                    border: OutlineInputBorder(),
                  ),
                  items: PontoRepository.situacoes
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: _salvando
                      ? null
                      : (valor) {
                          if (valor != null) {
                            setState(() => _situacao = valor);
                          }
                        },
                ),
                if (_situacao == 'Trabalhado') ...[
                  const SizedBox(height: 12),
                  _HorarioSolicitado(
                    titulo: 'Entrada',
                    valor: _entrada,
                    onTap: () async {
                      final valor = await _selecionarHora(_entrada);
                      if (mounted) {
                        setState(() => _entrada = valor);
                      }
                    },
                    onLimpar: null,
                  ),
                  _HorarioSolicitado(
                    titulo: 'Início do intervalo',
                    valor: _intervaloInicio,
                    onTap: () async {
                      final valor = await _selecionarHora(_intervaloInicio);
                      if (mounted) {
                        setState(() => _intervaloInicio = valor);
                      }
                    },
                    onLimpar: () => setState(() => _intervaloInicio = null),
                  ),
                  _HorarioSolicitado(
                    titulo: 'Fim do intervalo',
                    valor: _intervaloFim,
                    onTap: () async {
                      final valor = await _selecionarHora(_intervaloFim);
                      if (mounted) {
                        setState(() => _intervaloFim = valor);
                      }
                    },
                    onLimpar: () => setState(() => _intervaloFim = null),
                  ),
                  _HorarioSolicitado(
                    titulo: 'Saída',
                    valor: _saida,
                    onTap: () async {
                      final valor = await _selecionarHora(_saida);
                      if (mounted) {
                        setState(() => _saida = valor);
                      }
                    },
                    onLimpar: null,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _observacoes,
                  enabled: !_salvando,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observações do registro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _motivo,
                  enabled: !_salvando,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Por que precisa corrigir? *',
                    helperText: 'Ex.: esqueci de bater a saída às 17:04.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_salvando ? 'Enviando...' : 'Enviar solicitação'),
                ),
              ],
            ),
    );
  }
}

class _HorarioSolicitado extends StatelessWidget {
  const _HorarioSolicitado({
    required this.titulo,
    required this.valor,
    required this.onTap,
    required this.onLimpar,
  });

  final String titulo;
  final String? valor;
  final VoidCallback onTap;
  final VoidCallback? onLimpar;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(titulo),
      subtitle: Text(valor ?? 'Não informado'),
      trailing: Wrap(
        spacing: 2,
        children: [
          if (onLimpar != null && valor != null)
            IconButton(
              tooltip: 'Limpar',
              onPressed: onLimpar,
              icon: const Icon(Icons.clear_rounded),
            ),
          IconButton(
            tooltip: 'Selecionar horário',
            onPressed: onTap,
            icon: const Icon(Icons.schedule_rounded),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SolicitacaoCard extends StatelessWidget {
  const _SolicitacaoCard({
    required this.item,
    required this.administrador,
    required this.processando,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onCancelar,
  });

  final Map<String, dynamic> item;
  final bool administrador;
  final bool processando;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final VoidCallback onCancelar;

  String _hora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) {
      return '--:--';
    }
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }

  String _data(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null
        ? (valor?.toString() ?? '')
        : DateFormat('dd/MM/yyyy').format(data);
  }

  Color _corStatus(String status) {
    return switch (status) {
      'Aprovada' => Colors.greenAccent,
      'Rejeitada' => Colors.redAccent,
      'Cancelada' => Colors.white54,
      _ => Colors.orangeAccent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] ?? 'Pendente').toString();
    final situacao = (item['situacao_solicitada'] ?? 'Trabalhado').toString();
    final nome = (item['colaborador_nome'] ?? '').toString().trim();
    final motivoDecisao = (item['decisao_motivo'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    administrador && nome.isNotEmpty
                        ? '$nome • ${_data(item['data'])}'
                        : _data(item['data']),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _corStatus(status)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _corStatus(status),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Situação solicitada: $situacao'),
            if (situacao == 'Trabalhado')
              Text(
                'Entrada ${_hora(item['entrada_solicitada'])} • '
                'Intervalo ${_hora(item['intervalo_inicio_solicitado'])} • '
                'Volta ${_hora(item['intervalo_fim_solicitado'])} • '
                'Saída ${_hora(item['saida_solicitada'])}',
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 7),
            Text('Motivo: ${(item['motivo'] ?? '').toString()}'),
            if ((item['observacoes_solicitadas'] ?? '')
                .toString()
                .trim()
                .isNotEmpty)
              Text(
                'Observação: ${item['observacoes_solicitadas']}',
                style: const TextStyle(color: Colors.white70),
              ),
            if (motivoDecisao.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Decisão: $motivoDecisao',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
            if (status == 'Pendente') ...[
              const SizedBox(height: 12),
              if (administrador)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: processando ? null : onAprovar,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Aprovar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: processando ? null : onRejeitar,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Rejeitar'),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: processando ? null : onCancelar,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar solicitação'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
