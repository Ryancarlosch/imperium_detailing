import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

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
  bool _salvando = false;

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

  Future<void> _executar(
    Future<void> Function() acao, {
    required String sucesso,
  }) async {
    if (_salvando) return;
    setState(() => _salvando = true);
    try {
      await acao();
      if (!mounted) return;
      await _atualizar();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(sucesso)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_textoErro(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _adicionarFoto() async {
    final descricao = TextEditingController();
    PlatformFile? arquivo;
    var etapa = 'Antes';

    final draft = await showDialog<_NovaFotoOs>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Adicionar foto à OS'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: etapa,
                  decoration: const InputDecoration(labelText: 'Etapa'),
                  items: const [
                    DropdownMenuItem(value: 'Antes', child: Text('Antes')),
                    DropdownMenuItem(value: 'Durante', child: Text('Durante')),
                    DropdownMenuItem(value: 'Depois', child: Text('Depois')),
                  ],
                  onChanged: (value) {
                    if (value != null) setLocal(() => etapa = value);
                  },
                ),
                const SizedBox(height: 12),
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
                OutlinedButton.icon(
                  onPressed: () async {
                    final resultado = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
                      withData: true,
                    );
                    if (resultado != null) {
                      setLocal(() => arquivo = resultado.files.single);
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(arquivo?.name ?? 'Selecionar imagem'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: arquivo?.bytes?.isNotEmpty == true
                  ? () => Navigator.pop(
                      dialogContext,
                      _NovaFotoOs(
                        etapa: etapa,
                        descricao: descricao.text,
                        arquivo: arquivo!,
                      ),
                    )
                  : null,
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    descricao.dispose();
    if (draft == null || draft.arquivo.bytes == null) return;

    await _executar(
      () => _service.adicionarFoto(
        ordemId: widget.ordemId,
        etapa: draft.etapa,
        descricao: draft.descricao,
        bytes: draft.arquivo.bytes!,
        nomeOriginal: draft.arquivo.name,
      ),
      sucesso: 'Foto enviada e sincronizada com o aplicativo.',
    );
  }

  Future<void> _editarChecklist([Map<String, dynamic>? atual]) async {
    final categoria = TextEditingController(
      text: (atual?['categoria'] ?? 'Geral').toString(),
    );
    final item = TextEditingController(text: (atual?['item'] ?? '').toString());
    final observacao = TextEditingController(
      text: (atual?['observacao'] ?? '').toString(),
    );
    final localizacao = TextEditingController(
      text: (atual?['avaria_localizacao'] ?? '').toString(),
    );
    var status = _int(atual?['status']);
    PlatformFile? arquivo;

    final draft = await showDialog<_ChecklistOsDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo item do checklist' : 'Checklist'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: categoria,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: item,
                    decoration: const InputDecoration(labelText: 'Item *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Situação'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Pendente')),
                      DropdownMenuItem(value: 1, child: Text('Conforme')),
                      DropdownMenuItem(value: 2, child: Text('Avaria')),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocal(() => status = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: observacao,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observação',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (status == 2) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: localizacao,
                      decoration: const InputDecoration(
                        labelText: 'Localização da avaria',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final resultado = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const [
                            'jpg',
                            'jpeg',
                            'png',
                            'webp',
                          ],
                          withData: true,
                        );
                        if (resultado != null) {
                          setLocal(() => arquivo = resultado.files.single);
                        }
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        arquivo?.name ??
                            ((atual?['foto_avaria_storage_path'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty
                                ? 'Substituir foto da avaria'
                                : 'Adicionar foto da avaria'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _ChecklistOsDraft(
                  categoria: categoria.text,
                  item: item.text,
                  status: status,
                  observacao: observacao.text,
                  localizacaoAvaria: localizacao.text,
                  arquivo: arquivo,
                ),
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    categoria.dispose();
    item.dispose();
    observacao.dispose();
    localizacao.dispose();
    if (draft == null) return;

    await _executar(
      () => _service.salvarChecklist(
        ordemId: widget.ordemId,
        atual: atual,
        categoria: draft.categoria,
        item: draft.item,
        status: draft.status,
        observacao: draft.observacao,
        localizacaoAvaria: draft.localizacaoAvaria,
        fotoBytes: draft.arquivo?.bytes,
        fotoNome: draft.arquivo?.name ?? '',
      ),
      sucesso: 'Checklist salvo e sincronizado com o aplicativo.',
    );
  }

  Future<void> _assinar(Map<String, dynamic> ordem) async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      exportPenColor: Colors.black,
    );

    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assinatura do cliente'),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Assine no campo abaixo. Ao salvar, a assinatura ficará disponível também no aplicativo.',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF89939E)),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Signature(
                  controller: controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: controller.clear,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Limpar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.isEmpty) return;
              final png = await controller.toPngBytes();
              if (png != null && dialogContext.mounted) {
                Navigator.pop(dialogContext, png);
              }
            },
            child: const Text('Salvar assinatura'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (bytes == null || bytes.isEmpty) return;

    await _executar(
      () => _service.salvarAssinatura(
        ordemId: widget.ordemId,
        atualizadoEm: (ordem['atualizado_em'] ?? '').toString(),
        bytes: bytes,
      ),
      sucesso: 'Assinatura salva e sincronizada com o aplicativo.',
    );
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
          final checklist = (dados['checklist'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final ordem = Map<String, dynamic>.from(
            dados['ordem'] as Map? ?? const <String, dynamic>{},
          );
          final status = (ordem['status'] ?? '').toString().trim();
          final editavel = status == 'Aberta' || status == 'Em andamento';

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
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (editavel)
                                    FilledButton.tonalIcon(
                                      onPressed: _salvando
                                          ? null
                                          : _adicionarFoto,
                                      icon: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                      ),
                                      label: const Text('Adicionar foto'),
                                    ),
                                  if (editavel)
                                    FilledButton.tonalIcon(
                                      onPressed: _salvando
                                          ? null
                                          : () => _editarChecklist(),
                                      icon: const Icon(
                                        Icons.checklist_outlined,
                                      ),
                                      label: const Text('Checklist'),
                                    ),
                                  if (editavel)
                                    FilledButton.icon(
                                      onPressed: _salvando
                                          ? null
                                          : () => _assinar(ordem),
                                      icon: const Icon(Icons.draw_outlined),
                                      label: const Text('Assinar'),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: _baixarPdf,
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: const Text('Gerar PDF'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (compacto && editavel) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _salvando ? null : _adicionarFoto,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('Adicionar foto'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _salvando
                                ? null
                                : () => _editarChecklist(),
                            icon: const Icon(Icons.checklist_outlined),
                            label: const Text('Checklist'),
                          ),
                          FilledButton.icon(
                            onPressed: _salvando ? null : () => _assinar(ordem),
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('Assinar'),
                          ),
                        ],
                      ),
                    ],
                    if (_salvando) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.sync_lock_outlined,
                              color: ImperiumWebTheme.accentStrong,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                editavel
                                    ? 'Alterações feitas aqui usam o mesmo Storage privado e ficam disponíveis no mobile após a sincronização.'
                                    : 'Esta OS está $status e permanece somente para consulta. Os arquivos continuam protegidos pelas permissões da empresa.',
                                style: const TextStyle(
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
                            'Checklist da OS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${checklist.length} item(ns)',
                          style: const TextStyle(
                            color: Color(0xFF89939E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (checklist.isEmpty)
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 26,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.checklist_outlined,
                                size: 34,
                                color: Color(0xFF89939E),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  'Nenhum item cadastrado neste checklist.',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (editavel && !compacto)
                                FilledButton.tonal(
                                  onPressed: _salvando
                                      ? null
                                      : () => _editarChecklist(),
                                  child: const Text('Adicionar'),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: checklist
                            .map(
                              (item) => SizedBox(
                                width: larguraArquivo,
                                child: _ChecklistCard(
                                  item: item,
                                  editavel: editavel && !_salvando,
                                  onEditar: () => _editarChecklist(item),
                                ),
                              ),
                            )
                            .toList(),
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

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.item,
    required this.editavel,
    required this.onEditar,
  });

  final Map<String, dynamic> item;
  final bool editavel;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final status = _int(item['status']);
    final titulo = (item['item'] ?? 'Item do checklist').toString();
    final categoria = (item['categoria'] ?? 'Geral').toString().trim();
    final observacao = (item['observacao'] ?? '').toString().trim();
    final localizacao = (item['avaria_localizacao'] ?? '').toString().trim();
    final (rotulo, cor, icone) = switch (status) {
      1 => ('Conforme', Colors.green, Icons.check_circle_outline),
      2 => ('Avaria', Colors.redAccent, Icons.warning_amber_rounded),
      _ => ('Pendente', Colors.orange, Icons.schedule_outlined),
    };

    return Card(
      child: ListTile(
        leading: Icon(icone, color: cor),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (categoria.isNotEmpty) categoria,
            rotulo,
            if (localizacao.isNotEmpty) localizacao,
            if (observacao.isNotEmpty) observacao,
          ].join(' · '),
        ),
        trailing: editavel
            ? IconButton(
                tooltip: 'Editar item',
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
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

class _NovaFotoOs {
  const _NovaFotoOs({
    required this.etapa,
    required this.descricao,
    required this.arquivo,
  });

  final String etapa;
  final String descricao;
  final PlatformFile arquivo;
}

class _ChecklistOsDraft {
  const _ChecklistOsDraft({
    required this.categoria,
    required this.item,
    required this.status,
    required this.observacao,
    required this.localizacaoAvaria,
    required this.arquivo,
  });

  final String categoria;
  final String item;
  final int status;
  final String observacao;
  final String localizacaoAvaria;
  final PlatformFile? arquivo;
}

int _int(dynamic valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse((valor ?? '').toString()) ?? 0;
}

String _textoErro(Object erro) {
  return erro
      .toString()
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .split(', code:')
      .first
      .trim();
}
