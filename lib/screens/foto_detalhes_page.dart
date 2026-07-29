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
    final valor = widget.foto[campo];

    if (valor == null) {
      return padrao;
    }

    final texto = valor.toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
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

  int? obterIdRegistro() {
    final valor = widget.foto['id'];

    if (valor is int) {
      return valor;
    }

    return int.tryParse(
      valor?.toString() ?? '',
    );
  }

  Future<void> confirmarExclusao() async {
    if (excluindo) {
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: !excluindo,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Excluir registro',
                ),
              ),
            ],
          ),
          content: const Text(
            'Deseja realmente excluir este registro de fotos?\n\n'
                'As fotos salvas no aparelho também serão apagadas. '
                'Essa ação não poderá ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              icon: const Icon(
                Icons.delete_outline,
              ),
              label: const Text(
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

  Future<void> excluirArquivoImagem(
      String caminho,
      ) async {
    final caminhoLimpo = caminho.trim();

    if (caminhoLimpo.isEmpty) {
      return;
    }

    final arquivo = File(caminhoLimpo);

    if (await arquivo.exists()) {
      await arquivo.delete();
    }
  }

  Future<void> excluirRegistro() async {
    final id = obterIdRegistro();

    if (id == null) {
      mostrarMensagem(
        'Não foi possível identificar o registro.',
      );
      return;
    }

    setState(() {
      excluindo = true;
    });

    final caminhoAntes = obterTexto(
      'caminho_antes',
    );

    final caminhoDepois = obterTexto(
      'caminho_depois',
    );

    try {
      final registrosExcluidos =
      await _repository.excluirFoto(id);

      if (registrosExcluidos == 0) {
        throw Exception(
          'O registro não foi encontrado no banco de dados.',
        );
      }

      final errosAoExcluirArquivos =
      <String>[];

      try {
        await excluirArquivoImagem(
          caminhoAntes,
        );
      } catch (erro) {
        errosAoExcluirArquivos.add(
          'foto de antes',
        );
      }

      try {
        await excluirArquivoImagem(
          caminhoDepois,
        );
      } catch (erro) {
        errosAoExcluirArquivos.add(
          'foto de depois',
        );
      }

      if (!mounted) {
        return;
      }

      if (errosAoExcluirArquivos.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'O registro foi excluído, mas não foi possível apagar '
                  '${errosAoExcluirArquivos.join(' e ')} do armazenamento.',
            ),
          ),
        );
      }

      Navigator.pop(
        context,
        true,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        excluindo = false;
      });

      mostrarMensagem(
        'Erro ao excluir registro: $erro',
      );
    }
  }

  void mostrarMensagem(
      String mensagem,
      ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
      ),
    );
  }

  void abrirImagem(
      String caminho,
      String titulo,
      ) {
    final caminhoLimpo = caminho.trim();

    if (caminhoLimpo.isEmpty ||
        !File(caminhoLimpo).existsSync()) {
      mostrarMensagem(
        '$titulo não está disponível.',
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisualizarFotoPage(
          caminho: caminhoLimpo,
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
    final caminhoLimpo = caminho.trim();

    final existe = caminhoLimpo.isNotEmpty &&
        File(caminhoLimpo).existsSync();

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
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: existe
                  ? () {
                abrirImagem(
                  caminhoLimpo,
                  titulo,
                );
              }
                  : null,
              child: existe
                  ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(caminhoLimpo),
                    fit: BoxFit.cover,
                    errorBuilder: (
                        context,
                        erro,
                        stackTrace,
                        ) {
                      return criarImagemIndisponivel();
                    },
                  ),
                  const Positioned(
                    right: 12,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius:
                        BorderRadius.all(
                          Radius.circular(12),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(
                          Icons.zoom_in,
                          color: Colors.white,
                        ),
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

  Widget criarComparacao({
    required String caminhoAntes,
    required String caminhoDepois,
  }) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final telaLarga =
            constraints.maxWidth >= 700;

        if (telaLarga) {
          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(
                child: criarFoto(
                  titulo: 'Antes',
                  caminho: caminhoAntes,
                  icone: Icons.history_outlined,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: criarFoto(
                  titulo: 'Depois',
                  caminho: caminhoDepois,
                  icone:
                  Icons.auto_awesome_outlined,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            criarFoto(
              titulo: 'Antes',
              caminho: caminhoAntes,
              icone: Icons.history_outlined,
            ),
            const SizedBox(height: 24),
            criarFoto(
              titulo: 'Depois',
              caminho: caminhoDepois,
              icone:
              Icons.auto_awesome_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget criarImagemIndisponivel() {
    return const ColoredBox(
      color: Color(0xFF252525),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
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
                  fontWeight: FontWeight.w600,
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

    final veiculo = montarNomeVeiculo();

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

    return PopScope(
      canPop: !excluindo,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Antes e Depois',
          ),
          actions: [
            if (excluindo)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 18,
                ),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: confirmarExclusao,
                tooltip: 'Excluir registro',
                icon: const Icon(
                  Icons.delete_outline,
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
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
                  padding: const EdgeInsets.all(
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
                      CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons
                              .description_outlined,
                          color: Color(
                            0xFFD6A84B,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              const Text(
                                'Descrição',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                  Colors.white54,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                descricao,
                                style:
                                const TextStyle(
                                  fontSize: 16,
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
              criarComparacao(
                caminhoAntes: caminhoAntes,
                caminhoDepois:
                caminhoDepois,
              ),
            ],
          ),
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
    final arquivo = File(caminho);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: arquivo.existsSync()
          ? PhotoView(
        imageProvider: FileImage(
          arquivo,
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
        initialScale:
        PhotoViewComputedScale
            .contained,
        enableRotation: false,
        loadingBuilder: (
            context,
            event,
            ) {
          return const Center(
            child:
            CircularProgressIndicator(),
          );
        },
        errorBuilder: (
            context,
            erro,
            stackTrace,
            ) {
          return const Center(
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .broken_image_outlined,
                  size: 70,
                  color: Colors.white38,
                ),
                SizedBox(height: 12),
                Text(
                  'Não foi possível abrir a imagem.',
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          );
        },
      )
          : const Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .image_not_supported_outlined,
              size: 70,
              color: Colors.white38,
            ),
            SizedBox(height: 12),
            Text(
              'Imagem não encontrada.',
              style: TextStyle(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}