import 'package:flutter/material.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/chave_fiscal_service.dart';

class ChaveFiscalManualPage extends StatefulWidget {
  const ChaveFiscalManualPage({super.key, this.repository});

  final NotaFiscalEntradaRepository? repository;

  @override
  State<ChaveFiscalManualPage> createState() => _ChaveFiscalManualPageState();
}

class _ChaveFiscalManualPageState extends State<ChaveFiscalManualPage> {
  final _chaveController = TextEditingController();
  late final ChaveFiscalService _service;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _service = ChaveFiscalService(
      repository: widget.repository ?? NotaFiscalEntradaRepository(),
    );
  }

  @override
  void dispose() {
    _chaveController.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    try {
      final nota = await _service.registrarPreliminar(
        _chaveController.text,
        origem: 'chaveManual',
      );
      if (mounted) Navigator.of(context).pop<NotaFiscalEntrada>(nota);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: Colors.red[700]),
        );
        setState(() => _salvando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chave fiscal')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _chaveController,
              keyboardType: TextInputType.number,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Chave de acesso',
                hintText: '44 dígitos',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _salvando ? null : _registrar,
              icon: const Icon(Icons.save_outlined),
              label: Text(_salvando ? 'Registrando...' : 'Registrar chave'),
            ),
          ],
        ),
      ),
    );
  }
}
