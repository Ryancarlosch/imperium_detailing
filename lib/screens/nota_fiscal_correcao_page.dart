import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/nota_fiscal_entrada.dart';
import '../services/nota_fiscal_correcao_service.dart';

class NotaFiscalCorrecaoPage extends StatefulWidget {
  const NotaFiscalCorrecaoPage({super.key, required this.nota, this.service});

  final NotaFiscalEntrada nota;
  final NotaFiscalCorrecaoService? service;

  @override
  State<NotaFiscalCorrecaoPage> createState() => _NotaFiscalCorrecaoPageState();
}

class _NotaFiscalCorrecaoPageState extends State<NotaFiscalCorrecaoPage> {
  late final NotaFiscalCorrecaoService _service;
  final TextEditingController _motivo = TextEditingController();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  NotaFiscalCorrecaoImpacto? _impacto;
  bool _carregando = true;
  bool _executando = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NotaFiscalCorrecaoService();
    _carregar();
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final impacto = await _service.analisar(widget.nota.id!);
      if (!mounted) return;
      setState(() {
        _impacto = impacto;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _msg('$erro', erro: true);
    }
  }

  void _msg(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<bool> _confirmar(String titulo, String texto) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _desfazer() async {
    final impacto = _impacto;
    if (impacto == null || !impacto.podeDesfazerAutomaticamente) return;
    if (_motivo.text.trim().length < 5) {
      _msg('Informe um motivo com pelo menos 5 caracteres.', erro: true);
      return;
    }
    final confirmar = await _confirmar(
      'Desfazer integrações?',
      'O Imperium vai estornar a entrada de estoque ainda não consumida, '
          'cancelar previsões financeiras e gerar estorno compensatório para pagamentos '
          'já realizados, preservando o lançamento original no histórico. A nota continuará cadastrada para você corrigir ou integrar novamente.',
    );
    if (!confirmar) return;
    setState(() => _executando = true);
    try {
      await _service.desfazerIntegracoes(
        notaFiscalId: widget.nota.id!,
        motivo: _motivo.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _executando = false);
      _msg('$erro', erro: true);
    }
  }

  Future<void> _excluir() async {
    final impacto = _impacto;
    if (impacto == null || !impacto.podeDesfazerAutomaticamente) return;
    if (_motivo.text.trim().length < 5) {
      _msg('Informe um motivo com pelo menos 5 caracteres.', erro: true);
      return;
    }
    final confirmar = await _confirmar(
      'Excluir nota e desfazer tudo?',
      'A nota será removida do cadastro depois dos estornos seguros. '
          'O histórico de estoque/financeiro e a auditoria permanecerão registrados. '
          'Depois será possível importar novamente a mesma chave.',
    );
    if (!confirmar) return;
    setState(() => _executando = true);
    try {
      await _service.excluirNotaComDesfazimento(
        notaFiscalId: widget.nota.id!,
        motivo: _motivo.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _executando = false);
      _msg('$erro', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impacto = _impacto;
    return Scaffold(
      appBar: AppBar(title: const Text('Corrigir / excluir nota')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : impacto == null
          ? const Center(child: Text('Não foi possível analisar a nota.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          impacto.emitente.isEmpty
                              ? 'Fornecedor não informado'
                              : impacto.emitente,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Nota ${impacto.numero.isEmpty ? '-' : impacto.numero}',
                        ),
                        Text('Chave ${impacto.chaveAcesso}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Impacto detectado',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _linha(
                          'Entradas de estoque',
                          '${impacto.entradasEstoque}',
                        ),
                        _linha(
                          'Lotes já consumidos',
                          '${impacto.lotesConsumidos}',
                        ),
                        _linha(
                          'Financeiro previsto',
                          '${impacto.financeirosPrevistos}',
                        ),
                        _linha(
                          'Financeiro realizado',
                          '${impacto.financeirosRealizados}',
                        ),
                        _linha(
                          'Valor realizado',
                          _moeda.format(impacto.valorFinanceiroRealizado),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!impacto.podeDesfazerAutomaticamente) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.red.shade900.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Correção automática bloqueada',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          ...impacto.bloqueios.map((item) => Text('• $item')),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _motivo,
                  enabled: !_executando,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo da correção',
                    hintText:
                        'Ex.: nota importada errada / compra não pertence à empresa',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _executando || !impacto.podeDesfazerAutomaticamente
                      ? null
                      : _desfazer,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Desfazer integrações e manter nota'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  onPressed: _executando || !impacto.podeDesfazerAutomaticamente
                      ? null
                      : _excluir,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Excluir nota e desfazer integrações'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pagamentos realizados nunca são apagados silenciosamente. '
                  'O Imperium mantém o realizado como histórico estornado e cria um movimento compensatório para restaurar o saldo. '
                  'Se um lote já foi consumido por uma OS, a correção automática é bloqueada para preservar o custo histórico.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _linha(String titulo, String valor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(titulo)),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
