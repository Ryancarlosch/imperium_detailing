import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../repositories/ordem_servico_foto_repository.dart';

class OrdemServicoFotosPage extends StatefulWidget {
  const OrdemServicoFotosPage({
    super.key,
    required this.ordemServicoId,
    required this.numeroOrdem,
    required this.cliente,
    required this.veiculo,
    this.somenteLeitura = false,
  });

  final int ordemServicoId;
  final String numeroOrdem;
  final String cliente;
  final String veiculo;
  final bool somenteLeitura;

  @override
  State<OrdemServicoFotosPage> createState() => _OrdemServicoFotosPageState();
}

class _OrdemServicoFotosPageState extends State<OrdemServicoFotosPage>
    with SingleTickerProviderStateMixin {
  final OrdemServicoFotoRepository _repository = OrdemServicoFotoRepository();
  final ImagePicker _imagePicker = ImagePicker();

  late final TabController _tabController;

  List<Map<String, dynamic>> _fotosAntes = [];
  List<Map<String, dynamic>> _fotosDepois = [];

  bool _carregando = true;
  bool _salvando = false;
  bool _selecionandoImagem = false;
  bool _alterou = false;

  String get _etapaAtual => _tabController.index == 0 ? 'Antes' : 'Depois';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_aoTrocarAba);
    _carregarFotos();
  }

  @override
  void dispose() {
    _tabController.removeListener(_aoTrocarAba);
    _tabController.dispose();
    super.dispose();
  }

  void _aoTrocarAba() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  Future<void> _carregarFotos() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final resultados = await Future.wait([
        _repository.listarFotos(widget.ordemServicoId, etapa: 'Antes'),
        _repository.listarFotos(widget.ordemServicoId, etapa: 'Depois'),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _fotosAntes = resultados[0];
        _fotosDepois = resultados[1];
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
        'Não foi possível carregar as fotos.\n$erro',
        erro: true,
      );
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

  Future<ImageSource?> _selecionarOrigem() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Adicionar foto',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Escolha a origem da imagem'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Câmera'),
                  onTap: () {
                    Navigator.of(bottomContext).pop(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeria'),
                  onTap: () {
                    Navigator.of(bottomContext).pop(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _pedirDescricao() async {
    final controller = TextEditingController();

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Descrição da foto'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ex.: risco na porta dianteira direita',
              labelText: 'Descrição opcional',
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Salvar foto'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return resultado;
  }

  Future<void> _adicionarFoto() async {
    if (widget.somenteLeitura || _salvando || _selecionandoImagem) {
      return;
    }

    setState(() {
      _selecionandoImagem = true;
    });

    final origem = await _selecionarOrigem();

    if (origem == null) {
      if (mounted) {
        setState(() {
          _selecionandoImagem = false;
        });
      }
      return;
    }

    XFile? imagem;

    try {
      imagem = await _imagePicker.pickImage(
        source: origem,
        imageQuality: 86,
        maxWidth: 1920,
        maxHeight: 1920,
      );
    } catch (erro) {
      if (mounted) {
        setState(() {
          _selecionandoImagem = false;
        });
      }

      _mostrarMensagem(
        'Não foi possível abrir a câmera ou galeria.\n$erro',
        erro: true,
      );
      return;
    }

    if (imagem == null || !mounted) {
      if (mounted) {
        setState(() {
          _selecionandoImagem = false;
        });
      }

      return;
    }

    final descricao = await _pedirDescricao();

    if (descricao == null || !mounted) {
      if (mounted) {
        setState(() {
          _selecionandoImagem = false;
        });
      }

      return;
    }

    setState(() {
      _salvando = true;
      _selecionandoImagem = false;
    });

    String? caminhoSalvo;

    try {
      final diretorioAplicativo = await getApplicationDocumentsDirectory();

      final pasta = Directory(
        path.join(
          diretorioAplicativo.path,
          'ordens_servico',
          widget.ordemServicoId.toString(),
          _etapaAtual.toLowerCase(),
        ),
      );

      if (!await pasta.exists()) {
        await pasta.create(recursive: true);
      }

      final extensao = path.extension(imagem.path).isEmpty
          ? '.jpg'
          : path.extension(imagem.path);

      final aleatorio = Random.secure().nextInt(1 << 32);
      final nomeArquivo =
          '${_etapaAtual.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}_$aleatorio$extensao';

      caminhoSalvo = path.join(pasta.path, nomeArquivo);

      await File(imagem.path).copy(caminhoSalvo);

      await _repository.inserirFoto(
        ordemServicoId: widget.ordemServicoId,
        etapa: _etapaAtual,
        caminho: caminhoSalvo,
        descricao: descricao,
      );

      _alterou = true;
      await _carregarFotos();

      _mostrarMensagem('Foto adicionada em $_etapaAtual.');
    } catch (erro) {
      if (caminhoSalvo != null) {
        final arquivo = File(caminhoSalvo);
        if (await arquivo.exists()) {
          await arquivo.delete();
        }
      }

      _mostrarMensagem('Não foi possível salvar a foto.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
          _selecionandoImagem = false;
        });
      }
    }
  }

  Future<void> _excluirFoto(Map<String, dynamic> foto) async {
    if (widget.somenteLeitura || _salvando || _selecionandoImagem) {
      return;
    }

    final id = _obterInt(foto['id']);

    if (id <= 0) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir foto'),
          content: const Text('Deseja excluir permanentemente esta foto?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
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
      _salvando = true;
    });

    try {
      await _repository.excluirFoto(id);
      _alterou = true;

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      await _carregarFotos();
      _mostrarMensagem('Foto excluída.');
    } catch (erro) {
      _mostrarMensagem('Não foi possível excluir a foto.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  void _abrirFoto(Map<String, dynamic> foto) {
    final caminho = foto['caminho']?.toString().trim() ?? '';
    final descricao = foto['descricao']?.toString().trim() ?? '';
    final arquivo = File(caminho);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(_etapaAtual),
              actions: [
                if (!widget.somenteLeitura)
                  IconButton(
                    tooltip: 'Excluir foto',
                    onPressed: _salvando || _selecionandoImagem
                        ? null
                        : () => _excluirFoto(foto),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: FutureBuilder<bool>(
                    future: arquivo.exists(),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) {
                        return const Center(
                          child: Text(
                            'Arquivo da foto não encontrado.',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Center(
                          child: Image.file(
                            arquivo,
                            fit: BoxFit.contain,
                            cacheWidth: 1700,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) {
                              return const Center(
                                child: Text(
                                  'Não foi possível abrir a foto.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (descricao.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.black87,
                      child: Text(
                        descricao,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _obterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Widget _construirGaleria(List<Map<String, dynamic>> fotos) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (fotos.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _etapaAtual == 'Antes'
                    ? Icons.photo_camera_back_outlined
                    : Icons.auto_awesome_outlined,
                size: 72,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhuma foto de ${_etapaAtual.toLowerCase()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.somenteLeitura
                    ? 'Não há fotos registradas nesta etapa.'
                    : 'Registre as condições do veículo nesta etapa do serviço.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (!widget.somenteLeitura) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _salvando || _selecionandoImagem
                      ? null
                      : _adicionarFoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Adicionar foto'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregarFotos,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.88,
        ),
        itemCount: fotos.length,
        itemBuilder: (context, index) {
          final foto = fotos[index];
          final caminho = foto['caminho']?.toString().trim() ?? '';
          final descricao = foto['descricao']?.toString().trim() ?? '';

          return Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrirFoto(foto),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Image.file(
                      File(caminho),
                      fit: BoxFit.cover,
                      cacheWidth: 760,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: const Color(0xFF252525),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 42,
                            color: Colors.white38,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      descricao.isEmpty ? 'Foto ${index + 1}' : descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _aoVoltar() async {
    Navigator.of(context).pop(_alterou);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _aoVoltar();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _aoVoltar,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.numeroOrdem),
              Text(
                'Fotos do serviço',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Antes (${_fotosAntes.length})'),
              Tab(text: 'Depois (${_fotosDepois.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.cliente,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.veiculo,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  if (widget.somenteLeitura) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, size: 16),
                        SizedBox(width: 6),
                        Text('Somente leitura'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _construirGaleria(_fotosAntes),
                  _construirGaleria(_fotosDepois),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: widget.somenteLeitura
            ? null
            : FloatingActionButton.extended(
                onPressed: _salvando || _selecionandoImagem
                    ? null
                    : _adicionarFoto,
                icon: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  _salvando ? 'Salvando...' : 'Adicionar em $_etapaAtual',
                ),
              ),
      ),
    );
  }
}
