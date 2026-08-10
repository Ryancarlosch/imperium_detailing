import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/custo_fixo.dart';
import '../repositories/custos_repository.dart';

class CustosFixosPage extends StatefulWidget {
  const CustosFixosPage({super.key});

  @override
  State<CustosFixosPage> createState() => _CustosFixosPageState();
}

class _CustosFixosPageState extends State<CustosFixosPage> {
  final CustosRepository _repository = CustosRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  List<CustoFixo> _custos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }
    try {
      final custos = await _repository.listarCustosFixos();
      if (!mounted) {
        return;
      }
      setState(() {
        _custos = custos;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _abrirFormulario([CustoFixo? custo]) async {
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustoFixoForm(repository: _repository, custo: custo),
    );
    if (resultado == true) {
      await _carregar();
    }
  }

  Future<void> _arquivar(CustoFixo custo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arquivar custo fixo'),
        content: Text(
          'Arquivar "${custo.nome}"? O histórico do cadastro será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
    if (confirmar != true || custo.id == null) {
      return;
    }
    await _repository.arquivarCustoFixo(custo.id!);
    await _carregar();
  }

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
    final total = _custos.fold<double>(
      0,
      (soma, item) => soma + item.valorMensal,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Custos fixos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Adicionar'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.payments_outlined,
                        color: Color(0xFFD6A84B),
                      ),
                      title: const Text('Total mensal cadastrado'),
                      trailing: Text(
                        _moeda.format(total),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_custos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 60,
                        horizontal: 24,
                      ),
                      child: Text(
                        'Cadastre aluguel, energia, internet, contador, software e outros custos mensais para calcular o custo real da estrutura.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                  else
                    ..._custos.map(
                      (custo) => Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          title: Text(
                            custo.nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              custo.categoria,
                              if (custo.diaVencimento != null)
                                'Vence dia ${custo.diaVencimento}',
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _moeda.format(custo.valorMensal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (valor) {
                                  if (valor == 'editar') {
                                    _abrirFormulario(custo);
                                  }
                                  if (valor == 'arquivar') {
                                    _arquivar(custo);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'arquivar',
                                    child: Text('Arquivar'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _abrirFormulario(custo),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _CustoFixoForm extends StatefulWidget {
  const _CustoFixoForm({required this.repository, this.custo});

  final CustosRepository repository;
  final CustoFixo? custo;

  @override
  State<_CustoFixoForm> createState() => _CustoFixoFormState();
}

class _CustoFixoFormState extends State<_CustoFixoForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _valor;
  late final TextEditingController _dia;
  late final TextEditingController _observacoes;
  String _categoria = 'Despesa fixa';
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final custo = widget.custo;
    _nome = TextEditingController(text: custo?.nome ?? '');
    _valor = TextEditingController(
      text: custo == null
          ? ''
          : custo.valorMensal.toStringAsFixed(2).replaceAll('.', ','),
    );
    _dia = TextEditingController(text: custo?.diaVencimento?.toString() ?? '');
    _observacoes = TextEditingController(text: custo?.observacoes ?? '');
    _categoria = custo?.categoria ?? 'Despesa fixa';
  }

  @override
  void dispose() {
    _nome.dispose();
    _valor.dispose();
    _dia.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  double? _double(TextEditingController controller) {
    var texto = controller.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(texto.replaceAll(',', '.'));
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      final anterior = widget.custo;
      await widget.repository.salvarCustoFixo(
        CustoFixo(
          id: anterior?.id,
          nome: _nome.text.trim(),
          valorMensal: _double(_valor) ?? 0,
          categoria: _categoria,
          diaVencimento: _dia.text.trim().isEmpty
              ? null
              : int.tryParse(_dia.text.trim()),
          planoContaId: anterior?.planoContaId,
          observacoes: _observacoes.text.trim(),
          ativo: anterior?.ativo ?? true,
          criadoEm: anterior?.criadoEm ?? agora,
          atualizadoEm: agora,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.custo == null ? 'Novo custo fixo' : 'Editar custo fixo',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor mensal',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
                validator: (_) => (_double(_valor) ?? -1) < 0
                    ? 'Informe um valor válido.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoria,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Despesa fixa',
                    child: Text('Despesa fixa'),
                  ),
                  DropdownMenuItem(
                    value: 'Estrutura',
                    child: Text('Estrutura'),
                  ),
                  DropdownMenuItem(
                    value: 'Administrativo',
                    child: Text('Administrativo'),
                  ),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: (v) => setState(() => _categoria = v ?? _categoria),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dia,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dia do vencimento (opcional)',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return null;
                  }
                  final dia = int.tryParse(v.trim());
                  return dia == null || dia < 1 || dia > 31
                      ? 'Use um dia entre 1 e 31.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacoes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
