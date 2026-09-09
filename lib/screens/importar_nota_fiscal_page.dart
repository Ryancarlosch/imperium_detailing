import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_entrada_xml_service.dart';
import 'chave_fiscal_manual_page.dart';
import 'chave_fiscal_scanner_page.dart';
import 'integrar_nota_fiscal_page.dart';
import 'nota_fiscal_financeiro_page.dart';

class ImportarNotaFiscalPage extends StatefulWidget {
  const ImportarNotaFiscalPage({super.key});

  @override
  State<ImportarNotaFiscalPage> createState() => _ImportarNotaFiscalPageState();
}

class _ImportarNotaFiscalPageState extends State<ImportarNotaFiscalPage> {
  final NotaFiscalEntradaRepository _repository = NotaFiscalEntradaRepository();
  late final NotaFiscalEntradaXmlService _xmlService;

  String _filtro = 'todos';
  bool _carregando = true;
  List<NotaFiscalEntrada> _notas = const [];

  @override
  void initState() {
    super.initState();
    _xmlService = NotaFiscalEntradaXmlService(repository: _repository);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final notas = await _repository.listar(
        statusImportacao: _filtro == 'todos' ? null : _filtro,
      );
      if (!mounted) return;
      setState(() {
        _notas = notas;
        _carregando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar as notas: $error', erro: true);
    }
  }

  Future<void> _selecionarXml() async {
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        withData: true,
      );
      if (resultado == null ||
          (resultado.files.single.path == null &&
              resultado.files.single.bytes == null)) {
        return;
      }

      final arquivo = resultado.files.single;
      final conteudo = arquivo.bytes != null
          ? utf8.decode(arquivo.bytes!, allowMalformed: false)
          : await File(arquivo.path!).readAsString();
      final parsed = _xmlService.parsear(conteudo);
      final existente = await _repository.buscarPorChave(
        parsed.nota.chaveAcesso,
      );
      if (!mounted) return;

      final confirmar = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _NotaPreview(
          nota: parsed.nota,
          itens: parsed.itens,
          jaExiste: existente != null,
        ),
      );
      if (confirmar != true) return;

      await _xmlService.importarXml(conteudo);
      if (!mounted) return;
      _mensagem(
        existente == null
            ? 'Nota XML importada com sucesso.'
            : 'XML processado e nota existente atualizada sem duplicar.',
      );
      await _carregar();
    } catch (error) {
      if (mounted) {
        _mensagem('Não foi possível importar o XML: $error', erro: true);
      }
    }
  }

  Future<void> _abrirScanner() async {
    final nota = await Navigator.push<NotaFiscalEntrada>(
      context,
      MaterialPageRoute(builder: (_) => const ChaveFiscalScannerPage()),
    );
    if (!mounted || nota == null) return;

    if (nota.statusImportacao == 'processada') {
      final itens = nota.id == null
          ? const <NotaFiscalEntradaItem>[]
          : await _repository.listarItensDaNota(nota.id!);
      if (!mounted) return;
      final total = nota.valorTotal == null
          ? ''
          : ' · R\$ ${nota.valorTotal!.toStringAsFixed(2)}';
      _mensagem(
        'NFC-e consultada: ${nota.emitenteNome ?? 'fornecedor'} · '
        '${itens.length} itens$total.',
      );
    } else {
      final modelo = nota.chaveAcesso.length >= 22
          ? int.tryParse(nota.chaveAcesso.substring(20, 22))
          : null;
      _mensagem(
        modelo == 55
            ? 'NF-e identificada pela chave. Para trazer os itens sem XML, '
                  'será necessária a consulta DF-e autorizada da empresa.'
            : 'Chave registrada, mas o portal não entregou os dados completos. '
                  'Escaneie novamente o QR Code para tentar a consulta automática.',
      );
    }
    await _carregar();
  }

  Future<void> _abrirManual() async {
    final nota = await Navigator.push<NotaFiscalEntrada>(
      context,
      MaterialPageRoute(builder: (_) => const ChaveFiscalManualPage()),
    );
    if (!mounted || nota == null) return;
    _mensagem('Chave registrada como pendente. Adicione o XML para completar.');
    await _carregar();
  }

  bool _permiteMovimentar(NotaFiscalEntrada nota) =>
      !{'cancelada', 'denegada', 'inutilizada'}.contains(nota.situacaoFiscal);

  void _mensagem(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Nota Fiscal'),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _AcaoFiscal(
                    icone: Icons.upload_file_outlined,
                    titulo: 'Importar XML',
                    onTap: _selecionarXml,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AcaoFiscal(
                    icone: Icons.qr_code_scanner,
                    titulo: 'Ler e importar',
                    onTap: _abrirScanner,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AcaoFiscal(
                    icone: Icons.keyboard_outlined,
                    titulo: 'Digitar chave',
                    onTap: _abrirManual,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'todos', label: Text('Todas')),
                ButtonSegment(value: 'pendente', label: Text('Pendentes')),
                ButtonSegment(value: 'processada', label: Text('Processadas')),
                ButtonSegment(value: 'erro', label: Text('Erros')),
              ],
              selected: {_filtro},
              onSelectionChanged: (selecionado) {
                setState(() => _filtro = selecionado.first);
                _carregar();
              },
            ),
            const SizedBox(height: 16),
            if (_carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_notas.isEmpty)
              const _EstadoVazio()
            else
              ..._notas.map(
                (nota) =>
                    _NotaCard(nota: nota, onTap: () => _abrirDetalhes(nota)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirDetalhes(NotaFiscalEntrada nota) async {
    final itens = await _repository.listarItensDaNota(nota.id!);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NotaDetalhes(
        nota: nota,
        itens: itens,
        onAdicionarXml: nota.statusImportacao == 'pendente'
            ? () {
                Navigator.pop(context);
                _selecionarXml();
              }
            : null,
        onIntegrar:
            nota.statusImportacao == 'processada' && _permiteMovimentar(nota)
            ? () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        IntegrarNotaFiscalPage(nota: nota, itens: itens),
                  ),
                ).then((_) => _carregar());
              }
            : null,
        onFinanceiro:
            nota.statusImportacao == 'processada' && _permiteMovimentar(nota)
            ? () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotaFiscalFinanceiroPage(nota: nota),
                  ),
                ).then((_) => _carregar());
              }
            : null,
      ),
    );
  }
}

class _AcaoFiscal extends StatelessWidget {
  const _AcaoFiscal({
    required this.icone,
    required this.titulo,
    required this.onTap,
  });
  final IconData icone;
  final String titulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: onTap,
    icon: Icon(icone),
    label: Text(titulo, textAlign: TextAlign.center),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    ),
  );
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: Text('Nenhuma nota encontrada.')),
  );
}

class _NotaCard extends StatelessWidget {
  const _NotaCard({required this.nota, required this.onTap});
  final NotaFiscalEntrada nota;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: Icon(
        nota.statusImportacao == 'processada'
            ? Icons.check_circle_outline
            : Icons.pending_actions,
      ),
      title: Text(nota.emitenteNome ?? 'Emitente não informado'),
      subtitle: Text(
        'NF ${nota.numero ?? '-'} · ${nota.origemImportacao} · ${nota.statusImportacao}',
      ),
      trailing: Text(
        nota.valorTotal == null
            ? '-'
            : 'R\$ ${nota.valorTotal!.toStringAsFixed(2)}',
      ),
    ),
  );
}

class _NotaPreview extends StatelessWidget {
  const _NotaPreview({
    required this.nota,
    required this.itens,
    this.jaExiste = false,
  });
  final NotaFiscalEntrada nota;
  final List<NotaFiscalEntradaItem> itens;
  final bool jaExiste;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirmar importação',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (jaExiste)
          const Text(
            'Esta chave já está registrada. O mesmo registro será reaproveitado.',
          ),
        _ResumoNota(nota: nota, itens: itens),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}

class _NotaDetalhes extends StatelessWidget {
  const _NotaDetalhes({
    required this.nota,
    required this.itens,
    this.onAdicionarXml,
    this.onIntegrar,
    this.onFinanceiro,
  });
  final NotaFiscalEntrada nota;
  final List<NotaFiscalEntradaItem> itens;
  final VoidCallback? onAdicionarXml;
  final VoidCallback? onIntegrar;
  final VoidCallback? onFinanceiro;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .8,
    builder: (_, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.all(20),
      children: [
        Text('Nota fiscal', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        _ResumoNota(nota: nota, itens: itens),
        const Divider(height: 28),
        Text('Chave: ${nota.chaveAcesso}'),
        Text('Modelo: ${nota.modelo ?? '-'} · Série: ${nota.serie ?? '-'}'),
        Text('Situação: ${nota.situacaoFiscal}'),
        Text('Status: ${nota.statusImportacao}'),
        Text('Origem: ${nota.origemImportacao}'),
        if (onAdicionarXml != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onAdicionarXml,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Adicionar XML'),
          ),
        ],
        if (onIntegrar != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onIntegrar,
            icon: const Icon(Icons.link),
            label: const Text('Integrar fornecedor e estoque'),
          ),
        ],
        if (onFinanceiro != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onFinanceiro,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Financeiro da nota'),
          ),
        ],
        const SizedBox(height: 16),
        ...itens.map(
          (item) => ListTile(
            dense: true,
            title: Text('${item.numeroItem}. ${item.descricao}'),
            subtitle: Text(
              '${item.quantidade} ${item.unidade} · R\$ ${item.valorTotal.toStringAsFixed(2)}',
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResumoNota extends StatelessWidget {
  const _ResumoNota({required this.nota, required this.itens});
  final NotaFiscalEntrada nota;
  final List<NotaFiscalEntradaItem> itens;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(nota.emitenteNome ?? 'Emitente não informado'),
      Text('NF ${nota.numero ?? '-'} · ${nota.dataEmissao ?? '-'}'),
      Text(
        'Total: ${nota.valorTotal == null ? '-' : 'R\$ ${nota.valorTotal!.toStringAsFixed(2)}'}',
      ),
      Text('Itens: ${itens.length}'),
    ],
  );
}
