import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/chave_fiscal_service.dart';

class ChaveFiscalScannerPage extends StatefulWidget {
  const ChaveFiscalScannerPage({super.key, this.repository});

  final NotaFiscalEntradaRepository? repository;

  @override
  State<ChaveFiscalScannerPage> createState() => _ChaveFiscalScannerPageState();
}

class _ChaveFiscalScannerPageState extends State<ChaveFiscalScannerPage> {
  late final MobileScannerController _controller;
  late final ChaveFiscalService _service;
  bool _processando = false;
  bool _lanterna = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
    _service = ChaveFiscalService(
      repository: widget.repository ?? NotaFiscalEntradaRepository(),
    );
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

    setState(() => _processando = true);
    try {
      final nota = await _service.registrarPreliminar(conteudo, origem: origem);
      if (mounted) Navigator.of(context).pop<NotaFiscalEntrada>(nota);
    } catch (_) {
      if (mounted) setState(() => _processando = false);
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
        title: const Text('Ler chave fiscal'),
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
          if (_processando) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
