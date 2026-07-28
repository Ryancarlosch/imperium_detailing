import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../repositories/foto_servico_repository.dart';

class FotoDetalhesPage extends StatefulWidget {
  final Map<String, dynamic> foto;

  const FotoDetalhesPage({
    super.key,
    required this.foto,
  });

  @override
  State<FotoDetalhesPage> createState() =>
      _FotoDetalhesPageState();
}

class _FotoDetalhesPageState
    extends State<FotoDetalhesPage> {
  final FotoServicoRepository _repository =
  FotoServicoRepository();

  bool excluindo = false;

  String obterTexto(
      String campo, {
        String padrao = '',
      }) {
    return (widget.foto[campo] ?? padrao)
        .toString()
        .trim();
  }

  String montarNomeVeiculo() {
    final marca = obterTexto(
      'veiculo_marca',
    );

    final modelo = obterTexto(
      'veiculo_modelo',
    );

    final nome = '$marca $modelo'.trim();

    if (nome.isEmpty) {
      return 'Veículo não informado';
    }

    return nome;
  }

  Future<void> confirmarExclusao() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Excluir registro',
          ),
          content: const Text(
            'Deseja realmente excluir este registro de fotos? Essa ação não poderá ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Excluir',
              ),
            ),
          ],
        );
      },
    );

    if (confirmou == true) {
      await excluirRegistro();
    }
  }

  Future<void> excluirRegistro() async {
    final id = widget.foto['id'];

    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível identificar o registro.',
          ),
        ),
      );

      return;
    }

    setState(() {
      excluindo = true;
    });

    try {
      await _repository.excluirFoto(
        id as int,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        excluindo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir registro: $erro',
          ),
        ),
      );
    }
  }

  void abrirImagem(
      String caminho,
      String titulo,
      ) {
    if (caminho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$titulo não cadastrada.',
          ),
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisualizarFotoPage(
          caminho: caminho,
          titulo: titulo,
        ),
      ),
    );
  }

  Widget criarFoto({
    required String titulo,
    required String caminho,
    required IconData icone,
  }) {
    final existe = caminho.isNotEmpty &&
        File(caminho).existsSync();

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icone,
              size: 21,
              color: const Color(
                0xFFD6A84B,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior:
            Clip.antiAlias,
            child: InkWell(
              onTap: existe
                  ? () {
                abrirImagem(
                  caminho,
                  titulo,
                );
              }
                  : null,
              child: existe
                  ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(caminho),
                    fit: BoxFit.cover,
                    errorBuilder: (
                        context,
                        erro,
                        stackTrace,
                        ) {
                      return criarImagemIndisponivel();
                    },
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding:
                      const EdgeInsets.all(
                        9,
                      ),
                      decoration:
                      BoxDecoration(
                        color:
                        Colors.black54,
                        borderRadius:
                        BorderRadius
                            .circular(
                          12,
                        ),
                      ),
                      child: const Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
                  : criarImagemIndisponivel(),
            ),
          ),
        ),
      ],
    );
  }

  Widget criarImagemIndisponivel() {
    return const ColoredBox(
      color: Color(0xFF252525),
      child: Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .image_not_supported_outlined,
              size: 55,
              color: Colors.white38,
            ),
            SizedBox(height: 10),
            Text(
              'Imagem não disponível',
              style: TextStyle(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget criarInformacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Icon(
          icone,
          size: 21,
          color: const Color(
            0xFFD6A84B,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    final cliente = obterTexto(
      'cliente_nome',
      padrao: 'Cliente não informado',
    );

    final veiculo =
    montarNomeVeiculo();

    final placa = obterTexto(
      'veiculo_placa',
      padrao: 'Não informada',
    );

    final data = obterTexto(
      'data',
      padrao: 'Não informada',
    );

    final descricao = obterTexto(
      'descricao',
    );

    final caminhoAntes = obterTexto(
      'caminho_antes',
    );

    final caminhoDepois = obterTexto(
      'caminho_depois',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Antes e Depois',
        ),
        actions: [
          excluindo
              ? const Padding(
            padding:
            EdgeInsets.symmetric(
              horizontal: 18,
            ),
            child: Center(
              child:
              SizedBox(
                width: 22,
                height: 22,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          )
              : IconButton(
            onPressed:
            confirmarExclusao,
            tooltip:
            'Excluir registro',
            icon: const Icon(
              Icons.delete_outline,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding:
        const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          40,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding:
                const EdgeInsets.all(
                  18,
                ),
                child: Column(
                  children: [
                    criarInformacao(
                      icone:
                      Icons.person_outline,
                      titulo: 'Cliente',
                      valor: cliente,
                    ),
                    const Divider(
                      height: 28,
                    ),
                    criarInformacao(
                      icone: Icons
                          .directions_car_outlined,
                      titulo: 'Veículo',
                      valor: veiculo,
                    ),
                    const Divider(
                      height: 28,
                    ),
                    criarInformacao(
                      icone:
                      Icons.badge_outlined,
                      titulo: 'Placa',
                      valor: placa,
                    ),
                    const Divider(
                      height: 28,
                    ),
                    criarInformacao(
                      icone: Icons
                          .calendar_today_outlined,
                      titulo:
                      'Data do serviço',
                      valor: data,
                    ),
                  ],
                ),
              ),
            ),
            if (descricao.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding:
                  const EdgeInsets.all(
                    18,
                  ),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      const Icon(
                        Icons
                            .description_outlined,
                        color: Color(
                          0xFFD6A84B,
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            const Text(
                              'Descrição',
                              style:
                              TextStyle(
                                fontSize:
                                12,
                                color: Colors
                                    .white54,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              descricao,
                              style:
                              const TextStyle(
                                fontSize:
                                16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            criarFoto(
              titulo: 'Antes',
              caminho: caminhoAntes,
              icone:
              Icons.history_outlined,
            ),
            const SizedBox(height: 24),
            criarFoto(
              titulo: 'Depois',
              caminho: caminhoDepois,
              icone:
              Icons.auto_awesome_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class VisualizarFotoPage
    extends StatelessWidget {
  final String caminho;
  final String titulo;

  const VisualizarFotoPage({
    super.key,
    required this.caminho,
    required this.titulo,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: Colors.black,
      ),
      body: PhotoView(
        imageProvider:
        FileImage(
          File(caminho),
        ),
        backgroundDecoration:
        const BoxDecoration(
          color: Colors.black,
        ),
        minScale:
        PhotoViewComputedScale
            .contained,
        maxScale:
        PhotoViewComputedScale
            .covered *
            4,
      ),
    );
  }
}