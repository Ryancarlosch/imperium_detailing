import 'dart:io';

import 'package:flutter/material.dart';

class FotoVeiculoDetalhesPage extends StatelessWidget {
  const FotoVeiculoDetalhesPage({
    super.key,
    required this.caminho,
    required this.tipo,
    required this.descricao,
    required this.data,
    required this.nomeVeiculo,
    required this.placa,
  });

  final String caminho;
  final String tipo;
  final String descricao;
  final String data;
  final String nomeVeiculo;
  final String placa;

  bool get _arquivoExiste {
    if (caminho.trim().isEmpty) {
      return false;
    }

    return File(caminho).existsSync();
  }

  Color get _corTipo {
    return tipo == 'Depois' ? Colors.greenAccent : Colors.orangeAccent;
  }

  Widget _linhaInformacao({
    required IconData icone,
    required String titulo,
    required String valor,
  }) {
    final texto = valor.trim().isEmpty ? 'Não informado' : valor.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icone, color: const Color(0xFFD6A84B)),
        title: Text(titulo),
        subtitle: Text(texto),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeCompleto = [
      nomeVeiculo.trim(),
      placa.trim().toUpperCase(),
    ].where((valor) => valor.isNotEmpty).join(' • ');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('$tipo • $data'),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: _arquivoExiste
                    ? Image.file(
                        File(caminho),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image_outlined,
                            size: 74,
                            color: Colors.white30,
                          );
                        },
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            size: 74,
                            color: Colors.white30,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'A imagem não foi encontrada no dispositivo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 310),
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _corTipo.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tipo,
                          style: TextStyle(
                            color: _corTipo,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(data, style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    descricao.trim().isEmpty
                        ? 'Registro do serviço'
                        : descricao.trim(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _linhaInformacao(
                    icone: Icons.directions_car_outlined,
                    titulo: 'Veículo',
                    valor: nomeCompleto,
                  ),
                  _linhaInformacao(
                    icone: Icons.folder_outlined,
                    titulo: 'Arquivo',
                    valor: caminho,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
