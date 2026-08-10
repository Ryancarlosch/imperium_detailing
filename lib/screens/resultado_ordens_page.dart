import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/custos_repository.dart';

class ResultadoOrdensPage extends StatefulWidget {
  const ResultadoOrdensPage({super.key});

  @override
  State<ResultadoOrdensPage> createState() => _ResultadoOrdensPageState();
}

class _ResultadoOrdensPageState extends State<ResultadoOrdensPage> {
  final CustosRepository _repository = CustosRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  List<Map<String, dynamic>> _ordens = [];

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
      final ordens = await _repository.listarResultadoOrdens();
      if (!mounted) return;
      setState(() {
        _ordens = ordens;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível analisar as OS.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _percentual(double valor) {
    return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  String _dataTexto(dynamic valor) {
    final texto = (valor ?? '').toString().trim();
    final data = DateTime.tryParse(texto);
    return data == null ? texto : _data.format(data);
  }

  Future<void> _abrirDetalhes(Map<String, dynamic> ordem) async {
    final id = (ordem['id'] as num?)?.toInt();
    if (id == null) return;

    final completa = await _repository.obterResultadoOrdem(id);
    if (!mounted || completa == null) return;

    final maoObra = List<Map<String, dynamic>>.from(
      completa['mao_obra_lancamentos'] as List<dynamic>? ?? const [],
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (bottomContext) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                (completa['numero'] ?? 'OS').toString(),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text((completa['cliente_nome'] ?? '').toString()),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Resultado comercial',
                children: [
                  _linha('Venda', _double(completa['valor_negociado'])),
                  _linha('Produtos', -_double(completa['custo_produtos'])),
                  _linha(
                    'Taxas de pagamento',
                    -_double(completa['taxas_pagamento']),
                  ),
                  const Divider(),
                  _linha(
                    'Resultado comercial',
                    _double(completa['resultado_comercial']),
                    destaque: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Secao(
                titulo: 'Análise gerencial',
                children: [
                  _linha(
                    'Mão de obra estimada',
                    -_double(completa['custo_mao_obra']),
                  ),
                  _linha(
                    'Rateio da estrutura',
                    -_double(completa['rateio_custo_fixo']),
                  ),
                  const Divider(),
                  _linha(
                    'Resultado gerencial estimado',
                    _double(completa['resultado_gerencial_estimado']),
                    destaque: true,
                  ),
                ],
              ),
              if (maoObra.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Tempo e custo-hora registrados',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 7),
                ...maoObra.map((item) {
                  final nome = (item['colaborador_nome'] ??
                          item['descricao'] ??
                          'Mão de obra')
                      .toString();
                  final horas = _double(item['horas']);
                  final custoHora = _double(item['custo_hora_snapshot']);
                  final total = _double(item['custo_total']);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 7),
                    child: ListTile(
                      leading: const Icon(Icons.engineering_outlined),
                      title: Text(nome),
                      subtitle: Text(
                        '${horas.toStringAsFixed(2).replaceAll('.', ',')} h • '
                        '${_moeda.format(custoHora)}/h',
                      ),
                      trailing: Text(
                        _moeda.format(total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Mão de obra e rateio da estrutura são indicadores '
                    'gerenciais para precificação. Eles não geram saída de '
                    'caixa e não são lançados automaticamente na DRE.',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _linha(String titulo, double valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            _moeda.format(valor),
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              fontSize: destaque ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise gerencial por OS'),
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
          : RefreshIndicator(
              onRefresh: _carregar,
              child: _ordens.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Nenhuma OS finalizada para analisar.'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                      itemCount: _ordens.length,
                      itemBuilder: (_, index) {
                        final ordem = _ordens[index];
                        final numero = (ordem['numero'] ?? 'OS').toString();
                        final cliente =
                            (ordem['cliente_nome'] ?? '').toString();
                        final responsavel =
                            (ordem['funcionario_responsavel'] ?? '').toString();
                        final comercial =
                            _double(ordem['resultado_comercial']);
                        final gerencial =
                            _double(ordem['resultado_gerencial_estimado']);
                        final margem =
                            _double(ordem['margem_gerencial_estimada']);
                        final data = _dataTexto(ordem['data_finalizacao']);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 9),
                          child: ListTile(
                            onTap: () => _abrirDetalhes(ordem),
                            leading: const CircleAvatar(
                              child: Icon(Icons.receipt_long_outlined),
                            ),
                            title: Text(
                              numero,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              [
                                cliente,
                                if (responsavel.trim().isNotEmpty) responsavel,
                                if (data.isNotEmpty) data,
                                'Comercial ${_moeda.format(comercial)}',
                              ].where((e) => e.trim().isNotEmpty).join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _moeda.format(gerencial),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _percentual(margem),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
