import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/ponto_repository.dart';
import '../repositories/ponto_sincronizado_repository.dart';
import '../services/ponto_realtime_service.dart';

class MeuPontoPage extends StatefulWidget {
  const MeuPontoPage({
    super.key,
    required this.colaboradorId,
    required this.nome,
  });

  final int colaboradorId;
  final String nome;

  @override
  State<MeuPontoPage> createState() => _MeuPontoPageState();
}

class _MeuPontoPageState extends State<MeuPontoPage> {
  final PontoRepository _repository = PontoSincronizadoRepository();
  final PontoRealtimeService _realtime = PontoRealtimeService.instance;

  bool _carregando = true;
  bool _batendo = false;
  bool _realtimeAtivo = false;
  Map<String, dynamic>? _estado;
  Map<String, dynamic>? _mes;

  Set<String> _diasCorrigidos = const <String>{};
  DateTime get _inicioMes {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, 1);
  }

  DateTime get _fimMes {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month + 1, 0);
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarRealtime();
    });
  }

  // meu-ponto-iniciar-realtime-v4b
  Future<void> _iniciarRealtime() async {
    final ativo = await _realtime.assinarColaborador(
      colaboradorLocalId: widget.colaboradorId,
      onAtualizar: () async {
        if (!mounted || _batendo) return;
        await _carregar();
      },
    );

    if (!mounted) return;

    setState(() {
      _realtimeAtivo = ativo;
    });
  }

  @override
  void dispose() {
    unawaited(_realtime.cancelar());
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final resultados = await Future.wait<dynamic>([
        _repository.obterEstadoBatidaHoje(widget.colaboradorId),
        _repository.obterFechamentoMes(
          colaboradorId: widget.colaboradorId,
          inicio: _inicioMes,
          fim: _fimMes,
        ),
        _repository.listarDiasCorrigidos(
          colaboradorId: widget.colaboradorId,
          inicio: _inicioMes,
          fim: _fimMes,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _estado = Map<String, dynamic>.from(resultados[0] as Map);
        _mes = Map<String, dynamic>.from(resultados[1] as Map);
        _diasCorrigidos = Set<String>.from(resultados[2] as Iterable);
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);

      _mensagem('Não foi possível carregar seu ponto.\n$erro', erro: true);
    }
  }

  Future<void> _bater() async {
    if (_batendo) return;

    final estado = _estado;
    final rotulo = (estado?['rotulo'] ?? 'Bater ponto').toString();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(rotulo),
        content: Text(
          '${widget.nome}\n\n'
          'O aplicativo registra automaticamente a data e o horário. '
          'Com internet, o servidor confirma o horário; sem internet, '
          'a batida fica salva neste celular e sincroniza depois.\n\n'
          'Você só precisa confirmar a batida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _batendo = true);

    try {
      final resultado = await _repository.registrarBatida(
        colaboradorId: widget.colaboradorId,
      );

      final acao = (resultado['acao'] ?? 'Batida').toString();
      final hora = (resultado['hora'] ?? '').toString();

      await _carregar();

      _mensagem('$acao registrada às $hora.');
    } catch (erro) {
      _mensagem('$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() => _batendo = false);
      }
    }
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

  String _horas(dynamic minutos) {
    final total = minutos is num ? minutos.toInt() : 0;
    final h = total ~/ 60;
    final m = total % 60;

    return '${h}h '
        '${m.toString().padLeft(2, '0')}min';
  }

  Map<String, dynamic>? get _registro {
    final bruto = _estado?['registro'];

    if (bruto is Map) {
      return Map<String, dynamic>.from(bruto);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    final registro = _registro;

    final concluido = estado?['concluido'] == 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu ponto'),
        actions: [
          if (_realtimeAtivo)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.sync_rounded,
                size: 18,
                color: Colors.greenAccent,
              ),
            ), // meu-ponto-indicador-realtime-v4b
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
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.nome,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'EEEE, dd/MM/yyyy',
                              'pt_BR',
                            ).format(DateTime.now()),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.fingerprint_rounded, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (estado?['rotulo'] ?? 'Registrar batida')
                                      .toString(),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (registro != null)
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _BatidaChip(
                                  titulo: 'Entrada',
                                  valor: registro['entrada']?.toString(),
                                ),
                                _BatidaChip(
                                  titulo: 'Intervalo',
                                  valor: registro['intervalo_inicio']
                                      ?.toString(),
                                ),
                                _BatidaChip(
                                  titulo: 'Volta',
                                  valor: registro['intervalo_fim']?.toString(),
                                ),
                                _BatidaChip(
                                  titulo: 'Saída',
                                  valor: registro['saida']?.toString(),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: concluido || _batendo ? null : _bater,
                              icon: Icon(
                                concluido
                                    ? Icons.check_rounded
                                    : Icons.touch_app_rounded,
                              ),
                              label: Text(
                                concluido
                                    ? 'Ponto concluído'
                                    : _batendo
                                    ? 'Registrando...'
                                    : (estado?['rotulo'] ?? 'Bater ponto')
                                          .toString(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _RegistrosMesCard(
                    dadosMes: _mes,
                    diasCorrigidos: _diasCorrigidos,
                  ),
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resumo do mês',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _LinhaResumo(
                            titulo: 'Trabalhadas',
                            valor: _horas(_mes?['minutos_trabalhados']),
                          ),
                          _LinhaResumo(
                            titulo: 'Horas extras',
                            valor: _horas(_mes?['minutos_extras']),
                          ),
                          _LinhaResumo(
                            titulo: 'Horas faltantes',
                            valor: _horas(_mes?['minutos_faltantes']),
                          ),
                          _LinhaResumo(
                            titulo: 'Faltas',
                            valor: '${_mes?['faltas'] ?? 0}',
                          ),
                          _LinhaResumo(
                            titulo: 'Pendências',
                            valor: '${_mes?['pendencias'] ?? 0}',
                          ),
                          _LinhaResumo(
                            titulo: 'Fechamento',
                            valor: '${_mes?['fechamento_status'] ?? 'Aberto'}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RegistrosMesCard extends StatelessWidget {
  const _RegistrosMesCard({
    required this.dadosMes,
    required this.diasCorrigidos,
  });

  final Map<String, dynamic>? dadosMes;
  final Set<String> diasCorrigidos;

  @override
  Widget build(BuildContext context) {
    final bruto = dadosMes?['dias'];

    final dias = bruto is List
        ? bruto
              .whereType<Map>()
              .map<Map<String, dynamic>>(
                (item) => Map<String, dynamic>.from(item),
              )
              .where((dia) => dia['registro'] is Map)
              .toList()
        : <Map<String, dynamic>>[];

    dias.sort(
      (a, b) =>
          (b['data']?.toString() ?? '').compareTo(a['data']?.toString() ?? ''),
    );

    if (dias.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhuma batida registrada neste mês.',
            style: TextStyle(color: Colors.white60),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Meus registros do mês',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < dias.length; i++) ...[
              _RegistroMesLinha(
                dia: dias[i],
                corrigido: diasCorrigidos.contains(
                  dias[i]['data']?.toString() ?? '',
                ),
              ),
              if (i < dias.length - 1) const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

class _RegistroMesLinha extends StatelessWidget {
  const _RegistroMesLinha({required this.dia, required this.corrigido});

  final Map<String, dynamic> dia;
  final bool corrigido;

  String _hora(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? '--:--' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final data = DateTime.tryParse(dia['data']?.toString() ?? '');

    final registroBruto = dia['registro'];
    final registro = registroBruto is Map
        ? Map<String, dynamic>.from(registroBruto)
        : const <String, dynamic>{};

    final situacao = (registro['situacao'] ?? 'Trabalhado').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data == null
                      ? (dia['data']?.toString() ?? '')
                      : DateFormat('dd/MM/yyyy', 'pt_BR').format(data),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (corrigido)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'Corrigido',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          if (situacao == 'Trabalhado')
            Text(
              'Entrada ${_hora(registro['entrada'])} • '
              'Intervalo ${_hora(registro['intervalo_inicio'])} • '
              'Volta ${_hora(registro['intervalo_fim'])} • '
              'Saída ${_hora(registro['saida'])}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            Text(
              situacao,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _BatidaChip extends StatelessWidget {
  const _BatidaChip({required this.titulo, required this.valor});

  final String titulo;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    final texto = valor?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$titulo: '
        '${texto.isEmpty ? '--:--' : texto}',
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
