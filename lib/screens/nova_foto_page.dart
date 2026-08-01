import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/cliente.dart';
import '../models/foto_servico.dart';
import '../models/veiculo.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/foto_servico_repository.dart';
import '../repositories/veiculo_repository.dart';

class NovaFotoPage extends StatefulWidget {
  const NovaFotoPage({super.key});

  @override
  State<NovaFotoPage> createState() => _NovaFotoPageState();
}

class _NovaFotoPageState extends State<NovaFotoPage> {
  final ClienteRepository _clienteRepository = ClienteRepository();

  final VeiculoRepository _veiculoRepository = VeiculoRepository();

  final FotoServicoRepository _fotoRepository = FotoServicoRepository();

  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _descricaoController = TextEditingController();

  List<Cliente> clientes = [];
  List<Veiculo> veiculos = [];

  Cliente? clienteSelecionado;
  Veiculo? veiculoSelecionado;

  File? fotoAntes;
  File? fotoDepois;

  DateTime _dataSelecionada = DateTime.now();

  bool carregando = true;
  bool salvando = false;
  bool selecionandoFoto = false;

  final DateFormat _formatadorData = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    carregarClientes();
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    super.dispose();
  }

  Future<void> carregarClientes() async {
    try {
      final lista = await _clienteRepository.listarClientes();

      if (!mounted) return;

      setState(() {
        clientes = lista;
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar clientes: $erro')),
      );
    }
  }

  Future<void> carregarVeiculos(Cliente cliente) async {
    if (cliente.id == null) return;

    setState(() {
      clienteSelecionado = cliente;
      veiculoSelecionado = null;
      veiculos = [];
    });

    try {
      final lista = await _veiculoRepository.listarVeiculosDoCliente(
        cliente.id!,
      );

      if (!mounted) return;

      setState(() {
        veiculos = lista;
      });
    } catch (erro) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar veículos: $erro')),
      );
    }
  }

  Future<ImageSource?> escolherOrigem() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              children: [
                const ListTile(
                  title: Text(
                    'Escolher imagem',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Câmera'),
                  onTap: salvando || selecionandoFoto
                      ? null
                      : () {
                          Navigator.pop(bottomSheetContext, ImageSource.camera);
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeria'),
                  onTap: salvando || selecionandoFoto
                      ? null
                      : () {
                          Navigator.pop(
                            bottomSheetContext,
                            ImageSource.gallery,
                          );
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> selecionarFoto({required bool fotoDeAntes}) async {
    if (salvando || selecionandoFoto) {
      return;
    }

    final origem = await escolherOrigem();

    if (origem == null) return;

    setState(() {
      selecionandoFoto = true;
    });

    try {
      final imagem = await _imagePicker.pickImage(
        source: origem,
        imageQuality: 86,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (imagem == null || !mounted) return;

      setState(() {
        if (fotoDeAntes) {
          fotoAntes = File(imagem.path);
        } else {
          fotoDepois = File(imagem.path);
        }
      });
    } catch (erro) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível acessar a imagem. Verifique permissões e tente novamente.\n$erro',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          selecionandoFoto = false;
        });
      }
    }
  }

  Future<String> salvarImagemPermanente(
    File imagem,
    String tipo, {
    required int clienteId,
    required int veiculoId,
  }) async {
    final diretorio = await getApplicationDocumentsDirectory();

    final pastaFotos = Directory(path.join(diretorio.path, 'fotos_servicos'));

    if (!await pastaFotos.exists()) {
      await pastaFotos.create(recursive: true);
    }

    final extensaoOriginal = path.extension(imagem.path).toLowerCase();

    final extensao = extensaoOriginal.isEmpty ? '.jpg' : extensaoOriginal;

    final aleatorio = Random.secure().nextInt(1 << 32);

    final timestamp = DateTime.now().microsecondsSinceEpoch;

    final nomeArquivo =
        '${tipo}_c${clienteId}_v${veiculoId}_${timestamp}_$aleatorio$extensao';

    final novoCaminho = path.join(pastaFotos.path, nomeArquivo);

    final copia = await imagem.copy(novoCaminho);

    return copia.path;
  }

  String dataAtual() {
    return _dataSelecionada.toIso8601String();
  }

  Future<void> selecionarData() async {
    if (salvando || selecionandoFoto) {
      return;
    }

    final agora = DateTime.now();

    final data = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2000),
      lastDate: DateTime(agora.year + 2, 12, 31),
    );

    if (data == null || !mounted) {
      return;
    }

    setState(() {
      _dataSelecionada = data;
    });
  }

  Future<void> salvar() async {
    if (salvando || selecionandoFoto) {
      return;
    }

    if (clienteSelecionado == null) {
      mostrarMensagem('Selecione um cliente.');
      return;
    }

    if (veiculoSelecionado == null) {
      mostrarMensagem('Selecione um veículo.');
      return;
    }

    if (fotoAntes == null && fotoDepois == null) {
      mostrarMensagem('Adicione pelo menos uma foto.');
      return;
    }

    if (clienteSelecionado!.id == null || veiculoSelecionado!.id == null) {
      mostrarMensagem('Cliente ou veículo inválido.');
      return;
    }

    if (veiculoSelecionado!.clienteId != clienteSelecionado!.id) {
      mostrarMensagem(
        'O veículo selecionado não pertence ao cliente informado.',
      );
      return;
    }

    setState(() {
      salvando = true;
    });

    final caminhosCriados = <String>[];

    try {
      String caminhoAntes = '';
      String caminhoDepois = '';

      if (fotoAntes != null) {
        caminhoAntes = await salvarImagemPermanente(
          fotoAntes!,
          'antes',
          clienteId: clienteSelecionado!.id!,
          veiculoId: veiculoSelecionado!.id!,
        );

        caminhosCriados.add(caminhoAntes);
      }

      if (fotoDepois != null) {
        caminhoDepois = await salvarImagemPermanente(
          fotoDepois!,
          'depois',
          clienteId: clienteSelecionado!.id!,
          veiculoId: veiculoSelecionado!.id!,
        );

        caminhosCriados.add(caminhoDepois);
      }

      final foto = FotoServico(
        clienteId: clienteSelecionado!.id!,
        veiculoId: veiculoSelecionado!.id!,
        caminhoAntes: caminhoAntes,
        caminhoDepois: caminhoDepois,
        descricao: _descricaoController.text.trim(),
        data: dataAtual(),
      );

      await _fotoRepository.inserirFoto(foto);

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (erro) {
      for (final caminho in caminhosCriados) {
        try {
          final arquivo = File(caminho);
          if (await arquivo.exists()) {
            await arquivo.delete();
          }
        } catch (_) {
          // Falhas de limpeza local não devem ocultar o erro principal.
        }
      }

      if (!mounted) return;

      setState(() {
        salvando = false;
      });

      mostrarMensagem('Erro ao salvar as fotos: $erro');
    }
  }

  void mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Widget campoFoto({
    required String titulo,
    required File? imagem,
    required bool fotoDeAntes,
  }) {
    return InkWell(
      onTap: () {
        if (salvando || selecionandoFoto) {
          return;
        }

        selecionarFoto(fotoDeAntes: fotoDeAntes);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD6A84B).withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: imagem == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    size: 54,
                    color: Color(0xFFD6A84B),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Toque para usar câmera ou galeria',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    imagem,
                    fit: BoxFit.cover,
                    cacheWidth: 1280,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(
                        color: Color(0xFF252525),
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.white38,
                            size: 52,
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      onPressed: () {
                        if (salvando || selecionandoFoto) {
                          return;
                        }

                        setState(() {
                          if (fotoDeAntes) {
                            fotoAntes = null;
                          } else {
                            fotoDepois = null;
                          }
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar fotos')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : clientes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cadastre um cliente e um veículo antes de adicionar fotos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Cliente>(
                  initialValue: clienteSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Cliente',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: clientes.map((cliente) {
                    return DropdownMenuItem<Cliente>(
                      value: cliente,
                      child: Text(cliente.nome),
                    );
                  }).toList(),
                  onChanged: (cliente) {
                    if (cliente != null) {
                      carregarVeiculos(cliente);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Veiculo>(
                  initialValue: veiculoSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Veículo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                  items: veiculos.map((veiculo) {
                    return DropdownMenuItem<Veiculo>(
                      value: veiculo,
                      child: Text('${veiculo.marca} ${veiculo.modelo}'),
                    );
                  }).toList(),
                  onChanged: clienteSelecionado == null
                      ? null
                      : (veiculo) {
                          setState(() {
                            veiculoSelecionado = veiculo;
                          });
                        },
                ),
                if (clienteSelecionado != null && veiculos.isEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Este cliente ainda não possui veículos.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
                const SizedBox(height: 24),
                campoFoto(
                  titulo: 'Foto de antes',
                  imagem: fotoAntes,
                  fotoDeAntes: true,
                ),
                const SizedBox(height: 16),
                campoFoto(
                  titulo: 'Foto de depois',
                  imagem: fotoDepois,
                  fotoDeAntes: false,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: salvando || selecionandoFoto
                      ? null
                      : selecionarData,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    'Data do registro: ${_formatadorData.format(_dataSelecionada)}',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descricaoController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do serviço',
                    hintText: 'Exemplo: Polimento técnico e vitrificação',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: salvando || selecionandoFoto ? null : salvar,
                  icon: salvando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    salvando
                        ? 'Salvando...'
                        : selecionandoFoto
                        ? 'Processando imagem...'
                        : 'Salvar fotos',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
