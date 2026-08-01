import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/foto_servico_repository.dart';
import 'foto_detalhes_page.dart';
import 'nova_foto_page.dart';

class FotosPage extends StatefulWidget {
  const FotosPage({super.key});

  @override
  State<FotosPage> createState() => _FotosPageState();
}

class _FotosPageState extends State<FotosPage> {
  final FotoServicoRepository _repository = FotoServicoRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  List<Map<String, dynamic>> todasAsFotos = [];
  List<Map<String, dynamic>> fotosFiltradas = [];

  bool carregando = true;
  bool abrindoCadastro = false;
  String filtroTipo = 'Todos';

  final DateFormat _data = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();

    _pesquisaController.addListener(filtrarFotos);

    carregarFotos();
  }

  @override
  void dispose() {
    _pesquisaController.removeListener(filtrarFotos);

    _pesquisaController.dispose();

    super.dispose();
  }

  Future<void> carregarFotos() async {
    try {
      final lista = await _repository.listarFotosComDetalhes();

      if (!mounted) return;

      setState(() {
        todasAsFotos = lista;
        carregando = false;
      });

      filtrarFotos();
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar fotos: $erro')));
    }
  }

  void filtrarFotos() {
    if (!mounted) return;

    final pesquisa = _pesquisaController.text.trim().toLowerCase();

    final resultado = todasAsFotos.where((foto) {
      final cliente = (foto['cliente_nome'] ?? '').toString().toLowerCase();

      final marca = (foto['veiculo_marca'] ?? '').toString().toLowerCase();

      final modelo = (foto['veiculo_modelo'] ?? '').toString().toLowerCase();

      final placa = (foto['veiculo_placa'] ?? '').toString().toLowerCase();

      final descricao = (foto['descricao'] ?? '').toString().toLowerCase();

      final temAntes = (foto['caminho_antes'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

      final temDepois = (foto['caminho_depois'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;

      final passouFiltroTipo =
          filtroTipo == 'Todos' ||
          (filtroTipo == 'Antes' && temAntes) ||
          (filtroTipo == 'Depois' && temDepois);

      if (!passouFiltroTipo) {
        return false;
      }

      if (pesquisa.isEmpty) {
        return true;
      }

      return cliente.contains(pesquisa) ||
          marca.contains(pesquisa) ||
          modelo.contains(pesquisa) ||
          placa.contains(pesquisa) ||
          descricao.contains(pesquisa);
    }).toList();

    setState(() {
      fotosFiltradas = resultado;
    });
  }

  Future<void> novaFoto() async {
    if (abrindoCadastro) {
      return;
    }

    setState(() {
      abrindoCadastro = true;
    });

    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NovaFotoPage()),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      abrindoCadastro = false;
    });

    if (salvou != true) {
      return;
    }

    setState(() {
      carregando = true;
    });

    await carregarFotos();

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fotos salvas com sucesso!')));
  }

  Future<void> abrirDetalhes(Map<String, dynamic> foto) async {
    final excluiu = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FotoDetalhesPage(foto: foto)),
    );

    if (excluiu != true || !mounted) {
      return;
    }

    setState(() {
      carregando = true;
    });

    await carregarFotos();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro excluído com sucesso!')),
    );
  }

  String obterCaminhoMiniatura(Map<String, dynamic> foto) {
    final caminhoAntes = (foto['caminho_antes'] ?? '').toString().trim();

    final caminhoDepois = (foto['caminho_depois'] ?? '').toString().trim();

    if (caminhoAntes.isNotEmpty) {
      return caminhoAntes;
    }

    return caminhoDepois;
  }

  String montarNomeVeiculo(Map<String, dynamic> foto) {
    final marca = (foto['veiculo_marca'] ?? '').toString().trim();

    final modelo = (foto['veiculo_modelo'] ?? '').toString().trim();

    final nome = '$marca $modelo'.trim();

    if (nome.isEmpty) {
      return 'Veículo não informado';
    }

    return nome;
  }

  Widget criarMiniatura(String caminho) {
    if (caminho.isEmpty) {
      return criarImagemIndisponivel();
    }

    return Image.file(
      File(caminho),
      fit: BoxFit.cover,
      cacheWidth: 920,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return criarImagemIndisponivel();
      },
    );
  }

  Widget criarImagemIndisponivel() {
    return const ColoredBox(
      color: Color(0xFF252525),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 42,
          color: Colors.white38,
        ),
      ),
    );
  }

  Widget criarCardFoto(Map<String, dynamic> foto) {
    final caminhoMiniatura = obterCaminhoMiniatura(foto);

    final cliente = (foto['cliente_nome'] ?? 'Cliente não informado')
        .toString();

    final veiculo = montarNomeVeiculo(foto);

    final placa = (foto['veiculo_placa'] ?? '').toString().trim();

    final descricao = (foto['descricao'] ?? '').toString().trim();

    final data = _formatarData((foto['data'] ?? '').toString().trim());

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          abrirDetalhes(foto);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  criarMiniatura(caminhoMiniatura),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 17,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            data.isEmpty ? 'Data não informada' : data,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.compare_outlined,
                          color: Color(0xFFD6A84B),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Color(0xFFD6A84B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cliente,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.directions_car_outlined,
                        size: 20,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          placa.isEmpty ? veiculo : '$veiculo • $placa',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  if (descricao.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget criarEstadoVazio() {
    final pesquisando = _pesquisaController.text.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: carregarFotos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          Icon(
            pesquisando
                ? Icons.search_off_outlined
                : Icons.photo_library_outlined,
            size: 80,
            color: Colors.white38,
          ),
          const SizedBox(height: 18),
          Text(
            pesquisando
                ? 'Nenhum resultado encontrado'
                : 'Nenhuma foto cadastrada',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            pesquisando
                ? 'Tente pesquisar outro cliente, veículo ou placa.'
                : 'Toque no botão + para adicionar fotos de antes e depois.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  String _formatarData(String valor) {
    if (valor.trim().isEmpty) {
      return '';
    }

    final data = DateTime.tryParse(valor);

    if (data == null) {
      return valor;
    }

    return _data.format(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos Antes e Depois')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _pesquisaController,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar cliente, veículo ou placa',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _pesquisaController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _pesquisaController.clear();
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${fotosFiltradas.length} registro${fotosFiltradas.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'Todos',
                          label: Text('Todos'),
                        ),
                        ButtonSegment<String>(
                          value: 'Antes',
                          label: Text('Antes'),
                        ),
                        ButtonSegment<String>(
                          value: 'Depois',
                          label: Text('Depois'),
                        ),
                      ],
                      selected: {filtroTipo},
                      onSelectionChanged: (valores) {
                        setState(() {
                          filtroTipo = valores.first;
                        });

                        filtrarFotos();
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: fotosFiltradas.isEmpty
                      ? criarEstadoVazio()
                      : RefreshIndicator(
                          onRefresh: carregarFotos,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            itemCount: fotosFiltradas.length,
                            separatorBuilder: (context, index) {
                              return const SizedBox(height: 14);
                            },
                            itemBuilder: (context, index) {
                              return criarCardFoto(fotosFiltradas[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: abrindoCadastro ? null : novaFoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Adicionar'),
      ),
    );
  }
}
