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

      Map<String, dynamic>? orcamento;
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

        _descontoController.text = _formatarNumeroCampo(
          _converterNumero(orcamento['desconto']),
        );

        _observacoesController.text = (orcamento['observacoes'] ?? '')
            .toString();
      }

      setState(() {
        _clientes = clientes;
        _veiculos = veiculos;
        _clienteSelecionado = clienteSelecionado;
        _veiculoSelecionado = veiculoSelecionado;
        _numeroController.text = numero;
        _itensEstoque = itensEstoque;
        _catalogoServicos = catalogoServicos;
        _carregando = false;
      });
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

  Future<void> _selecionarCliente(Cliente? cliente) async {
    setState(() {
      _clienteSelecionado = cliente;
      _veiculoSelecionado = null;
      _veiculos = [];
    });

    final clienteId = cliente?.id;

    if (clienteId == null) {
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
                              ' • ${_moeda.format(servico.precoPadrao)}'
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
    formulario.valorController.text = _formatarNumeroCampo(
      selecionado.precoPadrao,
    );
    formulario.servicoCatalogoId = selecionado.id;

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
  }

  void _atualizarTela() {
    if (mounted) {
      setState(() {});
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
                setState(() {});
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
