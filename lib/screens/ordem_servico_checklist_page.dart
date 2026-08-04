import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../repositories/ordem_servico_checklist_repository.dart';

class OrdemServicoChecklistPage extends StatefulWidget {
  const OrdemServicoChecklistPage({
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
  State<OrdemServicoChecklistPage> createState() =>
      _OrdemServicoChecklistPageState();
}

class _OrdemServicoChecklistPageState extends State<OrdemServicoChecklistPage> {
  final OrdemServicoChecklistRepository _repository =
      OrdemServicoChecklistRepository();

  final ImagePicker _imagePicker = ImagePicker();
  final List<_ItemChecklistFormulario> _itens = [];
  final TextEditingController _quilometragemController =
      TextEditingController();
  final TextEditingController _combustivelController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  int? _itemProcessandoFotoId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }

    _quilometragemController.dispose();
    _combustivelController.dispose();

    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _repository.listarChecklist(widget.ordemServicoId),
        _repository.buscarDadosEntrada(widget.ordemServicoId),
      ]);

      final resultado = resultados[0] as List<Map<String, dynamic>>;
      final dadosEntrada = resultados[1] as Map<String, String>;

      if (!mounted) {
        return;
      }

      for (final item in _itens) {
        item.dispose();
      }

      setState(() {
        _itens
          ..clear()
          ..addAll(
            resultado.map((item) => _ItemChecklistFormulario.fromMap(item)),
          );

        _quilometragemController.text = dadosEntrada['quilometragem'] ?? '';
        _combustivelController.text = dadosEntrada['combustivel'] ?? '';

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
        'Não foi possível carregar o checklist.\n$erro',
        erro: true,
      );
    }
  }

  Future<void> _salvar() async {
    if (_salvando || widget.somenteLeitura) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _salvando = true;
    });

    try {
      await _repository.salvarDadosEntrada(
        ordemServicoId: widget.ordemServicoId,
        quilometragem: _quilometragemController.text,
        combustivel: _combustivelController.text,
      );

      await _repository.salvarChecklist(
        _itens.map((item) => item.toMap()).toList(),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checklist salvo com sucesso.')),
      );

      Navigator.of(context).pop(true);
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível salvar o checklist.\n$erro',
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

  Future<void> _selecionarFoto(
    _ItemChecklistFormulario item,
    ImageSource origem,
  ) async {
    if (widget.somenteLeitura || _itemProcessandoFotoId != null) {
      return;
    }

    setState(() {
      _itemProcessandoFotoId = item.id;
    });

    try {
      final imagem = await _imagePicker.pickImage(
        source: origem,
        imageQuality: 88,
        maxWidth: 2200,
      );

      if (imagem == null) {
        return;
      }

      final caminhoSalvo = await _salvarImagemPermanentemente(imagem, item.id);

      if (!mounted) {
        return;
      }

      final caminhoAnterior = item.fotoAvaria;

      setState(() {
        item.status = OrdemServicoChecklistRepository.statusAvaria;
        item.fotoAvaria = caminhoSalvo;
        item.dataAvariaRegistro ??= DateTime.now().toIso8601String();
      });

      await _excluirArquivoSeForFotoDoChecklist(
        caminhoAnterior,
        ignorarCaminho: caminhoSalvo,
      );
    } catch (erro) {
      _mostrarMensagem('Não foi possível adicionar a foto.\n$erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _itemProcessandoFotoId = null;
        });
      }
    }
  }

  Future<String> _salvarImagemPermanentemente(
    XFile imagem,
    int checklistId,
  ) async {
    final diretorioBase = await getApplicationDocumentsDirectory();

    final diretorioFotos = Directory(
      path.join(
        diretorioBase.path,
        'ordens_servico',
        widget.ordemServicoId.toString(),
        'checklist_avarias',
      ),
    );

    if (!await diretorioFotos.exists()) {
      await diretorioFotos.create(recursive: true);
    }

    final extensaoOriginal = path.extension(imagem.path).trim();
    final extensao = extensaoOriginal.isEmpty ? '.jpg' : extensaoOriginal;

    final nomeArquivo =
        'avaria_${checklistId}_${DateTime.now().millisecondsSinceEpoch}$extensao';

    final destino = path.join(diretorioFotos.path, nomeArquivo);

    final arquivoCopiado = await File(imagem.path).copy(destino);

    return arquivoCopiado.path;
  }

  Future<void> _removerFoto(_ItemChecklistFormulario item) async {
    if (widget.somenteLeitura) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover foto'),
          content: const Text(
            'Deseja remover a foto registrada para esta avaria?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    final caminhoAnterior = item.fotoAvaria;

    setState(() {
      item.fotoAvaria = null;
    });

    await _excluirArquivoSeForFotoDoChecklist(caminhoAnterior);
  }

  Future<void> _excluirArquivoSeForFotoDoChecklist(
    String? caminho, {
    String? ignorarCaminho,
  }) async {
    final caminhoLimpo = caminho?.trim() ?? '';

    if (caminhoLimpo.isEmpty || caminhoLimpo == ignorarCaminho) {
      return;
    }

    try {
      final arquivo = File(caminhoLimpo);

      if (await arquivo.exists()) {
        await arquivo.delete();
      }
    } catch (_) {
      // A falha ao excluir o arquivo antigo não impede o uso da nova foto.
    }
  }

  void _alterarStatus(_ItemChecklistFormulario item, int novoStatus) {
    if (widget.somenteLeitura) {
      return;
    }

    setState(() {
      item.status = novoStatus;

      if (novoStatus != OrdemServicoChecklistRepository.statusAvaria) {
        item.fotoAvaria = null;
        item.localizacaoAvariaController.clear();
        item.dataAvariaRegistro = null;
      } else {
        item.dataAvariaRegistro ??= DateTime.now().toIso8601String();
      }
    });
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  Map<String, List<_ItemChecklistFormulario>> get _itensPorCategoria {
    final resultado = <String, List<_ItemChecklistFormulario>>{};

    for (final item in _itens) {
      resultado.putIfAbsent(item.categoria, () => []).add(item);
    }

    return resultado;
  }

  int get _quantidadeConferida => _itens
      .where(
        (item) =>
            item.status != OrdemServicoChecklistRepository.statusNaoVerificado,
      )
      .length;

  int get _quantidadeAvarias => _itens
      .where(
        (item) => item.status == OrdemServicoChecklistRepository.statusAvaria,
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final progresso = _itens.isEmpty
        ? 0.0
        : _quantidadeConferida / _itens.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Checklist de entrada')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
              children: [
                _construirCabecalho(progresso),
                const SizedBox(height: 12),
                _construirCardDadosEntrada(),
                const SizedBox(height: 12),
                _construirAviso(),
                const SizedBox(height: 12),
                ..._itensPorCategoria.entries.map(
                  (entrada) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _construirCategoria(entrada.key, entrada.value),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _carregando || widget.somenteLeitura
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
                  label: Text(_salvando ? 'Salvando...' : 'Salvar checklist'),
                ),
              ),
            ),
    );
  }

  Widget _construirCabecalho(double progresso) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.numeroOrdem,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(widget.cliente),
            const SizedBox(height: 3),
            Text(widget.veiculo, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progresso),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$_quantidadeConferida de ${_itens.length} itens conferidos',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (_quantidadeAvarias > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      '$_quantidadeAvarias avaria(s)',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirAviso() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Marque cada item como OK ou Avaria. '
                'Quando houver avaria, registre a observação '
                'e, sempre que possível, adicione uma foto.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirCardDadosEntrada() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dados de entrada',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quilometragemController,
              enabled: !widget.somenteLeitura,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quilometragem',
                hintText: 'Ex.: 125430 km',
                prefixIcon: Icon(Icons.speed_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _combustivelController,
              enabled: !widget.somenteLeitura,
              decoration: const InputDecoration(
                labelText: 'Nível de combustível',
                hintText: 'Ex.: 1/2 tanque',
                prefixIcon: Icon(Icons.local_gas_station_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirCategoria(
    String categoria,
    List<_ItemChecklistFormulario> itens,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              categoria,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...List.generate(itens.length, (indice) {
              final item = itens[indice];

              return Padding(
                padding: EdgeInsets.only(
                  bottom: indice == itens.length - 1 ? 0 : 10,
                ),
                child: _construirItem(item),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _construirItem(_ItemChecklistFormulario item) {
    final possuiAvaria =
        item.status == OrdemServicoChecklistRepository.statusAvaria;

    final corBorda = switch (item.status) {
      OrdemServicoChecklistRepository.statusOk => Colors.green.shade300,
      OrdemServicoChecklistRepository.statusAvaria => Colors.red.shade300,
      _ => Colors.grey.shade300,
    };

    final corFundo = switch (item.status) {
      OrdemServicoChecklistRepository.statusOk => Colors.green.shade50,
      OrdemServicoChecklistRepository.statusAvaria => Colors.red.shade50,
      _ => Colors.transparent,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: corFundo,
        border: Border.all(color: corBorda),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.item,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: OrdemServicoChecklistRepository.statusNaoVerificado,
                icon: Icon(Icons.remove_circle_outline),
                label: Text('Pendente'),
              ),
              ButtonSegment<int>(
                value: OrdemServicoChecklistRepository.statusOk,
                icon: Icon(Icons.check_circle_outline),
                label: Text('OK'),
              ),
              ButtonSegment<int>(
                value: OrdemServicoChecklistRepository.statusAvaria,
                icon: Icon(Icons.warning_amber_rounded),
                label: Text('Avaria'),
              ),
            ],
            selected: {item.status},
            showSelectedIcon: false,
            onSelectionChanged: widget.somenteLeitura
                ? null
                : (selecionados) {
                    _alterarStatus(item, selecionados.first);
                  },
          ),
          if (possuiAvaria) ...[
            const SizedBox(height: 12),
            TextField(
              controller: item.observacaoController,
              enabled: !widget.somenteLeitura,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição da avaria',
                hintText: 'Ex.: risco profundo na porta dianteira',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.localizacaoAvariaController,
              enabled: !widget.somenteLeitura,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Local da avaria',
                hintText: 'Ex.: porta dianteira esquerda',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (item.dataAvariaRegistro != null) ...[
              const SizedBox(height: 8),
              Text(
                'Registrada em ${_formatarDataHora(item.dataAvariaRegistro!)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            _construirAreaFoto(item),
          ] else if (item.observacaoController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Observação registrada: '
              '${item.observacaoController.text.trim()}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirAreaFoto(_ItemChecklistFormulario item) {
    final caminho = item.fotoAvaria?.trim() ?? '';
    final arquivo = caminho.isEmpty ? null : File(caminho);
    final fotoExiste = arquivo != null && arquivo.existsSync();
    final processando = _itemProcessandoFotoId == item.id;

    if (fotoExiste) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Foto da avaria',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              arquivo,
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) {
                return Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: Colors.grey.shade200,
                  child: const Text('Não foi possível abrir a foto.'),
                );
              },
            ),
          ),
          if (!widget.somenteLeitura) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: processando
                        ? null
                        : () => _mostrarOpcoesFoto(item),
                    icon: const Icon(Icons.sync_outlined),
                    label: const Text('Trocar foto'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: processando ? null : () => _removerFoto(item),
                  tooltip: 'Remover foto',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ],
      );
    }

    if (widget.somenteLeitura) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            Icon(Icons.image_not_supported_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text('Nenhuma foto foi registrada para esta avaria.'),
            ),
          ],
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: processando ? null : () => _mostrarOpcoesFoto(item),
      icon: processando
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_a_photo_outlined),
      label: Text(
        processando ? 'Processando foto...' : 'Adicionar foto da avaria',
      ),
    );
  }

  Future<void> _mostrarOpcoesFoto(_ItemChecklistFormulario item) async {
    if (widget.somenteLeitura) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Adicionar foto da avaria',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Tirar foto'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _selecionarFoto(item, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Escolher da galeria'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _selecionarFoto(item, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatarDataHora(String valor) {
    final data = DateTime.tryParse(valor.trim());

    if (data == null) {
      return valor;
    }

    String doisDigitos(int numero) => numero.toString().padLeft(2, '0');

    final dia = doisDigitos(data.day);
    final mes = doisDigitos(data.month);
    final ano = data.year.toString();
    final hora = doisDigitos(data.hour);
    final minuto = doisDigitos(data.minute);

    return '$dia/$mes/$ano às $hora:$minuto';
  }
}

class _ItemChecklistFormulario {
  _ItemChecklistFormulario({
    required this.id,
    required this.categoria,
    required this.item,
    required this.status,
    required String observacao,
    required String localizacaoAvaria,
    required this.dataAvariaRegistro,
    required this.fotoAvaria,
  }) : observacaoController = TextEditingController(text: observacao),
       localizacaoAvariaController = TextEditingController(
         text: localizacaoAvaria,
       );

  factory _ItemChecklistFormulario.fromMap(Map<String, dynamic> mapa) {
    final statusBanco = _converterInt(mapa['status']);

    final status = statusBanco == 1 || statusBanco == 2
        ? statusBanco
        : _converterBool(mapa['marcado'])
        ? OrdemServicoChecklistRepository.statusOk
        : OrdemServicoChecklistRepository.statusNaoVerificado;

    final foto = mapa['foto_avaria']?.toString().trim() ?? '';

    return _ItemChecklistFormulario(
      id: _converterInt(mapa['id']),
      categoria: (mapa['categoria'] ?? 'Geral').toString(),
      item: (mapa['item'] ?? '').toString(),
      status: status,
      observacao: (mapa['observacao'] ?? '').toString(),
      localizacaoAvaria: (mapa['avaria_localizacao'] ?? '').toString(),
      dataAvariaRegistro:
          (mapa['avaria_data_registro'] ?? '').toString().trim().isEmpty
          ? null
          : (mapa['avaria_data_registro'] ?? '').toString().trim(),
      fotoAvaria: foto.isEmpty ? null : foto,
    );
  }

  final int id;
  final String categoria;
  final String item;
  int status;
  String? fotoAvaria;
  final TextEditingController observacaoController;
  final TextEditingController localizacaoAvariaController;
  String? dataAvariaRegistro;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'status': status,
      'marcado': status != OrdemServicoChecklistRepository.statusNaoVerificado
          ? 1
          : 0,
      'observacao': observacaoController.text.trim(),
      'foto_avaria': fotoAvaria,
      'avaria_localizacao': localizacaoAvariaController.text.trim(),
      'avaria_data_registro': dataAvariaRegistro,
    };
  }

  void dispose() {
    observacaoController.dispose();
    localizacaoAvariaController.dispose();
  }

  static int _converterInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static bool _converterBool(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
