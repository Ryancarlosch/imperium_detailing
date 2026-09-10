import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_importacao_service.dart';
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
  late final NotaFiscalImportacaoService _importacao;
  bool _processando = false;
  bool _lanterna = false;
  String _status = 'Aponte para o QR Code ou código de barras fiscal.';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? NotaFiscalEntradaRepository();
    _controller = MobileScannerController();
    _importacao = NotaFiscalImportacaoService(repository: _repository);
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
      _status = 'Validando e consultando documento fiscal...';
    });

    try {
      var resultado = await _importacao.processarConteudo(
        conteudo,
        origem: origem,
      );
      if (!mounted) return;

      if (resultado.exigePortalAssistido) {
        setState(() {
          _status =
              'O portal exige navegação humana. Resolva o CAPTCHA, se aparecer, e importe os dados exibidos.';
        });
        final assistida = await Navigator.of(context).push<NotaFiscalEntrada>(
          MaterialPageRoute(
            builder: (_) => NotaFiscalPortalAssistidoPage(
              url: resultado.portalAssistidoUrl!,
              chaveAcesso: resultado.nota.chaveAcesso,
              origem: origem,
              repository: _repository,
            ),
          ),
        );
        if (assistida != null) {
          resultado = NotaFiscalImportacaoResultado(
            nota: assistida,
            mensagem: 'NFC-e importada pela consulta fiscal assistida.',
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop<NotaFiscalEntrada>(resultado.nota);
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
