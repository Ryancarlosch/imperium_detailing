import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/web_os_arquivos_service.dart';
import '../services/web_os_pdf_service.dart';
import 'imperium_web_theme.dart';

class WebOsArquivosPage extends StatefulWidget {
  const WebOsArquivosPage({
    required this.ordemId,
    required this.numero,
    super.key,
  });

  final String ordemId;
  final String numero;

  @override
  State<WebOsArquivosPage> createState() => _WebOsArquivosPageState();
}

class _WebOsArquivosPageState extends State<WebOsArquivosPage> {
  final _service = WebOsArquivosService.instance;
  final _pdfService = WebOsPdfService.instance;

  late Future<Map<String, dynamic>> _dados;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  void _recarregar() {
    _dados = _service.carregar(widget.ordemId);
  }

  Future<void> _atualizar() async {
    setState(_recarregar);
    await _dados;
  }

  Future<void> _baixarPdf() async {
    try {
      await _pdfService.baixarPdf(
        ordemId: widget.ordemId,
        numero: widget.numero,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('PDF da OS gerado com sucesso.')),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Não foi possível gerar o PDF: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.numero.trim().isEmpty
        ? 'Arquivos da OS'
        : 'Arquivos da OS ${widget.numero}';

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(
            tooltip: 'Baixar PDF da OS',
            onPressed: _baixarPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar arquivos',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dados,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErroArquivos(
              erro: snapshot.error.toString(),
              onTentarNovamente: _atualizar,
            );
          }

          final dados = snapshot.data ?? const <String, dynamic>{};
          final arquivos = (dados['arquivos'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 760;
              final larguraDisponivel =
                  constraints.maxWidth - (compacto ? 32 : 48);
              final colunasResumo = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              final larguraResumo =
                  (larguraDisponivel - (12 * (colunasResumo - 1))) /
                  colunasResumo;
              final colunasArquivos = constraints.maxWidth >= 1180 ? 2 : 1;
              final larguraArquivo =
                  (larguraDisponivel - (12 * (colunasArquivos - 1))) /
                  colunasArquivos;

              return RefreshIndicator(
                onRefresh: _atualizar,
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
                                'Fotos, avarias e assinatura',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Arquivos privados da OS, protegidos pelas permissões da empresa.',
                                style: TextStyle(color: Color(0xFFAAB3BD)),
                              ),
                            ],
                          ),
                        ),
                        if (!compacto) ...[
                          const SizedBox(width: 14),
                          OutlinedButton.icon(
                            onPressed: _baixarPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Gerar PDF'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: ImperiumWebTheme.accentStrong,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'O Web apenas visualiza os arquivos sincronizados no Storage privado. '
                                'O envio continua seguindo as permissões e o fluxo operacional da empresa.',
                                style: TextStyle(
                                  color: Color(0xFF89939E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ResumoArquivo(
                          width: larguraResumo,
                          icone: Icons.photo_library_outlined,
                          titulo: 'Fotos da OS',
                          valor: '${dados['total_fotos'] ?? 0}',
                        ),
                        _ResumoArquivo(
                          width: larguraResumo,
                          icone: Icons.car_crash_outlined,
                          titulo: 'Fotos de avaria',
                          valor: '${dados['total_avarias'] ?? 0}',
                        ),
                        _ResumoArquivo(
                          width: larguraResumo,
                          icone: Icons.draw_outlined,
                          titulo: 'Assinatura',
                          valor: dados['tem_assinatura'] == true
                              ? 'Disponível'
                              : 'Pendente',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Arquivos sincronizados',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${arquivos.length} arquivo(s)',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (arquivos.isEmpty)
                      const Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 38,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 42,
                                color: Color(0xFF89939E),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Nenhum arquivo sincronizado para esta OS',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Quando fotos, avarias ou assinatura forem sincronizadas, elas aparecerão aqui.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFFAAB3BD)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: arquivos
                            .map(
                              (arquivo) => SizedBox(
                                width: larguraArquivo,
                                child: _ArquivoCard(
                                  arquivo: arquivo,
                                  onAbrir: () => _abrirArquivo(arquivo),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _abrirArquivo(Map<String, dynamic> arquivo) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (arquivo['titulo'] ?? 'Arquivo da OS').toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<Uint8List>(
                  future: _service.baixar(arquivo),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError ||
                        snapshot.data == null ||
                        snapshot.data!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            snapshot.hasError
                                ? 'Não foi possível abrir o arquivo: ${snapshot.error}'
                                : 'O arquivo está vazio.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Este arquivo não pôde ser exibido como imagem.',
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumoArquivo extends StatelessWidget {
  const _ResumoArquivo({
    required this.width,
    required this.icone,
    required this.titulo,
    required this.valor,
  });

  final double width;

  final IconData icone;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icone, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
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

class _ArquivoCard extends StatelessWidget {
  const _ArquivoCard({required this.arquivo, required this.onAbrir});

  final Map<String, dynamic> arquivo;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final tipo = (arquivo['tipo'] ?? '').toString();
    final descricao = (arquivo['descricao'] ?? '').toString().trim();
    final nome = (arquivo['nome'] ?? '').toString().trim();
    final data = (arquivo['data'] ?? '').toString().trim();

    final icone = switch (tipo) {
      'assinatura' => Icons.draw_outlined,
      'avaria' => Icons.car_crash_outlined,
      _ => Icons.photo_outlined,
    };

    return Card(
      child: ListTile(
        leading: Icon(icone),
        title: Text((arquivo['titulo'] ?? 'Arquivo da OS').toString()),
        subtitle: Text(
          [
            if (descricao.isNotEmpty) descricao,
            if (nome.isNotEmpty) nome,
            if (data.isNotEmpty) data,
          ].join(' · '),
        ),
        trailing: FilledButton.tonalIcon(
          onPressed: onAbrir,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Abrir'),
        ),
      ),
    );
  }
}

class _ErroArquivos extends StatelessWidget {
  const _ErroArquivos({required this.erro, required this.onTentarNovamente});

  final String erro;
  final Future<void> Function() onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 42,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Não foi possível carregar os arquivos da OS.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(erro, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onTentarNovamente,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
