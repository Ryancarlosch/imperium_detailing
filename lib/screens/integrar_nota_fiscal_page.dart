import 'package:flutter/material.dart';

import '../models/item_estoque.dart';
import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';
import '../repositories/estoque_repository.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_entrada_integracao_service.dart';

class IntegrarNotaFiscalPage extends StatefulWidget {
  const IntegrarNotaFiscalPage({
    super.key,
    required this.nota,
    required this.itens,
  });

  final NotaFiscalEntrada nota;
  final List<NotaFiscalEntradaItem> itens;

  @override
  State<IntegrarNotaFiscalPage> createState() => _IntegrarNotaFiscalPageState();
}

class _IntegrarNotaFiscalPageState extends State<IntegrarNotaFiscalPage> {
  late final NotaFiscalEntradaIntegracaoService _service;
  final EstoqueRepository _estoqueRepository = EstoqueRepository();
  final NotaFiscalEntradaRepository _notaRepository =
      NotaFiscalEntradaRepository();
  List<ItemEstoque> _estoque = const [];
  int? _fornecedorId;
  final Map<int, int> _vinculos = {};
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _service = NotaFiscalEntradaIntegracaoService(
      notaRepository: _notaRepository,
    );
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      _estoque = await _estoqueRepository.listarItens();
      _fornecedorId = widget.nota.fornecedorId;
      _fornecedorId ??= await _service.fornecedorExistentePorDocumento(
        widget.nota.emitenteCnpjCpf ?? '',
      );
      if (_fornecedorId != null &&
          widget.nota.fornecedorId != _fornecedorId &&
          widget.nota.id != null) {
        await _service.vincularFornecedorDaNota(
          notaFiscalId: widget.nota.id!,
          fornecedorId: _fornecedorId!,
        );
      }
      for (final item in widget.itens) {
        if (item.id == null) continue;
        if (item.estoqueItemId != null) {
          _vinculos[item.id!] = item.estoqueItemId!;
          continue;
        }
        var candidatos = await _service.localizarItensPorEan(item.ean ?? '');
        if (candidatos.isEmpty) {
          candidatos = await _service.localizarItensPorDescricaoExata(
            item.descricao,
          );
        }
        if (candidatos.length == 1) {
          _vinculos[item.id!] = candidatos.single;
        }
      }
    } catch (error) {
      if (mounted) _mensagem('$error', erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _criarFornecedor() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cadastrar fornecedor?'),
        content: Text(
          'Usar o emitente fiscal "${widget.nota.emitenteNome ?? '-'}" '
          'com documento ${widget.nota.emitenteCnpjCpf ?? '-'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final id = await _service.criarFornecedorConfirmado(
        nome: widget.nota.emitenteNome ?? '',
        documento: widget.nota.emitenteCnpjCpf ?? '',
      );
      await _service.vincularFornecedorDaNota(
        notaFiscalId: widget.nota.id!,
        fornecedorId: id,
      );
      if (mounted) setState(() => _fornecedorId = id);
    } catch (error) {
      _mensagem('$error', erro: true);
    }
  }

  Future<int> _criarItemSemRecarregar(NotaFiscalEntradaItem fiscal) async {
    final agora = DateTime.now().toIso8601String();
    final id = await _estoqueRepository.inserirItem(
      ItemEstoque(
        nome: fiscal.descricao,
        categoria: 'Importado fiscal',
        quantidade: 0,
        quantidadeMinima: 0,
        unidade: fiscal.unidade,
        ean: fiscal.ean ?? '',
        custoUnitario: 0,
        fornecedor: widget.nota.emitenteNome ?? '',
        observacoes: 'Criado para vínculo da nota ${widget.nota.chaveAcesso}',
        atualizadoEm: agora,
      ),
    );
    await _service.vincularItemFiscal(
      itemFiscalId: fiscal.id!,
      estoqueItemId: id,
    );
    return id;
  }

  Future<void> _criarItem(NotaFiscalEntradaItem fiscal) async {
    try {
      final id = await _criarItemSemRecarregar(fiscal);
      await _carregar();
      if (mounted) setState(() => _vinculos[fiscal.id!] = id);
    } catch (error) {
      _mensagem('$error', erro: true);
    }
  }

  Future<void> _prepararVinculosFaltantes() async {
    final pendentes = widget.itens
        .where((item) => item.id != null && !_vinculos.containsKey(item.id))
        .toList();
    final precisaFornecedor = _fornecedorId == null;
    if (pendentes.isEmpty && !precisaFornecedor) {
      _mensagem('Fornecedor e itens já estão vinculados.');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Preparar vínculos automaticamente?'),
        content: Text(
          '${precisaFornecedor ? 'O fornecedor será cadastrado a partir dos dados fiscais.\n' : ''}'
          '${pendentes.isEmpty ? '' : '${pendentes.length} item(ns) sem correspondência exata serão criados no estoque.\n'}'
          'Nenhuma quantidade entra no estoque até você confirmar a entrada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Preparar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _salvando = true);
    try {
      if (precisaFornecedor) {
        final id = await _service.criarFornecedorConfirmado(
          nome: widget.nota.emitenteNome ?? '',
          documento: widget.nota.emitenteCnpjCpf ?? '',
        );
        await _service.vincularFornecedorDaNota(
          notaFiscalId: widget.nota.id!,
          fornecedorId: id,
        );
        _fornecedorId = id;
      }

      for (final fiscal in pendentes) {
        final id = await _criarItemSemRecarregar(fiscal);
        _vinculos[fiscal.id!] = id;
      }
      await _carregar();
      if (mounted) {
        setState(() => _salvando = false);
        _mensagem('Vínculos fiscais preparados. Revise e confirme a entrada.');
      }
    } catch (error) {
      if (mounted) setState(() => _salvando = false);
      _mensagem('$error', erro: true);
    }
  }

  Future<void> _confirmarEstoque() async {
    if (_vinculos.length != widget.itens.length) {
      _mensagem('Vincule todos os itens antes de confirmar.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      for (final item in widget.itens) {
        await _service.vincularItemFiscal(
          itemFiscalId: item.id!,
          estoqueItemId: _vinculos[item.id!]!,
        );
      }
      await _service.confirmarEntradaEstoque(widget.nota.id!);
      if (mounted) {
        _mensagem('Entrada de estoque confirmada.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _salvando = false);
        _mensagem('$error', erro: true);
      }
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red[700] : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar integração fiscal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.nota.emitenteNome ?? 'Emitente não informado'),
            subtitle: Text(
              widget.nota.emitenteCnpjCpf ?? 'Documento não informado',
            ),
            trailing: _fornecedorId == null
                ? OutlinedButton(
                    onPressed: _criarFornecedor,
                    child: const Text('Cadastrar'),
                  )
                : const Chip(label: Text('Fornecedor vinculado')),
          ),
          const Divider(),
          ...widget.itens.map(_itemTile),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _salvando ? null : _prepararVinculosFaltantes,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Criar vínculos faltantes'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _salvando ? null : _confirmarEstoque,
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(
              _salvando ? 'Confirmando...' : 'Confirmar entrada no estoque',
            ),
          ),
          const SizedBox(height: 8),
          const Text('Nada é lançado no estoque até esta confirmação.'),
        ],
      ),
    );
  }

  Widget _itemTile(NotaFiscalEntradaItem fiscal) {
    final selecionado = _vinculos[fiscal.id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${fiscal.numeroItem}. ${fiscal.descricao}'),
            DropdownButton<int>(
              isExpanded: true,
              value: _estoque.any((item) => item.id == selecionado)
                  ? selecionado
                  : null,
              hint: Text(
                fiscal.ean == null
                    ? 'Selecionar item do estoque'
                    : 'Selecionar item/EAN',
              ),
              items: _estoque
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${item.nome}${item.ean.isEmpty ? '' : ' · ${item.ean}'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) async {
                if (id == null || fiscal.id == null) return;
                await _service.vincularItemFiscal(
                  itemFiscalId: fiscal.id!,
                  estoqueItemId: id,
                );
                if (mounted) setState(() => _vinculos[fiscal.id!] = id);
              },
            ),
            TextButton.icon(
              onPressed: fiscal.id == null ? null : () => _criarItem(fiscal),
              icon: const Icon(Icons.add),
              label: const Text('Criar novo item/insumo'),
            ),
          ],
        ),
      ),
    );
  }
}
