import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/imperium_planos_admin_service.dart';

class ImperiumPlanosPage extends StatefulWidget {
  const ImperiumPlanosPage({super.key});

  @override
  State<ImperiumPlanosPage> createState() => _ImperiumPlanosPageState();
}

class _ImperiumPlanosPageState extends State<ImperiumPlanosPage> {
  final ImperiumPlanosAdminService _service = const ImperiumPlanosAdminService();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  List<ImperiumPlanoAdmin> _planos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final planos = await _service.listar();
      if (!mounted) return;
      setState(() {
        _planos = planos;
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

  Future<void> _editar([ImperiumPlanoAdmin? plano]) async {
    if (_salvando) return;

    final resultado = await showDialog<_PlanoEditorResultado>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanoEditorDialog(plano: plano),
    );

    if (resultado == null || _salvando) return;

    setState(() => _salvando = true);
    try {
      await _service.salvar(
        codigo: plano?.codigo,
        nome: resultado.nome,
        meses: resultado.meses,
        valorCentavos: resultado.valorCentavos,
        ativo: resultado.ativo,
        ordem: resultado.ordem,
      );
      await _carregar();
      if (!mounted) return;
      _mensagem(plano == null ? 'Plano criado.' : 'Plano atualizado.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _alternar(ImperiumPlanoAdmin plano, bool ativo) async {
    if (_salvando) return;

    setState(() => _salvando = true);
    try {
      await _service.salvar(
        codigo: plano.codigo,
        nome: plano.nome,
        meses: plano.meses,
        valorCentavos: plano.valorCentavos,
        ativo: ativo,
        ordem: plano.ordem,
      );
      await _carregar();
      if (!mounted) return;
      _mensagem(ativo ? 'Plano ativado.' : 'Plano desativado.');
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'Exception: ',
      'PostgrestException: ',
      'AuthException: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto.isEmpty ? 'Não foi possível concluir a operação.' : texto;
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  String _duracao(ImperiumPlanoAdmin plano) {
    if (plano.meses == 1) return '1 mês';
    if (plano.meses == 12) return '12 meses';
    return '${plano.meses} meses';
  }

  Widget _planoCard(ImperiumPlanoAdmin plano) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plano.nome,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_duracao(plano)} • ${_moeda.format(plano.valor)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar plano',
                  onPressed: _salvando ? null : () => _editar(plano),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (plano.ativo ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    plano.ativo ? 'ATIVO' : 'INATIVO',
                    style: TextStyle(
                      color: plano.ativo
                          ? Colors.greenAccent
                          : Colors.white60,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Disponível para clientes',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: plano.ativo,
                  onChanged: _salvando
                      ? null
                      : (valor) => _alternar(plano, valor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Código interno: ${plano.codigo} • Ordem: ${plano.ordem}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos de assinatura'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando || _salvando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _salvando ? null : () => _editar(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo plano'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(_erro!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _carregar,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const Card(
                    margin: EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Você define os planos e valores aqui. O cliente apenas escolhe um plano ativo; o preço usado no checkout vem do servidor e não pode ser digitado ou alterado pelo cliente.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_planos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('Nenhum plano cadastrado.'),
                      ),
                    )
                  else
                    ..._planos.map(_planoCard),
                ],
              ),
            ),
    );
  }
}

class _PlanoEditorResultado {
  const _PlanoEditorResultado({
    required this.nome,
    required this.meses,
    required this.valorCentavos,
    required this.ativo,
    required this.ordem,
  });

  final String nome;
  final int meses;
  final int valorCentavos;
  final bool ativo;
  final int ordem;
}

class _PlanoEditorDialog extends StatefulWidget {
  const _PlanoEditorDialog({this.plano});

  final ImperiumPlanoAdmin? plano;

  @override
  State<_PlanoEditorDialog> createState() => _PlanoEditorDialogState();
}

class _PlanoEditorDialogState extends State<_PlanoEditorDialog> {
  late final TextEditingController _nome;
  late final TextEditingController _meses;
  late final TextEditingController _valor;
  late final TextEditingController _ordem;
  late bool _ativo;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final plano = widget.plano;
    _nome = TextEditingController(text: plano?.nome ?? '');
    _meses = TextEditingController(text: plano?.meses.toString() ?? '1');
    _valor = TextEditingController(
      text: plano == null
          ? ''
          : (plano.valorCentavos / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    _ordem = TextEditingController(text: plano?.ordem.toString() ?? '0');
    _ativo = plano?.ativo ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _meses.dispose();
    _valor.dispose();
    _ordem.dispose();
    super.dispose();
  }

  int? _valorEmCentavos(String texto) {
    var valor = texto.trim().replaceAll(RegExp(r'[^0-9,.]'), '');
    if (valor.isEmpty) return null;

    if (valor.contains(',')) {
      valor = valor.replaceAll('.', '').replaceAll(',', '.');
    }

    final numero = double.tryParse(valor);
    if (numero == null || numero <= 0) return null;
    return (numero * 100).round();
  }

  void _salvar() {
    final nome = _nome.text.trim();
    final meses = int.tryParse(_meses.text.trim());
    final valorCentavos = _valorEmCentavos(_valor.text);
    final ordem = int.tryParse(_ordem.text.trim());

    String? erro;
    if (nome.length < 2 || nome.length > 80) {
      erro = 'Informe um nome entre 2 e 80 caracteres.';
    } else if (meses == null || meses < 1 || meses > 120) {
      erro = 'A duração deve ficar entre 1 e 120 meses.';
    } else if (valorCentavos == null || valorCentavos < 1) {
      erro = 'Informe um valor válido.';
    } else if (ordem == null || ordem < 0 || ordem > 10000) {
      erro = 'A ordem deve ficar entre 0 e 10000.';
    }

    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }

    Navigator.of(context).pop(
      _PlanoEditorResultado(
        nome: nome,
        meses: meses!,
        valorCentavos: valorCentavos!,
        ativo: _ativo,
        ordem: ordem!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.plano != null;

    return AlertDialog(
      title: Text(editando ? 'Editar plano' : 'Novo plano'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do plano',
                  hintText: 'Ex.: Semestral',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _meses,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duração em meses',
                  helperText: 'Ex.: 1, 3, 6 ou 12',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$ ',
                  helperText: 'Este será o valor enviado à InfinitePay.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ordem,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ordem de exibição',
                  helperText: 'Menor número aparece primeiro.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Plano ativo'),
                subtitle: const Text(
                  'Somente planos ativos aparecem para o cliente.',
                ),
                value: _ativo,
                onChanged: (valor) => setState(() => _ativo = valor),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erro!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _salvar,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}
