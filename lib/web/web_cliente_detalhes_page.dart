import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/ordem_servico_valor.dart';
import '../services/comercial_growth_cloud_service.dart';
import '../services/web_cloud_operacional_service.dart';
import '../services/web_os_pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'imperium_web_theme.dart';

class WebClienteDetalhesPage extends StatefulWidget {
  const WebClienteDetalhesPage({super.key, required this.cliente});

  final Map<String, dynamic> cliente;

  @override
  State<WebClienteDetalhesPage> createState() => _WebClienteDetalhesPageState();
}

class _WebClienteDetalhesPageState extends State<WebClienteDetalhesPage> {
  final _operacional = WebCloudOperacionalService.instance;
  final _growth = ComercialGrowthCloudService.instance;
  final _pdf = WebOsPdfService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  bool _carregando = true;
  bool _acao = false;
  String? _erro;
  List<Map<String, dynamic>> _veiculos = const [];
  List<Map<String, dynamic>> _ordens = const [];
  GrowthPosVendaCliente? _posVenda;

  String get _clienteId => (widget.cliente['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultados = await Future.wait<dynamic>([
        _operacional.listarVeiculos(),
        _operacional.listarOrdens(),
        _growth.carregarPosVenda(),
      ]);

      final veiculos = (resultados[0] as List<Map<String, dynamic>>)
          .where((e) => (e['cliente_id'] ?? '').toString() == _clienteId)
          .toList();
      final ordens =
          (resultados[1] as List<Map<String, dynamic>>)
              .where((e) => (e['cliente_id'] ?? '').toString() == _clienteId)
              .toList()
            ..sort((a, b) {
              final da =
                  _parseData(a['data_finalizacao']) ??
                  _parseData(a['data_abertura']) ??
                  DateTime(1900);
              final db =
                  _parseData(b['data_finalizacao']) ??
                  _parseData(b['data_abertura']) ??
                  DateTime(1900);
              return db.compareTo(da);
            });
      final painel = resultados[2] as GrowthPosVendaPainel;
      GrowthPosVendaCliente? posVenda;
      for (final item in painel.clientes) {
        if (item.id == _clienteId) {
          posVenda = item;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _veiculos = veiculos;
        _ordens = ordens;
        _posVenda = posVenda;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double _valorOrdem(Map<String, dynamic> ordem) {
    return OrdemServicoValor.valorNegociado(
      valorTotal: _double(ordem['valor_total']),
      desconto: _double(ordem['desconto']),
      descontoNegociacao: _double(ordem['desconto_negociacao']),
      acrescimoNegociacao: _double(ordem['acrescimo_negociacao']),
      jurosParcelamento: _double(ordem['juros_parcelamento']),
    );
  }

  Future<void> _abrirWhatsApp() async {
    final telefone = (widget.cliente['telefone'] ?? '').toString().trim();
    if (telefone.isEmpty) {
      _snack('Este cliente não possui telefone cadastrado.', erro: true);
      return;
    }

    setState(() => _acao = true);
    try {
      await WhatsAppService.enviarMensagemPersonalizada(
        telefone: telefone,
        mensagem:
            'Olá, ${widget.cliente['nome'] ?? 'cliente'}! Tudo bem? Estamos entrando em contato pela nossa equipe.',
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _acao = false);
    }
  }

  Future<void> _baixarPdf(Map<String, dynamic> ordem) async {
    final id = (ordem['id'] ?? '').toString();
    if (id.isEmpty) return;

    setState(() => _acao = true);
    try {
      await _pdf.baixarPdf(
        ordemId: id,
        numero: (ordem['numero'] ?? '').toString(),
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _acao = false);
    }
  }

  Widget _indicador(
    String titulo,
    String valor,
    IconData icon, {
    String detalhe = '',
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: ImperiumWebTheme.accentStrong),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (detalhe.isNotEmpty)
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
    );
  }

  Widget _statusRelacionamento() {
    final pos = _posVenda;
    if (pos == null) {
      return const Chip(
        avatar: Icon(Icons.info_outline_rounded, size: 16),
        label: Text('Sem histórico de OS'),
      );
    }

    final color = switch (pos.status) {
      'Reativação' => Colors.redAccent,
      'Hora do retorno' => Colors.orangeAccent,
      'Agendado' => Colors.lightBlueAccent,
      _ => Colors.greenAccent,
    };

    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(pos.status),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.cliente;
    final nome = (cliente['nome'] ?? 'Cliente').toString();
    final total = _ordens.fold<double>(0, (s, e) => s + _valorOrdem(e));
    final ticket = _ordens.isEmpty ? 0.0 : total / _ordens.length;
    final ultimo = _ordens.isEmpty
        ? null
        : _parseData(_ordens.first['data_finalizacao']) ??
              _parseData(_ordens.first['data_abertura']);

    return Scaffold(
      appBar: AppBar(
        title: Text(nome),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if ((cliente['telefone'] ?? '').toString().trim().isNotEmpty)
            IconButton(
              tooltip: 'WhatsApp',
              onPressed: _acao ? null : _abrirWhatsApp,
              icon: const Icon(Icons.chat_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _carregando && _ordens.isEmpty && _veiculos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _ordens.isEmpty && _veiculos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_erro!, textAlign: TextAlign.center),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 760;
                final width = constraints.maxWidth;
                final colunas = width >= 1100
                    ? 4
                    : width >= 650
                    ? 2
                    : 1;
                final cardWidth =
                    (width - (compacto ? 32 : 48) - 12 * (colunas - 1)) /
                    colunas;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compacto ? 16 : 24,
                    20,
                    compacto ? 16 : 24,
                    40,
                  ),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: ImperiumWebTheme.accentStrong
                                  .withValues(alpha: 0.12),
                              child: Text(
                                nome.trim().isEmpty
                                    ? '?'
                                    : nome.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                  color: ImperiumWebTheme.accentStrong,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        nome,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      _statusRelacionamento(),
                                      if (cliente['ativo'] == false)
                                        const Chip(
                                          label: Text('Arquivado'),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    [
                                          (cliente['telefone'] ?? '')
                                              .toString(),
                                          (cliente['email'] ?? '').toString(),
                                          (cliente['endereco'] ?? '')
                                              .toString(),
                                        ]
                                        .where((e) => e.trim().isNotEmpty)
                                        .join(' · '),
                                    style: const TextStyle(
                                      color: Color(0xFFAAB3BD),
                                    ),
                                  ),
                                  if ((cliente['observacoes'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      (cliente['observacoes'] ?? '').toString(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _indicador(
                            'Veículos',
                            '${_veiculos.length}',
                            Icons.directions_car_outlined,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _indicador(
                            'Ordens de serviço',
                            '${_ordens.length}',
                            Icons.receipt_long_outlined,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _indicador(
                            'Total negociado',
                            _moeda.format(total),
                            Icons.payments_outlined,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _indicador(
                            'Ticket médio',
                            _moeda.format(ticket),
                            Icons.analytics_outlined,
                            detalhe: ultimo == null
                                ? 'Nenhum atendimento'
                                : 'Último: ${_data.format(ultimo)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Veículos',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_veiculos.isEmpty)
                      const Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Nenhum veículo vinculado.'),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _veiculos
                            .map(
                              (v) => SizedBox(
                                width: compacto ? width - 32 : 340,
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(
                                        Icons.directions_car_outlined,
                                      ),
                                    ),
                                    title: Text(
                                      '${v['marca'] ?? ''} ${v['modelo'] ?? ''}'
                                          .trim(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                            (v['placa'] ?? '').toString(),
                                            (v['ano'] ?? '').toString(),
                                            (v['cor'] ?? '').toString(),
                                          ]
                                          .where((e) => e.trim().isNotEmpty)
                                          .join(' · '),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Histórico de ordens de serviço',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${_ordens.length} registro(s)',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_ordens.isEmpty)
                      const Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Nenhuma ordem de serviço encontrada.'),
                        ),
                      )
                    else
                      ..._ordens.map((ordem) {
                        final data =
                            _parseData(ordem['data_finalizacao']) ??
                            _parseData(ordem['data_abertura']);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.receipt_long_outlined),
                              ),
                              title: Text(
                                'OS ${ordem['numero'] ?? ''} · '
                                '${_moeda.format(_valorOrdem(ordem))}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  (ordem['status'] ?? '').toString(),
                                  (ordem['status_pagamento'] ?? '').toString(),
                                  if (data != null) _data.format(data),
                                  (ordem['funcionario_responsavel'] ?? '')
                                      .toString(),
                                ].where((e) => e.trim().isNotEmpty).join(' · '),
                              ),
                              trailing: IconButton(
                                tooltip: 'Baixar/compartilhar PDF',
                                onPressed: _acao
                                    ? null
                                    : () => _baixarPdf(ordem),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
    );
  }

  void _snack(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static DateTime? _parseData(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.toLocal();
    final partes = text.split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      final a = int.tryParse(partes[2]);
      if (d != null && m != null && a != null) {
        return DateTime(a, m, d);
      }
    }
    return null;
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
