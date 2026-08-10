import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/agendamento.dart';
import '../models/cliente.dart';
import '../models/ordem_servico.dart';
import '../models/ordem_servico_item.dart';
import '../models/item_estoque.dart';
import '../models/veiculo.dart';
import '../models/servico_catalogo.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/orcamento_repository.dart';
import '../repositories/ordem_servico_repository.dart';
import '../repositories/estoque_repository.dart';
import '../database/app_database.dart';
import '../repositories/veiculo_repository.dart';
import '../repositories/servico_repository.dart';
import '../repositories/precificacao_repository.dart';
import '../repositories/fidelidade_repository.dart';

class NovaOrdemServicoPage extends StatefulWidget {
  const NovaOrdemServicoPage({super.key, this.orcamentoId, this.agendamento});

  final int? orcamentoId;
  final Agendamento? agendamento;

  @override
  State<NovaOrdemServicoPage> createState() => _NovaOrdemServicoPageState();
}

class _NovaOrdemServicoPageState extends State<NovaOrdemServicoPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final ClienteRepository _clienteRepository = ClienteRepository();

  final VeiculoRepository _veiculoRepository = VeiculoRepository();

  final OrdemServicoRepository _ordemRepository = OrdemServicoRepository();

  final OrcamentoRepository _orcamentoRepository = OrcamentoRepository();

  final EstoqueRepository _estoqueRepository = EstoqueRepository();

  final ServicoRepository _servicoRepository = ServicoRepository();

  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();
  final FidelidadeRepository _fidelidadeRepository = FidelidadeRepository();

  final TextEditingController _numeroController = TextEditingController();

  final TextEditingController _responsavelController = TextEditingController();

  final TextEditingController _descontoController = TextEditingController(
    text: '0,00',
  );

  final TextEditingController _observacoesController = TextEditingController();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  List<Cliente> _clientes = [];
  List<Veiculo> _veiculos = [];
  final List<_ServicoFormulario> _servicos = [];
  List<ItemEstoque> _itensEstoque = [];
  List<ServicoCatalogo> _catalogoServicos = [];
  final List<_ProdutoOsFormulario> _produtos = [];
  PrecificacaoPainel? _precificacao;
  Map<int, PrecificacaoServico> _precificacaoPorId = const {};
  String _perfilPreco = 'cliente';
  DescontoDocumentoSnapshot? _snapshotDescontoOrcamento;
  double _descontoImportadoOrcamento = 0;
  FidelidadeConfig _fidelidadeConfig = const FidelidadeConfig();
  FidelidadeBeneficio? _beneficioFidelidade;
  String _origemDesconto = 'nenhum';
  double _descontoFidelidadeSugerido = 0;
  double _percentualFidelidadeAplicado = 0;
  bool _alterandoDescontoInternamente = false;

  Cliente? _clienteSelecionado;
  Veiculo? _veiculoSelecionado;

  bool _carregando = true;
  bool _carregandoVeiculos = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();

    _adicionarServico();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _responsavelController.dispose();
    _descontoController.dispose();
    _observacoesController.dispose();

    for (final servico in _servicos) {
      servico.dispose();
    }

    for (final produto in _produtos) {
      produto.dispose();
    }

    super.dispose();
  }

  Future<void> _carregarDadosIniciais() async {
    try {
      final resultados = await Future.wait([
        _clienteRepository.listarClientes(),
        _ordemRepository.gerarProximoNumero(),
        _estoqueRepository.listarItens(),
        _servicoRepository.listarServicos(somenteAtivos: true),
      ]);

      final clientes = resultados[0] as List<Cliente>;
      final numero = resultados[1] as String;
      final itensEstoque = resultados[2] as List<ItemEstoque>;
      final catalogoServicos = resultados[3] as List<ServicoCatalogo>;

      PrecificacaoPainel? precificacao;
      try {
        precificacao = await _precificacaoRepository.carregar();
      } catch (_) {
        // A criação da OS continua funcionando com o preço padrão do catálogo
        // caso a análise de precificação não esteja disponível.
      }

      FidelidadeConfig fidelidadeConfig;
      try {
        fidelidadeConfig = await _fidelidadeRepository.carregarConfig();
      } catch (_) {
        fidelidadeConfig = const FidelidadeConfig();
      }

      Map<String, dynamic>? orcamento;
      DescontoDocumentoSnapshot? snapshotDescontoOrcamento;
      List<Veiculo> veiculos = [];

      if (widget.agendamento != null) {
        veiculos = await _veiculoRepository.listarVeiculosDoCliente(
          widget.agendamento!.clienteId,
        );
      }

      if (widget.orcamentoId != null) {
        orcamento = await _orcamentoRepository.buscarOrcamentoComDetalhes(
          widget.orcamentoId!,
        );

        if (orcamento == null) {
          throw Exception('Orçamento não encontrado.');
        }

        try {
          snapshotDescontoOrcamento =
              await _fidelidadeRepository.buscarDescontoDocumento(
            documentoTipo: 'ORCAMENTO',
            documentoId: widget.orcamentoId!,
          );
        } catch (_) {
          snapshotDescontoOrcamento = null;
        }

        final clienteId = _converterInt(orcamento['cliente_id']);

        if (clienteId != null) {
          veiculos = await _veiculoRepository.listarVeiculosDoCliente(
            clienteId,
          );
        }
      }

      if (!mounted) {
        return;
      }

      Cliente? clienteSelecionado;
      Veiculo? veiculoSelecionado;

      final agendamento = widget.agendamento;

      if (agendamento != null) {
        for (final cliente in clientes) {
          if (cliente.id == agendamento.clienteId) {
            clienteSelecionado = cliente;
            break;
          }
        }

        for (final veiculo in veiculos) {
          if (veiculo.id == agendamento.veiculoId) {
            veiculoSelecionado = veiculo;
            break;
          }
        }

        for (final servico in _servicos) {
          servico.dispose();
        }

        _servicos
          ..clear()
          ..add(
            _ServicoFormulario(
              aoAlterar: _atualizarTela,
              nome: agendamento.servico,
              quantidade: '1',
              valor: _formatarNumeroCampo(agendamento.valor),
            ),
          );

        _observacoesController.text = agendamento.observacoes;
      }

      if (orcamento != null) {
        final clienteId = _converterInt(orcamento['cliente_id']);

        final veiculoId = _converterInt(orcamento['veiculo_id']);

        for (final cliente in clientes) {
          if (cliente.id == clienteId) {
            clienteSelecionado = cliente;
            break;
          }
        }

        for (final veiculo in veiculos) {
          if (veiculo.id == veiculoId) {
            veiculoSelecionado = veiculo;
            break;
          }
        }

        for (final servico in _servicos) {
          servico.dispose();
        }

        _servicos.clear();

        final itens = orcamento['itens'];

        if (itens is List) {
          for (final item in itens) {
            if (item is! Map) {
              continue;
            }

            final mapa = Map<String, dynamic>.from(item);

            _servicos.add(
              _ServicoFormulario(
                aoAlterar: _atualizarTela,
                nome: (mapa['servico'] ?? '').toString(),
                descricao: (mapa['descricao'] ?? '').toString(),
                quantidade: _formatarNumeroCampo(
                  _converterNumero(mapa['quantidade'], padrao: 1),
                ),
                valor: _formatarNumeroCampo(
                  _converterNumero(mapa['valor_unitario']),
                ),
              ),
            );
          }
        }

        if (_servicos.isEmpty) {
          _servicos.add(_ServicoFormulario(aoAlterar: _atualizarTela));
        }

        final descontoImportado = _converterNumero(orcamento['desconto']);

        _descontoController.text = _formatarNumeroCampo(
          descontoImportado,
        );
        _descontoImportadoOrcamento = descontoImportado;

        _observacoesController.text = (orcamento['observacoes'] ?? '')
            .toString();
      }

      _vincularServicosAoCatalogo(catalogoServicos);

      final mapaPrecificacao = <int, PrecificacaoServico>{};
      if (precificacao != null) {
        for (final servico in precificacao.servicos) {
          mapaPrecificacao[servico.id] = servico;
        }
      }

      FidelidadeBeneficio? beneficioFidelidade;

      if (clienteSelecionado?.id != null) {
        try {
          beneficioFidelidade =
              await _fidelidadeRepository.avaliarCliente(
            clienteSelecionado!.id!,
          );
        } catch (_) {
          beneficioFidelidade = null;
        }
      }

      var perfilInicial = 'cliente';

      if (widget.agendamento != null) {
        perfilInicial = 'informado';
      }

      if (orcamento != null) {
        final perfilOrcamento =
            (orcamento['perfil_preco'] ?? 'informado').toString().trim();

        const perfisValidos = <String>{
          'informado',
          'cliente',
          'parceiro_1_4',
          'parceiro_5_9',
          'parceiro_10_mais',
        };

        perfilInicial = perfisValidos.contains(perfilOrcamento)
            ? perfilOrcamento
            : 'informado';
      }

      setState(() {
        _clientes = clientes;
        _veiculos = veiculos;
        _clienteSelecionado = clienteSelecionado;
        _veiculoSelecionado = veiculoSelecionado;
        _numeroController.text = numero;
        _itensEstoque = itensEstoque;
        _catalogoServicos = catalogoServicos;
        _precificacao = precificacao;
        _precificacaoPorId = mapaPrecificacao;
        _perfilPreco = perfilInicial;
        _snapshotDescontoOrcamento = snapshotDescontoOrcamento;
        _fidelidadeConfig = fidelidadeConfig;
        _beneficioFidelidade = beneficioFidelidade;
        _origemDesconto = snapshotDescontoOrcamento?.origem ??
            (_desconto > 0 ? 'manual' : 'nenhum');
        _percentualFidelidadeAplicado =
            snapshotDescontoOrcamento?.percentual ?? 0;
        _carregando = false;
      });

      _recalcularSugestaoFidelidadeOs(
        aplicarAutomatico: false,
        reaplicarExistente: false,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar os dados.\n$erro',
        erro: true,
      );
    }
  }

  int? _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  double _converterNumero(dynamic valor, {double padrao = 0}) {
    if (valor is num) {
      return valor.toDouble();
    }

    final convertido = double.tryParse(
      (valor ?? '').toString().replaceAll(',', '.'),
    );

    return convertido ?? padrao;
  }

  String _formatarNumeroCampo(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  void _vincularServicosAoCatalogo(List<ServicoCatalogo> catalogo) {
    for (final formulario in _servicos) {
      if (formulario.servicoCatalogoId != null) {
        continue;
      }

      final nome = formulario.nomeController.text.trim().toLowerCase();
      if (nome.isEmpty) {
        continue;
      }

      final candidatos = catalogo.where(
        (item) => item.nome.trim().toLowerCase() == nome,
      );

      if (candidatos.length == 1) {
        formulario.servicoCatalogoId = candidatos.first.id;
      }
    }
  }

  PrecificacaoServico? _precificacaoDoCatalogo(ServicoCatalogo servico) {
    final id = servico.id;
    if (id == null) {
      return null;
    }
    return _precificacaoPorId[id];
  }

  double _precoDoPerfil(ServicoCatalogo servico) {
    final precificacao = _precificacaoDoCatalogo(servico);

    if (_perfilPreco == 'informado') {
      return servico.precoPadrao;
    }

    if (_perfilPreco == 'cliente') {
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

    switch (_perfilPreco) {
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

  String _descricaoPerfilPreco(String perfil) {
    switch (perfil) {
      case 'cliente':
        return 'Usa a sugestão de cliente final da Precificação.';
      case 'parceiro_1_4':
        return 'Usa a faixa de parceiro de 1 a 4 serviços por mês.';
      case 'parceiro_5_9':
        return 'Usa a faixa de parceiro de 5 a 9 serviços por mês.';
      case 'parceiro_10_mais':
        return 'Usa a faixa de parceiro de 10 ou mais serviços por mês.';
      case 'informado':
      default:
        return 'Mantém os valores já informados ou combinados.';
    }
  }

  bool get _perfilEhParceiro => _perfilPreco.startsWith('parceiro_');

  Future<void> _alterarPerfilPreco(String novoPerfil) async {
    if (novoPerfil == _perfilPreco) {
      return;
    }

    final temServicosCatalogo = _servicos.any(
      (item) => item.servicoCatalogoId != null,
    );

    if (temServicosCatalogo && novoPerfil != 'informado') {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Aplicar perfil de preço?'),
            content: Text(
              'Os valores dos serviços selecionados do catálogo serão '
              'recalculados para:\n\n'
              '${_nomePerfilPreco(novoPerfil)}\n\n'
              'Serviços digitados manualmente não serão alterados. '
              'Depois você ainda poderá ajustar qualquer valor manualmente.',
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
      _aplicarPerfilAosServicos();
    }

    _recalcularSugestaoFidelidadeOs(
      aplicarAutomatico: _fidelidadeConfig.automatica,
      reaplicarExistente: true,
    );
  }

  void _aplicarPerfilAosServicos() {
    var atualizados = 0;
    var naoElegiveisParceiro = 0;

    for (final formulario in _servicos) {
      final servicoId = formulario.servicoCatalogoId;
      if (servicoId == null) {
        continue;
      }

      ServicoCatalogo? catalogo;
      for (final item in _catalogoServicos) {
        if (item.id == servicoId) {
          catalogo = item;
          break;
        }
      }

      if (catalogo == null) {
        continue;
      }

      final precificacao = _precificacaoDoCatalogo(catalogo);
      if (_perfilEhParceiro &&
          (precificacao == null || !precificacao.aceitaRevenda)) {
        naoElegiveisParceiro++;
      }

      formulario.valorController.text = _formatarNumeroCampo(
        _precoDoPerfil(catalogo),
      );
      atualizados++;
    }

    if (mounted) {
      setState(() {});
    }

    if (atualizados > 0) {
      final complemento = naoElegiveisParceiro > 0
          ? ' $naoElegiveisParceiro serviço'
                '${naoElegiveisParceiro == 1 ? '' : 's'} não '
                '${naoElegiveisParceiro == 1 ? 'está habilitado' : 'estão habilitados'} '
                'para revenda; nesses casos foi mantido o preço de '
                'cliente final.'
          : '';

      _mostrarMensagem(
        'Perfil ${_nomePerfilPreco(_perfilPreco)} aplicado.$complemento',
      );
    }
  }

  double _calcularDescontoFidelidadeSeguroOs() {
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

    for (final formulario in _servicos) {
      final servicoId = formulario.servicoCatalogoId;
      final precificacao =
          servicoId == null ? null : _precificacaoPorId[servicoId];

      if (precificacao == null) {
        continue;
      }

      final quantidade = _converterValor(
        formulario.quantidadeController.text,
      );
      final valorUnitario = _converterValor(
        formulario.valorController.text,
      );

      if (quantidade <= 0 || valorUnitario <= 0) {
        continue;
      }

      final subtotalItem = quantidade * valorUnitario;
      subtotalElegivel += subtotalItem;

      final folgaUnitaria =
          valorUnitario - precificacao.precoMinimoSeguro;
      final folgaItem = folgaUnitaria > 0
          ? folgaUnitaria * quantidade
          : 0.0;

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

  void _recalcularSugestaoFidelidadeOs({
    bool aplicarAutomatico = false,
    bool reaplicarExistente = false,
  }) {
    final sugerido = _calcularDescontoFidelidadeSeguroOs();

    if (!mounted) {
      return;
    }

    setState(() {
      _descontoFidelidadeSugerido = sugerido;
    });

    final fidelidadeJaAplicada =
        _origemDesconto.startsWith('fidelidade');

    if (reaplicarExistente && fidelidadeJaAplicada) {
      _definirDescontoOs(
        sugerido,
        origem: _origemDesconto,
        percentual: _beneficioFidelidade?.percentual ?? 0,
      );
      return;
    }

    if (!aplicarAutomatico ||
        !_fidelidadeConfig.automatica ||
        sugerido <= 0) {
      return;
    }

    final descontoManualAtivo =
        _desconto > 0 && !fidelidadeJaAplicada;

    if (descontoManualAtivo) {
      return;
    }

    _definirDescontoOs(
      sugerido,
      origem: 'fidelidade_automatica',
      percentual: _beneficioFidelidade?.percentual ?? 0,
    );
  }

  Future<void> _atualizarFidelidadeClienteOs({
    bool aplicarAutomatico = false,
  }) async {
    final clienteId = _clienteSelecionado?.id;

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
      );

      if (!mounted) {
        return;
      }

      final tinhaFidelidade =
          _origemDesconto.startsWith('fidelidade');

      setState(() {
        _beneficioFidelidade = beneficio;
      });

      if (tinhaFidelidade && !aplicarAutomatico) {
        _definirDescontoOs(0, origem: 'nenhum');
      }

      _recalcularSugestaoFidelidadeOs(
        aplicarAutomatico: aplicarAutomatico,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _beneficioFidelidade = null;
          _descontoFidelidadeSugerido = 0;
        });
      }
    }
  }

  void _definirDescontoOs(
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
        _percentualFidelidadeAplicado =
            valor <= 0 ? 0 : percentual;
      });
    }
  }

  void _descontoAlteradoManualOs() {
    if (_alterandoDescontoInternamente) {
      return;
    }

    setState(() {
      _origemDesconto = _desconto <= 0 ? 'nenhum' : 'manual';
      _percentualFidelidadeAplicado = 0;
    });
  }

  Future<void> _aplicarFidelidadeSugeridaOs() async {
    final sugerido = _descontoFidelidadeSugerido;
    final beneficio = _beneficioFidelidade;

    if (sugerido <= 0 || beneficio == null || !beneficio.elegivel) {
      return;
    }

    if (_desconto > 0 &&
        !_origemDesconto.startsWith('fidelidade')) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Substituir desconto atual?'),
            content: Text(
              'A OS já possui desconto manual de '
              '${_moeda.format(_desconto)}.\n\n'
              'Aplicar fidelidade substituirá por '
              '${_moeda.format(sugerido)}.',
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

    _definirDescontoOs(
      sugerido,
      origem: 'fidelidade_sugerida',
      percentual: beneficio.percentual,
    );
  }

  Future<void> _editarClienteDesdeOs() async {
    final clienteId = _clienteSelecionado?.id;

    if (clienteId == null) {
      return;
    }

    DateTime? atual = _beneficioFidelidade?.clienteDesde;

    try {
      atual ??= await _fidelidadeRepository.buscarClienteDesde(clienteId);
    } catch (_) {}

    if (!mounted) {
      return;
    }

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
      await _fidelidadeRepository.salvarClienteDesde(
        clienteId,
        escolhida,
      );

      await _atualizarFidelidadeClienteOs(
        aplicarAutomatico: _fidelidadeConfig.automatica,
      );

      if (mounted) {
        _mostrarMensagem(
          'Data "Cliente desde" atualizada.',
        );
      }
    } catch (erro) {
      if (mounted) {
        _mostrarMensagem('$erro', erro: true);
      }
    }
  }

  String _origemDescontoTextoOs() {
    switch (_origemDesconto) {
      case 'fidelidade_sugerida':
        return 'Fidelidade aplicada após sugestão';
      case 'fidelidade_automatica':
        return 'Fidelidade automática';
      case 'manual':
        return 'Desconto manual';
      case 'nenhum':
      default:
        return 'Sem desconto';
    }
  }

  String _tempoRelacionamentoOs(int meses) {
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

  Future<void> _selecionarCliente(Cliente? cliente) async {
    setState(() {
      _clienteSelecionado = cliente;
      _veiculoSelecionado = null;
      _veiculos = [];
    });

    final clienteId = cliente?.id;

    if (clienteId == null) {
      setState(() {
        _beneficioFidelidade = null;
        _descontoFidelidadeSugerido = 0;
      });

      if (_origemDesconto.startsWith('fidelidade')) {
        _definirDescontoOs(0, origem: 'nenhum');
      }

      return;
    }

    setState(() {
      _carregandoVeiculos = true;
    });

    try {
      final veiculos = await _veiculoRepository.listarVeiculosDoCliente(
        clienteId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _veiculos = veiculos;
        _carregandoVeiculos = false;

        if (veiculos.length == 1) {
          _veiculoSelecionado = veiculos.first;
        }
      });

      await _atualizarFidelidadeClienteOs(
        aplicarAutomatico: _fidelidadeConfig.automatica,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoVeiculos = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar os veículos.\n$erro',
        erro: true,
      );
    }
  }

  void _adicionarServico() {
    setState(() {
      _servicos.add(_ServicoFormulario(aoAlterar: _atualizarTela));
    });
  }

  Future<void> _selecionarServicoCatalogo(int indice) async {
    if (_catalogoServicos.isEmpty) {
      _mostrarMensagem(
        'Nenhum serviço ativo foi cadastrado no catálogo.',
        erro: true,
      );
      return;
    }

    final selecionado = await showModalBottomSheet<ServicoCatalogo>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) {
        final categorias =
            _catalogoServicos
                .map((servico) => servico.categoria.trim())
                .where((categoria) => categoria.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        String? categoriaSelecionada;

        return StatefulBuilder(
          builder: (context, setStateModal) {
            final servicosFiltrados = _catalogoServicos.where((servico) {
              if (categoriaSelecionada == null ||
                  categoriaSelecionada!.isEmpty) {
                return true;
              }
              return servico.categoria.trim().toLowerCase() ==
                  categoriaSelecionada!.trim().toLowerCase();
            }).toList();

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.75,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 4, 18, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Selecionar serviço do catálogo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: DropdownButtonFormField<String?>(
                        initialValue: categoriaSelecionada,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todas as categorias'),
                          ),
                          ...categorias.map(
                            (categoria) => DropdownMenuItem<String?>(
                              value: categoria,
                              child: Text(categoria),
                            ),
                          ),
                        ],
                        onChanged: (valor) {
                          setStateModal(() {
                            categoriaSelecionada = valor;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: servicosFiltrados.length,
                        itemBuilder: (_, itemIndex) {
                          final servico = servicosFiltrados[itemIndex];

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.cleaning_services_outlined),
                            ),
                            title: Text(servico.nome),
                            subtitle: Text(
                              '${servico.categoria.isEmpty ? "Sem categoria" : servico.categoria}'
                              ' • ${_moeda.format(_precoDoPerfil(servico))}'
                              ' • ${servico.duracaoFormatada}',
                            ),
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

    if (selecionado == null || !mounted) {
      return;
    }

    final formulario = _servicos[indice];

    formulario.nomeController.text = selecionado.nome;
    formulario.descricaoController.text = selecionado.descricao;
    formulario.quantidadeController.text = '1';
    final precoAplicado = _precoDoPerfil(selecionado);
    formulario.valorController.text = _formatarNumeroCampo(precoAplicado);
    formulario.servicoCatalogoId = selecionado.id;

    final precificacaoSelecionada = _precificacaoDoCatalogo(selecionado);
    if (_perfilEhParceiro &&
        (precificacaoSelecionada == null ||
            !precificacaoSelecionada.aceitaRevenda)) {
      _mostrarMensagem(
        '${selecionado.nome} não está habilitado para revenda. '
        'Foi usado o preço de cliente final.',
      );
    }

    if (selecionado.observacoesPadrao.trim().isNotEmpty) {
      final atual = _observacoesController.text.trim();

      _observacoesController.text = atual.isEmpty
          ? selecionado.observacoesPadrao
          : '$atual\n${selecionado.observacoesPadrao}';
    }

    if (selecionado.id != null) {
      await _carregarProdutosDoServico(selecionado.id!);
    }

    if (mounted) {
      setState(() {});
      _recalcularSugestaoFidelidadeOs(
        aplicarAutomatico: _fidelidadeConfig.automatica,
        reaplicarExistente: true,
      );
    }
  }

  Future<void> _carregarProdutosDoServico(int servicoId) async {
    final produtosCatalogo = await _servicoRepository.listarProdutosDoServico(
      servicoId,
    );

    for (final produtoCatalogo in produtosCatalogo) {
      final deveAdicionar =
          produtoCatalogo.obrigatorio || produtoCatalogo.marcadoPorPadrao;

      if (!deveAdicionar) {
        continue;
      }

      ItemEstoque? item;

      for (final estoque in _itensEstoque) {
        if (estoque.id == produtoCatalogo.itemEstoqueId) {
          item = estoque;
          break;
        }
      }

      if (item == null) {
        continue;
      }

      if (produtoCatalogo.quantidadePadrao <= 0) {
        continue;
      }

      _adicionarOuSomarProdutoFormulario(
        item: item,
        quantidade: produtoCatalogo.quantidadePadrao,
        selecionado:
            produtoCatalogo.obrigatorio || produtoCatalogo.marcadoPorPadrao,
        obrigatorio: produtoCatalogo.obrigatorio,
      );
    }
  }

  void _adicionarOuSomarProdutoFormulario({
    required ItemEstoque item,
    required double quantidade,
    required bool selecionado,
    required bool obrigatorio,
  }) {
    if (quantidade <= 0) {
      return;
    }

    for (final produtoExistente in _produtos) {
      if (produtoExistente.item.id == item.id) {
        final quantidadeAtual = _converterValor(
          produtoExistente.quantidadeController.text,
        );

        final novaQuantidade = quantidadeAtual + quantidade;

        produtoExistente.quantidadeController.text = _formatarNumeroCampo(
          novaQuantidade,
        );

        if (selecionado || obrigatorio) {
          produtoExistente.selecionado = true;
        }

        if (obrigatorio) {
          produtoExistente.obrigatorio = true;
        }

        return;
      }
    }

    _produtos.add(
      _ProdutoOsFormulario(
        item: item,
        quantidade: _formatarNumeroCampo(quantidade),
        selecionado: selecionado || obrigatorio,
        obrigatorio: obrigatorio,
      ),
    );
  }

  void _removerServico(int indice) {
    if (_servicos.length == 1) {
      _mostrarMensagem(
        'A Ordem de Serviço precisa ter pelo menos um serviço.',
        erro: true,
      );

      return;
    }

    final servico = _servicos.removeAt(indice);
    servico.dispose();

    setState(() {});
    _recalcularSugestaoFidelidadeOs(
      aplicarAutomatico: _fidelidadeConfig.automatica,
      reaplicarExistente: true,
    );
  }

  void _atualizarTela() {
    if (mounted) {
      setState(() {});
      _recalcularSugestaoFidelidadeOs(
        aplicarAutomatico: _fidelidadeConfig.automatica,
        reaplicarExistente: true,
      );
    }
  }

  double _converterValor(String texto) {
    var valor = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');

    if (valor.isEmpty) {
      return 0;
    }

    if (valor.contains(',')) {
      valor = valor.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(valor) ?? 0;
  }

  double get _subtotal {
    return _servicos.fold<double>(0, (total, servico) {
      final quantidade = _converterValor(servico.quantidadeController.text);

      final valorUnitario = _converterValor(servico.valorController.text);

      return total + (quantidade * valorUnitario);
    });
  }

  double get _desconto {
    return _converterValor(_descontoController.text);
  }

  double get _totalFinal {
    final total = _subtotal - _desconto;

    if (total < 0) {
      return 0;
    }

    return total;
  }

  double get _custoProdutosSelecionados {
    return _produtos.fold<double>(0, (total, produto) {
      if (!produto.selecionado) {
        return total;
      }

      final quantidade = _converterValor(produto.quantidadeController.text);

      if (quantidade <= 0) {
        return total;
      }

      return total + (quantidade * produto.item.custoUnitarioEfetivo);
    });
  }

  double get _lucroBrutoEstimado {
    final lucro = _totalFinal - _custoProdutosSelecionados;

    if (lucro < 0) {
      return 0;
    }

    return lucro;
  }

  String _formatarDataBanco(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');

    return '$ano-$mes-$dia';
  }

  Future<void> _salvar() async {
    FocusScope.of(context).unfocus();

    if (_salvando) {
      return;
    }

    final formularioValido = _formKey.currentState?.validate() ?? false;

    if (!formularioValido) {
      return;
    }

    final cliente = _clienteSelecionado;

    if (cliente?.id == null) {
      _mostrarMensagem('Selecione um cliente.', erro: true);

      return;
    }

    final servicosValidos = _servicos.where(
      (servico) => servico.nomeController.text.trim().isNotEmpty,
    );

    if (servicosValidos.isEmpty) {
      _mostrarMensagem('Adicione pelo menos um serviço.', erro: true);

      return;
    }

    if (_desconto > _subtotal) {
      _mostrarMensagem(
        'O desconto não pode ser maior que o subtotal.',
        erro: true,
      );

      return;
    }

    for (final produto in _produtos) {
      if (!produto.selecionado) {
        continue;
      }

      final quantidade = _converterValor(produto.quantidadeController.text);

      if (quantidade <= 0) {
        _mostrarMensagem(
          'Informe uma quantidade válida para ${produto.item.nome}.',
          erro: true,
        );
        return;
      }

      if (quantidade > produto.item.quantidade) {
        _mostrarMensagem(
          'Estoque insuficiente para ${produto.item.nome}. '
          'Disponível: ${_formatarNumeroCampo(produto.item.quantidade)} '
          '${produto.item.unidade}.',
          erro: true,
        );
        return;
      }
    }

    final preservandoDescontoDoOrcamento =
        widget.orcamentoId != null &&
        (_desconto - _descontoImportadoOrcamento).abs() <= 0.01 &&
        _snapshotDescontoOrcamento != null &&
        _origemDesconto == _snapshotDescontoOrcamento!.origem;

    if (_origemDesconto.startsWith('fidelidade') &&
        !preservandoDescontoDoOrcamento &&
        _desconto > _descontoFidelidadeSugerido + 0.01) {
      _mostrarMensagem(
        'O desconto de fidelidade ultrapassou o limite seguro atual. '
        'Reaplique o benefício antes de salvar a OS.',
        erro: true,
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final ordem = OrdemServico(
        orcamentoId: widget.orcamentoId,
        agendamentoId: widget.agendamento?.id,
        clienteId: cliente!.id!,
        veiculoId: _veiculoSelecionado?.id,
        numero: _numeroController.text.trim(),
        status: 'Aberta',
        dataAbertura: _formatarDataBanco(DateTime.now()),
        funcionarioResponsavel: _responsavelController.text.trim(),
        observacoes: _observacoesController.text.trim(),
        valorTotal: _subtotal,
        desconto: _desconto,
      );

      final itens = <OrdemServicoItem>[];

      for (var indice = 0; indice < _servicos.length; indice++) {
        final servico = _servicos[indice];
        final nome = servico.nomeController.text.trim();

        if (nome.isEmpty) {
          continue;
        }

        itens.add(
          OrdemServicoItem(
            ordemServicoId: 0,
            servico: nome,
            descricao: servico.descricaoController.text.trim(),
            quantidade: _converterValor(servico.quantidadeController.text),
            valorUnitario: _converterValor(servico.valorController.text),
            ordem: indice,
          ),
        );
      }

      final ordemServicoId = await _ordemRepository.inserirOrdemServico(
        ordem,
        itens: itens,
      );

      try {
        await _precificacaoRepository.registrarPerfilDocumento(
          documentoTipo: 'OS',
          documentoId: ordemServicoId,
          perfil: _perfilPreco,
        );
      } catch (_) {
        // O perfil é metadado gerencial. Uma falha ao registrar esse snapshot
        // não deve impedir a criação da Ordem de Serviço.
      }

      try {
        final snapshotOrcamento = _snapshotDescontoOrcamento;
        final preservouDescontoOrcamento =
            widget.orcamentoId != null &&
            (_desconto - _descontoImportadoOrcamento).abs() <= 0.01;

        final origem = preservouDescontoOrcamento &&
                snapshotOrcamento != null
            ? snapshotOrcamento.origem
            : (_desconto > 0 ? _origemDesconto : 'nenhum');

        final double percentual = preservouDescontoOrcamento &&
                snapshotOrcamento != null
            ? snapshotOrcamento.percentual
            : (_origemDesconto.startsWith('fidelidade')
                ? _percentualFidelidadeAplicado
                : (_subtotal > 0 ? (_desconto / _subtotal) * 100 : 0.0));

        await _fidelidadeRepository.registrarDescontoDocumento(
          DescontoDocumentoSnapshot(
            documentoTipo: 'OS',
            documentoId: ordemServicoId,
            origem: origem,
            valorDesconto: _desconto,
            percentual: percentual,
            valorSugerido: preservouDescontoOrcamento
                ? (snapshotOrcamento?.valorSugerido ?? 0)
                : _descontoFidelidadeSugerido,
            clienteDesde: preservouDescontoOrcamento
                ? snapshotOrcamento?.clienteDesde
                : _beneficioFidelidade?.clienteDesde,
            faixaMeses: preservouDescontoOrcamento
                ? snapshotOrcamento?.faixaMeses
                : _beneficioFidelidade?.faixaMeses,
            perfilPreco: _perfilPreco,
          ),
        );
      } catch (_) {
        // A origem do desconto é metadado gerencial e não bloqueia a OS.
      }

      final database = await AppDatabase.instance.database;

      for (final produto in _produtos) {
        if (!produto.selecionado) {
          continue;
        }

        final item = produto.item;
        final quantidade = _converterValor(produto.quantidadeController.text);

        if (item.id == null || quantidade <= 0) {
          continue;
        }

        await database.insert('ordem_servico_produtos', {
          'ordem_servico_id': ordemServicoId,
          'produto_id': item.id,
          'produto_nome': item.nome,
          'quantidade': quantidade,
          'unidade': item.unidade,
          'custo_unitario': item.custoUnitarioEfetivo,
          'custo_unitario_no_momento': item.custoUnitarioEfetivo,
          'custo_total_no_momento': quantidade * item.custoUnitarioEfetivo,
          'composicao_lotes_json': '',
          'baixado_estoque': 0,
        });
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ordem de Serviço criada com sucesso.')),
      );

      Navigator.of(context).pop(true);
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível salvar a Ordem de Serviço.\n'
        '$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : null,
      ),
    );
  }

  String _nomeVeiculo(Veiculo veiculo) {
    final nome = '${veiculo.marca} ${veiculo.modelo}'.trim();

    final detalhes = <String>[];

    if (veiculo.placa.trim().isNotEmpty) {
      detalhes.add(veiculo.placa.trim().toUpperCase());
    }

    if (veiculo.cor.trim().isNotEmpty) {
      detalhes.add(veiculo.cor.trim());
    }

    if (detalhes.isEmpty) {
      return nome.isEmpty ? 'Veículo sem identificação' : nome;
    }

    return '$nome — ${detalhes.join(' • ')}';
  }

  Widget _construirCabecalho() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_outlined),
                SizedBox(width: 8),
                Text(
                  'Identificação',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _numeroController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Número da OS',
                prefixIcon: Icon(Icons.tag_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _responsavelController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Responsável pelo serviço',
                hintText: 'Exemplo: João',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirClienteVeiculo() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_search_outlined),
                SizedBox(width: 8),
                Text(
                  'Cliente e veículo',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Cliente>(
              initialValue: _clienteSelecionado,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cliente *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              items: _clientes.map((cliente) {
                final telefone = cliente.telefone.trim();

                return DropdownMenuItem<Cliente>(
                  value: cliente,
                  child: Text(
                    telefone.isEmpty
                        ? cliente.nome
                        : '${cliente.nome} — $telefone',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _salvando ? null : _selecionarCliente,
              validator: (valor) {
                if (valor == null) {
                  return 'Selecione o cliente';
                }

                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<Veiculo>(
              initialValue: _veiculoSelecionado,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Veículo',
                prefixIcon: const Icon(Icons.directions_car),
                border: const OutlineInputBorder(),
                suffixIcon: _carregandoVeiculos
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              items: _veiculos.map((veiculo) {
                return DropdownMenuItem<Veiculo>(
                  value: veiculo,
                  child: Text(
                    _nomeVeiculo(veiculo),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged:
                  _clienteSelecionado == null ||
                      _carregandoVeiculos ||
                      _salvando
                  ? null
                  : (veiculo) {
                      setState(() {
                        _veiculoSelecionado = veiculo;
                      });
                    },
            ),
            if (_clienteSelecionado != null &&
                !_carregandoVeiculos &&
                _veiculos.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Este cliente ainda não possui veículo cadastrado.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _adicionarProduto() async {
    if (_itensEstoque.isEmpty) {
      _mostrarMensagem('Nenhum produto cadastrado no estoque.', erro: true);
      return;
    }

    ItemEstoque? itemSelecionado;
    String quantidadeDigitada = '1';

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, atualizarDialogo) {
            return AlertDialog(
              title: const Text('Adicionar produto'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<ItemEstoque>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Produto',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _itensEstoque.map((item) {
                        return DropdownMenuItem<ItemEstoque>(
                          value: item,
                          child: Text(
                            '${item.nome} — Estoque: '
                            '${_formatarNumeroCampo(item.quantidade)} '
                            '${item.unidade}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (item) {
                        atualizarDialogo(() {
                          itemSelecionado = item;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: '1',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantidade utilizada',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (valor) {
                        quantidadeDigitada = valor;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(dialogContext).unfocus();
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final item = itemSelecionado;
                    final quantidade = _converterValor(quantidadeDigitada);

                    if (item == null) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selecione um produto.')),
                      );
                      return;
                    }

                    if (quantidade <= 0) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Informe uma quantidade válida.'),
                        ),
                      );
                      return;
                    }

                    if (quantidade > item.quantidade) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Quantidade maior que o estoque disponível: '
                            '${_formatarNumeroCampo(item.quantidade)} '
                            '${item.unidade}.',
                          ),
                        ),
                      );
                      return;
                    }

                    FocusScope.of(dialogContext).unfocus();
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmou != true || !mounted) {
      return;
    }

    final item = itemSelecionado;

    if (item == null) {
      return;
    }

    setState(() {
      _adicionarOuSomarProdutoFormulario(
        item: item,
        quantidade: _converterValor(quantidadeDigitada),
        selecionado: true,
        obrigatorio: false,
      );
    });
  }

  Widget _construirProdutos() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Produtos utilizados',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _salvando ? null : _adicionarProduto,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Marque somente o que foi realmente usado e ajuste a quantidade.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (_produtos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('Nenhum produto adicionado.'),
              )
            else ...[
              const SizedBox(height: 12),
              ...List.generate(_produtos.length, (indice) {
                final produto = _produtos[indice];

                final quantidade = _converterValor(
                  produto.quantidadeController.text,
                );

                final custo = quantidade * produto.item.custoUnitarioEfetivo;

                final estoqueInsuficiente =
                    produto.selecionado && quantidade > produto.item.quantidade;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: estoqueInsuficiente
                          ? Colors.redAccent
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: produto.selecionado,
                            onChanged: produto.obrigatorio || _salvando
                                ? null
                                : (valor) {
                                    setState(() {
                                      produto.selecionado = valor ?? false;
                                    });
                                  },
                          ),
                          const SizedBox(width: 4),
                          const CircleAvatar(
                            child: Icon(Icons.science_outlined),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  produto.item.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  produto.obrigatorio
                                      ? 'Obrigatório'
                                      : 'Opcional',
                                  style: TextStyle(
                                    color: produto.obrigatorio
                                        ? Colors.orangeAccent
                                        : Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!produto.obrigatorio)
                            IconButton(
                              tooltip: 'Remover produto',
                              onPressed: _salvando
                                  ? null
                                  : () {
                                      setState(() {
                                        final removido = _produtos.removeAt(
                                          indice,
                                        );

                                        removido.dispose();
                                      });
                                    },
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: produto.quantidadeController,
                        enabled: produto.selecionado && !_salvando,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'Quantidade realmente utilizada',
                          suffixText: produto.item.unidade,
                          prefixIcon: const Icon(Icons.scale_outlined),
                          border: const OutlineInputBorder(),
                          helperText:
                              'Estoque: ${_formatarNumeroCampo(produto.item.quantidade)} '
                              '${produto.item.unidade}',
                          errorText: estoqueInsuficiente
                              ? 'Quantidade maior que o estoque disponível'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Custo unitário: '
                              '${_moeda.format(produto.item.custoUnitarioEfetivo)}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            'Custo: ${_moeda.format(custo)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD6A84B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
              _LinhaValor(
                titulo: 'Custo total dos produtos',
                valor: _moeda.format(_custoProdutosSelecionados),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirPerfilPreco() {
    final config = _precificacao?.config;
    final precificacaoDisponivel = _precificacao != null;

    String margem(double valor) {
      return '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sell_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Perfil de preço',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Escolha como o Imperium deve preencher o valor dos serviços '
              'selecionados do catálogo. O valor continua editável depois.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_perfilPreco),
              initialValue: _perfilPreco,
              decoration: const InputDecoration(
                labelText: 'Tipo de preço da OS',
                prefixIcon: Icon(Icons.price_change_outlined),
                border: OutlineInputBorder(),
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
                  enabled: precificacaoDisponivel,
                  child: Text(
                    config == null
                        ? 'Parceiro • 1 a 4/mês'
                        : 'Parceiro • 1 a 4/mês • '
                              '${margem(config.margemRevenda1a4)}',
                  ),
                ),
                DropdownMenuItem(
                  value: 'parceiro_5_9',
                  enabled: precificacaoDisponivel,
                  child: Text(
                    config == null
                        ? 'Parceiro • 5 a 9/mês'
                        : 'Parceiro • 5 a 9/mês • '
                              '${margem(config.margemRevenda5a9)}',
                  ),
                ),
                DropdownMenuItem(
                  value: 'parceiro_10_mais',
                  enabled: precificacaoDisponivel,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _perfilEhParceiro
                      ? Icons.handshake_outlined
                      : Icons.info_outline_rounded,
                  size: 17,
                  color: _perfilEhParceiro
                      ? const Color(0xFFD6A84B)
                      : null,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _descricaoPerfilPreco(_perfilPreco),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (!precificacaoDisponivel) ...[
              const SizedBox(height: 8),
              Text(
                'A Precificação não pôde ser carregada. Cliente final usa '
                'o preço padrão do catálogo e as faixas de parceiro ficam '
                'indisponíveis.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.orcamentoId != null) ...[
              const SizedBox(height: 8),
              Text(
                _perfilPreco == 'informado'
                    ? 'Esta OS veio de orçamento. O valor combinado foi '
                          'preservado como preço informado.'
                    : 'Perfil herdado do orçamento: '
                          '${_nomePerfilPreco(_perfilPreco)}. Os valores '
                          'combinados foram preservados e só serão '
                          'recalculados se você trocar o perfil.',
                style: const TextStyle(fontSize: 11.5),
              ),
            ] else if (widget.agendamento != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Esta OS veio de agendamento. O valor informado foi '
                'preservado e só muda quando você escolher outro perfil.',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirFidelidadeOs() {
    final config = _fidelidadeConfig;
    final beneficio = _beneficioFidelidade;
    final clienteDesde = beneficio?.clienteDesde;
    final parceiroBloqueado =
        _perfilEhParceiro && !config.permitirParceiro;

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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.loyalty_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fidelidade do cliente',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LinhaValor(
              titulo: 'Funcionamento',
              valor: modoTexto(),
            ),
            if (!config.ativa) ...[
              const SizedBox(height: 8),
              Text(
                'Desativada. Nenhum desconto por tempo de cliente será '
                'sugerido ou aplicado nesta OS.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (_clienteSelecionado == null) ...[
              const SizedBox(height: 8),
              const Text('Selecione um cliente para verificar a fidelidade.'),
            ] else ...[
              const SizedBox(height: 8),
              _LinhaValor(
                titulo: 'Cliente desde',
                valor: clienteDesde == null
                    ? 'Não informado'
                    : DateFormat('dd/MM/yyyy').format(clienteDesde),
              ),
              if (beneficio != null && clienteDesde != null) ...[
                const SizedBox(height: 6),
                _LinhaValor(
                  titulo: 'Tempo',
                  valor: _tempoRelacionamentoOs(
                    beneficio.mesesRelacionamento,
                  ),
                ),
                const SizedBox(height: 6),
                _LinhaValor(
                  titulo: 'Benefício da faixa',
                  valor: beneficio.percentual > 0
                      ? '${beneficio.percentual.toStringAsFixed(1).replaceAll('.', ',')}%'
                      : 'Ainda não atingiu uma faixa',
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _salvando ? null : _editarClienteDesdeOs,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  clienteDesde == null
                      ? 'Definir "Cliente desde"'
                      : 'Corrigir "Cliente desde"',
                ),
              ),
              if (parceiroBloqueado) ...[
                const SizedBox(height: 10),
                const Text(
                  'A fidelidade não está autorizada a acumular com preço '
                  'de parceiro.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ] else if (beneficio != null && beneficio.elegivel) ...[
                const SizedBox(height: 10),
                _LinhaValor(
                  titulo: 'Desconto seguro',
                  valor: _moeda.format(_descontoFidelidadeSugerido),
                  destaque: true,
                ),
                const SizedBox(height: 5),
                Text(
                  _descontoFidelidadeSugerido > 0
                      ? 'Limitado pela margem mínima segura dos serviços '
                            'vinculados ao catálogo.'
                      : 'Não há folga segura para desconto nos serviços '
                            'atuais.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (config.sugerir &&
                    _descontoFidelidadeSugerido > 0) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _salvando
                        ? null
                        : _aplicarFidelidadeSugeridaOs,
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
                        ? 'Existe um desconto manual; ele não foi '
                              'sobrescrito automaticamente.'
                        : 'Será aplicado automaticamente quando houver '
                              'valor seguro disponível.',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ],
            ],
            const Divider(height: 22),
            _LinhaValor(
              titulo: 'Origem do desconto',
              valor: _origemDescontoTextoOs(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirServicos() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Serviços',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _salvando ? null : _adicionarServico,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_servicos.length, (indice) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: indice == _servicos.length - 1 ? 0 : 14,
                ),
                child: _construirServico(indice, _servicos[indice]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _construirServico(int indice, _ServicoFormulario servico) {
    final quantidade = _converterValor(servico.quantidadeController.text);

    final valorUnitario = _converterValor(servico.valorController.text);

    final subtotal = quantidade * valorUnitario;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Serviço ${indice + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Remover serviço',
                onPressed: _salvando ? null : () => _removerServico(indice),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _salvando
                ? null
                : () => _selecionarServicoCatalogo(indice),
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('Selecionar do catálogo'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: servico.nomeController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome do serviço *',
              hintText: 'Exemplo: Polimento técnico',
              border: OutlineInputBorder(),
            ),
            validator: (valor) {
              if (indice == 0 && (valor == null || valor.trim().isEmpty)) {
                return 'Informe o serviço';
              }

              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: servico.descricaoController,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              hintText: 'Detalhes opcionais do serviço',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: servico.quantidadeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    if (servico.nomeController.text.trim().isEmpty &&
                        (valor == null || valor.trim().isEmpty)) {
                      return null;
                    }

                    if (_converterValor(valor ?? '') <= 0) {
                      return 'Inválida';
                    }

                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: servico.valorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Valor unitário',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    if (servico.nomeController.text.trim().isEmpty &&
                        (valor == null || valor.trim().isEmpty)) {
                      return null;
                    }

                    if (_converterValor(valor ?? '') < 0) {
                      return 'Valor inválido';
                    }

                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Subtotal: ${_moeda.format(subtotal)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirValores() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.payments_outlined),
                SizedBox(width: 8),
                Text(
                  'Valores',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descontoController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              onChanged: (_) {
                _descontoAlteradoManualOs();
              },
              decoration: const InputDecoration(
                labelText: 'Desconto',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                final desconto = _converterValor(valor ?? '');

                if (desconto < 0) {
                  return 'Informe um desconto válido';
                }

                if (desconto > _subtotal) {
                  return 'O desconto é maior que o subtotal';
                }

                return null;
              },
            ),
            const SizedBox(height: 18),
            _LinhaValor(titulo: 'Subtotal', valor: _moeda.format(_subtotal)),
            const SizedBox(height: 8),
            _LinhaValor(titulo: 'Desconto', valor: _moeda.format(_desconto)),
            const SizedBox(height: 6),
            _LinhaValor(
              titulo: 'Origem',
              valor: _origemDescontoTextoOs(),
            ),
            const Divider(height: 24),
            _LinhaValor(
              titulo: 'Total final',
              valor: _moeda.format(_totalFinal),
              destaque: true,
            ),
            const SizedBox(height: 10),
            _LinhaValor(
              titulo: 'Custo dos produtos',
              valor: _moeda.format(_custoProdutosSelecionados),
            ),
            const SizedBox(height: 8),
            _LinhaValor(
              titulo: 'Lucro bruto estimado',
              valor: _moeda.format(_lucroBrutoEstimado),
              destaque: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirObservacoes() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _observacoesController,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Observações',
            hintText:
                'Condições do veículo, orientações ou informações adicionais',
            prefixIcon: Icon(Icons.notes_outlined),
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.orcamentoId == null
              ? 'Nova Ordem de Serviço'
              : 'Gerar Ordem de Serviço',
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
                children: [
                  _construirCabecalho(),
                  const SizedBox(height: 12),
                  _construirClienteVeiculo(),
                  const SizedBox(height: 12),
                  _construirPerfilPreco(),
                  const SizedBox(height: 12),
                  _construirFidelidadeOs(),
                  const SizedBox(height: 12),
                  _construirServicos(),
                  const SizedBox(height: 12),
                  _construirProdutos(),
                  const SizedBox(height: 12),
                  _construirValores(),
                  const SizedBox(height: 12),
                  _construirObservacoes(),
                ],
              ),
            ),
      bottomNavigationBar: _carregando
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _salvando ? 'Salvando...' : 'Salvar Ordem de Serviço',
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProdutoOsFormulario {
  _ProdutoOsFormulario({
    required this.item,
    required String quantidade,
    this.selecionado = true,
    this.obrigatorio = false,
  }) : quantidadeController = TextEditingController(text: quantidade);

  final ItemEstoque item;
  final TextEditingController quantidadeController;
  bool selecionado;
  bool obrigatorio;

  void dispose() {
    quantidadeController.dispose();
  }
}

class _ServicoFormulario {
  _ServicoFormulario({
    required VoidCallback aoAlterar,
    String nome = '',
    String descricao = '',
    String quantidade = '1',
    String valor = '0,00',
  }) : nomeController = TextEditingController(text: nome),
       descricaoController = TextEditingController(text: descricao),
       quantidadeController = TextEditingController(text: quantidade),
       valorController = TextEditingController(text: valor);

  final TextEditingController nomeController;
  final TextEditingController descricaoController;
  final TextEditingController quantidadeController;
  final TextEditingController valorController;
  int? servicoCatalogoId;

  void dispose() {
    nomeController.dispose();
    descricaoController.dispose();
    quantidadeController.dispose();
    valorController.dispose();
  }
}

class _LinhaValor extends StatelessWidget {
  const _LinhaValor({
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
      children: [
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: destaque ? 17 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: destaque ? 20 : 15,
            fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
