import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/imperium_regras_negocio.dart';
import '../repositories/precificacao_repository.dart';
import '../repositories/fidelidade_repository.dart';

class CustoServicosPage extends StatefulWidget {
  const CustoServicosPage({super.key});

  @override
  State<CustoServicosPage> createState() => _CustoServicosPageState();
}

class _CustoServicosPageState extends State<CustoServicosPage> {
  final PrecificacaoRepository _repository = PrecificacaoRepository();
  final FidelidadeRepository _fidelidadeRepository = FidelidadeRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  final TextEditingController _horasController = TextEditingController();
  final TextEditingController _margemClienteController =
      TextEditingController();
  final TextEditingController _margemRevenda1a4Controller =
      TextEditingController();
  final TextEditingController _margemRevendaController =
      TextEditingController();
  final TextEditingController _margemRevenda10MaisController =
      TextEditingController();
  final TextEditingController _margemMinimaController = TextEditingController();

  bool _carregando = true;
  bool _salvandoBase = false;
  bool _salvandoFidelidade = false;
  int _mesesMedia = 3;
  PrecificacaoPainel? _painel;
  FidelidadeConfig? _fidelidadeConfig;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _horasController.dispose();
    _margemClienteController.dispose();
    _margemRevenda1a4Controller.dispose();
    _margemRevendaController.dispose();
    _margemRevenda10MaisController.dispose();
    _margemMinimaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _carregando = true);

    try {
      final painel = await _repository.carregar();

      FidelidadeConfig? fidelidade;
      try {
        fidelidade = await _fidelidadeRepository.carregarConfig();
      } catch (_) {
        // A precificação continua disponível mesmo se a configuração
        // opcional de fidelidade não puder ser carregada.
      }

      if (!mounted) return;

      _preencherConfig(painel.config);
      setState(() {
        _painel = painel;
        _fidelidadeConfig = fidelidade;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível calcular a precificação.\n$erro', erro: true);
    }
  }

  void _preencherConfig(PrecificacaoConfig config) {
    _horasController.text = _numero(ImperiumRegrasNegocio.horasMensaisPadrao);
    _margemClienteController.text = _numero(config.margemCliente);
    _margemRevenda1a4Controller.text = _numero(config.margemRevenda1a4);
    _margemRevendaController.text = _numero(config.margemRevenda5a9);
    _margemRevenda10MaisController.text = _numero(config.margemRevenda10Mais);
    _margemMinimaController.text = _numero(config.margemMinima);
    _mesesMedia = config.mesesMedia;
  }

  Future<void> _salvarBase() async {
    const horas = ImperiumRegrasNegocio.horasMensaisPadrao;
    final margemCliente = _valor(_margemClienteController.text);
    final margemRevenda1a4 = _valor(_margemRevenda1a4Controller.text);
    final margemRevenda5a9 = _valor(_margemRevendaController.text);
    final margemRevenda10Mais = _valor(_margemRevenda10MaisController.text);
    final margemMinima = _valor(_margemMinimaController.text);

    if (horas <= 0) {
      _mensagem('Informe as horas produtivas mensais.', erro: true);
      return;
    }

    setState(() => _salvandoBase = true);

    try {
      await _repository.salvarConfig(
        PrecificacaoConfig(
          horasProdutivasMes: horas,
          mesesMedia: _mesesMedia,
          margemCliente: margemCliente,
          // Compatibilidade: a margem única antiga passa a ser a faixa 5–9.
          margemRevenda: margemRevenda5a9,
          margemMinima: margemMinima,
          margemRevenda1a4: margemRevenda1a4,
          margemRevenda5a9: margemRevenda5a9,
          margemRevenda10Mais: margemRevenda10Mais,
        ),
      );

      if (!mounted) return;
      _mensagem('Base de precificação atualizada.');
      await _carregar();
    } catch (erro) {
      if (mounted) {
        _mensagem('$erro', erro: true);
      }
    } finally {
      if (mounted) setState(() => _salvandoBase = false);
    }
  }

  Future<void> _editarServico(PrecificacaoServico servico) async {
    final horasController = TextEditingController(
      text: _numero(servico.tempoPrecificacaoMinutos / 60),
    );
    var aceitaRevenda = servico.aceitaRevenda;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final media = servico.tempoMedioRealMinutos;

            return AlertDialog(
              title: Text(servico.nome),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Informe o tempo que você considera adequado para '
                      'precificar este serviço.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: horasController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Horas para precificação',
                        suffixText: 'h',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (media != null && media > 0) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          horasController.text = _numero(media / 60);
                        },
                        icon: const Icon(Icons.history_rounded),
                        label: Text('Usar média real (${_tempo(media)})'),
                      ),
                      Text(
                        '${servico.amostrasTempoReal} '
                        '${servico.amostrasTempoReal == 1 ? 'OS exclusiva' : 'OS exclusivas'} '
                        'usadas na média.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Disponível para revenda'),
                      subtitle: const Text(
                        'Mostra os preços de parceiro por faixa de volume.',
                      ),
                      value: aceitaRevenda,
                      onChanged: (valor) {
                        setModalState(() => aceitaRevenda = valor);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvar != true) {
      horasController.dispose();
      return;
    }

    final horas = _valor(horasController.text);
    horasController.dispose();

    if (horas <= 0) {
      _mensagem('Informe um tempo maior que zero.', erro: true);
      return;
    }

    try {
      await _repository.salvarPreferenciasServico(
        servicoId: servico.id,
        tempoPrecificacaoMinutos: horas * 60,
        aceitaRevenda: aceitaRevenda,
      );

      if (!mounted) return;
      _mensagem('Tempo de ${servico.nome} atualizado.');
      await _carregar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
    }
  }

  Future<void> _aplicarPreco(PrecificacaoServico servico) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Aplicar preço sugerido?'),
          content: Text(
            '${servico.nome}\n\n'
            'Preço atual: ${_moeda.format(servico.precoAtual)}\n'
            'Novo preço padrão: ${_moeda.format(servico.precoSugerido)}\n\n'
            'Isso altera o preço padrão do catálogo. '
            'Você poderá editá-lo novamente depois.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await _repository.aplicarPrecoPadrao(
        servicoId: servico.id,
        preco: servico.precoSugerido,
      );

      if (!mounted) return;
      _mensagem('Preço padrão de ${servico.nome} atualizado.');
      await _carregar();
    } catch (erro) {
      if (mounted) _mensagem('$erro', erro: true);
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
    final painel = _painel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Precificação dos serviços'),
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
          : painel == null
          ? const Center(child: Text('Não foi possível calcular os preços.'))
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
                children: [
                  _CabecalhoPrecificacao(
                    resumo: painel.resumo,
                    moeda: _moeda,
                    data: _data,
                  ),
                  const SizedBox(height: 12),
                  _configuracaoBase(),
                  const SizedBox(height: 12),
                  _configuracaoFidelidade(),
                  const SizedBox(height: 18),
                  const Text(
                    'Saúde dos preços',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'O Imperium compara o custo estimado de cada serviço '
                    'com o preço atual e sugere uma correção.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (painel.servicos.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Nenhum serviço ativo foi encontrado no catálogo.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ...painel.servicos.map(
                      (servico) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _ServicoPrecificacaoCard(
                          servico: servico,
                          config: painel.config,
                          resumo: painel.resumo,
                          moeda: _moeda,
                          tempo: _tempo,
                          percentual: _percentual,
                          onEditar: () => _editarServico(servico),
                          onAplicar: () => _aplicarPreco(servico),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const _NotaPrecificacao(),
                ],
              ),
            ),
    );
  }

  Future<void> _editarFidelidade() async {
    // fidelidade-tempo-ui-bloqueada-v1
    if (kFidelidadeTempoTemporariamenteDesativada) {
      _mensagem(
        'O desconto por tempo de cliente está temporariamente desativado. '
        'As configurações existentes foram preservadas.',
      );
      return;
    }

    final atual = _fidelidadeConfig ?? const FidelidadeConfig();

    var modo = atual.modo;
    var permitirParceiro = atual.permitirParceiro;

    final maximoController = TextEditingController(
      text: _numero(atual.descontoMaximoPercentual),
    );

    final faixas = atual.faixas
        .map(
          (item) => _FaixaFidelidadeEdicao(
            meses: item.mesesMinimos,
            percentual: item.percentual,
            ativo: item.ativo,
          ),
        )
        .toList();

    if (faixas.isEmpty) {
      faixas.add(_FaixaFidelidadeEdicao(meses: 12, percentual: 3, ativo: true));
    }

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Fidelidade do cliente'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: modo,
                        decoration: const InputDecoration(
                          labelText: 'Funcionamento',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'desativado',
                            child: Text('Desativado'),
                          ),
                          DropdownMenuItem(
                            value: 'sugerir',
                            child: Text('Sugerir desconto'),
                          ),
                          DropdownMenuItem(
                            value: 'automatico',
                            child: Text('Aplicar automaticamente'),
                          ),
                        ],
                        onChanged: (valor) {
                          if (valor != null) {
                            setModalState(() => modo = valor);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        modo == 'desativado'
                            ? 'Nenhum desconto por tempo de cliente será '
                                  'sugerido ou aplicado.'
                            : modo == 'sugerir'
                            ? 'O Imperium mostra o benefício disponível e '
                                  'você decide se deseja aplicar.'
                            : 'O benefício é aplicado automaticamente quando '
                                  'houver uma faixa válida, respeitando os '
                                  'limites de segurança.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: maximoController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Desconto máximo de fidelidade',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Permitir fidelidade junto com preço de parceiro',
                        ),
                        subtitle: const Text(
                          'Desativado é mais seguro para não acumular '
                          'descontos de parceiro e fidelidade.',
                        ),
                        value: permitirParceiro,
                        onChanged: (valor) {
                          setModalState(() => permitirParceiro = valor);
                        },
                      ),
                      const Divider(height: 24),
                      const Text(
                        'Faixas por tempo de cliente',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'O sistema usa a maior faixa já alcançada pelo '
                        'cliente. Você pode adicionar ou remover faixas.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...List.generate(faixas.length, (indice) {
                        final faixa = faixas[indice];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  dialogContext,
                                ).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: faixa.mesesController,
                                        enabled: faixa.ativo,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Após',
                                          suffixText: 'meses',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: faixa.percentualController,
                                        enabled: faixa.ativo,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9,.]'),
                                          ),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Desconto',
                                          suffixText: '%',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: faixa.ativo
                                          ? 'Desativar faixa'
                                          : 'Ativar faixa',
                                      onPressed: () {
                                        setModalState(
                                          () => faixa.ativo = !faixa.ativo,
                                        );
                                      },
                                      icon: Icon(
                                        faixa.ativo
                                            ? Icons.toggle_on_rounded
                                            : Icons.toggle_off_rounded,
                                        size: 30,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remover faixa',
                                      onPressed: faixas.length <= 1
                                          ? null
                                          : () {
                                              final removida = faixas.removeAt(
                                                indice,
                                              );
                                              removida.dispose();
                                              setModalState(() {});
                                            },
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: () {
                          setModalState(() {
                            final ultimoMes = faixas
                                .map((item) => item.meses)
                                .fold<int>(
                                  0,
                                  (maior, atual) =>
                                      atual > maior ? atual : maior,
                                );

                            faixas.add(
                              _FaixaFidelidadeEdicao(
                                meses: ultimoMes > 0 ? ultimoMes + 12 : 12,
                                percentual: 0,
                                ativo: true,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar faixa'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvar != true) {
      maximoController.dispose();
      for (final faixa in faixas) {
        faixa.dispose();
      }
      return;
    }

    final maximo = _valor(maximoController.text);
    final novasFaixas = <FidelidadeFaixa>[];

    for (var i = 0; i < faixas.length; i++) {
      final faixa = faixas[i];
      final meses = faixa.meses;
      final percentual = _valor(faixa.percentualController.text);

      if (meses <= 0) {
        maximoController.dispose();
        for (final item in faixas) {
          item.dispose();
        }
        _mensagem(
          'Informe um número de meses maior que zero nas faixas.',
          erro: true,
        );
        return;
      }

      novasFaixas.add(
        FidelidadeFaixa(
          mesesMinimos: meses,
          percentual: percentual,
          ativo: faixa.ativo,
          ordem: i,
        ),
      );
    }

    maximoController.dispose();
    for (final faixa in faixas) {
      faixa.dispose();
    }

    setState(() => _salvandoFidelidade = true);

    try {
      final config = FidelidadeConfig(
        modo: modo,
        descontoMaximoPercentual: maximo,
        permitirParceiro: permitirParceiro,
        faixas: novasFaixas,
      );

      await _fidelidadeRepository.salvarConfig(config);

      if (!mounted) return;

      setState(() {
        _fidelidadeConfig = config;
      });

      _mensagem(
        modo == 'desativado'
            ? 'Fidelidade desativada.'
            : 'Regras de fidelidade atualizadas.',
      );
    } catch (erro) {
      if (mounted) {
        _mensagem('$erro', erro: true);
      }
    } finally {
      if (mounted) {
        setState(() => _salvandoFidelidade = false);
      }
    }
  }

  Widget _configuracaoFidelidade() {
    final config = _fidelidadeConfig;

    String modoTexto() {
      switch (config?.modo) {
        case 'sugerir':
          return 'Sugerir desconto';
        case 'automatico':
          return 'Aplicar automaticamente';
        default:
          return 'Desativado';
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.loyalty_outlined),
        title: const Text(
          'Fidelidade do cliente',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          config == null
              ? 'Configuração não disponível'
              : '${modoTexto()} • padrão seguro: desligado',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (config == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Não foi possível carregar a configuração de fidelidade.',
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                config.modo == 'desativado'
                    ? 'A fidelidade está desligada. O desconto do orçamento '
                          'continua totalmente manual.'
                    : config.modo == 'sugerir'
                    ? 'Quando o cliente atingir uma faixa, o Imperium apenas '
                          'sugere o benefício. Você escolhe se aplica.'
                    : 'Quando o cliente atingir uma faixa, o Imperium pode '
                          'preencher o desconto automaticamente, sempre '
                          'respeitando a proteção de preço mínimo.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _LinhaFidelidadeResumo(titulo: 'Modo', valor: modoTexto()),
            _LinhaFidelidadeResumo(
              titulo: 'Desconto máximo',
              valor: _percentual(config.descontoMaximoPercentual),
            ),
            _LinhaFidelidadeResumo(
              titulo: 'Acumula com parceiro',
              valor: config.permitirParceiro ? 'Permitido' : 'Não',
            ),
            const Divider(height: 20),
            ...config.faixas
                .where((item) => item.ativo)
                .map(
                  (faixa) => _LinhaFidelidadeResumo(
                    titulo: 'Após ${faixa.mesesMinimos} meses',
                    valor: _percentual(faixa.percentual),
                  ),
                ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _salvandoFidelidade ? null : _editarFidelidade,
                icon: _salvandoFidelidade
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.tune_rounded),
                label: Text(
                  _salvandoFidelidade ? 'Salvando...' : 'Configurar fidelidade',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _configuracaoBase() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.tune_rounded),
        title: const Text(
          'Base da precificação',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Horas produtivas, média de custos e margens'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _horasController,
                  readOnly: true, // precificacao-horas-220-readonly-v2
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Horas produtivas/mês',
                    suffixText: 'h',
                    border: OutlineInputBorder(),
                    helperText:
                        'Base mensal atual: 220h. Não multiplique pela quantidade de funcionários.',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _mesesMedia,
                  decoration: const InputDecoration(
                    labelText: 'Média de custos',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 mês')),
                    DropdownMenuItem(value: 3, child: Text('3 meses')),
                    DropdownMenuItem(value: 6, child: Text('6 meses')),
                    DropdownMenuItem(value: 12, child: Text('12 meses')),
                  ],
                  onChanged: (valor) {
                    if (valor != null) setState(() => _mesesMedia = valor);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _margemClienteController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Margem cliente final',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _margemMinimaController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Margem mínima segura',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Revenda / parceiro por volume',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quanto maior o volume mensal do parceiro, menor pode ser '
              'a margem — sem passar da margem mínima segura.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final estreito = constraints.maxWidth < 520;

              final campos = <Widget>[
                _CampoMargemRevenda(
                  controller: _margemRevenda1a4Controller,
                  titulo: '1 a 4 / mês',
                ),
                _CampoMargemRevenda(
                  controller: _margemRevendaController,
                  titulo: '5 a 9 / mês',
                ),
                _CampoMargemRevenda(
                  controller: _margemRevenda10MaisController,
                  titulo: '10+ / mês',
                ),
              ];

              if (estreito) {
                return Column(
                  children: [
                    for (var i = 0; i < campos.length; i++) ...[
                      campos[i],
                      if (i < campos.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: campos[0]),
                  const SizedBox(width: 8),
                  Expanded(child: campos[1]),
                  const SizedBox(width: 8),
                  Expanded(child: campos[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _salvandoBase ? null : _salvarBase,
              icon: _salvandoBase
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calculate_outlined),
              label: Text(
                _salvandoBase ? 'Recalculando...' : 'Recalcular preços',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _tempo(double minutos) {
    final total = minutos.round();
    final horas = total ~/ 60;
    final resto = total % 60;

    if (horas <= 0) return '${resto}min';
    if (resto == 0) return '${horas}h';
    return '${horas}h ${resto}min';
  }

  String _numero(double valor) {
    final inteiro = valor.roundToDouble() == valor;
    final texto = inteiro ? valor.toInt().toString() : valor.toStringAsFixed(2);
    return texto.replaceAll('.', ',');
  }

  String _percentual(double valor) {
    return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  double _valor(String texto) {
    final bruto = texto.trim();
    if (bruto.contains(',')) {
      return double.tryParse(bruto.replaceAll('.', '').replaceAll(',', '.')) ??
          0;
    }
    return double.tryParse(bruto) ?? 0;
  }
}

class _FaixaFidelidadeEdicao {
  _FaixaFidelidadeEdicao({
    required int meses,
    required double percentual,
    required this.ativo,
  }) : mesesController = TextEditingController(text: meses.toString()),
       percentualController = TextEditingController(
         text: percentual == percentual.roundToDouble()
             ? percentual.toInt().toString()
             : percentual.toStringAsFixed(2).replaceAll('.', ','),
       );

  final TextEditingController mesesController;
  final TextEditingController percentualController;
  bool ativo;

  int get meses => int.tryParse(mesesController.text.trim()) ?? 0;

  void dispose() {
    mesesController.dispose();
    percentualController.dispose();
  }
}

class _LinhaFidelidadeResumo extends StatelessWidget {
  const _LinhaFidelidadeResumo({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CampoMargemRevenda extends StatelessWidget {
  const _CampoMargemRevenda({required this.controller, required this.titulo});

  final TextEditingController controller;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      decoration: InputDecoration(
        labelText: titulo,
        suffixText: '%',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _FaixaRevendaLinha extends StatelessWidget {
  const _FaixaRevendaLinha({
    required this.faixa,
    required this.margem,
    required this.preco,
    required this.precoCliente,
    required this.precoMinimo,
    required this.moeda,
    required this.percentual,
  });

  final String faixa;
  final double margem;
  final double preco;
  final double precoCliente;
  final double precoMinimo;
  final NumberFormat moeda;
  final String Function(double) percentual;

  @override
  Widget build(BuildContext context) {
    final economia = (precoCliente - preco)
        .clamp(0, double.infinity)
        .toDouble();
    final noLimite = preco <= precoMinimo + 0.01;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(faixa, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                'Margem ${percentual(margem)}'
                '${economia > 0 ? ' • ${moeda.format(economia)} abaixo do cliente final' : ''}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (noLimite) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: Colors.orange.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'No limite do preço mínimo seguro',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          moeda.format(preco),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _CabecalhoPrecificacao extends StatelessWidget {
  const _CabecalhoPrecificacao({
    required this.resumo,
    required this.moeda,
    required this.data,
  });

  final PrecificacaoResumo resumo;
  final NumberFormat moeda;
  final DateFormat data;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined),
                SizedBox(width: 8),
                Text(
                  'Análise de custo mensal',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _linha(
              'Média mensal realizada',
              moeda.format(resumo.mediaMensalReal),
            ),
            _linha(
              'Estrutura cadastrada',
              moeda.format(resumo.estruturaCadastrada),
            ),
            const Divider(),
            _linha(
              'Base mensal usada',
              moeda.format(resumo.baseMensalUsada),
              destaque: true,
            ),
            _linha(
              'Custo por hora produtiva',
              moeda.format(resumo.custoHora),
              destaque: true,
            ),
            _linha(
              'Taxa média de cartão',
              '${resumo.taxaCartaoMediaPercentual.toStringAsFixed(2).replaceAll('.', ',')}%',
            ),
            const SizedBox(height: 8),
            Text(
              resumo.usouHistoricoFinanceiro
                  ? 'A média realizada dos ${resumo.mesesConsiderados} meses '
                        'completos ficou acima da estrutura cadastrada e foi '
                        'usada como proteção de custo. Período: '
                        '${data.format(resumo.inicioHistorico)} a '
                        '${data.format(resumo.fimHistorico)}.'
                  : 'A estrutura cadastrada foi usada como proteção de custo. '
                        'O Imperium compara a média mensal realizada com os '
                        'custos fixos + equipe e sempre usa a maior referência '
                        'para evitar subprecificação.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(String titulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              fontSize: destaque ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicoPrecificacaoCard extends StatelessWidget {
  const _ServicoPrecificacaoCard({
    required this.servico,
    required this.config,
    required this.resumo,
    required this.moeda,
    required this.tempo,
    required this.percentual,
    required this.onEditar,
    required this.onAplicar,
  });

  final PrecificacaoServico servico;
  final PrecificacaoConfig config;
  final PrecificacaoResumo resumo;
  final NumberFormat moeda;
  final String Function(double) tempo;
  final String Function(double) percentual;
  final VoidCallback onEditar;
  final VoidCallback onAplicar;

  @override
  Widget build(BuildContext context) {
    final diferenca = servico.diferencaSugerida;
    final diferencaAbs = diferenca.abs();
    final taxaDecimal =
        resumo.taxaCartaoMediaPercentual.clamp(0.0, 30.0).toDouble() / 100;
    final resultadoAtual =
        servico.precoAtual -
        servico.custoBase -
        (servico.precoAtual * taxaDecimal);
    final resultadoSugerido =
        servico.precoSugerido -
        servico.custoBase -
        (servico.precoSugerido * taxaDecimal);
    final ganhoResultado = resultadoSugerido - resultadoAtual;

    late final String saude;
    late final IconData icone;
    late final Color cor;

    if (servico.precoAtual <= 0 ||
        servico.precoAtual < servico.precoMinimoSeguro) {
      saude = 'Preço abaixo do mínimo seguro';
      icone = Icons.error_outline_rounded;
      cor = Colors.red.shade400;
    } else if (diferenca > servico.precoSugerido * 0.10) {
      saude = 'Revisar preço';
      icone = Icons.warning_amber_rounded;
      cor = Colors.orange.shade400;
    } else {
      saude = 'Preço adequado';
      icone = Icons.check_circle_outline_rounded;
      cor = Colors.green.shade500;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(icone, color: cor),
        title: Text(
          servico.nome,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('$saude • ${tempo(servico.tempoPrecificacaoMinutos)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moeda.format(servico.precoSugerido),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('sugerido', style: TextStyle(fontSize: 10.5)),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (servico.categoria.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                servico.categoria,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          _LinhaPreco('Preço atual', servico.precoAtual, moeda),
          _LinhaPreco(
            'Tempo usado na precificação',
            servico.tempoPrecificacaoMinutos,
            moeda,
            texto: tempo(servico.tempoPrecificacaoMinutos),
          ),
          if (servico.tempoMedioRealMinutos != null)
            _LinhaPreco(
              'Tempo médio real',
              servico.tempoMedioRealMinutos!,
              moeda,
              texto:
                  '${tempo(servico.tempoMedioRealMinutos!)} '
                  '(${servico.amostrasTempoReal} '
                  '${servico.amostrasTempoReal == 1 ? 'OS' : 'OSs'})',
            ),
          const Divider(),
          _LinhaPreco('Produtos', servico.custoProdutos, moeda),
          _LinhaPreco(
            'Estrutura + equipe pelo tempo',
            servico.custoEstrutura,
            moeda,
          ),
          _LinhaPreco(
            'Custo base do serviço',
            servico.custoBase,
            moeda,
            destaque: true,
          ),
          if (resumo.taxaCartaoMediaPercentual > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Taxa média de cartão de '
                  '${percentual(resumo.taxaCartaoMediaPercentual)} '
                  'considerada na formação dos preços.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const Divider(),
          _LinhaPreco('Preço de equilíbrio', servico.precoEquilibrio, moeda),
          _LinhaPreco(
            'Preço mínimo seguro (${percentual(config.margemMinima)})',
            servico.precoMinimoSeguro,
            moeda,
          ),
          _LinhaPreco(
            'Sugestão cliente (${percentual(config.margemCliente)})',
            servico.precoSugerido,
            moeda,
            destaque: true,
          ),
          _LinhaPreco(
            'Margem estimada do preço atual',
            servico.margemAtual,
            moeda,
            texto: percentual(servico.margemAtual),
          ),
          _LinhaPreco(
            'Resultado estimado no preço atual',
            resultadoAtual,
            moeda,
            destaque: resultadoAtual < 0,
          ),
          _LinhaPreco(
            'Resultado estimado no preço sugerido',
            resultadoSugerido,
            moeda,
            destaque: true,
          ),
          if (ganhoResultado > 0.01)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Potencial de resultado: +${moeda.format(ganhoResultado)} '
                  'por execução ao aplicar o preço sugerido.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade500,
                  ),
                ),
              ),
            ),
          if (servico.aceitaRevenda) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.handshake_outlined, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Revenda / parceiro por volume',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Mesmo custo do serviço; a margem diminui conforme '
                    'o volume mensal do parceiro.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FaixaRevendaLinha(
                    faixa: '1 a 4 serviços/mês',
                    margem: config.margemRevenda1a4,
                    preco: servico.precoRevenda1a4,
                    precoCliente: servico.precoSugerido,
                    precoMinimo: servico.precoMinimoSeguro,
                    moeda: moeda,
                    percentual: percentual,
                  ),
                  const Divider(height: 14),
                  _FaixaRevendaLinha(
                    faixa: '5 a 9 serviços/mês',
                    margem: config.margemRevenda5a9,
                    preco: servico.precoRevenda5a9,
                    precoCliente: servico.precoSugerido,
                    precoMinimo: servico.precoMinimoSeguro,
                    moeda: moeda,
                    percentual: percentual,
                  ),
                  const Divider(height: 14),
                  _FaixaRevendaLinha(
                    faixa: '10+ serviços/mês',
                    margem: config.margemRevenda10Mais,
                    preco: servico.precoRevenda10Mais,
                    precoCliente: servico.precoSugerido,
                    precoMinimo: servico.precoMinimoSeguro,
                    moeda: moeda,
                    percentual: percentual,
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 17),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Preço mínimo seguro: '
                          '${moeda.format(servico.precoMinimoSeguro)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (diferencaAbs > 0.01)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                diferenca > 0
                    ? 'Sugestão: aumentar ${moeda.format(diferencaAbs)} '
                          '(${percentual(servico.variacaoPercentual)}).'
                    : 'O preço atual está ${moeda.format(diferencaAbs)} '
                          'acima da sugestão.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: diferenca > 0 ? Colors.orange.shade400 : null,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEditar,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Ajustar tempo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: servico.precoSugerido <= 0 ? null : onAplicar,
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('Aplicar preço'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinhaPreco extends StatelessWidget {
  const _LinhaPreco(
    this.titulo,
    this.valor,
    this.moeda, {
    this.destaque = false,
    this.texto,
  });

  final String titulo;
  final double valor;
  final NumberFormat moeda;
  final bool destaque;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: destaque ? FontWeight.bold : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            texto ?? moeda.format(valor),
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotaPrecificacao extends StatelessWidget {
  const _NotaPrecificacao();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'A precificação é uma análise gerencial. Ela não cria '
                'movimentos financeiros nem despesas no DRE. Produtos entram '
                'pelo consumo estimado do serviço; os demais custos mensais '
                'são transformados em custo/hora usando as horas produtivas '
                'que você informar. As faixas de revenda usam o mesmo custo '
                'base e reduzem somente a margem conforme o volume. Nesta '
                'etapa elas são uma referência de preço; a escolha automática '
                'da faixa na OS/orçamento será ligada em uma próxima etapa. '
                'O tempo médio real usa apenas OS finalizadas que tinham '
                'somente aquele serviço.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
