import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_fotos_service.dart';
import 'imperium_web_theme.dart';

class WebFotosPage extends StatefulWidget {
  const WebFotosPage({super.key});

  @override
  State<WebFotosPage> createState() => _WebFotosPageState();
}

class _WebFotosPageState extends State<WebFotosPage> {
  final _service = WebFotosService.instance;
  final _busca = TextEditingController();
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  bool _carregando = true;
  String? _erro;
  WebFotosPacote? _pacote;
  String _tipo = 'Todas';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pacote = await _service.carregar();
      if (!mounted) return;
      setState(() => _pacote = pacote);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _novoAntesDepois() async {
    final pacote = _pacote;
    if (pacote == null || pacote.clientes.isEmpty || pacote.veiculos.isEmpty) {
      _snack(
        'Cadastre cliente e veículo antes de adicionar fotos.',
        erro: true,
      );
      return;
    }

    var clienteId = pacote.clientes.first['id'].toString();
    var veiculos = pacote.veiculos
        .where((e) => e['cliente_id'].toString() == clienteId)
        .toList();
    if (veiculos.isEmpty) {
      _snack('O primeiro cliente não possui veículo cadastrado.', erro: true);
      return;
    }
    var veiculoId = veiculos.first['id'].toString();
    final descricao = TextEditingController();
    DateTime data = DateTime.now();
    PlatformFile? antes;
    PlatformFile? depois;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          veiculos = pacote.veiculos
              .where((e) => e['cliente_id'].toString() == clienteId)
              .toList();
          if (!veiculos.any((e) => e['id'].toString() == veiculoId)) {
            veiculoId = veiculos.isEmpty ? '' : veiculos.first['id'].toString();
          }

          return AlertDialog(
            title: const Text('Novo Antes e Depois'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: clienteId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Cliente',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      items: pacote.clientes
                          .map(
                            (e) => DropdownMenuItem(
                              value: e['id'].toString(),
                              child: Text((e['nome'] ?? 'Cliente').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          clienteId = v;
                          final lista = pacote.veiculos
                              .where((e) => e['cliente_id'].toString() == v)
                              .toList();
                          veiculoId = lista.isEmpty
                              ? ''
                              : lista.first['id'].toString();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey('foto-veiculo-' + clienteId),
                      initialValue: veiculoId.isEmpty ? null : veiculoId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Veículo',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      items: veiculos
                          .map(
                            (e) => DropdownMenuItem(
                              value: e['id'].toString(),
                              child: Text(_veiculo(e)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setLocal(() => veiculoId = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final escolhida = await showDatePicker(
                          context: context,
                          initialDate: data,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (escolhida != null) {
                          setLocal(() => data = escolhida);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                        child: Text(_data.format(data)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descricao,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _ArquivoEscolha(
                            titulo: 'Foto Antes *',
                            arquivo: antes?.name,
                            icon: Icons.photo_camera_back_outlined,
                            onTap: () async {
                              final resultado = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.image,
                                    withData: true,
                                  );
                              if (resultado != null) {
                                setLocal(() => antes = resultado.files.single);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ArquivoEscolha(
                            titulo: 'Foto Depois',
                            arquivo: depois?.name,
                            icon: Icons.photo_camera_front_outlined,
                            onTap: () async {
                              final resultado = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.image,
                                    withData: true,
                                  );
                              if (resultado != null) {
                                setLocal(() => depois = resultado.files.single);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  veiculoId.isNotEmpty &&
                      antes != null &&
                      (antes!.bytes?.isNotEmpty ?? false),
                ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Salvar fotos'),
              ),
            ],
          );
        },
      ),
    );

    if (salvar != true || antes?.bytes == null) return;

    try {
      await _service.criarAntesDepois(
        clienteId: clienteId,
        veiculoId: veiculoId,
        descricao: descricao.text,
        data: _data.format(data),
        antesBytes: antes!.bytes!,
        antesNome: antes!.name,
        depoisBytes: depois?.bytes,
        depoisNome: depois?.name ?? '',
      );
      await _carregar();
      _snack('Fotos salvas no Cloud.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pacote = _pacote;
    if (_carregando && pacote == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && pacote == null) {
      return Center(child: Text(_erro!));
    }

    final dados = pacote!;
    final clientes = {
      for (final e in dados.clientes)
        e['id'].toString(): (e['nome'] ?? 'Cliente').toString(),
    };
    final veiculos = {
      for (final e in dados.veiculos) e['id'].toString(): _veiculo(e),
    };
    final ordens = {for (final e in dados.ordens) e['id'].toString(): e};

    final termo = _busca.text.trim().toLowerCase();

    final gerais = dados.gerais.where((e) {
      if (_tipo == 'OS') return false;
      final textos = [
        clientes[e['cliente_id']?.toString()] ?? '',
        veiculos[e['veiculo_id']?.toString()] ?? '',
        e['descricao'],
        e['data'],
      ];
      return termo.isEmpty ||
          textos.any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    final fotosOs = dados.fotosOs.where((e) {
      if (_tipo == 'Antes/Depois') return false;
      final ordem = ordens[e['ordem_servico_id']?.toString()] ?? const {};
      final textos = [
        ordem['numero'],
        clientes[ordem['cliente_id']?.toString()] ?? '',
        veiculos[ordem['veiculo_id']?.toString()] ?? '',
        e['descricao'],
        e['etapa'],
      ];
      return termo.isEmpty ||
          textos.any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final largura = constraints.maxWidth - (compacto ? 32 : 48);
        final colunas = constraints.maxWidth >= 1250
            ? 3
            : constraints.maxWidth >= 760
            ? 2
            : 1;
        final cardWidth = (largura - 12 * (colunas - 1)) / colunas;

        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compacto ? 16 : 24,
              compacto ? 18 : 24,
              compacto ? 16 : 24,
              40,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fotos',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Galeria geral Antes/Depois e imagens sincronizadas das ordens de serviço.',
                          style: TextStyle(color: Color(0xFFAAB3BD)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _novoAntesDepois,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(compacto ? 'Nova' : 'Novo Antes/Depois'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ResumoFotos(
                    width: cardWidth,
                    titulo: 'Antes/Depois',
                    valor: dados.gerais.length.toString(),
                    icon: Icons.compare_outlined,
                  ),
                  _ResumoFotos(
                    width: cardWidth,
                    titulo: 'Fotos de OS',
                    valor: dados.fotosOs.length.toString(),
                    icon: Icons.photo_library_outlined,
                  ),
                  _ResumoFotos(
                    width: cardWidth,
                    titulo: 'Total de registros',
                    valor: (dados.gerais.length + dados.fotosOs.length)
                        .toString(),
                    icon: Icons.collections_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: compacto ? largura - 28 : 420,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText:
                                'Buscar cliente, veículo, OS ou descrição',
                            suffixIcon: _busca.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _busca.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Todas', label: Text('Todas')),
                          ButtonSegment(
                            value: 'Antes/Depois',
                            label: Text('Antes/Depois'),
                          ),
                          ButtonSegment(value: 'OS', label: Text('OS')),
                        ],
                        selected: {_tipo},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) =>
                            setState(() => _tipo = v.first),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (gerais.isEmpty && fotosOs.isEmpty)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 42),
                    child: Center(child: Text('Nenhuma foto encontrada.')),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ...gerais.map(
                      (e) => SizedBox(
                        width: cardWidth,
                        child: _AntesDepoisCard(
                          item: e,
                          cliente:
                              clientes[e['cliente_id']?.toString()] ??
                              'Cliente',
                          veiculo:
                              veiculos[e['veiculo_id']?.toString()] ??
                              'Veículo',
                          service: _service,
                        ),
                      ),
                    ),
                    ...fotosOs.map((e) {
                      final ordem =
                          ordens[e['ordem_servico_id']?.toString()] ?? const {};
                      return SizedBox(
                        width: cardWidth,
                        child: _FotoOsCard(
                          item: e,
                          numero: (ordem['numero'] ?? '').toString(),
                          cliente:
                              clientes[ordem['cliente_id']?.toString()] ?? '',
                          veiculo:
                              veiculos[ordem['veiculo_id']?.toString()] ?? '',
                          service: _service,
                        ),
                      );
                    }),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  void _snack(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static String _veiculo(Map<String, dynamic> v) {
    return [
      (v['marca'] ?? '').toString(),
      (v['modelo'] ?? '').toString(),
      (v['placa'] ?? '').toString(),
    ].where((e) => e.trim().isNotEmpty).join(' ');
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}

class _ImagemCloud extends StatelessWidget {
  const _ImagemCloud({
    required this.service,
    required this.bucket,
    required this.path,
    this.altura = 180,
  });

  final WebFotosService service;
  final String bucket;
  final String path;
  final double altura;

  @override
  Widget build(BuildContext context) {
    if (path.trim().isEmpty) {
      return Container(
        height: altura,
        alignment: Alignment.center,
        color: ImperiumWebTheme.surfaceRaised,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return FutureBuilder<Uint8List>(
      future: service.baixar(bucket: bucket, storagePath: path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            height: altura,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!.isEmpty) {
          return SizedBox(
            height: altura,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        return Image.memory(
          snapshot.data!,
          height: altura,
          width: double.infinity,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

class _AntesDepoisCard extends StatelessWidget {
  const _AntesDepoisCard({
    required this.item,
    required this.cliente,
    required this.veiculo,
    required this.service,
  });

  final Map<String, dynamic> item;
  final String cliente;
  final String veiculo;
  final WebFotosService service;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text(
                        'ANTES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _ImagemCloud(
                      service: service,
                      bucket:
                          (item['antes_storage_bucket'] ??
                                  WebFotosService.bucketGaleria)
                              .toString(),
                      path: (item['antes_storage_path'] ?? '').toString(),
                      altura: 160,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Text(
                        'DEPOIS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _ImagemCloud(
                      service: service,
                      bucket:
                          (item['depois_storage_bucket'] ??
                                  WebFotosService.bucketGaleria)
                              .toString(),
                      path: (item['depois_storage_path'] ?? '').toString(),
                      altura: 160,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(veiculo, style: const TextStyle(color: Color(0xFFAAB3BD))),
                if ((item['descricao'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text((item['descricao'] ?? '').toString()),
                  ),
                if ((item['data'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      (item['data'] ?? '').toString(),
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FotoOsCard extends StatelessWidget {
  const _FotoOsCard({
    required this.item,
    required this.numero,
    required this.cliente,
    required this.veiculo,
    required this.service,
  });

  final Map<String, dynamic> item;
  final String numero;
  final String cliente;
  final String veiculo;
  final WebFotosService service;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImagemCloud(
            service: service,
            bucket: (item['storage_bucket'] ?? 'imperium-os-arquivos')
                .toString(),
            path: (item['storage_path'] ?? '').toString(),
            altura: 210,
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  numero.isEmpty ? 'Foto de OS' : 'OS ' + numero,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  [
                    cliente,
                    veiculo,
                    (item['etapa'] ?? '').toString(),
                  ].where((e) => e.trim().isNotEmpty).join(' · '),
                  style: const TextStyle(color: Color(0xFFAAB3BD)),
                ),
                if ((item['descricao'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text((item['descricao'] ?? '').toString()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArquivoEscolha extends StatelessWidget {
  const _ArquivoEscolha({
    required this.titulo,
    required this.arquivo,
    required this.icon,
    required this.onTap,
  });

  final String titulo;
  final String? arquivo;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              arquivo == null ? titulo : arquivo!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoFotos extends StatelessWidget {
  const _ResumoFotos({
    required this.width,
    required this.titulo,
    required this.valor,
    required this.icon,
  });

  final double width;
  final String titulo;
  final String valor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
