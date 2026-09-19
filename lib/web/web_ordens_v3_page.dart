import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';
import '../services/web_cloud_operacional_service.dart';
import '../services/web_os_cancelamento_v5_service.dart';
import '../services/web_os_v3_service.dart';
import 'imperium_web_theme.dart';
import 'web_os_arquivos_page.dart';

class WebOrdensV3Page extends StatefulWidget {
  const WebOrdensV3Page({super.key});

  @override
  State<WebOrdensV3Page> createState() => _WebOrdensV3PageState();
}

class _WebOrdensV3PageState extends State<WebOrdensV3Page> {
  final _operacional = WebCloudOperacionalService.instance;
  final _service = WebOsV3Service.instance;
  final _cancelamento = WebOsCancelamentoV5Service.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _busca = TextEditingController();

  bool _carregando = true;
  String? _erro;
  String _status = 'Todos';
  List<Map<String, dynamic>> _ordens = const [];
  List<Map<String, dynamic>> _clientes = const [];
  List<Map<String, dynamic>> _veiculos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final dados = await Future.wait([
        _operacional.listarOrdens(),
        _operacional.listarClientes(),
        _operacional.listarVeiculos(),
      ]);

      if (!mounted) return;

      setState(() {
        _ordens = dados[0];
        _clientes = dados[1];
        _veiculos = dados[2];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _editar(Map<String, dynamic> resumo) async {
    final status = (resumo['status'] ?? '').toString();

    if (status != 'Aberta' && status != 'Em andamento') {
      _mensagem(
        'Somente OS Aberta ou Em andamento pode ser editada pelo Web. '
        'A finalização continua protegida pelo fluxo transacional.',
        erro: true,
      );
      return;
    }

    try {
      final original = await _service.carregarEdicao(resumo['id'].toString());

      if (!mounted) return;

      final draft = await showDialog<_WebOsDraft>(
        context: context,
        builder: (context) => _WebOsEditDialog(original: original),
      );

      if (draft == null) return;

      await _service.salvarEdicao(
        original: original,
        status: draft.status,
        dataAbertura: draft.dataAbertura,
        dataInicio: draft.dataInicio,
        horaEntrada: draft.horaEntrada,
        horaSaida: draft.horaSaida,
        funcionarioResponsavel: draft.funcionarioResponsavel,
        observacoes: draft.observacoes,
        quilometragemEntrada: draft.quilometragemEntrada,
        combustivelEntrada: draft.combustivelEntrada,
        desconto: draft.desconto,
        itens: draft.itens,
      );

      if (!mounted) return;

      _mensagem(
        'OS atualizada com CAS e transação atômica. '
        'O Android receberá a alteração no próximo sync.',
      );

      await _carregar();
    } catch (e) {
      _mensagem(e.toString(), erro: true);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> resumo) async {
    final status = (resumo['status'] ?? '').toString().trim();

    if (status != 'Aberta' && status != 'Em andamento') {
      _mensagem(
        'Somente OS Aberta ou Em andamento pode ser cancelada por este fluxo. '
        'OS finalizada exige estorno/correção.',
        erro: true,
      );
      return;
    }

    final motivoController = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancelar OS ${resumo['numero'] ?? ''}?'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O cancelamento é transacional: cobranças pendentes serão '
                'canceladas, reservas de estoque serão liberadas e o '
                'agendamento vinculado será atualizado. Se qualquer etapa '
                'falhar, nenhuma alteração será gravada.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: motivoController,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Voltar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final texto = motivoController.text.trim();
              if (texto.length < 3) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o motivo do cancelamento.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, texto);
            },
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
    motivoController.dispose();

    if (motivo == null) return;

    try {
      final resultado = await _cancelamento.cancelar(
        ordem: resumo,
        motivo: motivo,
      );

      final reservaRaw = resultado['reserva'];
      final reserva = reservaRaw is Map
          ? Map<String, dynamic>.from(reservaRaw)
          : <String, dynamic>{};
      final reservasLiberadas = (reserva['quantidade'] as num?)?.toInt() ?? 0;
      final pagamentosCancelados =
          (resultado['pagamentos_cancelados'] as num?)?.toInt() ?? 0;

      _mensagem(
        'OS cancelada com segurança. Reservas liberadas: '
        '$reservasLiberadas. Cobranças pendentes canceladas: '
        '$pagamentosCancelados.',
      );
      await _carregar();
    } catch (e) {
      _mensagem(e.toString(), erro: true);
    }
  }

  Future<void> _abrirArquivos(Map<String, dynamic> resumo) async {
    final id = (resumo['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      _mensagem('Não foi possível identificar esta OS.', erro: true);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WebOsArquivosPage(
          ordemId: id,
          numero: (resumo['numero'] ?? '').toString(),
        ),
      ),
    );
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

  Widget _resumo({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
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
    );
  }

  Widget _statusChip(String status) {
    final normalizado = status.toLowerCase();
    final cor = normalizado.contains('cancel')
        ? Colors.redAccent
        : normalizado.contains('final')
        ? Colors.greenAccent
        : normalizado.contains('andamento')
        ? Colors.lightBlueAccent
        : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.40)),
      ),
      child: Text(
        status.trim().isEmpty ? 'Sem status' : status,
        style: TextStyle(
          color: cor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _acoesOs(Map<String, dynamic> os, bool editavel) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Fotos, avarias e assinatura',
          onPressed: () => _abrirArquivos(os),
          icon: const Icon(Icons.photo_library_outlined),
        ),
        IconButton(
          tooltip: editavel
              ? 'Editar com proteção de concorrência'
              : 'OS bloqueada para edição Web',
          onPressed: editavel ? () => _editar(os) : null,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: editavel
              ? 'Cancelar OS com transação segura'
              : 'Cancelamento disponível apenas para OS aberta/em andamento',
          onPressed: editavel ? () => _cancelar(os) : null,
          icon: const Icon(Icons.cancel_outlined),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42),
              const SizedBox(height: 12),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final nomes = <String, String>{
      for (final c in _clientes)
        c['id'].toString(): (c['nome'] ?? 'Cliente').toString(),
    };

    final carros = <String, String>{
      for (final v in _veiculos)
        v['id'].toString():
            '${v['marca'] ?? ''} ${v['modelo'] ?? ''} ${v['placa'] ?? ''}'
                .trim(),
    };

    final termo = _busca.text.trim().toLowerCase();

    final filtradas =
        _ordens.where((os) {
          if (_status != 'Todos' && '${os['status']}' != _status) return false;
          if (termo.isEmpty) return true;

          return <dynamic>[
            os['numero'],
            nomes[os['cliente_id']?.toString()],
            carros[os['veiculo_id']?.toString()],
            os['funcionario_responsavel'],
            os['status'],
          ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
        }).toList()..sort(
          (a, b) => '${b['data_abertura']}'.compareTo('${a['data_abertura']}'),
        );

    final abertas = _ordens.where((e) => e['status'] == 'Aberta').length;
    final andamento =
        _ordens.where((e) => e['status'] == 'Em andamento').length;
    final bloqueadas = _ordens
        .where((e) => e['status'] != 'Aberta' && e['status'] != 'Em andamento')
        .length;
    final valorEditavel = _ordens
        .where((e) => e['status'] == 'Aberta' || e['status'] == 'Em andamento')
        .fold<double>(
          0,
          (total, os) =>
              total +
              OrdemServicoValor.valorNegociado(
                valorTotal: _double(os['valor_total']),
                desconto: _double(os['desconto']),
                descontoNegociacao: _double(os['desconto_negociacao']),
                acrescimoNegociacao: _double(os['acrescimo_negociacao']),
                jurosParcelamento: _double(os['juros_parcelamento']),
              ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final tabela = constraints.maxWidth >= 1050;
        final larguraDisponivel =
            constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final larguraResumo =
            (larguraDisponivel - (12 * (colunas - 1))) / colunas;

        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compacto ? 16 : 24,
              compacto ? 18 : 24,
              compacto ? 16 : 24,
              40,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar ordens de serviço',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Edição segura de OS abertas/em andamento com CAS, histórico e cancelamento transacional.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _carregar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Abertas',
                    valor: '$abertas',
                    detalhe: 'Disponíveis para edição',
                    icone: Icons.edit_note_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Em andamento',
                    valor: '$andamento',
                    detalhe: 'Em execução e ainda editáveis',
                    icone: Icons.car_repair_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Valor editável',
                    valor: _moeda.format(valorEditavel),
                    detalhe: 'Total negociado das OS editáveis',
                    icone: Icons.payments_outlined,
                  ),
                  _resumo(
                    width: larguraResumo,
                    titulo: 'Bloqueadas',
                    valor: '$bloqueadas',
                    detalhe: 'Finalizadas/canceladas protegidas',
                    icone: Icons.lock_outline_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: compacto ? larguraDisponivel - 28 : 430,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText:
                                'Buscar OS, cliente, veículo ou responsável',
                            suffixIcon: _busca.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpar busca',
                                    onPressed: () {
                                      _busca.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            'Todos',
                            'Aberta',
                            'Em andamento',
                            'Finalizada',
                            'Cancelada',
                          ]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _status = v ?? 'Todos'),
                        ),
                      ),
                      Text(
                        '${filtradas.length} resultado(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (filtradas.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 40,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.edit_note_outlined,
                          size: 42,
                          color: Color(0xFF89939E),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nenhuma OS encontrada',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (tabela)
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 52,
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 80,
                      columns: const [
                        DataColumn(label: Text('OS / CLIENTE')),
                        DataColumn(label: Text('VEÍCULO')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('RESPONSÁVEL')),
                        DataColumn(label: Text('ABERTURA')),
                        DataColumn(label: Text('VALOR')),
                        DataColumn(label: Text('AÇÕES')),
                      ],
                      rows: filtradas.map((os) {
                        final negociado = OrdemServicoValor.valorNegociado(
                          valorTotal: _double(os['valor_total']),
                          desconto: _double(os['desconto']),
                          descontoNegociacao:
                              _double(os['desconto_negociacao']),
                          acrescimoNegociacao:
                              _double(os['acrescimo_negociacao']),
                          jurosParcelamento:
                              _double(os['juros_parcelamento']),
                        );
                        final editavel =
                            os['status'] == 'Aberta' ||
                            os['status'] == 'Em andamento';

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 250,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'OS ${os['numero'] ?? ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      nomes[os['cliente_id']?.toString()] ??
                                          'Cliente',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFAAB3BD),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  carros[os['veiculo_id']?.toString()] ?? '—',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              _statusChip(
                                (os['status'] ?? 'Sem status').toString(),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 170,
                                child: Text(
                                  (os['funcionario_responsavel'] ?? '—')
                                      .toString(),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                (os['data_abertura'] ?? '—').toString(),
                              ),
                            ),
                            DataCell(
                              Text(
                                _moeda.format(negociado),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            DataCell(_acoesOs(os, editavel)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                ...filtradas.map((os) {
                  final negociado = OrdemServicoValor.valorNegociado(
                    valorTotal: _double(os['valor_total']),
                    desconto: _double(os['desconto']),
                    descontoNegociacao:
                        _double(os['desconto_negociacao']),
                    acrescimoNegociacao:
                        _double(os['acrescimo_negociacao']),
                    jurosParcelamento:
                        _double(os['juros_parcelamento']),
                  );
                  final editavel =
                      os['status'] == 'Aberta' ||
                      os['status'] == 'Em andamento';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Icon(
                                editavel
                                    ? Icons.edit_note_outlined
                                    : Icons.lock_outline,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'OS ${os['numero'] ?? ''} · '
                                    '${nomes[os['cliente_id']?.toString()] ?? 'Cliente'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      carros[os['veiculo_id']?.toString()] ??
                                          '',
                                      (os['funcionario_responsavel'] ?? '')
                                          .toString(),
                                      (os['data_abertura'] ?? '').toString(),
                                    ]
                                        .where((e) => e.trim().isNotEmpty)
                                        .join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFAAB3BD),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      _statusChip(
                                        (os['status'] ?? 'Sem status')
                                            .toString(),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _moeda.format(negociado),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _acoesOs(os, editavel),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}


class _WebOsEditDialog extends StatefulWidget {
  const _WebOsEditDialog({required this.original});

  final Map<String, dynamic> original;

  @override
  State<_WebOsEditDialog> createState() => _WebOsEditDialogState();
}

class _WebOsEditDialogState extends State<_WebOsEditDialog> {
  late final TextEditingController _dataAbertura;
  late final TextEditingController _dataInicio;
  late final TextEditingController _horaEntrada;
  late final TextEditingController _horaSaida;
  late final TextEditingController _responsavel;
  late final TextEditingController _observacoes;
  late final TextEditingController _km;
  late final TextEditingController _combustivel;
  late final TextEditingController _desconto;
  late String _status;
  late final List<_WebOsItemController> _itens;

  @override
  void initState() {
    super.initState();

    final ordem = Map<String, dynamic>.from(widget.original['ordem'] as Map);
    final itens = (widget.original['itens'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    _status = (ordem['status'] ?? 'Aberta').toString();
    _dataAbertura = TextEditingController(
      text: (ordem['data_abertura'] ?? '').toString(),
    );
    _dataInicio = TextEditingController(
      text: (ordem['data_inicio'] ?? '').toString(),
    );
    _horaEntrada = TextEditingController(
      text: (ordem['hora_entrada'] ?? '').toString(),
    );
    _horaSaida = TextEditingController(
      text: (ordem['hora_saida'] ?? '').toString(),
    );
    _responsavel = TextEditingController(
      text: (ordem['funcionario_responsavel'] ?? '').toString(),
    );
    _observacoes = TextEditingController(
      text: (ordem['observacoes'] ?? '').toString(),
    );
    _km = TextEditingController(
      text: (ordem['quilometragem_entrada'] ?? '').toString(),
    );
    _combustivel = TextEditingController(
      text: (ordem['combustivel_entrada'] ?? '').toString(),
    );
    _desconto = TextEditingController(
      text: _double(ordem['desconto']).toStringAsFixed(2),
    );
    _itens = itens.map(_WebOsItemController.fromMap).toList();

    if (_itens.isEmpty) {
      _itens.add(_WebOsItemController.novo());
    }
  }

  @override
  void dispose() {
    _dataAbertura.dispose();
    _dataInicio.dispose();
    _horaEntrada.dispose();
    _horaSaida.dispose();
    _responsavel.dispose();
    _observacoes.dispose();
    _km.dispose();
    _combustivel.dispose();
    _desconto.dispose();

    for (final item in _itens) {
      item.dispose();
    }

    super.dispose();
  }

  void _salvar() {
    final itens = <Map<String, Object?>>[];

    for (final item in _itens) {
      final nome = item.servico.text.trim();
      final quantidade = _double(item.quantidade.text);
      final valor = _double(item.valor.text);

      if (nome.isEmpty || quantidade <= 0 || valor < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Revise serviço, quantidade e valor dos itens.'),
          ),
        );
        return;
      }

      itens.add(<String, Object?>{
        if (item.id != null) 'id': item.id,
        'servico': nome,
        'descricao': item.descricao.text.trim(),
        'quantidade': quantidade,
        'valor_unitario': valor,
        'concluido': item.concluido,
      });
    }

    Navigator.pop(
      context,
      _WebOsDraft(
        status: _status,
        dataAbertura: _dataAbertura.text,
        dataInicio: _dataInicio.text,
        horaEntrada: _horaEntrada.text,
        horaSaida: _horaSaida.text,
        funcionarioResponsavel: _responsavel.text,
        observacoes: _observacoes.text,
        quilometragemEntrada: _km.text,
        combustivelEntrada: _combustivel.text,
        desconto: _double(_desconto.text),
        itens: itens,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar OS com proteção de concorrência'),
      content: SizedBox(
        width: 820,
        height: 650,
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                'Aberta',
                'Em andamento',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dataAbertura,
                    decoration: const InputDecoration(
                      labelText: 'Data de abertura',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _dataInicio,
                    decoration: const InputDecoration(
                      labelText: 'Data de início/entrada',
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _horaEntrada,
                    decoration: const InputDecoration(
                      labelText: 'Hora de entrada',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _horaSaida,
                    decoration: const InputDecoration(
                      labelText: 'Hora de saída',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _responsavel,
              decoration: const InputDecoration(labelText: 'Responsável'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _km,
                    decoration: const InputDecoration(
                      labelText: 'Quilometragem de entrada',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _combustivel,
                    decoration: const InputDecoration(
                      labelText: 'Combustível de entrada',
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _desconto,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Desconto da OS'),
            ),
            TextField(
              controller: _observacoes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Serviços',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      setState(() => _itens.add(_WebOsItemController.novo())),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar serviço'),
                ),
              ],
            ),
            ...List.generate(_itens.length, (i) {
              final item = _itens[i];

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Serviço ${i + 1}')),
                          Checkbox(
                            value: item.concluido,
                            onChanged: (v) =>
                                setState(() => item.concluido = v == true),
                          ),
                          const Text('Concluído'),
                          IconButton(
                            tooltip: 'Remover',
                            onPressed: _itens.length == 1
                                ? null
                                : () {
                                    final removido = _itens.removeAt(i);
                                    removido.dispose();
                                    setState(() {});
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: item.servico,
                        decoration: const InputDecoration(
                          labelText: 'Serviço *',
                        ),
                      ),
                      TextField(
                        controller: item.descricao,
                        decoration: const InputDecoration(
                          labelText: 'Descrição',
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: item.quantidade,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Quantidade *',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: item.valor,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Valor unitário *',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _salvar,
          icon: const Icon(Icons.save),
          label: const Text('Salvar edição segura'),
        ),
      ],
    );
  }
}

class _WebOsItemController {
  _WebOsItemController({
    required this.id,
    required this.servico,
    required this.descricao,
    required this.quantidade,
    required this.valor,
    required this.concluido,
  });

  factory _WebOsItemController.fromMap(Map<String, dynamic> map) {
    return _WebOsItemController(
      id: map['id']?.toString(),
      servico: TextEditingController(text: '${map['servico'] ?? ''}'),
      descricao: TextEditingController(text: '${map['descricao'] ?? ''}'),
      quantidade: TextEditingController(
        text: _double(map['quantidade']).toStringAsFixed(2),
      ),
      valor: TextEditingController(
        text: _double(map['valor_unitario']).toStringAsFixed(2),
      ),
      concluido: map['concluido'] == true,
    );
  }

  factory _WebOsItemController.novo() {
    return _WebOsItemController(
      id: null,
      servico: TextEditingController(),
      descricao: TextEditingController(),
      quantidade: TextEditingController(text: '1'),
      valor: TextEditingController(),
      concluido: false,
    );
  }

  final String? id;
  final TextEditingController servico;
  final TextEditingController descricao;
  final TextEditingController quantidade;
  final TextEditingController valor;
  bool concluido;

  void dispose() {
    servico.dispose();
    descricao.dispose();
    quantidade.dispose();
    valor.dispose();
  }
}

class _WebOsDraft {
  const _WebOsDraft({
    required this.status,
    required this.dataAbertura,
    required this.dataInicio,
    required this.horaEntrada,
    required this.horaSaida,
    required this.funcionarioResponsavel,
    required this.observacoes,
    required this.quilometragemEntrada,
    required this.combustivelEntrada,
    required this.desconto,
    required this.itens,
  });

  final String status;
  final String dataAbertura;
  final String dataInicio;
  final String horaEntrada;
  final String horaSaida;
  final String funcionarioResponsavel;
  final String observacoes;
  final String quilometragemEntrada;
  final String combustivelEntrada;
  final double desconto;
  final List<Map<String, Object?>> itens;
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
