import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/veiculo.dart';
import '../repositories/ordem_servico_repository.dart';
import '../repositories/veiculo_repository.dart';
import 'novo_veiculo_page.dart';

class VeiculoDetalhesPage extends StatefulWidget {
  const VeiculoDetalhesPage({
    super.key,
    required this.veiculoId,
  });

  final int veiculoId;

  @override
  State<VeiculoDetalhesPage> createState() =>
      _VeiculoDetalhesPageState();
}

class _VeiculoDetalhesPageState
    extends State<VeiculoDetalhesPage> {
  final VeiculoRepository _veiculoRepository =
      VeiculoRepository();

  final OrdemServicoRepository _ordemRepository =
      OrdemServicoRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  final DateFormat _dataBrasileira =
      DateFormat('dd/MM/yyyy');

  Map<String, dynamic>? _veiculo;
  Map<String, dynamic> _resumo = {};
  Map<String, dynamic> _estatisticas = {};
  Map<String, dynamic>? _ultimoServico;

  List<Map<String, dynamic>> _historico = [];
  List<Map<String, dynamic>> _fotos = [];

  bool _carregando = true;
  bool _executandoAcao = false;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final resultados = await Future.wait([
        _veiculoRepository
            .buscarVeiculoComClientePorId(
          widget.veiculoId,
        ),
        _ordemRepository.obterResumoDoVeiculo(
          widget.veiculoId,
        ),
        _ordemRepository.listarHistoricoDoVeiculo(
          widget.veiculoId,
        ),
        _ordemRepository.buscarUltimoServicoDoVeiculo(
          widget.veiculoId,
        ),
        _veiculoRepository
            .obterEstatisticasBasicasDoVeiculo(
          widget.veiculoId,
        ),
        _veiculoRepository
            .listarFotosResumidasDoVeiculo(
          widget.veiculoId,
          limite: 6,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _veiculo =
            resultados[0] as Map<String, dynamic>?;

        _resumo =
            resultados[1] as Map<String, dynamic>;

        _historico =
            resultados[2]
                as List<Map<String, dynamic>>;

        _ultimoServico =
            resultados[3] as Map<String, dynamic>?;

        _estatisticas =
            resultados[4] as Map<String, dynamic>;

        _fotos =
            resultados[5]
                as List<Map<String, dynamic>>;

        _carregando = false;
      });

      if (_veiculo == null) {
        _mostrarMensagem(
          'Veículo não encontrado.',
          erro: true,
        );
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar o histórico do veículo.\n'
        '$erro',
        erro: true,
      );
    }
  }

  void _mostrarMensagem(
    String mensagem, {
    bool erro = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor:
              erro ? Colors.red.shade700 : null,
        ),
      );
  }

  String _texto(
    Map<String, dynamic>? dados,
    String campo, {
    String padrao = '',
  }) {
    final valor =
        (dados?[campo] ?? '').toString().trim();

    return valor.isEmpty ? padrao : valor;
  }

  int _inteiro(
    Map<String, dynamic>? dados,
    String campo,
  ) {
    final valor = dados?[campo];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(
          valor?.toString() ?? '',
        ) ??
        0;
  }

  double _numero(
    Map<String, dynamic>? dados,
    String campo,
  ) {
    final valor = dados?[campo];

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
          valor?.toString() ?? '',
        ) ??
        0;
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return 'Não informado';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _dataBrasileira.format(data);
  }

  String _dataDaOrdem(
    Map<String, dynamic> ordem,
  ) {
    final valor = _texto(
      ordem,
      'data_finalizacao',
      padrao: _texto(
        ordem,
        'data_inicio',
        padrao: _texto(
          ordem,
          'data_abertura',
        ),
      ),
    );

    return _formatarData(valor);
  }

  double _valorFinal(
    Map<String, dynamic> ordem,
  ) {
    final total =
        _numero(ordem, 'valor_total');

    final desconto =
        _numero(ordem, 'desconto');

    final resultado = total - desconto;

    return resultado < 0 ? 0 : resultado;
  }

  Duration? _duracao(
    Map<String, dynamic> ordem,
  ) {
    final dataInicio =
        _texto(ordem, 'data_inicio');

    final horaEntrada =
        _texto(ordem, 'hora_entrada');

    final dataFim =
        _texto(ordem, 'data_finalizacao');

    final horaSaida =
        _texto(ordem, 'hora_saida');

    if (dataInicio.isEmpty ||
        horaEntrada.isEmpty ||
        dataFim.isEmpty ||
        horaSaida.isEmpty) {
      return null;
    }

    final inicio = DateTime.tryParse(
      '${dataInicio}T$horaEntrada:00',
    );

    final fim = DateTime.tryParse(
      '${dataFim}T$horaSaida:00',
    );

    if (inicio == null ||
        fim == null ||
        fim.isBefore(inicio)) {
      return null;
    }

    return fim.difference(inicio);
  }

  String _formatarDuracao(
    Duration? duracao,
  ) {
    if (duracao == null) {
      return 'Não informada';
    }

    final horas = duracao.inHours;

    final minutos =
        duracao.inMinutes.remainder(60);

    if (horas <= 0) {
      return '${minutos}min';
    }

    if (minutos <= 0) {
      return '${horas}h';
    }

    return '${horas}h ${minutos}min';
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Finalizada':
        return Colors.green;
      case 'Em andamento':
        return Colors.blue;
      case 'Cancelada':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Veiculo? _montarVeiculoParaEdicao() {
    if (_veiculo == null) {
      return null;
    }

    final id = _inteiro(_veiculo, 'id');
    final clienteId =
        _inteiro(_veiculo, 'cliente_id');

    if (id <= 0 || clienteId <= 0) {
      return null;
    }

    return Veiculo(
      id: id,
      clienteId: clienteId,
      marca: _texto(_veiculo, 'marca'),
      modelo: _texto(_veiculo, 'modelo'),
      placa: _texto(_veiculo, 'placa'),
      cor: _texto(_veiculo, 'cor'),
      ano: _texto(_veiculo, 'ano'),
      observacoes:
          _texto(_veiculo, 'observacoes'),
    );
  }

  Future<void> _editarVeiculo() async {
    if (_executandoAcao) {
      return;
    }

    final veiculo =
        _montarVeiculoParaEdicao();

    if (veiculo == null) {
      _mostrarMensagem(
        'Não foi possível preparar o veículo para edição.',
        erro: true,
      );
      return;
    }

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NovoVeiculoPage(
          veiculo: veiculo,
        ),
      ),
    );

    if (alterou == true) {
      await _carregarTudo();

      _mostrarMensagem(
        'Veículo atualizado com sucesso.',
      );
    }
  }

  Future<void> _excluirVeiculo() async {
    if (_executandoAcao) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir veículo'),
          content: const Text(
            'Deseja excluir este veículo permanentemente?\n\n'
            'Agendamentos, fotos e outros registros vinculados '
            'também podem ser afetados.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    Colors.red.shade700,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _executandoAcao = true;
    });

    try {
      await _veiculoRepository.excluirVeiculo(
        widget.veiculoId,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível excluir o veículo.\n$erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _executandoAcao = false;
        });
      }
    }
  }

  Widget _indicador({
    required String titulo,
    required String valor,
    required IconData icone,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              icone,
              color: const Color(0xFFD6A84B),
            ),
            const SizedBox(height: 10),
            Text(
              valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              titulo,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    final marca = _texto(
      _veiculo,
      'marca',
      padrao: 'Marca não informada',
    );

    final modelo = _texto(
      _veiculo,
      'modelo',
      padrao: 'Modelo não informado',
    );

    final placa = _texto(
      _veiculo,
      'placa',
      padrao: 'Sem placa',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6A84B)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFD6A84B)
                  .withValues(alpha: 0.13),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 36,
              color: Color(0xFFD6A84B),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$marca $modelo'.trim(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  placa.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoInformacoes() {
    Widget linha(
      String titulo,
      String valor,
    ) {
      return Padding(
        padding:
            const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              valor.trim().isEmpty
                  ? 'Não informado'
                  : valor,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Color(0xFFD6A84B),
                ),
                SizedBox(width: 8),
                Text(
                  'Dados do veículo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            linha(
              'Proprietário',
              _texto(
                _veiculo,
                'cliente_nome',
              ),
            ),
            linha(
              'Telefone',
              _texto(
                _veiculo,
                'cliente_telefone',
              ),
            ),
            linha(
              'Cor',
              _texto(_veiculo, 'cor'),
            ),
            linha(
              'Ano',
              _texto(_veiculo, 'ano'),
            ),
            linha(
              'Observações',
              _texto(
                _veiculo,
                'observacoes',
                padrao:
                    'Nenhuma observação registrada.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniaturaFoto(
    Map<String, dynamic> foto,
  ) {
    final antes =
        _texto(foto, 'caminho_antes');

    final depois =
        _texto(foto, 'caminho_depois');

    final caminho =
        antes.isNotEmpty ? antes : depois;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFF252525),
        child: caminho.isEmpty
            ? const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: Colors.white30,
                ),
              )
            : Image.file(
                File(caminho),
                fit: BoxFit.cover,
                errorBuilder: (
                  context,
                  error,
                  stackTrace,
                ) {
                  return const Center(
                    child: Icon(
                      Icons
                          .image_not_supported_outlined,
                      color: Colors.white30,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _galeriaResumida() {
    if (_fotos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Fotos recentes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${_inteiro(_estatisticas, 'quantidade_fotos')} registro(s)',
              style: const TextStyle(
                color: Colors.white54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount: _fotos.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (_, indice) {
            return _miniaturaFoto(
              _fotos[indice],
            );
          },
        ),
      ],
    );
  }

  Widget _cardOrdem(
    Map<String, dynamic> ordem,
  ) {
    final status = _texto(
      ordem,
      'status',
      padrao: 'Aberta',
    );

    final servicos = _texto(
      ordem,
      'servicos',
      padrao: 'Serviços não informados',
    );

    final produtos = _texto(
      ordem,
      'produtos_utilizados',
    );

    final custoProdutos =
        _numero(ordem, 'custo_produtos');

    final valorFinal = _valorFinal(ordem);

    final lucroEstimado =
        valorFinal - custoProdutos;

    final duracao = _duracao(ordem);

    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _texto(
                      ordem,
                      'numero',
                      padrao:
                          'Ordem de Serviço',
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _corStatus(status)
                        .withValues(alpha: 0.16),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _corStatus(status),
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              servicos,
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  _dataDaOrdem(ordem),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  _moeda.format(valorFinal),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD6A84B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tempo: ${_formatarDuracao(duracao)}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (produtos.isNotEmpty) ...[
              const Divider(height: 22),
              const Text(
                'Produtos utilizados',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                produtos,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Custo: ${_moeda.format(custoProdutos)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    'Lucro estimado: ${_moeda.format(lucroEstimado < 0 ? 0 : lucroEstimado)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalInvestido =
        _numero(_resumo, 'total_investido');

    final quantidadeOrdens =
        _inteiro(_resumo, 'quantidade_ordens');

    final quantidadeFotos =
        _inteiro(
      _estatisticas,
      'quantidade_fotos',
    );

    final ultimoAtendimento =
        _texto(_resumo, 'ultimo_atendimento');

    final ultimoServico = _texto(
      _ultimoServico,
      'servicos',
      padrao: 'Nenhum serviço finalizado',
    );

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Detalhes do veículo'),
        actions: [
          IconButton(
            onPressed: _carregando
                ? null
                : _carregarTudo,
            tooltip: 'Atualizar',
            icon: const Icon(
              Icons.refresh_outlined,
            ),
          ),
          IconButton(
            onPressed:
                _carregando || _executandoAcao
                    ? null
                    : _editarVeiculo,
            tooltip: 'Editar veículo',
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),
          PopupMenuButton<String>(
            enabled:
                !_carregando && !_executandoAcao,
            onSelected: (valor) {
              if (valor == 'excluir') {
                _excluirVeiculo();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'excluir',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    SizedBox(width: 10),
                    Text('Excluir veículo'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _veiculo == null
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _carregarTudo,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Tentar novamente',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregarTudo,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      32,
                    ),
                    children: [
                      _cabecalho(),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.45,
                        children: [
                          _indicador(
                            titulo:
                                'Total investido',
                            valor: _moeda.format(
                              totalInvestido,
                            ),
                            icone:
                                Icons.payments_outlined,
                          ),
                          _indicador(
                            titulo:
                                'Ordens de Serviço',
                            valor:
                                quantidadeOrdens.toString(),
                            icone: Icons
                                .assignment_outlined,
                          ),
                          _indicador(
                            titulo: 'Fotos',
                            valor:
                                quantidadeFotos.toString(),
                            icone:
                                Icons.photo_library_outlined,
                          ),
                          _indicador(
                            titulo:
                                'Último atendimento',
                            valor: _formatarData(
                              ultimoAtendimento,
                            ),
                            icone: Icons
                                .event_available_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(
                            Icons
                                .auto_awesome_outlined,
                            color:
                                Color(0xFFD6A84B),
                          ),
                          title: const Text(
                            'Último serviço',
                          ),
                          subtitle:
                              Text(ultimoServico),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _secaoInformacoes(),
                      if (_fotos.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _galeriaResumida(),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Histórico do veículo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${_historico.length} registro(s)',
                            style: const TextStyle(
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_historico.isEmpty)
                        const Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding:
                                EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons
                                      .history_toggle_off_outlined,
                                  size: 44,
                                  color:
                                      Colors.white38,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Este veículo ainda não possui Ordens de Serviço.',
                                  textAlign:
                                      TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._historico.map(
                          _cardOrdem,
                        ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed:
                            _executandoAcao
                                ? null
                                : _editarVeiculo,
                        icon: const Icon(
                          Icons.edit_outlined,
                        ),
                        label: const Text(
                          'Editar veículo',
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
