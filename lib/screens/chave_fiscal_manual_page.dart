import 'package:flutter/material.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_importacao_service.dart';

class ChaveFiscalManualPage extends StatefulWidget {
  const ChaveFiscalManualPage({super.key, this.repository});

  final NotaFiscalEntradaRepository? repository;

  @override
  State<ChaveFiscalManualPage> createState() => _ChaveFiscalManualPageState();
}

class _ChaveFiscalManualPageState extends State<ChaveFiscalManualPage> {
  final _chaveController = TextEditingController();
  late final NotaFiscalImportacaoService _importacao;
  bool _salvando = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final repository = widget.repository ?? NotaFiscalEntradaRepository();
    _importacao = NotaFiscalImportacaoService(repository: repository);
  }

  @override
  void dispose() {
    _chaveController.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_salvando) return;
    setState(() {
      _salvando = true;
      _status = 'Validando e consultando a chave...';
    });
    try {
      final resultado = await _importacao.processarConteudo(
        _chaveController.text,
        origem: 'chaveManual',
      );
      if (!mounted) return;
      if (!resultado.processada) {
        setState(() {
          _status = resultado.mensagem;
          _salvando = false;
        });
      }
      Navigator.of(context).pop<NotaFiscalEntrada>(resultado.nota);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: Colors.red[700]),
      );
      setState(() {
        _salvando = false;
        _status = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chave fiscal')),
      body: ListView(
        padding: const EdgeInsets.all(24),
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
            icon: const Icon(Icons.search),
            label: Text(_salvando ? 'Consultando...' : 'Registrar / consultar'),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          const Text(
            'NF-e modelo 55: o Imperium tenta o backend DF-e. Se o XML completo ainda não estiver disponível, a chave fica pendente para reprocessamento ou importação manual do XML.\n\n'
            'NFC-e modelo 65: digitar apenas a chave registra o documento; para trazer os itens automaticamente, prefira ler o QR Code do cupom.',
          ),
        ],
      ),
    );
  }
}
