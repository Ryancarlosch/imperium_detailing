import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';

class ComparativoContaPage extends StatefulWidget {
  const ComparativoContaPage({super.key, required this.conta, DateTime? mes})
    : mesInicial = mes;

  final ContaFinanceira conta;
  final DateTime? mesInicial;

  @override
  State<ComparativoContaPage> createState() => _ComparativoContaPageState();
}

class _ComparativoContaPageState extends State<ComparativoContaPage> {
  final ContaFinanceiraRepository _repository = ContaFinanceiraRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _mesAno = DateFormat('MMMM yyyy', 'pt_BR');
  final DateFormat _dia = DateFormat('dd/MM');

  late DateTime _mes;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _atual;
  Map<String, dynamic>? _anterior;

  @override
  void initState() {
    super.initState();
    final base = widget.mesInicial ?? DateTime.now();
    _mes = DateTime(base.year, base.month, 1);
    _carregar();
  }

  Future<void> _carregar() async {
    final contaId = widget.conta.id;
    if (contaId == null) {
      setState(() {
        _carregando = false;
        _erro = 'Conta financeira sem ID.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final mesAnterior = DateTime(_mes.year, _mes.month - 1, 1);

      final resultados = await Future.wait<dynamic>([
        _repository.obterExtratoMensal(contaId: contaId, mes: _mes),
        _repository.obterExtratoMensal(contaId: contaId, mes: mesAnterior),
      ]);

      if (!mounted) return;

      setState(() {
        _atual = Map<String, dynamic>.from(
          resultados[0] as Map<String, dynamic>,
        );
        _anterior = Map<String, dynamic>.from(
          resultados[1] as Map<String, dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _erro = '$erro';
        _carregando = false;
      });
    }
  }

  void _mudarMes(int delta) {
    setState(() {
      _mes = DateTime(_mes.year, _mes.month + delta, 1);
    });
    _carregar();
  }

  double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  String _nomeMes(DateTime data) {
    final texto = _mesAno.format(data);
    if (texto.isEmpty) return texto;
    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }

  String _variacao(double atual, double anterior) {
    if (anterior.abs() < 0.005) {
      if (atual.abs() < 0.005) return '0,0%';
      return atual > 0 ? 'Novo' : '—';
    }

    final percentual = ((atual - anterior) / anterior.abs()) * 100;
    final sinal = percentual > 0 ? '+' : '';
    return '$sinal${percentual.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  List<Map<String, dynamic>> _movimentosAtual() {
    final atual = _atual;
    if (atual == null) return const [];

    return List<Map<String, dynamic>>.from(
      atual['movimentos'] as List<dynamic>? ?? const [],
    );
  }

  DateTime _dataMovimento(Map<String, dynamic> item) {
    final texto = (item['data_pagamento'] ?? item['data'] ?? '').toString();
    return DateTime.tryParse(texto) ?? _mes;
  }

  bool _entrada(Map<String, dynamic> item) {
    return (item['tipo'] ?? '').toString().trim().toLowerCase() == 'entrada';
  }

  List<_ResumoDia> _resumoDias() {
    final grupos = <String, _ResumoDia>{};

    for (final item in _movimentosAtual()) {
      final data = _dataMovimento(item);
      final chave =
          '${data.year.toString().padLeft(4, '0')}-'
          '${data.month.toString().padLeft(2, '0')}-'
          '${data.day.toString().padLeft(2, '0')}';

      final grupo = grupos.putIfAbsent(
        chave,
        () => _ResumoDia(data: DateTime(data.year, data.month, data.day)),
      );

      final valor = _double(item['valor']);

      if (_entrada(item)) {
        grupo.entradas += valor;
      } else {
        grupo.saidas += valor;
      }
    }

    final dias = grupos.values.toList()
      ..sort((a, b) => a.data.compareTo(b.data));

    return dias;
  }

  @override
  Widget build(BuildContext context) {
    final mesAnterior = DateTime(_mes.year, _mes.month - 1, 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparativo da conta'),
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
          ? _ErroComparativo(mensagem: _erro!, onTentarNovamente: _carregar)
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _cabecalhoPeriodo(mesAnterior),
                  const SizedBox(height: 14),
                  _tabelaComparativa(mesAnterior),
                  const SizedBox(height: 16),
                  _resumoDiaADia(),
                ],
              ),
            ),
    );
  }

  Widget _cabecalhoPeriodo(DateTime mesAnterior) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => _mudarMes(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    widget.conta.nome,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_nomeMes(mesAnterior)} x ${_nomeMes(_mes)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: () => _mudarMes(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabelaComparativa(DateTime mesAnterior) {
    final atual = _atual ?? const <String, dynamic>{};
    final anterior = _anterior ?? const <String, dynamic>{};

    final entradasAtual = _double(atual['entradas']);
    final entradasAnterior = _double(anterior['entradas']);
    final saidasAtual = _double(atual['saidas']);
    final saidasAnterior = _double(anterior['saidas']);
    final liquidoAtual = entradasAtual - saidasAtual;
    final liquidoAnterior = entradasAnterior - saidasAnterior;
    final saldoFinalAtual = _double(atual['saldo_final_mes']);
    final saldoFinalAnterior = _double(anterior['saldo_final_mes']);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mês anterior x mês atual',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _cabecalhoTabela(mesAnterior),
            const Divider(height: 20),
            _linhaComparativa(
              titulo: 'Entradas',
              anterior: entradasAnterior,
              atual: entradasAtual,
              variacao: _variacao(entradasAtual, entradasAnterior),
            ),
            const SizedBox(height: 11),
            _linhaComparativa(
              titulo: 'Saídas',
              anterior: saidasAnterior,
              atual: saidasAtual,
              variacao: _variacao(saidasAtual, saidasAnterior),
            ),
            const SizedBox(height: 11),
            _linhaComparativa(
              titulo: 'Mov. líquido',
              anterior: liquidoAnterior,
              atual: liquidoAtual,
              variacao: _variacao(liquidoAtual, liquidoAnterior),
              destaque: true,
            ),
            const SizedBox(height: 11),
            _linhaComparativa(
              titulo: 'Saldo final',
              anterior: saldoFinalAnterior,
              atual: saldoFinalAtual,
              variacao: _variacao(saldoFinalAtual, saldoFinalAnterior),
              destaque: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalhoTabela(DateTime mesAnterior) {
    return Row(
      children: [
        const Expanded(
          flex: 4,
          child: Text(
            'Indicador',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            DateFormat('MMM/yy', 'pt_BR').format(mesAnterior),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            DateFormat('MMM/yy', 'pt_BR').format(_mes),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const Expanded(
          flex: 2,
          child: Text(
            'Var.',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _linhaComparativa({
    required String titulo,
    required double anterior,
    required double atual,
    required String variacao,
    bool destaque = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            titulo,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(_moeda.format(anterior), textAlign: TextAlign.right),
          ),
        ),
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _moeda.format(atual),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            variacao,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _resumoDiaADia() {
    final dias = _resumoDias();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Movimento dia a dia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _nomeMes(_mes),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (dias.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Nenhuma movimentação realizada neste mês.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              const Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Dia',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Entradas',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Saídas',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Resultado',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...dias.map((dia) {
                final resultado = dia.entradas - dia.saidas;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(_dia.format(dia.data))),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_moeda.format(dia.entradas)),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_moeda.format(dia.saidas)),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _moeda.format(resultado),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResumoDia {
  _ResumoDia({required this.data});

  final DateTime data;
  double entradas = 0;
  double saidas = 0;
}

class _ErroComparativo extends StatelessWidget {
  const _ErroComparativo({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
