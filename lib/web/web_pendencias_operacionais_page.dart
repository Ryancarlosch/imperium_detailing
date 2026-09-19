import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_pendencias_operacionais_service.dart';

class WebPendenciasOperacionaisPage extends StatefulWidget {
  const WebPendenciasOperacionaisPage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<WebPendenciasOperacionaisPage> createState() =>
      _WebPendenciasOperacionaisPageState();
}

class _WebPendenciasOperacionaisPageState
    extends State<WebPendenciasOperacionaisPage> {
  final _service = WebPendenciasOperacionaisService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  String? _erro;
  String _filtro = 'Todos';
  WebPendenciasOperacionaisResumo? _resumo;

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
      final resumo = await _service.carregar();
      if (!mounted) return;
      setState(() => _resumo = resumo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    if (_carregando && resumo == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && resumo == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro!, textAlign: TextAlign.center),
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

    final dados = resumo!;
    final tipos = dados.itens.map((e) => e.tipo).toSet().toList()..sort();
    final itens = dados.itens.where((e) {
      return _filtro == 'Todos' || e.tipo == _filtro;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final conteudo = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final cardWidth = (conteudo - 12 * (colunas - 1)) / colunas;

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
                          'Pendências operacionais',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Recebimentos, contas, OS paradas, estoque e ponto que precisam de atenção.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _carregando ? null : _carregar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ResumoPendencia(
                    width: cardWidth,
                    titulo: 'Críticas',
                    valor: dados.criticas.toString(),
                    detalhe: 'Exigem ação imediata',
                    icon: Icons.error_outline_rounded,
                    alerta: dados.criticas > 0,
                  ),
                  _ResumoPendencia(
                    width: cardWidth,
                    titulo: 'Atenções',
                    valor: dados.atencoes.toString(),
                    detalhe: 'Devem ser acompanhadas',
                    icon: Icons.warning_amber_rounded,
                    alerta: dados.atencoes > 0,
                  ),
                  _ResumoPendencia(
                    width: cardWidth,
                    titulo: 'Recebimentos vencidos',
                    valor: dados.quantidade('Recebimentos').toString(),
                    detalhe: _moeda.format(dados.valor('Recebimentos')),
                    icon: Icons.schedule_rounded,
                    alerta: dados.quantidade('Recebimentos') > 0,
                  ),
                  _ResumoPendencia(
                    width: cardWidth,
                    titulo: 'Total pendências',
                    valor: dados.itens.length.toString(),
                    detalhe: 'Sem incluir backup local do Android',
                    icon: Icons.notification_important_outlined,
                    alerta: dados.itens.isNotEmpty,
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
                        width: compacto ? conteudo - 28 : 260,
                        child: DropdownButtonFormField<String>(
                          initialValue: _filtro,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            prefixIcon: Icon(Icons.filter_alt_outlined),
                          ),
                          items: ['Todos', ...tipos]
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _filtro = v ?? 'Todos'),
                        ),
                      ),
                      Text(
                        itens.length.toString() + ' resultado(s)',
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
              if (itens.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 44,
                          color: Colors.greenAccent,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nenhuma pendência neste filtro',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...itens.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => widget.onNavigate(item.moduloIndice),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color:
                                      (item.critica
                                              ? Colors.redAccent
                                              : Colors.orangeAccent)
                                          .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.critica
                                      ? Icons.error_outline_rounded
                                      : Icons.warning_amber_rounded,
                                  color: item.critica
                                      ? Colors.redAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Text(
                                          item.titulo,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(item.nivel),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        Chip(
                                          label: Text(item.tipo),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                    if (item.descricao.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.descricao,
                                        style: const TextStyle(
                                          color: Color(0xFFAAB3BD),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (item.valor > 0) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _moeda.format(item.valor),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}

class _ResumoPendencia extends StatelessWidget {
  const _ResumoPendencia({
    required this.width,
    required this.titulo,
    required this.valor,
    required this.detalhe,
    required this.icon,
    required this.alerta,
  });

  final double width;
  final String titulo;
  final String valor;
  final String detalhe;
  final IconData icon;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? Colors.orangeAccent : Colors.greenAccent;
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
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cor),
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
}
