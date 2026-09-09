import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/chave_fiscal_service.dart';
import '../services/nota_fiscal_consulta_publica_service.dart';
import '../services/nota_fiscal_dfe_backend_service.dart';
import 'nota_fiscal_portal_assistido_page.dart';

class ChaveFiscalScannerPage extends StatefulWidget {
  const ChaveFiscalScannerPage({super.key, this.repository});

  final NotaFiscalEntradaRepository? repository;

  @override
  State<ChaveFiscalScannerPage> createState() => _ChaveFiscalScannerPageState();
}

class _ChaveFiscalScannerPageState extends State<ChaveFiscalScannerPage> {
  late final MobileScannerController _controller;
  late final NotaFiscalEntradaRepository _repository;
  late final ChaveFiscalService _chaveService;
  late final NotaFiscalConsultaPublicaService _consultaService;
  late final NotaFiscalDfeBackendService _dfeService;
  bool _processando = false;
  bool _lanterna = false;
  String _status = 'Aponte para o QR Code ou código de barras fiscal.';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? NotaFiscalEntradaRepository();
    _controller = MobileScannerController();
    _chaveService = ChaveFiscalService(repository: _repository);
    _consultaService = NotaFiscalConsultaPublicaService(
      repository: _repository,
    );
    _dfeService = NotaFiscalDfeBackendService(repository: _repository);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _capturar(BarcodeCapture captura) async {
    if (_processando) return;
    Barcode? barcode;
    for (final candidato in captura.barcodes) {
      if (candidato.rawValue?.trim().isNotEmpty == true) {
        barcode = candidato;
        break;
      }
    }
    final conteudo = barcode?.rawValue?.trim() ?? '';
    if (conteudo.isEmpty) return;
    final origem = barcode?.format == BarcodeFormat.qrCode
        ? 'qrCode'
        : 'codigoBarras';

    setState(() {
      _processando = true;
      _status = 'Identificando documento fiscal...';
    });

    try {
      final capturada = _chaveService.extrair(conteudo, origem: origem);
      final modelo = NotaFiscalConsultaPublicaService.modeloDaChave(
        capturada.chave,
      );

      NotaFiscalEntrada nota;
      final url = NotaFiscalConsultaPublicaService.extrairUrlConsulta(conteudo);

      if (origem == 'qrCode' && modelo == 65 && url != null) {
        nota = await _processarNfceComQr(
          conteudo: conteudo,
          origem: origem,
          chave: capturada.chave,
          url: url,
        );
      } else if (modelo == 55) {
        nota = await _processarNfeModelo55(
          conteudo: conteudo,
          origem: origem,
          chave: capturada.chave,
        );
      } else {
        nota = await _chaveService.registrarPreliminar(
          conteudo,
          origem: origem,
        );
      }

      if (mounted) Navigator.of(context).pop<NotaFiscalEntrada>(nota);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processando = false;
        _status = '$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: Colors.red[700]),
      );
    }
  }

  Future<NotaFiscalEntrada> _processarNfceComQr({
    required String conteudo,
    required String origem,
    required String chave,
    required Uri url,
  }) async {
    if (mounted) {
      setState(() => _status = 'Consultando fornecedor, itens e valores...');
    }

    try {
      return await _consultaService.consultarEImportar(
        conteudo,
        origem: origem,
      );
    } on ConsultaPublicaFiscalException {
      final preliminar = await _chaveService.registrarPreliminar(
        conteudo,
        origem: origem,
      );
      if (!mounted) return preliminar;

      setState(() {
        _status =
            'O portal precisa de confirmação humana. Abra a consulta e resolva o CAPTCHA.';
      });

      final assistida = await Navigator.of(context).push<NotaFiscalEntrada>(
        MaterialPageRoute(
          builder: (_) => NotaFiscalPortalAssistidoPage(
            url: NotaFiscalConsultaPublicaService.urlSegura(url),
            chaveAcesso: chave,
            origem: origem,
            repository: _repository,
          ),
        ),
      );
      return assistida ?? preliminar;
    }
  }

  Future<NotaFiscalEntrada> _processarNfeModelo55({
    required String conteudo,
    required String origem,
    required String chave,
  }) async {
    if (mounted) {
      setState(
        () => _status = 'Consultando NF-e recebida no backend fiscal...',
      );
    }

    try {
      return await _dfeService.consultarEImportar(chave);
    } on DfeBackendException {
      return _chaveService.registrarPreliminar(conteudo, origem: origem);
    }
  }

  Future<void> _alternarLanterna() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _lanterna = !_lanterna);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ler documento fiscal'),
        actions: [
          IconButton(
            tooltip: 'Alternar lanterna',
            onPressed: _alternarLanterna,
            icon: Icon(_lanterna ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _capturar),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 300,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 36,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          if (_processando)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
