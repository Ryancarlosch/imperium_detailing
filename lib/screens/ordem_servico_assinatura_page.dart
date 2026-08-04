import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../repositories/ordem_servico_repository.dart';

class OrdemServicoAssinaturaPage extends StatefulWidget {
  final int ordemServicoId;
  final String numeroOrdem;
  final String cliente;
  final String veiculo;
  final bool somenteLeitura;

  const OrdemServicoAssinaturaPage({
    super.key,
    required this.ordemServicoId,
    required this.numeroOrdem,
    required this.cliente,
    required this.veiculo,
    this.somenteLeitura = false,
  });

  @override
  State<OrdemServicoAssinaturaPage> createState() =>
      _OrdemServicoAssinaturaPageState();
}

class _OrdemServicoAssinaturaPageState
    extends State<OrdemServicoAssinaturaPage> {
  final OrdemServicoRepository _repository = OrdemServicoRepository();

  late final SignatureController _signatureController;

  bool _carregando = true;
  bool _salvando = false;
  bool _alterou = false;

  String? _caminhoAssinatura;
  String? _erroCarregamento;

  @override
  void initState() {
    super.initState();

    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      exportPenColor: Colors.black,
    );

    _carregarAssinatura();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _carregarAssinatura() async {
    setState(() {
      _carregando = true;
      _erroCarregamento = null;
    });

    try {
      final caminho = await _repository.buscarAssinaturaCliente(
        widget.ordemServicoId,
      );

      if (!mounted) {
        return;
      }

      String? caminhoValido;

      if (caminho != null && caminho.trim().isNotEmpty) {
        final arquivo = File(caminho.trim());

        if (await arquivo.exists()) {
          caminhoValido = arquivo.path;
        }
      }

      setState(() {
        _caminhoAssinatura = caminhoValido;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erroCarregamento = 'Não foi possível carregar a assinatura.';
      });
    }
  }

  Future<Directory> _obterPastaAssinaturas() async {
    final pastaDocumentos = await getApplicationDocumentsDirectory();

    final pastaAssinaturas = Directory(
      path.join(pastaDocumentos.path, 'assinaturas_ordens_servico'),
    );

    if (!await pastaAssinaturas.exists()) {
      await pastaAssinaturas.create(recursive: true);
    }

    return pastaAssinaturas;
  }

  Future<String> _salvarArquivoAssinatura(Uint8List bytes) async {
    final pasta = await _obterPastaAssinaturas();

    final nomeArquivo =
        'assinatura_os_${widget.ordemServicoId}_${DateTime.now().microsecondsSinceEpoch}.png';

    final arquivo = File(path.join(pasta.path, nomeArquivo));

    await arquivo.writeAsBytes(bytes, flush: true);

    return arquivo.path;
  }

  Future<void> _salvarAssinatura() async {
    if (_salvando) {
      return;
    }

    if (_signatureController.isEmpty) {
      _mostrarMensagem(
        'Peça ao cliente para assinar antes de salvar.',
        erro: true,
      );
      return;
    }

    setState(() {
      _salvando = true;
    });

    try {
      final bytes = await _signatureController.toPngBytes();

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Não foi possível gerar a imagem da assinatura.');
      }

      final caminhoAnterior = _caminhoAssinatura;

      final novoCaminho = await _salvarArquivoAssinatura(bytes);

      await _repository.salvarAssinaturaCliente(
        ordemServicoId: widget.ordemServicoId,
        caminhoAssinatura: novoCaminho,
      );

      if (caminhoAnterior != null &&
          caminhoAnterior.trim().isNotEmpty &&
          caminhoAnterior != novoCaminho) {
        final arquivoAnterior = File(caminhoAnterior);

        if (await arquivoAnterior.exists()) {
          await arquivoAnterior.delete();
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _caminhoAssinatura = novoCaminho;
        _alterou = true;
        _salvando = false;
      });

      _signatureController.clear();

      _mostrarMensagem('Assinatura salva com sucesso.');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem('Não foi possível salvar a assinatura.', erro: true);
    }
  }

  Future<void> _confirmarRemocao() async {
    if (widget.somenteLeitura || _salvando) {
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remover assinatura'),
          content: const Text(
            'Deseja remover a assinatura salva? '
            'O cliente precisará assinar novamente.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmou == true) {
      await _removerAssinatura();
    }
  }

  Future<void> _removerAssinatura() async {
    setState(() {
      _salvando = true;
    });

    try {
      final caminhoAnterior = _caminhoAssinatura;

      await _repository.removerAssinaturaCliente(widget.ordemServicoId);

      if (caminhoAnterior != null && caminhoAnterior.trim().isNotEmpty) {
        final arquivo = File(caminhoAnterior);

        if (await arquivo.exists()) {
          await arquivo.delete();
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _caminhoAssinatura = null;
        _alterou = true;
        _salvando = false;
      });

      _signatureController.clear();

      _mostrarMensagem('Assinatura removida.');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem('Não foi possível remover a assinatura.', erro: true);
    }
  }

  void _limparDesenho() {
    if (_salvando || widget.somenteLeitura) {
      return;
    }

    _signatureController.clear();
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<bool> _aoTentarVoltar() async {
    Navigator.of(context).pop(_alterou);
    return false;
  }

  Widget _construirCabecalho() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.numeroOrdem,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _construirInformacao(
              icone: Icons.person_outline,
              titulo: 'Cliente',
              valor: widget.cliente,
            ),
            const SizedBox(height: 8),
            _construirInformacao(
              icone: Icons.directions_car_outlined,
              titulo: 'Veículo',
              valor: widget.veiculo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirInformacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$titulo: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: valor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirAssinaturaSalva() {
    final caminho = _caminhoAssinatura;

    if (caminho == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assinatura salva',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.file(
                File(caminho),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      'Não foi possível exibir a assinatura.',
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            if (!widget.somenteLeitura) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _salvando ? null : _confirmarRemocao,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover e assinar novamente'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirAreaAssinatura() {
    if (widget.somenteLeitura) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.lock_outline, size: 42, color: Colors.grey.shade600),
              const SizedBox(height: 12),
              const Text(
                'Esta Ordem de Serviço está bloqueada '
                'para alterações.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _caminhoAssinatura == null
                  ? 'Assinatura do cliente'
                  : 'Nova assinatura',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Peça ao cliente para assinar com o dedo '
              'dentro do espaço abaixo.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade400, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Assinatura',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _salvando ? null : _limparDesenho,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _salvando ? null : _salvarAssinatura,
                    icon: _salvando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erroCarregamento != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: Colors.red),
              const SizedBox(height: 12),
              Text(_erroCarregamento!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _carregarAssinatura,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _construirCabecalho(),
        if (_caminhoAssinatura != null) ...[
          const SizedBox(height: 16),
          _construirAssinaturaSalva(),
        ],
        const SizedBox(height: 16),
        if (_caminhoAssinatura == null || !widget.somenteLeitura)
          _construirAreaAssinatura(),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _aoTentarVoltar();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Assinatura do Cliente'),
          leading: IconButton(
            onPressed: _salvando
                ? null
                : () {
                    Navigator.of(context).pop(_alterou);
                  },
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(child: _construirConteudo()),
      ),
    );
  }
}
