import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/item_orcamento.dart';
import '../models/orcamento.dart';
import '../models/servico_catalogo.dart';
import '../repositories/orcamento_repository.dart';
import '../repositories/servico_repository.dart';
import '../repositories/precificacao_repository.dart';
import '../repositories/fidelidade_repository.dart';

class NovoOrcamentoPage extends StatefulWidget {
  const NovoOrcamentoPage({super.key, this.orcamento});

  final Orcamento? orcamento;

  @override
  State<NovoOrcamentoPage> createState() => _NovoOrcamentoPageState();
}

class _NovoOrcamentoPageState extends State<NovoOrcamentoPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = OrcamentoRepository();
  final _servicoRepository = ServicoRepository();
  final _precificacaoRepository = PrecificacaoRepository();
  final _fidelidadeRepository = FidelidadeRepository();

  final _observacoesController = TextEditingController();

  final _descontoController = TextEditingController();

  final _formatoData = DateFormat('dd/MM/yyyy');

  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _veiculos = [];
  List<ItemOrcamento> _itens = [];
  List<int?> _servicoCatalogoIds = [];
  List<ServicoCatalogo> _catalogoServicos = [];
  Map<int, PrecificacaoServico> _precificacaoPorId = const {};
  PrecificacaoPainel? _precificacao;
  FidelidadeConfig _fidelidadeConfig = const FidelidadeConfig();
  FidelidadeBeneficio? _beneficioFidelidade;

  int? _clienteId;
  int? _veiculoId;
  String _perfilPreco = 'cliente';
  String _origemDesconto = 'manual';
  double _descontoFidelidadeSugerido = 0;
  double _percentualFidelidadeAplicado = 0;
  bool _alterandoDescontoInternamente = false;

  DateTime _dataEmissao = DateTime.now();

  DateTime _validade = DateTime.now().add(const Duration(days: 15));

  String _status = 'Pendente';

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    final orcamento = widget.orcamento;

    if (orcamento != null) {
      _clienteId = orcamento.clienteId;
      _veiculoId = orcamento.veiculoId;
      _status = orcamento.status;

      _dataEmissao = DateTime.tryParse(orcamento.dataEmissao) ?? DateTime.now();

      _validade =
          DateTime.tryParse(orcamento.validade) ??
          DateTime.now().add(const Duration(days: 15));

      _observacoesController.text = orcamento.observacoes;

      if (orcamento.desconto > 0) {
        _descontoController.text = orcamento.desconto
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }

      if (orcamento.itens.isNotEmpty) {
        _itens = List<ItemOrcamento>.from(orcamento.itens);
        _servicoCatalogoIds = List<int?>.filled(_itens.length, null);
      } else if (orcamento.servico.trim().isNotEmpty || orcamento.valor > 0) {
        _itens = [
          ItemOrcamento(
            servico: orcamento.servico.trim().isEmpty
                ? 'Serviço'
                : orcamento.servico,
            descricao: orcamento.descricao,
            quantidade: 1,
            valorUnitario: orcamento.valor,
            ordem: 0,
          ),
        ];
        _servicoCatalogoIds = <int?>[null];
      }
    }

    _carregarDados();
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    _descontoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final database = await AppDatabase.instance.database;

      final clientes = await database.query('clientes', orderBy: 'nome ASC');
      final catalogo = await _servicoRepository.listarServicos(
        somenteAtivos: true,
      );

      PrecificacaoPainel? precificacao;
      try {
        precificacao = await _precificacaoRepository.carregar();
      } catch (_) {
        // Orçamento manual continua disponível sem a precificação.
      }

      FidelidadeConfig fidelidadeConfig;
      try {
        fidelidadeConfig = await _fidelidadeRepository.carregarConfig();
      } catch (_) {
        fidelidadeConfig = const FidelidadeConfig();
      }

      List<Map<String, dynamic>> veiculos = [];

      if (_clienteId != null) {
        veiculos = await database.query(
          'veiculos',
          where: 'cliente_id = ?',
          whereArgs: [_clienteId],
          orderBy: 'marca ASC, modelo ASC',
        );
      }

      var perfil = 'cliente';
      var origemDesconto = _desconto > 0 ? 'manual' : 'nenhum';
      var percentualAplicado = 0.0;
      Map<int, int> mapeamento = const <int, int>{};

      final orcamentoId = widget.orcamento?.id;

      if (orcamentoId != null) {
        try {
          perfil = await _repository.buscarPerfilPreco(orcamentoId);
        } catch (_) {
          perfil = 'informado';
        }

        try {
          mapeamento = await _repository.buscarMapeamentoCatalogo(orcamentoId);
        } catch (_) {
          mapeamento = const <int, int>{};
        }

        try {
          final snapshot = await _fidelidadeRepository.buscarDescontoDocumento(
            documentoTipo: 'ORCAMENTO',
            documentoId: orcamentoId,
          );

          if (snapshot != null) {
            origemDesconto = snapshot.origem;
            percentualAplicado = snapshot.percentual;
          }
        } catch (_) {
          // Orçamentos antigos permanecem como desconto manual.
        }
      }

      const perfisValidos = <String>{
        'informado',
        'cliente',
        'parceiro_1_4',
        'parceiro_5_9',
        'parceiro_10_mais',
      };

      if (!perfisValidos.contains(perfil)) {
        perfil = 'informado';
      }

      final precificacaoPorId = <int, PrecificacaoServico>{};

      if (precificacao != null) {
        for (final servico in precificacao.servicos) {
          precificacaoPorId[servico.id] = servico;
        }
      }

      final idsCatalogo = <int?>[];

      for (var indice = 0; indice < _itens.length; indice++) {
        final salvo = mapeamento[indice];

        if (salvo != null) {
          idsCatalogo.add(salvo);
          continue;
        }

        final nome = _itens[indice].servico.trim().toLowerCase();
        final candidatos = catalogo
            .where((item) => item.nome.trim().toLowerCase() == nome)
            .toList();

        idsCatalogo.add(candidatos.length == 1 ? candidatos.first.id : null);
      }

      FidelidadeBeneficio? beneficio;

      if (_clienteId != null) {
        try {
          beneficio = await _fidelidadeRepository.avaliarCliente(
            _clienteId!,
            dataReferencia: _dataEmissao,
          );
        } catch (_) {
          beneficio = null;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _clientes = clientes;
        _veiculos = veiculos;
        _catalogoServicos = catalogo;
        _precificacao = precificacao;
        _precificacaoPorId = precificacaoPorId;
        _fidelidadeConfig = fidelidadeConfig;
        _beneficioFidelidade = beneficio;
        _perfilPreco = perfil;
        _origemDesconto = origemDesconto;
        _percentualFidelidadeAplicado = percentualAplicado;
        _servicoCatalogoIds = idsCatalogo;
        _carregando = false;
      });

      await _atualizarSugestaoFidelidade(
        aplicarAutomatico:
            widget.orcamento == null && fidelidadeConfig.automatica,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem('Não foi possível carregar os dados: $erro', erro: true);
    }
  }

  Future<void> _carregarVeiculos(int clienteId) async {
    try {
      final database = await AppDatabase.instance.database;

      final veiculos = await database.query(
        'veiculos',
        where: 'cliente_id = ?',
        whereArgs: [clienteId],
        orderBy: 'marca ASC, modelo ASC',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _veiculos = veiculos;
        _veiculoId = null;
      });

      await _atualizarFidelidadeCliente(
        aplicarAutomatico: _fidelidadeConfig.automatica,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível carregar os veículos: $erro',
        erro: true,
      );
    }
  }

  int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }

  double _converterValor(String texto) {
    final valorLimpo = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');

    if (valorLimpo.isEmpty) {
      return 0;
    }

    if (valorLimpo.contains(',')) {
      return double.tryParse(
            valorLimpo.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0;
    }

    return double.tryParse(valorLimpo) ?? 0;
  }

  double get _subtotal {
    return _itens.fold<double>(0, (total, item) => total + item.subtotal);
  }

  double get _desconto {
    return _converterValor(_descontoController.text);
  }

  double get _total {
    final total = _subtotal - _desconto;

    if (total < 0) {
      return 0;
    }

    return total;
  }

  String _formatarNumeroCampo(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _nomePerfilPreco(String perfil) {
    switch (perfil) {
      case 'cliente':
        return 'Cliente final';
      case 'parceiro_1_4':
        return 'Parceiro • 1 a 4/mês';
      case 'parceiro_5_9':
        return 'Parceiro • 5 a 9/mês';
      case 'parceiro_10_mais':
        return 'Parceiro • 10+/mês';
      case 'informado':
      default:
        return 'Preço informado / combinado';
    }
  }

  bool get _perfilEhParceiro => _perfilPreco.startsWith('parceiro_');

  ServicoCatalogo? _catalogoPorId(int? id) {
    if (id == null) {
      return null;
    }

    for (final servico in _catalogoServicos) {
      if (servico.id == id) {
        return servico;
      }
    }

    return null;
  }

  PrecificacaoServico? _precificacaoDoServico(ServicoCatalogo servico) {
    final id = servico.id;
    return id == null ? null : _precificacaoPorId[id];
  }

  double _precoDoPerfil(ServicoCatalogo servico, {String? perfil}) {
    final perfilUsado = perfil ?? _perfilPreco;
    final precificacao = _precificacaoDoServico(servico);

    if (perfilUsado == 'informado') {
      return servico.precoPadrao;
    }

    if (perfilUsado == 'cliente') {
      final sugerido = precificacao?.precoSugerido ?? 0;
      return sugerido > 0 ? sugerido : servico.precoPadrao;
    }

    if (precificacao == null || !precificacao.aceitaRevenda) {
      final sugerido = precificacao?.precoSugerido ?? 0;
      return sugerido > 0 ? sugerido : servico.precoPadrao;
    }

    final fallbackCliente = precificacao.precoSugerido > 0
        ? precificacao.precoSugerido
        : servico.precoPadrao;

    switch (perfilUsado) {
      case 'parceiro_1_4':
        return precificacao.precoRevenda1a4 > 0
            ? precificacao.precoRevenda1a4
            : fallbackCliente;
      case 'parceiro_5_9':
        return precificacao.precoRevenda5a9 > 0
            ? precificacao.precoRevenda5a9
            : fallbackCliente;
      case 'parceiro_10_mais':
        return precificacao.precoRevenda10Mais > 0
            ? precificacao.precoRevenda10Mais
            : fallbackCliente;
      default:
        return servico.precoPadrao;
    }
  }

  Future<void> _alterarPerfilPreco(String novoPerfil) async {
    if (novoPerfil == _perfilPreco) {
      return;
    }

    final vinculados = _servicoCatalogoIds.whereType<int>().length;

    if (vinculados > 0 && novoPerfil != 'informado') {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Aplicar perfil de preço?'),
            content: Text(
              'Os $vinculados serviço'
              '${vinculados == 1 ? '' : 's'} vinculados ao catálogo serão '
              'recalculados para:\n\n${_nomePerfilPreco(novoPerfil)}\n\n'
              'Serviços digitados manualmente não serão alterados. '
              'Os valores continuam editáveis depois.',
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

      if (confirmar != true || !mounted) {
        return;
      }
    }

    setState(() {
      _perfilPreco = novoPerfil;
    });

    if (novoPerfil != 'informado') {
      _recalcularItensPerfil();
    }

    await _atualizarSugestaoFidelidade(
      aplicarAutomatico: _fidelidadeConfig.automatica,
    );
  }

  void _recalcularItensPerfil() {
    final novos = <ItemOrcamento>[];

    for (var indice = 0; indice < _itens.length; indice++) {
      final item = _itens[indice];
      final servico = indice < _servicoCatalogoIds.length
          ? _catalogoPorId(_servicoCatalogoIds[indice])
          : null;

      if (servico == null) {
        novos.add(item);
        continue;
      }

      novos.add(
        item.copyWith(
          servico: servico.nome,
          descricao: item.descricao.trim().isEmpty
              ? servico.descricao
              : item.descricao,
          valorUnitario: _precoDoPerfil(servico),
        ),
      );
    }

    setState(() {
      _itens = novos;
    });
  }

  Future<ServicoCatalogo?> _selecionarServicoCatalogoOrcamento() async {
    if (_catalogoServicos.isEmpty) {
      _mostrarMensagem(
        'Nenhum serviço ativo foi encontrado no catálogo.',
        erro: true,
      );
      return null;
    }

    return showModalBottomSheet<ServicoCatalogo>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomContext) {
        var pesquisa = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final termo = pesquisa.trim().toLowerCase();

            final filtrados = _catalogoServicos.where((servico) {
              if (termo.isEmpty) return true;

              return [
                servico.nome,
                servico.categoria,
                servico.descricao,
              ].join(' ').toLowerCase().contains(termo);
            }).toList();

            return FractionallySizedBox(
              heightFactor: 0.82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Selecionar serviço do catálogo',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Pesquisar serviço',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (valor) {
                        setModalState(() => pesquisa = valor);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(
                              child: Text('Nenhum serviço encontrado.'),
                            )
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (context, indiceSeparador) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, indice) {
                                final servico = filtrados[indice];
                                final precificacao = _precificacaoDoServico(
                                  servico,
                                );
                                final parceiroNaoElegivel =
                                    _perfilEhParceiro &&
                                    (precificacao == null ||
                                        !precificacao.aceitaRevenda);

                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.design_services_outlined),
                                  ),
                                  title: Text(servico.nome),
                                  subtitle: Text(
                                    [
                                      if (servico.categoria.trim().isNotEmpty)
                                        servico.categoria,
                                      _formatoMoeda.format(
                                        _precoDoPerfil(servico),
                                      ),
                                      if (parceiroNaoElegivel)
                                        'usa preço de cliente final',
                                    ].join(' • '),
                                  ),
                                  trailing: const Icon(Icons.add),
                                  onTap: () {
                                    Navigator.pop(bottomContext, servico);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _adicionarServicoDoCatalogo() async {
    final servico = await _selecionarServicoCatalogoOrcamento();

    if (servico == null || !mounted) {
      return;
    }

    final precificacao = _precificacaoDoServico(servico);
    final parceiroNaoElegivel =
        _perfilEhParceiro &&
        (precificacao == null || !precificacao.aceitaRevenda);

    setState(() {
      _itens.add(
        ItemOrcamento(
          servico: servico.nome,
          descricao: servico.descricao,
          quantidade: 1,
          valorUnitario: _precoDoPerfil(servico),
          ordem: _itens.length,
        ),
      );
      _servicoCatalogoIds.add(servico.id);
    });

    if (parceiroNaoElegivel) {
      _mostrarMensagem(
        '${servico.nome} não está habilitado para revenda. '
        'Foi usado o preço de cliente final.',
      );
    }

    await _atualizarSugestaoFidelidade(
      aplicarAutomatico: _fidelidadeConfig.automatica,
    );
  }

  Future<void> _abrirAdicionarServico() async {
    final opcao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (bottomContext) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Adicionar serviço',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.list_alt_outlined),
                ),
                title: const Text('Selecionar do catálogo'),
                subtitle: Text(
                  'Aplica automaticamente ${_nomePerfilPreco(_perfilPreco)}.',
                ),
                onTap: () => Navigator.pop(bottomContext, 'catalogo'),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.edit_outlined)),
                title: const Text('Digitar serviço manualmente'),
                subtitle: const Text('Nome e valor ficam totalmente livres.'),
                onTap: () => Navigator.pop(bottomContext, 'manual'),
              ),
            ],
          ),
        );
      },
    );

    if (opcao == 'catalogo') {
      await _adicionarServicoDoCatalogo();
      return;
    }

    if (opcao == 'manual') {
      await _abrirFormularioItem();
    }
  }

  Future<void> _atualizarFidelidadeCliente({
    bool aplicarAutomatico = false,
  }) async {
    final clienteId = _clienteId;

    if (clienteId == null) {
      if (mounted) {
        setState(() {
          _beneficioFidelidade = null;
          _descontoFidelidadeSugerido = 0;
        });
      }
      return;
    }

    try {
      final beneficio = await _fidelidadeRepository.avaliarCliente(
        clienteId,
        dataReferencia: _dataEmissao,
      );

      if (!mounted) return;

      setState(() {
        _beneficioFidelidade = beneficio;
      });

      // Ao trocar/corrigir o cliente, um benefício aplicado anteriormente
      // não pode permanecer ligado ao cliente anterior.
      if (!aplicarAutomatico && _origemDesconto.startsWith('fidelidade')) {
        _definirDesconto(0, origem: 'nenhum');
      }

      await _atualizarSugestaoFidelidade(aplicarAutomatico: aplicarAutomatico);
    } catch (_) {
      if (mounted) {
        setState(() {
          _beneficioFidelidade = null;
          _descontoFidelidadeSugerido = 0;
        });
      }
    }
  }

  double _calcularDescontoFidelidadeSeguro() {
    if (!_fidelidadeConfig.ativa) {
      return 0;
    }

    if (_perfilEhParceiro && !_fidelidadeConfig.permitirParceiro) {
      return 0;
    }

    final beneficio = _beneficioFidelidade;

    if (beneficio == null || !beneficio.elegivel) {
      return 0;
    }

    final subtotalGeral = _subtotal;
    var subtotalElegivel = 0.0;
    double? limiteGlobalSeguro;

    if (subtotalGeral <= 0) {
      return 0;
    }

    for (var indice = 0; indice < _itens.length; indice++) {
      if (indice >= _servicoCatalogoIds.length) {
        continue;
      }

      final servicoId = _servicoCatalogoIds[indice];
      final precificacao = servicoId == null
          ? null
          : _precificacaoPorId[servicoId];

      if (precificacao == null) {
        continue;
      }

      final item = _itens[indice];
      final subtotalItem = item.subtotal;

      if (subtotalItem <= 0) {
        continue;
      }

      subtotalElegivel += subtotalItem;

      final folgaUnitaria = item.valorUnitario - precificacao.precoMinimoSeguro;
      final folgaItem = folgaUnitaria > 0
          ? folgaUnitaria * item.quantidade
          : 0.0;

      // O desconto do orçamento é global e, nos relatórios, é rateado
      // proporcionalmente entre os itens. Portanto, somar as folgas não é
      // suficiente: cada serviço individual precisa continuar acima do seu
      // mínimo depois do rateio. Este é o maior desconto global que este
      // item suporta sem cruzar seu preço mínimo seguro.
      final limiteDoItem = folgaItem <= 0
          ? 0.0
          : folgaItem * subtotalGeral / subtotalItem;

      limiteGlobalSeguro = limiteGlobalSeguro == null
          ? limiteDoItem
          : (limiteDoItem < limiteGlobalSeguro
                ? limiteDoItem
                : limiteGlobalSeguro);
    }

    if (subtotalElegivel <= 0 ||
        limiteGlobalSeguro == null ||
        limiteGlobalSeguro <= 0) {
      return 0;
    }

    final desejado = subtotalElegivel * beneficio.percentual / 100;

    return desejado.clamp(0, limiteGlobalSeguro).toDouble();
  }

  Future<void> _atualizarSugestaoFidelidade({
    bool aplicarAutomatico = false,
  }) async {
    final sugerido = _calcularDescontoFidelidadeSeguro();

    if (!mounted) return;

    setState(() {
      _descontoFidelidadeSugerido = sugerido;
    });

    if (!aplicarAutomatico || !_fidelidadeConfig.automatica || sugerido <= 0) {
      return;
    }

    final descontoManualAtivo =
        _desconto > 0 && !_origemDesconto.startsWith('fidelidade');

    if (descontoManualAtivo) {
      return;
    }

    _definirDesconto(
      sugerido,
      origem: 'fidelidade_automatica',
      percentual: _beneficioFidelidade?.percentual ?? 0,
    );
  }

  void _definirDesconto(
    double valor, {
    required String origem,
    double percentual = 0,
  }) {
    _alterandoDescontoInternamente = true;
    _descontoController.text = _formatarNumeroCampo(valor);
    _alterandoDescontoInternamente = false;

    if (mounted) {
      setState(() {
        _origemDesconto = valor <= 0 ? 'nenhum' : origem;
        _percentualFidelidadeAplicado = valor <= 0 ? 0 : percentual;
      });
    }
  }

  void _descontoAlteradoManualmente() {
    if (_alterandoDescontoInternamente) {
      return;
    }

    setState(() {
      _origemDesconto = _desconto <= 0 ? 'nenhum' : 'manual';
      _percentualFidelidadeAplicado = 0;
    });
  }

  Future<void> _aplicarFidelidadeSugerida() async {
    final sugerido = _descontoFidelidadeSugerido;
    final beneficio = _beneficioFidelidade;

    if (sugerido <= 0 || beneficio == null || !beneficio.elegivel) {
      return;
    }

    if (_desconto > 0 && !_origemDesconto.startsWith('fidelidade') && mounted) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Substituir desconto atual?'),
            content: Text(
              'O orçamento já possui desconto manual de '
              '${_formatoMoeda.format(_desconto)}.\n\n'
              'Aplicar a fidelidade substituirá esse desconto por '
              '${_formatoMoeda.format(sugerido)}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Manter manual'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Aplicar fidelidade'),
              ),
            ],
          );
        },
      );

      if (confirmar != true || !mounted) {
        return;
      }
    }

    _definirDesconto(
      sugerido,
      origem: 'fidelidade_sugerida',
      percentual: beneficio.percentual,
    );
  }

  Future<void> _editarClienteDesde() async {
    final clienteId = _clienteId;

    if (clienteId == null) {
      return;
    }

    DateTime? atual = _beneficioFidelidade?.clienteDesde;

    try {
      atual ??= await _fidelidadeRepository.buscarClienteDesde(clienteId);
    } catch (_) {}

    if (!mounted) return;

    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      helpText: 'Cliente desde',
    );

    if (escolhida == null) {
      return;
    }

    try {
      await _fidelidadeRepository.salvarClienteDesde(clienteId, escolhida);

      await _atualizarFidelidadeCliente(
        aplicarAutomatico: _fidelidadeConfig.automatica,
      );

      if (mounted) {
        _mostrarMensagem(
          'Data "Cliente desde" atualizada para '
          '${_formatoData.format(escolhida)}.',
        );
      }
    } catch (erro) {
      if (mounted) {
        _mostrarMensagem('$erro', erro: true);
      }
    }
  }

  String _origemDescontoTexto() {
    switch (_origemDesconto) {
      case 'fidelidade_sugerida':
        return 'Fidelidade aplicada após sugestão';
      case 'fidelidade_automatica':
        return 'Fidelidade automática';
      case 'nenhum':
        return 'Sem desconto';
      case 'manual':
      default:
        return 'Desconto manual';
    }
  }

  Future<void> _selecionarData({required bool validade}) async {
    final dataAtual = validade ? _validade : _dataEmissao;

    final dataEscolhida = await showDatePicker(
      context: context,
      initialDate: dataAtual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (dataEscolhida == null || !mounted) {
      return;
    }

    setState(() {
      if (validade) {
        _validade = dataEscolhida;
      } else {
        _dataEmissao = dataEscolhida;
      }
    });

    if (!validade) {
      await _atualizarFidelidadeCliente(
        aplicarAutomatico: _fidelidadeConfig.automatica,
      );
    }
  }

  Future<void> _abrirFormularioItem({ItemOrcamento? item, int? indice}) async {
    final resultado = await showModalBottomSheet<ItemOrcamento>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return _FormularioItemOrcamento(
          item: item,
          ordem: indice ?? _itens.length,
        );
      },
    );

    if (resultado == null || !mounted) {
      return;
    }

    setState(() {
      if (indice == null) {
        _itens.add(resultado.copyWith(ordem: _itens.length));
        // Serviço digitado manualmente fica fora dos recálculos automáticos.
        _servicoCatalogoIds.add(null);
      } else {
        _itens[indice] = resultado.copyWith(ordem: indice);

        final idAtual = indice < _servicoCatalogoIds.length
            ? _servicoCatalogoIds[indice]
            : null;
        final catalogo = _catalogoPorId(idAtual);

        if (catalogo != null &&
            catalogo.nome.trim().toLowerCase() !=
                resultado.servico.trim().toLowerCase()) {
          _servicoCatalogoIds[indice] = null;
        }
      }
    });

    await _atualizarSugestaoFidelidade(
      aplicarAutomatico: _fidelidadeConfig.automatica,
    );
  }

  Future<void> _removerItem(int indice) async {
    final item = _itens[indice];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover serviço'),
          content: Text(
            'Deseja remover "${item.servico}" '
            'deste orçamento?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _itens.removeAt(indice);

      if (indice < _servicoCatalogoIds.length) {
        _servicoCatalogoIds.removeAt(indice);
      }

      _itens = List<ItemOrcamento>.generate(_itens.length, (index) {
        return _itens[index].copyWith(ordem: index);
      });
    });

    await _atualizarSugestaoFidelidade(
      aplicarAutomatico: _fidelidadeConfig.automatica,
    );
  }

  Future<void> _salvar() async {
    if (_salvando) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_clienteId == null) {
      _mostrarMensagem('Selecione um cliente.', erro: true);

      return;
    }

    if (_itens.isEmpty) {
      _mostrarMensagem('Adicione pelo menos um serviço.', erro: true);

      return;
    }

    if (_validade.isBefore(_dataEmissao)) {
      _mostrarMensagem(
        'A validade não pode ser anterior à emissão.',
        erro: true,
      );

      return;
    }

    if (_desconto < 0) {
      _mostrarMensagem('O desconto não pode ser negativo.', erro: true);

      return;
    }

    if (_desconto > _subtotal) {
      _mostrarMensagem(
        'O desconto não pode ser maior que o subtotal.',
        erro: true,
      );

      return;
    }

    if (_origemDesconto.startsWith('fidelidade') &&
        _desconto > _descontoFidelidadeSugerido + 0.01) {
      _mostrarMensagem(
        'O desconto de fidelidade ultrapassou o limite seguro atual. '
        'Reaplique o benefício antes de salvar.',
        erro: true,
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final primeiroItem = _itens.first;

      final orcamento = Orcamento(
        id: widget.orcamento?.id,
        clienteId: _clienteId!,
        veiculoId: _veiculoId,
        servico: primeiroItem.servico,
        descricao: primeiroItem.descricao,
        valor: _total,
        dataEmissao: _dataEmissao.toIso8601String(),
        validade: _validade.toIso8601String(),
        status: _status,
        observacoes: _observacoesController.text.trim(),
        desconto: _desconto,
        itens: List<ItemOrcamento>.generate(_itens.length, (index) {
          return _itens[index].copyWith(ordem: index);
        }),
      );

      final mapeamentoCatalogo = <int, int?>{
        for (var indice = 0; indice < _servicoCatalogoIds.length; indice++)
          if (_servicoCatalogoIds[indice] != null)
            indice: _servicoCatalogoIds[indice],
      };

      late final int orcamentoId;

      if (widget.orcamento == null) {
        orcamentoId = await _repository.inserirOrcamento(
          orcamento,
          perfilPreco: _perfilPreco,
          servicoCatalogoPorOrdem: mapeamentoCatalogo,
        );
      } else {
        orcamentoId = widget.orcamento!.id!;

        await _repository.atualizarOrcamento(
          orcamento,
          perfilPreco: _perfilPreco,
          servicoCatalogoPorOrdem: mapeamentoCatalogo,
        );
      }

      try {
        final double percentualSnapshot =
            _origemDesconto.startsWith('fidelidade')
            ? _percentualFidelidadeAplicado
            : (_subtotal > 0 ? (_desconto / _subtotal) * 100 : 0.0);

        await _fidelidadeRepository.registrarDescontoDocumento(
          DescontoDocumentoSnapshot(
            documentoTipo: 'ORCAMENTO',
            documentoId: orcamentoId,
            origem: _desconto <= 0 ? 'nenhum' : _origemDesconto,
            valorDesconto: _desconto,
            percentual: percentualSnapshot,
            valorSugerido: _descontoFidelidadeSugerido,
            clienteDesde: _beneficioFidelidade?.clienteDesde,
            faixaMeses: _beneficioFidelidade?.faixaMeses,
            perfilPreco: _perfilPreco,
          ),
        );
      } catch (_) {
        // Snapshot gerencial não bloqueia o salvamento comercial do orçamento.
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem(
        'Não foi possível salvar o orçamento: $erro',
        erro: true,
      );
    }
  }

  String _formatarTempoCliente(int meses) {
    final anos = meses ~/ 12;
    final resto = meses % 12;

    if (anos <= 0) {
      return '$meses ${meses == 1 ? 'mês' : 'meses'}';
    }

    if (resto == 0) {
      return '$anos ${anos == 1 ? 'ano' : 'anos'}';
    }

    return '$anos ${anos == 1 ? 'ano' : 'anos'} e '
        '$resto ${resto == 1 ? 'mês' : 'meses'}';
  }

  Widget _construirPerfilPreco() {
    final config = _precificacao?.config;

    String margem(double valor) {
      return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
    }

    return _Secao(
      titulo: 'Perfil de preço',
      icone: Icons.sell_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_perfilPreco),
            initialValue: _perfilPreco,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Tipo de preço',
              prefixIcon: Icon(Icons.price_change_outlined),
            ),
            items: [
              const DropdownMenuItem(
                value: 'informado',
                child: Text('Preço informado / combinado'),
              ),
              DropdownMenuItem(
                value: 'cliente',
                child: Text(
                  config == null
                      ? 'Cliente final'
                      : 'Cliente final • ${margem(config.margemCliente)}',
                ),
              ),
              DropdownMenuItem(
                value: 'parceiro_1_4',
                enabled: _precificacao != null,
                child: Text(
                  config == null
                      ? 'Parceiro • 1 a 4/mês'
                      : 'Parceiro • 1 a 4/mês • '
                            '${margem(config.margemRevenda1a4)}',
                ),
              ),
              DropdownMenuItem(
                value: 'parceiro_5_9',
                enabled: _precificacao != null,
                child: Text(
                  config == null
                      ? 'Parceiro • 5 a 9/mês'
                      : 'Parceiro • 5 a 9/mês • '
                            '${margem(config.margemRevenda5a9)}',
                ),
              ),
              DropdownMenuItem(
                value: 'parceiro_10_mais',
                enabled: _precificacao != null,
                child: Text(
                  config == null
                      ? 'Parceiro • 10+/mês'
                      : 'Parceiro • 10+/mês • '
                            '${margem(config.margemRevenda10Mais)}',
                ),
              ),
            ],
            onChanged: _salvando
                ? null
                : (valor) {
                    if (valor != null) {
                      _alterarPerfilPreco(valor);
                    }
                  },
          ),
          const SizedBox(height: 8),
          Text(
            _perfilPreco == 'informado'
                ? 'Serviços digitados ou escolhidos do catálogo usam o '
                      'valor informado. Nenhum recálculo automático é feito.'
                : 'Serviços escolhidos do catálogo usam automaticamente '
                      '${_nomePerfilPreco(_perfilPreco)}. Serviços manuais '
                      'continuam livres.',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_precificacao == null) ...[
            const SizedBox(height: 7),
            Text(
              'A Precificação não pôde ser carregada. As faixas de parceiro '
              'ficam indisponíveis e cliente final usa o preço do catálogo.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirFidelidade() {
    final config = _fidelidadeConfig;
    final beneficio = _beneficioFidelidade;
    final clienteDesde = beneficio?.clienteDesde;
    final parceiroBloqueado = _perfilEhParceiro && !config.permitirParceiro;

    String modoTexto() {
      switch (config.modo) {
        case 'sugerir':
          return 'Sugerir desconto';
        case 'automatico':
          return 'Aplicar automaticamente';
        default:
          return 'Desativado';
      }
    }

    return _Secao(
      titulo: 'Fidelidade do cliente',
      icone: Icons.loyalty_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LinhaResumoComercial(titulo: 'Funcionamento', valor: modoTexto()),
          const SizedBox(height: 8),
          if (!config.ativa)
            Text(
              'Desativada. Nenhum desconto por tempo de cliente será '
              'sugerido ou aplicado. O desconto continua manual.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else if (_clienteId == null)
            const Text('Selecione um cliente para verificar a fidelidade.')
          else ...[
            _LinhaResumoComercial(
              titulo: 'Cliente desde',
              valor: clienteDesde == null
                  ? 'Não informado'
                  : _formatoData.format(clienteDesde),
            ),
            if (beneficio != null && clienteDesde != null) ...[
              const SizedBox(height: 5),
              _LinhaResumoComercial(
                titulo: 'Tempo de relacionamento',
                valor: _formatarTempoCliente(beneficio.mesesRelacionamento),
              ),
              const SizedBox(height: 5),
              _LinhaResumoComercial(
                titulo: 'Benefício da faixa',
                valor: beneficio.percentual > 0
                    ? '${beneficio.percentual.toStringAsFixed(1).replaceAll('.', ',')}%'
                    : 'Ainda não atingiu uma faixa',
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _salvando ? null : _editarClienteDesde,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                clienteDesde == null
                    ? 'Definir "Cliente desde"'
                    : 'Corrigir "Cliente desde"',
              ),
            ),
            if (parceiroBloqueado) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Text(
                  'A fidelidade está configurada para não acumular com '
                  'preço de parceiro. Nenhum desconto adicional será aplicado.',
                ),
              ),
            ] else if (beneficio != null && beneficio.elegivel) ...[
              const SizedBox(height: 10),
              _LinhaResumoComercial(
                titulo: 'Desconto seguro calculado',
                valor: _formatoMoeda.format(_descontoFidelidadeSugerido),
                destaque: true,
              ),
              const SizedBox(height: 4),
              Text(
                _descontoFidelidadeSugerido > 0
                    ? 'O valor é limitado pela margem mínima segura de cada '
                          'serviço vinculado ao catálogo.'
                    : 'O cliente atingiu uma faixa, mas não há folga segura '
                          'nos serviços atuais para aplicar desconto.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (config.sugerir && _descontoFidelidadeSugerido > 0) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _salvando ? null : _aplicarFidelidadeSugerida,
                  icon: const Icon(Icons.redeem_outlined),
                  label: const Text('Aplicar benefício de fidelidade'),
                ),
              ],
              if (config.automatica) ...[
                const SizedBox(height: 8),
                Text(
                  _origemDesconto == 'fidelidade_automatica'
                      ? 'Benefício aplicado automaticamente.'
                      : _desconto > 0 &&
                            !_origemDesconto.startsWith('fidelidade')
                      ? 'Há um desconto manual neste orçamento; o Imperium '
                            'não o sobrescreveu automaticamente.'
                      : 'O benefício automático será aplicado quando houver '
                            'valor seguro disponível.',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ],
          ],
          const Divider(height: 22),
          _LinhaResumoComercial(
            titulo: 'Origem do desconto atual',
            valor: _origemDescontoTexto(),
          ),
        ],
      ),
    );
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.orcamento != null;

    return PopScope(
      canPop: !_salvando,
      child: Scaffold(
        appBar: AppBar(
          title: Text(editando ? 'Editar orçamento' : 'Novo orçamento'),
          actions: [
            TextButton(
              onPressed: _salvando ? null : _salvar,
              child: const Text('SALVAR'),
            ),
          ],
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _clientes.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Cadastre um cliente antes '
                    'de criar um orçamento.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Secao(
                      titulo: 'Cliente e veículo',
                      icone: Icons.person_outline,
                      child: Column(
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: _clienteId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: _clientes.map((cliente) {
                              return DropdownMenuItem<int>(
                                value: _converterInt(cliente['id']),
                                child: Text((cliente['nome'] ?? '').toString()),
                              );
                            }).toList(),
                            onChanged: _salvando
                                ? null
                                : (valor) async {
                                    if (valor == null) {
                                      return;
                                    }

                                    setState(() {
                                      _clienteId = valor;
                                    });

                                    await _carregarVeiculos(valor);
                                  },
                            validator: (valor) {
                              if (valor == null) {
                                return 'Selecione um cliente.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int?>(
                            initialValue: _veiculoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Veículo (opcional)',
                              prefixIcon: Icon(Icons.directions_car_outlined),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Sem veículo vinculado'),
                              ),
                              ..._veiculos.map((veiculo) {
                                final marca = (
                                  veiculo['marca'] ?? '',
                                ).toString();

                                final modelo = (
                                  veiculo['modelo'] ?? '',
                                ).toString();

                                final placa = (
                                  veiculo['placa'] ?? '',
                                ).toString();

                                final texto = placa.isEmpty
                                    ? '$marca $modelo'
                                    : '$marca $modelo • $placa';

                                return DropdownMenuItem<int?>(
                                  value: _converterInt(veiculo['id']),
                                  child: Text(texto.trim()),
                                );
                              }),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) {
                                    setState(() {
                                      _veiculoId = valor;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _construirPerfilPreco(),
                    const SizedBox(height: 16),
                    _construirFidelidade(),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Serviços',
                      icone: Icons.design_services_outlined,
                      acao: TextButton.icon(
                        onPressed: _salvando ? null : _abrirAdicionarServico,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar'),
                      ),
                      child: _itens.isEmpty
                          ? _EstadoSemItens(aoAdicionar: _abrirAdicionarServico)
                          : Column(
                              children: List.generate(_itens.length, (indice) {
                                final item = _itens[indice];

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: indice == _itens.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: _CardItemOrcamento(
                                    item: item,
                                    formatoMoeda: _formatoMoeda,
                                    aoEditar: () {
                                      _abrirFormularioItem(
                                        item: item,
                                        indice: indice,
                                      );
                                    },
                                    aoRemover: () {
                                      _removerItem(indice);
                                    },
                                  ),
                                );
                              }),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Valores do orçamento',
                      icone: Icons.payments_outlined,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _descontoController,
                            enabled: !_salvando,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Desconto',
                              prefixText: 'R\$ ',
                              prefixIcon: Icon(Icons.discount_outlined),
                            ),
                            onChanged: (_) {
                              _descontoAlteradoManualmente();
                            },
                            validator: (texto) {
                              final desconto = _converterValor(texto ?? '');

                              if (desconto < 0) {
                                return 'Informe um desconto válido.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          _LinhaTotal(
                            titulo: 'Subtotal',
                            valor: _formatoMoeda.format(_subtotal),
                          ),
                          const SizedBox(height: 8),
                          _LinhaTotal(
                            titulo: 'Desconto',
                            valor: _formatoMoeda.format(_desconto),
                          ),
                          const SizedBox(height: 5),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _origemDescontoTexto(),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                          _LinhaTotal(
                            titulo: 'Total',
                            valor: _formatoMoeda.format(_total),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Datas e situação',
                      icone: Icons.calendar_month_outlined,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _CampoData(
                                  titulo: 'Emissão',
                                  data: _formatoData.format(_dataEmissao),
                                  aoTocar: _salvando
                                      ? null
                                      : () {
                                          _selecionarData(validade: false);
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CampoData(
                                  titulo: 'Validade',
                                  data: _formatoData.format(_validade),
                                  aoTocar: _salvando
                                      ? null
                                      : () {
                                          _selecionarData(validade: true);
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              prefixIcon: Icon(
                                Icons.assignment_turned_in_outlined,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Pendente',
                                child: Text('Pendente'),
                              ),
                              DropdownMenuItem(
                                value: 'Aprovado',
                                child: Text('Aprovado'),
                              ),
                              DropdownMenuItem(
                                value: 'Recusado',
                                child: Text('Recusado'),
                              ),
                            ],
                            onChanged: _salvando
                                ? null
                                : (valor) {
                                    if (valor == null) {
                                      return;
                                    }

                                    setState(() {
                                      _status = valor;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Secao(
                      titulo: 'Observações',
                      icone: Icons.notes_outlined,
                      child: TextFormField(
                        controller: _observacoesController,
                        enabled: !_salvando,
                        minLines: 3,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Observações gerais',
                          hintText:
                              'Condições, prazo, garantia ou outras informações',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _salvando
                            ? 'Salvando...'
                            : editando
                            ? 'Salvar alterações'
                            : 'Criar orçamento',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

class _FormularioItemOrcamento extends StatefulWidget {
  const _FormularioItemOrcamento({required this.ordem, this.item});

  final ItemOrcamento? item;
  final int ordem;

  @override
  State<_FormularioItemOrcamento> createState() =>
      _FormularioItemOrcamentoState();
}

class _FormularioItemOrcamentoState extends State<_FormularioItemOrcamento> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _servicoController;

  late final TextEditingController _descricaoController;

  late final TextEditingController _quantidadeController;

  late final TextEditingController _valorController;

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    _servicoController = TextEditingController(text: item?.servico ?? '');

    _descricaoController = TextEditingController(text: item?.descricao ?? '');

    _quantidadeController = TextEditingController(
      text: item == null ? '1' : _formatarNumero(item.quantidade),
    );

    _valorController = TextEditingController(
      text: item == null
          ? ''
          : item.valorUnitario.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _servicoController.dispose();
    _descricaoController.dispose();
    _quantidadeController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  static String _formatarNumero(double numero) {
    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    return numero
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }

  double _converterValor(String texto) {
    final textoLimpo = texto.trim();

    if (textoLimpo.isEmpty) {
      return 0;
    }

    if (textoLimpo.contains(',')) {
      return double.tryParse(
            textoLimpo.replaceAll('.', '').replaceAll(',', '.'),
          ) ??
          0;
    }

    return double.tryParse(textoLimpo) ?? 0;
  }

  double get _quantidade {
    return _converterValor(_quantidadeController.text);
  }

  double get _valorUnitario {
    return _converterValor(_valorController.text);
  }

  double get _subtotal {
    return _quantidade * _valorUnitario;
  }

  void _salvarItem() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final item = ItemOrcamento(
      id: widget.item?.id,
      orcamentoId: widget.item?.orcamentoId,
      servico: _servicoController.text.trim(),
      descricao: _descricaoController.text.trim(),
      quantidade: _quantidade,
      valorUnitario: _valorUnitario,
      ordem: widget.ordem,
    );

    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final editando = widget.item != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editando ? 'Editar serviço' : 'Adicionar serviço',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _servicoController,
                autofocus: !editando,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Serviço',
                  hintText: 'Ex.: Polimento técnico',
                  prefixIcon: Icon(Icons.design_services_outlined),
                ),
                validator: (texto) {
                  if (texto == null || texto.trim().isEmpty) {
                    return 'Informe o serviço.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descricaoController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                  hintText: 'Detalhes do serviço',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantidadeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      validator: (texto) {
                        final quantidade = _converterValor(texto ?? '');

                        if (quantidade <= 0) {
                          return 'Valor inválido.';
                        }

                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _valorController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Valor unitário',
                        prefixText: 'R\$ ',
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      validator: (texto) {
                        final valor = _converterValor(texto ?? '');

                        if (valor <= 0) {
                          return 'Valor inválido.';
                        }

                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subtotal do serviço',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(_subtotal),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _salvarItem,
                icon: const Icon(Icons.check),
                label: Text(editando ? 'Salvar serviço' : 'Adicionar serviço'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaResumoComercial extends StatelessWidget {
  const _LinhaResumoComercial({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(titulo)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.icone,
    required this.child,
    this.acao,
  });

  final String titulo;
  final IconData icone;
  final Widget child;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icone, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?acao,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _EstadoSemItens extends StatelessWidget {
  const _EstadoSemItens({required this.aoAdicionar});

  final VoidCallback aoAdicionar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          const Icon(Icons.playlist_add_outlined, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Nenhum serviço adicionado',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Adicione os serviços que farão parte deste orçamento.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: aoAdicionar,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar serviço'),
          ),
        ],
      ),
    );
  }
}

class _CardItemOrcamento extends StatelessWidget {
  const _CardItemOrcamento({
    required this.item,
    required this.formatoMoeda,
    required this.aoEditar,
    required this.aoRemover,
  });

  final ItemOrcamento item;
  final NumberFormat formatoMoeda;
  final VoidCallback aoEditar;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.servico,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (opcao) {
                  if (opcao == 'editar') {
                    aoEditar();
                  } else if (opcao == 'remover') {
                    aoRemover();
                  }
                },
                itemBuilder: (context) {
                  return const [
                    PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remover',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Remover'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          if (item.descricao.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.descricao),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _InfoItem(
                titulo: 'Quantidade',
                valor: _formatarQuantidade(item.quantidade),
              ),
              _InfoItem(
                titulo: 'Valor unitário',
                valor: formatoMoeda.format(item.valorUnitario),
              ),
              _InfoItem(
                titulo: 'Subtotal',
                valor: formatoMoeda.format(item.subtotal),
                destaque: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatarQuantidade(double quantidade) {
    if (quantidade == quantidade.roundToDouble()) {
      return quantidade.toInt().toString();
    }

    return quantidade
        .toStringAsFixed(2)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r',$'), '');
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaTotal extends StatelessWidget {
  const _LinhaTotal({
    required this.titulo,
    required this.valor,
    this.destaque = false,
  });

  final String titulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final estilo = destaque
        ? Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;

    return Row(
      children: [
        Expanded(child: Text(titulo, style: estilo)),
        Text(valor, style: estilo),
      ],
    );
  }
}

class _CampoData extends StatelessWidget {
  const _CampoData({
    required this.titulo,
    required this.data,
    required this.aoTocar,
  });

  final String titulo;
  final String data;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: titulo,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(data),
      ),
    );
  }
}
