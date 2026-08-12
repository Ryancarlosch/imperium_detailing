import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/financeiro_repository.dart';

enum _PeriodoPrevistoRealizado { mes, trimestre, ano }

class PrevistoRealizadoPage extends StatefulWidget {
  const PrevistoRealizadoPage({super.key});

  @override
  State<PrevistoRealizadoPage> createState() => _PrevistoRealizadoPageState();
}

class _PrevistoRealizadoPageState extends State<PrevistoRealizadoPage> {
  final FinanceiroRepository _repository = FinanceiroRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _referencia = DateTime.now();
  _PeriodoPrevistoRealizado _periodo = _PeriodoPrevistoRealizado.mes;

  bool _carregando = true;
  Map<String, double> _resumo = const {};
  List<Map<String, dynamic>> _categorias = const [];
  List<Map<String, dynamic>> _servicos = const [];

  DateTime get _inicio {
    switch (_periodo) {
      case _PeriodoPrevistoRealizado.mes:
        return DateTime(_referencia.year, _referencia.month, 1);
      case _PeriodoPrevistoRealizado.trimestre:
        final primeiroMes = ((_referencia.month - 1) ~/ 3) * 3 + 1;
        return DateTime(_referencia.year, primeiroMes, 1);
      case _PeriodoPrevistoRealizado.ano:
        return DateTime(_referencia.year, 1, 1);
    }
  }

  DateTime get _fim {
    switch (_periodo) {
      case _PeriodoPrevistoRealizado.mes:
        return DateTime(_referencia.year, _referencia.month + 1, 0, 23, 59, 59);
      case _PeriodoPrevistoRealizado.trimestre:
        final primeiroMes = ((_referencia.month - 1) ~/ 3) * 3 + 1;
        return DateTime(_referencia.year, primeiroMes + 3, 0, 23, 59, 59);
      case _PeriodoPrevistoRealizado.ano:
        return DateTime(_referencia.year, 12, 31, 23, 59, 59);
    }
  }

  String get _tituloPeriodo {
    switch (_periodo) {
      case _PeriodoPrevistoRealizado.mes:
        final texto = DateFormat('MMMM yyyy', 'pt_BR').format(_referencia);
        return texto[0].toUpperCase() + texto.substring(1);
      case _PeriodoPrevistoRealizado.trimestre:
        final trimestre = ((_referencia.month - 1) ~/ 3) + 1;
        return '$trimestreº trimestre de ${_referencia.year}';
      case _PeriodoPrevistoRealizado.ano:
        return '${_referencia.year}';
    }
  }

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
      final resultados = await Future.wait<dynamic>([
        _repository.obterPrevistoRealizado(inicio: _inicio, fim: _fim),
        _repository.listarPrevistoRealizadoPorCategoria(
          inicio: _inicio,
          fim: _fim,
        ),
        _repository.listarPrevistoRealizadoPorServico(
          inicio: _inicio,
          fim: _fim,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _resumo = Map<String, double>.from(
          resultados[0] as Map<String, double>,
        );
        _categorias = List<Map<String, dynamic>>.from(
          resultados[1] as List<dynamic>,
        );
        _servicos = List<Map<String, dynamic>>.from(
          resultados[2] as List<dynamic>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() => _carregando = false);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível carregar o Previsto x Realizado.\n$erro',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  void _alterarPeriodo(int delta) {
    setState(() {
      switch (_periodo) {
        case _PeriodoPrevistoRealizado.mes:
          _referencia = DateTime(
            _referencia.year,
            _referencia.month + delta,
            1,
          );
        case _PeriodoPrevistoRealizado.trimestre:
          _referencia = DateTime(
            _referencia.year,
            _referencia.month + (delta * 3),
            1,
          );
        case _PeriodoPrevistoRealizado.ano:
          _referencia = DateTime(_referencia.year + delta, 1, 1);
      }
    });

    _carregar();
  }

  void _alterarTipoPeriodo(_PeriodoPrevistoRealizado valor) {
    if (_periodo == valor) return;

    setState(() => _periodo = valor);
    _carregar();
  }

  Map<String, List<Map<String, dynamic>>> get _servicosPorCategoria {
    final mapa = <String, List<Map<String, dynamic>>>{};

    for (final item in _servicos) {
      final categoria = (item['categoria'] ?? 'Sem categoria')
          .toString()
          .trim();
      final nome = categoria.isEmpty ? 'Sem categoria' : categoria;
      mapa.putIfAbsent(nome, () => <Map<String, dynamic>>[]).add(item);
    }

    return mapa;
  }

  List<Map<String, dynamic>> get _outrasCategorias {
    return _categorias.where((item) {
      final codigo = (item['codigo'] ?? '').toString().trim();

      // Receitas de serviços ligadas a OS aparecem na seção própria abaixo.
      // Mantemos lançamentos não classificados e demais contas financeiras.
      return codigo != '1.01' && !codigo.startsWith('1.01.');
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsto x Realizado'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
                children: [
                  SegmentedButton<_PeriodoPrevistoRealizado>(
                    segments: const [
                      ButtonSegment(
                        value: _PeriodoPrevistoRealizado.mes,
                        label: Text('Mês'),
                      ),
                      ButtonSegment(
                        value: _PeriodoPrevistoRealizado.trimestre,
                        label: Text('Trimestre'),
                      ),
                      ButtonSegment(
                        value: _PeriodoPrevistoRealizado.ano,
                        label: Text('Ano'),
                      ),
                    ],
                    selected: {_periodo},
                    onSelectionChanged: (selecionado) {
                      _alterarTipoPeriodo(selecionado.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  _SeletorPeriodo(
                    titulo: _tituloPeriodo,
                    onAnterior: () => _alterarPeriodo(-1),
                    onProximo: () => _alterarPeriodo(1),
                  ),
                  const SizedBox(height: 12),
                  _ResumoPrevistoRealizado(resumo: _resumo, moeda: _moeda),
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 20),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Previsto mostra valores programados para o '
                              'período. Realizado mostra o que efetivamente '
                              'foi pago ou recebido. Transferências internas '
                              'e itens que não afetam o resultado ficam fora.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ReceitasServicosSection(
                    porCategoria: _servicosPorCategoria,
                    categoriasFinanceiras: _categorias,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 20),
                  _DemaisCategoriasSection(
                    categorias: _outrasCategorias,
                    moeda: _moeda,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SeletorPeriodo extends StatelessWidget {
  const _SeletorPeriodo({
    required this.titulo,
    required this.onAnterior,
    required this.onProximo,
  });

  final String titulo;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Período anterior',
          onPressed: onAnterior,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Próximo período',
          onPressed: onProximo,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _ResumoPrevistoRealizado extends StatelessWidget {
  const _ResumoPrevistoRealizado({required this.resumo, required this.moeda});

  final Map<String, double> resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final entradaPrevista = resumo['entrada_prevista'] ?? 0;
    final entradaRealizada = resumo['entrada_realizada'] ?? 0;
    final saidaPrevista = resumo['saida_prevista'] ?? 0;
    final saidaRealizada = resumo['saida_realizada'] ?? 0;
    final resultadoPrevisto = resumo['resultado_previsto'] ?? 0;
    final resultadoRealizado = resumo['resultado_realizado'] ?? 0;

    return Column(
      children: [
        _ComparacaoCard(
          titulo: 'Receitas',
          previsto: entradaPrevista,
          realizado: entradaRealizada,
          moeda: moeda,
          icone: Icons.south_west_rounded,
          despesa: false,
        ),
        const SizedBox(height: 8),
        _ComparacaoCard(
          titulo: 'Despesas',
          previsto: saidaPrevista,
          realizado: saidaRealizada,
          moeda: moeda,
          icone: Icons.north_east_rounded,
          despesa: true,
        ),
        const SizedBox(height: 8),
        _ComparacaoCard(
          titulo: 'Resultado',
          previsto: resultadoPrevisto,
          realizado: resultadoRealizado,
          moeda: moeda,
          icone: Icons.account_balance_wallet_outlined,
          despesa: false,
          destaque: true,
        ),
      ],
    );
  }
}

class _ComparacaoCard extends StatelessWidget {
  const _ComparacaoCard({
    required this.titulo,
    required this.previsto,
    required this.realizado,
    required this.moeda,
    required this.icone,
    required this.despesa,
    this.destaque = false,
  });

  final String titulo;
  final double previsto;
  final double realizado;
  final NumberFormat moeda;
  final IconData icone;
  final bool despesa;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final diferenca = realizado - previsto;
    final temPrevisto = previsto.abs() > 0.000001;
    final atingimento = temPrevisto ? realizado / previsto * 100 : null;

    final String leitura;
    final bool favoravel;

    if (!temPrevisto) {
      leitura = realizado.abs() <= 0.000001
          ? 'Sem movimento no período'
          : 'Sem valor previsto para comparar';
      favoravel = true;
    } else if (despesa) {
      final saldo = previsto - realizado;
      if (saldo >= 0) {
        leitura = 'Disponível no previsto: ${moeda.format(saldo)}';
        favoravel = true;
      } else {
        leitura = 'Acima do previsto: ${moeda.format(saldo.abs())}';
        favoravel = false;
      }
    } else {
      if (diferenca >= 0) {
        leitura = 'Acima do previsto: ${moeda.format(diferenca)}';
        favoravel = true;
      } else {
        leitura = 'Falta realizar: ${moeda.format(diferenca.abs())}';
        favoravel = false;
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(destaque ? 16 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: destaque ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (atingimento != null)
                  Text(
                    '${atingimento.toStringAsFixed(1).replaceAll('.', ',')}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: favoravel
                          ? Colors.green.shade500
                          : Colors.orange.shade500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: _ValorResumo(
                    titulo: 'Previsto',
                    valor: moeda.format(previsto),
                  ),
                ),
                Expanded(
                  child: _ValorResumo(
                    titulo: 'Realizado',
                    valor: moeda.format(realizado),
                    destaque: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              leitura,
              style: TextStyle(
                fontSize: 12.5,
                color: favoravel
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Colors.orange.shade500,
              ),
            ),
            if (temPrevisto) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (realizado / previsto).clamp(0, 1).toDouble(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValorResumo extends StatelessWidget {
  const _ValorResumo({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: destaque ? 18 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ReceitasServicosSection extends StatelessWidget {
  const _ReceitasServicosSection({
    required this.porCategoria,
    required this.categoriasFinanceiras,
    required this.moeda,
  });

  final Map<String, List<Map<String, dynamic>>> porCategoria;
  final List<Map<String, dynamic>> categoriasFinanceiras;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final entradasServico = categoriasFinanceiras.where((item) {
      final codigo = (item['codigo'] ?? '').toString().trim();
      final tipo = (item['tipo'] ?? '').toString().trim().toLowerCase();
      return tipo == 'entrada' &&
          (codigo == '1.01' || codigo.startsWith('1.01.'));
    }).toList();

    final totalPrevistoConta = entradasServico.fold<double>(
      0,
      (soma, item) => soma + _double(item['previsto']),
    );
    final totalRealizadoConta = entradasServico.fold<double>(
      0,
      (soma, item) => soma + _double(item['realizado']),
    );

    final totalPrevistoDetalhado = porCategoria.values
        .expand((lista) => lista)
        .fold<double>(0, (soma, item) => soma + _double(item['previsto']));
    final totalRealizadoDetalhado = porCategoria.values
        .expand((lista) => lista)
        .fold<double>(0, (soma, item) => soma + _double(item['realizado']));

    final residualPrevisto = totalPrevistoConta - totalPrevistoDetalhado;
    final residualRealizado = totalRealizadoConta - totalRealizadoDetalhado;

    final categorias = porCategoria.entries.toList()
      ..sort((a, b) {
        final realizadoA = a.value.fold<double>(
          0,
          (soma, item) => soma + _double(item['realizado']),
        );
        final realizadoB = b.value.fold<double>(
          0,
          (soma, item) => soma + _double(item['realizado']),
        );
        return realizadoB.compareTo(realizadoA);
      });

    final temResidual =
        residualPrevisto.abs() > 0.01 || residualRealizado.abs() > 0.01;

    if (categorias.isEmpty && !temResidual) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Receitas de serviços',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Categoria → serviço. A estrutura vem do catálogo e os valores '
          'são rateados pelas Ordens de Serviço.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 9),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < categorias.length; index++) ...[
                _CategoriaServicoPrevisto(
                  categoria: categorias[index].key,
                  servicos: categorias[index].value,
                  moeda: moeda,
                ),
                if (index < categorias.length - 1 || temResidual)
                  const Divider(height: 1),
              ],
              if (temResidual)
                _LinhaPrevistoRealizado(
                  titulo: 'Outros / sem vínculo com OS',
                  subtitulo:
                      'Receita de serviços que não pôde ser associada a um '
                      'serviço cadastrado.',
                  previsto: residualPrevisto,
                  realizado: residualRealizado,
                  moeda: moeda,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoriaServicoPrevisto extends StatelessWidget {
  const _CategoriaServicoPrevisto({
    required this.categoria,
    required this.servicos,
    required this.moeda,
  });

  final String categoria;
  final List<Map<String, dynamic>> servicos;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final previsto = servicos.fold<double>(
      0,
      (soma, item) => soma + _double(item['previsto']),
    );
    final realizado = servicos.fold<double>(
      0,
      (soma, item) => soma + _double(item['realizado']),
    );

    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        categoria,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${servicos.length} ${servicos.length == 1 ? 'serviço' : 'serviços'}',
      ),
      trailing: _MiniValores(
        previsto: previsto,
        realizado: realizado,
        moeda: moeda,
      ),
      children: [
        for (final item in servicos)
          _LinhaPrevistoRealizado(
            titulo: (item['servico'] ?? 'Serviço').toString(),
            previsto: _double(item['previsto']),
            realizado: _double(item['realizado']),
            moeda: moeda,
            recuo: true,
          ),
      ],
    );
  }
}

class _DemaisCategoriasSection extends StatelessWidget {
  const _DemaisCategoriasSection({
    required this.categorias,
    required this.moeda,
  });

  final List<Map<String, dynamic>> categorias;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final receitas = categorias.where((item) {
      return (item['tipo'] ?? '').toString().toLowerCase() == 'entrada';
    }).toList();

    final despesas = categorias.where((item) {
      return (item['tipo'] ?? '').toString().toLowerCase() != 'entrada';
    }).toList();

    if (receitas.isEmpty && despesas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Demais categorias',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'As categorias abaixo seguem o Plano de Contas.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 9),
        if (receitas.isNotEmpty)
          _GrupoFinanceiro(
            titulo: 'Outras receitas',
            icone: Icons.south_west_rounded,
            itens: receitas,
            moeda: moeda,
          ),
        if (receitas.isNotEmpty && despesas.isNotEmpty)
          const SizedBox(height: 8),
        if (despesas.isNotEmpty)
          _GrupoFinanceiro(
            titulo: 'Despesas',
            icone: Icons.north_east_rounded,
            itens: despesas,
            moeda: moeda,
          ),
      ],
    );
  }
}

class _GrupoFinanceiro extends StatelessWidget {
  const _GrupoFinanceiro({
    required this.titulo,
    required this.icone,
    required this.itens,
    required this.moeda,
  });

  final String titulo;
  final IconData icone;
  final List<Map<String, dynamic>> itens;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final previsto = itens.fold<double>(
      0,
      (soma, item) => soma + _double(item['previsto']),
    );
    final realizado = itens.fold<double>(
      0,
      (soma, item) => soma + _double(item['realizado']),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(icone),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: _MiniValores(
          previsto: previsto,
          realizado: realizado,
          moeda: moeda,
        ),
        children: [
          for (final item in itens)
            _LinhaPrevistoRealizado(
              titulo: (item['categoria'] ?? 'Sem categoria').toString(),
              subtitulo: (item['codigo'] ?? '').toString(),
              previsto: _double(item['previsto']),
              realizado: _double(item['realizado']),
              moeda: moeda,
            ),
        ],
      ),
    );
  }
}

class _LinhaPrevistoRealizado extends StatelessWidget {
  const _LinhaPrevistoRealizado({
    required this.titulo,
    required this.previsto,
    required this.realizado,
    required this.moeda,
    this.subtitulo,
    this.recuo = false,
  });

  final String titulo;
  final String? subtitulo;
  final double previsto;
  final double realizado;
  final NumberFormat moeda;
  final bool recuo;

  @override
  Widget build(BuildContext context) {
    final percentual = previsto.abs() <= 0.000001
        ? null
        : (realizado / previsto) * 100;

    return Padding(
      padding: EdgeInsets.fromLTRB(recuo ? 32 : 16, 9, 14, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitulo != null && subtitulo!.trim().isNotEmpty)
                      Text(
                        subtitulo!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (percentual != null)
                Text(
                  '${percentual.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Prev. ${moeda.format(previsto)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Real. ${moeda.format(realizado)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (previsto > 0.000001) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (realizado / previsto).clamp(0, 1).toDouble(),
              minHeight: 4,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniValores extends StatelessWidget {
  const _MiniValores({
    required this.previsto,
    required this.realizado,
    required this.moeda,
  });

  final double previsto;
  final double realizado;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          moeda.format(realizado),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
        ),
        Text(
          'de ${moeda.format(previsto)}',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
