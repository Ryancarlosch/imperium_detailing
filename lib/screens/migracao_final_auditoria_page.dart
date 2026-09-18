import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/migracao_final_auditoria_service.dart';

class MigracaoFinalAuditoriaPage extends StatefulWidget {
  const MigracaoFinalAuditoriaPage({super.key});

  @override
  State<MigracaoFinalAuditoriaPage> createState() =>
      _MigracaoFinalAuditoriaPageState();
}

class _MigracaoFinalAuditoriaPageState
    extends State<MigracaoFinalAuditoriaPage> {
  final MigracaoFinalAuditoriaService _service =
      MigracaoFinalAuditoriaService.instance;
  final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  String? _erro;
  MigracaoFinalAuditoriaResultado? _resultado;

  @override
  void initState() {
    super.initState();
    _auditar();
  }

  Future<void> _auditar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultado = await _service.auditar();
      if (!mounted) return;

      setState(() {
        _resultado = resultado;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'PostgrestException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto;
  }

  String _formatar(MigracaoFinalAuditoriaItem item, double valor) {
    if (item.inteiro) return valor.round().toString();
    if (item.unidade == 'moeda') return _moeda.format(valor);
    return valor.toStringAsFixed(3);
  }

  String _formatarDiferenca(MigracaoFinalAuditoriaItem item) {
    final valor = item.diferenca;
    final prefixo = valor > 0 ? '+' : '';

    if (item.inteiro) {
      return prefixo + valor.round().toString();
    }
    if (item.unidade == 'moeda') {
      return prefixo + _moeda.format(valor);
    }
    return prefixo + valor.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final resultado = _resultado;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoria da migração final'),
        actions: [
          IconButton(
            tooltip: 'Comparar novamente',
            onPressed: _carregando ? null : _auditar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _auditar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Comparação somente leitura entre o SQLite da empresa ativa '
                  'e o Supabase. Sincronize antes de usar esta tela como gate. '
                  'Ela não promove a nuvem nem altera dados.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_carregando && resultado == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 42),
                      const SizedBox(height: 10),
                      Text(_erro!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _carregando ? null : _auditar,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else if (resultado != null) ...[
              Card(
                child: ListTile(
                  leading: Icon(
                    resultado.tudoConfere
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                    size: 34,
                  ),
                  title: Text(
                    resultado.tudoConfere
                        ? 'SQLite e Cloud conferem neste gate'
                        : '${resultado.divergencias} divergência(s) encontrada(s)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    resultado.tudoConfere
                        ? 'As contagens e totais críticos do V1 estão equivalentes.'
                        : 'Não promova a nuvem como fonte principal enquanto '
                            'houver diferenças sem explicação.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final item in resultado.itens) ...[
                _ItemAuditoriaCard(
                  item: item,
                  local: _formatar(item, item.local),
                  cloud: _formatar(item, item.cloud),
                  diferenca: _formatarDiferenca(item),
                ),
                const SizedBox(height: 8),
              ],
              if (resultado.geradoEmCloud != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Cloud consultado em '
                    '${_dataHora.format(resultado.geradoEmCloud!.toLocal())}.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemAuditoriaCard extends StatelessWidget {
  const _ItemAuditoriaCard({
    required this.item,
    required this.local,
    required this.cloud,
    required this.diferenca,
  });

  final MigracaoFinalAuditoriaItem item;
  final String local;
  final String cloud;
  final String diferenca;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.confere
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(item.confere ? 'Confere' : 'Diverge'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Valor(titulo: 'SQLite', valor: local)),
                const SizedBox(width: 8),
                Expanded(child: _Valor(titulo: 'Cloud', valor: cloud)),
                const SizedBox(width: 8),
                Expanded(
                  child: _Valor(
                    titulo: 'Cloud - local',
                    valor: diferenca,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          valor,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
