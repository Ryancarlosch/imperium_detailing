import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/foto_servico_repository.dart';
import 'foto_veiculo_detalhes_page.dart';

class GaleriaVeiculoPage extends StatefulWidget {
  const GaleriaVeiculoPage({
    super.key,
    required this.veiculoId,
    required this.nomeVeiculo,
    required this.placa,
  });

  final int veiculoId;
  final String nomeVeiculo;
  final String placa;

  @override
  State<GaleriaVeiculoPage> createState() =>
      _GaleriaVeiculoPageState();
}

class _GaleriaVeiculoPageState
    extends State<GaleriaVeiculoPage> {
  final FotoServicoRepository _repository =
      FotoServicoRepository();

  final DateFormat _data =
      DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  String _filtro = 'Todos';

  List<Map<String, dynamic>> _registros = [];

  Map<String, int> _contagem = {
    'registros': 0,
    'fotos_antes': 0,
    'fotos_depois': 0,
    'total_imagens': 0,
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
    });

    try {
      final resultados = await Future.wait([
        _repository.listarGaleriaCompletaDoVeiculo(
          widget.veiculoId,
        ),
        _repository.contarFotosAntesEDepoisDoVeiculo(
          widget.veiculoId,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _registros =
            resultados[0]
                as List<Map<String, dynamic>>;

        _contagem =
            resultados[1] as Map<String, int>;

        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível carregar a galeria.\n$erro',
            ),
            backgroundColor:
                Colors.red.shade700,
          ),
        );
    }
  }

  String _texto(
    Map<String, dynamic> dados,
    String campo, {
    String padrao = '',
  }) {
    final texto =
        (dados[campo] ?? '').toString().trim();

    return texto.isEmpty ? padrao : texto;
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return 'Data não informada';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _data.format(data);
  }

  bool _arquivoExiste(String caminho) {
    if (caminho.trim().isEmpty) {
      return false;
    }

    return File(caminho).existsSync();
  }

  List<_ImagemGaleria> get _imagens {
    final imagens = <_ImagemGaleria>[];

    for (final registro in _registros) {
      final antes = _texto(
        registro,
        'caminho_antes',
      );

      final depois = _texto(
        registro,
        'caminho_depois',
      );

      final descricao = _texto(
        registro,
        'descricao',
        padrao: 'Registro do serviço',
      );

      final data = _formatarData(
        _texto(registro, 'data'),
      );

      if (_filtro != 'Depois' &&
          _arquivoExiste(antes)) {
        imagens.add(
          _ImagemGaleria(
            caminho: antes,
            tipo: 'Antes',
            descricao: descricao,
            data: data,
          ),
        );
      }

      if (_filtro != 'Antes' &&
          _arquivoExiste(depois)) {
        imagens.add(
          _ImagemGaleria(
            caminho: depois,
            tipo: 'Depois',
            descricao: descricao,
            data: data,
          ),
        );
      }
    }

    return imagens;
  }

  Future<void> _abrirImagem(
    _ImagemGaleria imagem,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FotoVeiculoDetalhesPage(
          caminho: imagem.caminho,
          tipo: imagem.tipo,
          descricao: imagem.descricao,
          data: imagem.data,
          nomeVeiculo: widget.nomeVeiculo,
          placa: widget.placa,
        ),
      ),
    );
  }

  Widget _indicador({
    required String titulo,
    required int valor,
    required IconData icone,
  }) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            children: [
              Icon(
                icone,
                color: const Color(0xFFD6A84B),
              ),
              const SizedBox(height: 7),
              Text(
                valor.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtros() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment<String>(
          value: 'Todos',
          label: Text('Todos'),
          icon: Icon(
            Icons.photo_library_outlined,
          ),
        ),
        ButtonSegment<String>(
          value: 'Antes',
          label: Text('Antes'),
          icon: Icon(
            Icons.first_page_outlined,
          ),
        ),
        ButtonSegment<String>(
          value: 'Depois',
          label: Text('Depois'),
          icon: Icon(
            Icons.auto_awesome_outlined,
          ),
        ),
      ],
      selected: {_filtro},
      onSelectionChanged: (valores) {
        setState(() {
          _filtro = valores.first;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagens = _imagens;

    final tituloVeiculo =
        widget.nomeVeiculo.trim().isEmpty
            ? 'Veículo'
            : widget.nomeVeiculo.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galeria do veículo'),
        actions: [
          IconButton(
            onPressed:
                _carregando ? null : _carregar,
            tooltip: 'Atualizar',
            icon: const Icon(
              Icons.refresh_outlined,
            ),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  28,
                ),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(
                          Icons
                              .directions_car_outlined,
                        ),
                      ),
                      title: Text(
                        tituloVeiculo,
                        style: const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        widget.placa.trim().isEmpty
                            ? 'Placa não informada'
                            : widget.placa
                                .toUpperCase(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _indicador(
                        titulo: 'Registros',
                        valor:
                            _contagem['registros'] ??
                                0,
                        icone:
                            Icons.collections_outlined,
                      ),
                      const SizedBox(width: 8),
                      _indicador(
                        titulo: 'Antes',
                        valor:
                            _contagem['fotos_antes'] ??
                                0,
                        icone:
                            Icons.first_page_outlined,
                      ),
                      const SizedBox(width: 8),
                      _indicador(
                        titulo: 'Depois',
                        valor:
                            _contagem['fotos_depois'] ??
                                0,
                        icone:
                            Icons.auto_awesome_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _filtros(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Imagens',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${imagens.length} foto(s)',
                        style: const TextStyle(
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (imagens.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding:
                            EdgeInsets.all(28),
                        child: Column(
                          children: [
                            Icon(
                              Icons
                                  .photo_library_outlined,
                              size: 54,
                              color: Colors.white30,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Nenhuma imagem encontrada para este filtro.',
                              textAlign:
                                  TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics:
                          const NeverScrollableScrollPhysics(),
                      itemCount: imagens.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemBuilder:
                          (context, indice) {
                        final imagem =
                            imagens[indice];

                        return InkWell(
                          borderRadius:
                              BorderRadius.circular(
                            15,
                          ),
                          onTap: () =>
                              _abrirImagem(imagem),
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior:
                                Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .stretch,
                              children: [
                                Expanded(
                                  child: Image.file(
                                    File(
                                      imagem.caminho,
                                    ),
                                    fit: BoxFit.cover,
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) {
                                      return const Center(
                                        child: Icon(
                                          Icons
                                              .broken_image_outlined,
                                          size: 44,
                                          color: Colors
                                              .white30,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets
                                          .all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal:
                                                  8,
                                              vertical:
                                                  4,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: imagem.tipo ==
                                                      'Depois'
                                                  ? Colors
                                                      .green
                                                      .withValues(
                                                        alpha:
                                                            0.18,
                                                      )
                                                  : Colors
                                                      .orange
                                                      .withValues(
                                                        alpha:
                                                            0.18,
                                                      ),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                20,
                                              ),
                                            ),
                                            child: Text(
                                              imagem.tipo,
                                              style:
                                                  TextStyle(
                                                color: imagem.tipo ==
                                                        'Depois'
                                                    ? Colors
                                                        .greenAccent
                                                    : Colors
                                                        .orangeAccent,
                                                fontSize:
                                                    11,
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            imagem.data,
                                            style:
                                                const TextStyle(
                                              color: Colors
                                                  .white38,
                                              fontSize:
                                                  10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(
                                        height: 7,
                                      ),
                                      Text(
                                        imagem
                                            .descricao,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow
                                                .ellipsis,
                                        style:
                                            const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

class _ImagemGaleria {
  const _ImagemGaleria({
    required this.caminho,
    required this.tipo,
    required this.descricao,
    required this.data,
  });

  final String caminho;
  final String tipo;
  final String descricao;
  final String data;
}
