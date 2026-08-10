import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/conta_financeira.dart';
import '../repositories/conta_financeira_repository.dart';

class RegrasTaxaPage extends StatefulWidget {
  const RegrasTaxaPage({super.key});

  @override
  State<RegrasTaxaPage> createState() => _RegrasTaxaPageState();
}

class _RegrasTaxaPageState extends State<RegrasTaxaPage> {
  final ContaFinanceiraRepository _contasRepository =
      ContaFinanceiraRepository();

  bool _carregando = true;
  List<_GrupoRegraTaxa> _grupos = const [];
  List<ContaFinanceira> _contas = const [];

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
      final database = await AppDatabase.instance.database;
      final resultados = await Future.wait<dynamic>([
        database.rawQuery(
          '''
          SELECT
            r.*,
            c.nome AS conta_nome
          FROM financeiro_regras_taxa r
          LEFT JOIN financeiro_contas c ON c.id = r.conta_id
          ORDER BY
            r.ativo DESC,
            r.nome COLLATE NOCASE,
            r.forma_pagamento,
            r.parcelas,
            r.id
          ''',
        ),
        _contasRepository.listar(incluirInativas: true),
      ]);

      final linhas = List<Map<String, Object?>>.from(
        resultados[0] as List<dynamic>,
      );
      final contas = List<ContaFinanceira>.from(
        resultados[1] as List<dynamic>,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _grupos = _agrupar(linhas);
        _contas = contas;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() => _carregando = false);
      _mensagem('Não foi possível carregar as regras.\n$erro', erro: true);
    }
  }

  List<_GrupoRegraTaxa> _agrupar(List<Map<String, Object?>> linhas) {
    final grupos = <String, List<_LinhaRegraTaxa>>{};

    for (final linha in linhas) {
      final item = _LinhaRegraTaxa.fromMap(linha);
      final chave = [
        item.nome.trim().toLowerCase(),
        item.formaPagamento,
        item.contaId?.toString() ?? 'null',
      ].join('|');

      grupos.putIfAbsent(chave, () => <_LinhaRegraTaxa>[]).add(item);
    }

    final resultado = grupos.values
        .map((itens) => _GrupoRegraTaxa(itens: itens))
        .toList();

    resultado.sort((a, b) {
      if (a.ativo != b.ativo) {
        return a.ativo ? -1 : 1;
      }
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

    return resultado;
  }

  Future<void> _abrirEditor([_GrupoRegraTaxa? grupo]) async {
    if (_contas.where((conta) => conta.ativo).isEmpty && grupo == null) {
      _mensagem(
        'Cadastre primeiro uma conta do tipo Maquininha em Contas e caixa.',
        erro: true,
      );
      return;
    }

    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorRegraTaxaSheet(
        grupo: grupo,
        contas: _contas,
        salvar: _salvarGrupo,
      ),
    );

    if (salvo == true) {
      await _carregar();
      _mensagem(grupo == null ? 'Regra criada.' : 'Regra atualizada.');
    }
  }

  Future<void> _salvarGrupo({
    required _GrupoRegraTaxa? grupoAnterior,
    required String nome,
    required String formaPagamento,
    required int contaId,
    required bool ativo,
    required bool repassarCliente,
    required Map<int, double> taxas,
  }) async {
    final database = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();

    await database.transaction((transaction) async {
      final limite = formaPagamento == 'Cartão de crédito' ? 12 : 1;
      final anteriores = <int, _LinhaRegraTaxa>{};

      if (grupoAnterior != null) {
        for (final item in grupoAnterior.itens) {
          anteriores[item.parcelas] = item;
        }
      }

      for (var parcelas = 1; parcelas <= limite; parcelas++) {
        final taxa = taxas[parcelas];
        if (taxa == null || taxa < 0 || taxa > 100) {
          throw ArgumentError('Taxa inválida para ${parcelas}x.');
        }

        final anterior = anteriores[parcelas];

        final dados = <String, Object?>{
          'nome': nome.trim(),
          'forma_pagamento': formaPagamento,
          'parcelas': parcelas,
          'conta_id': contaId,
          'taxa_percentual': taxa,
          'taxa_fixa': anterior?.taxaFixa ?? 0,
          'prazo_recebimento_dias':
              anterior?.prazoRecebimentoDias ?? 0,
          'prioridade': anterior?.prioridade ?? 0,
          'repassar_cliente': repassarCliente ? 1 : 0,
          'observacoes': anterior?.observacoes ?? '',
          'ativo': ativo ? 1 : 0,
          'atualizado_em': agora,
        };

        if (anterior?.id != null) {
          await transaction.update(
            'financeiro_regras_taxa',
            dados,
            where: 'id = ?',
            whereArgs: [anterior!.id],
          );
        } else {
          dados['criado_em'] = agora;
          await transaction.insert(
            'financeiro_regras_taxa',
            dados,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      if (grupoAnterior != null) {
        final idsMantidos = <int>{};

        for (var parcelas = 1; parcelas <= limite; parcelas++) {
          final id = anteriores[parcelas]?.id;
          if (id != null) {
            idsMantidos.add(id);
          }
        }

        final idsExcluir = grupoAnterior.itens
            .map((item) => item.id)
            .whereType<int>()
            .where((id) => !idsMantidos.contains(id))
            .toList();

        if (idsExcluir.isNotEmpty) {
          final placeholders = List.filled(idsExcluir.length, '?').join(',');
          await transaction.delete(
            'financeiro_regras_taxa',
            where: 'id IN ($placeholders)',
            whereArgs: idsExcluir,
          );
        }
      }
    });
  }

  Future<void> _alternar(_GrupoRegraTaxa grupo) async {
    final ids = grupo.itens.map((item) => item.id).whereType<int>().toList();
    if (ids.isEmpty) {
      return;
    }

    try {
      final database = await AppDatabase.instance.database;
      final placeholders = List.filled(ids.length, '?').join(',');

      await database.update(
        'financeiro_regras_taxa',
        {
          'ativo': grupo.ativo ? 0 : 1,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      await _carregar();
    } catch (erro) {
      _mensagem('Não foi possível alterar a regra.\n$erro', erro: true);
    }
  }

  Future<void> _excluir(_GrupoRegraTaxa grupo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir regra'),
        content: Text(
          'Excluir "${grupo.nome}" e todas as taxas cadastradas de parcelas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    final ids = grupo.itens.map((item) => item.id).whereType<int>().toList();
    if (ids.isEmpty) {
      return;
    }

    try {
      final database = await AppDatabase.instance.database;
      final placeholders = List.filled(ids.length, '?').join(',');

      await database.delete(
        'financeiro_regras_taxa',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      await _carregar();
      _mensagem('Regra excluída.');
    } catch (erro) {
      _mensagem('Não foi possível excluir a regra.\n$erro', erro: true);
    }
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }

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
        title: const Text('Regras de maquininha'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _carregando ? null : () => _abrirEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova regra'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _grupos.isEmpty
              ? _EstadoVazio(onCriar: () => _abrirEditor())
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _grupos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final grupo = _grupos[index];
                      return _CardGrupoRegra(
                        grupo: grupo,
                        onEditar: () => _abrirEditor(grupo),
                        onAlternar: () => _alternar(grupo),
                        onExcluir: () => _excluir(grupo),
                      );
                    },
                  ),
                ),
    );
  }
}

class _CardGrupoRegra extends StatelessWidget {
  const _CardGrupoRegra({
    required this.grupo,
    required this.onEditar,
    required this.onAlternar,
    required this.onExcluir,
  });

  final _GrupoRegraTaxa grupo;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onExcluir;

  @override
  Widget build(BuildContext context) {
    final limite = grupo.credito ? 12 : 1;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFFD6A84B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            grupo.nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (!grupo.ativo)
                          const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Inativa'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${grupo.formaPagamento} • ${grupo.contaNome}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (grupo.repassarCliente) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Taxa repassada ao cliente',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var parcela = 1; parcela <= limite; parcela++)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              '${parcela}x ${_formatarPercentual(grupo.taxa(parcela))}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (valor) {
                  if (valor == 'alternar') {
                    onAlternar();
                  } else if (valor == 'excluir') {
                    onExcluir();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'alternar',
                    child: Text(grupo.ativo ? 'Desativar' : 'Ativar'),
                  ),
                  const PopupMenuItem(
                    value: 'excluir',
                    child: Text('Excluir'),
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

class _EditorRegraTaxaSheet extends StatefulWidget {
  const _EditorRegraTaxaSheet({
    required this.grupo,
    required this.contas,
    required this.salvar,
  });

  final _GrupoRegraTaxa? grupo;
  final List<ContaFinanceira> contas;
  final Future<void> Function({
    required _GrupoRegraTaxa? grupoAnterior,
    required String nome,
    required String formaPagamento,
    required int contaId,
    required bool ativo,
    required bool repassarCliente,
    required Map<int, double> taxas,
  }) salvar;

  @override
  State<_EditorRegraTaxaSheet> createState() => _EditorRegraTaxaSheetState();
}

class _EditorRegraTaxaSheetState extends State<_EditorRegraTaxaSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  final Map<int, TextEditingController> _taxas = {};

  late String _formaPagamento;
  int? _contaId;
  bool _ativo = true;
  bool _repassarCliente = false;
  bool _salvando = false;

  bool get _credito => _formaPagamento == 'Cartão de crédito';

  @override
  void initState() {
    super.initState();

    final grupo = widget.grupo;
    _nomeController = TextEditingController(text: grupo?.nome ?? '');
    _formaPagamento = grupo?.formaPagamento ?? 'Cartão de crédito';
    _contaId = grupo?.contaId;
    _ativo = grupo?.ativo ?? true;
    _repassarCliente = grupo?.repassarCliente ?? false;

    final ativas = widget.contas.where((conta) => conta.ativo).toList();
    if (_contaId == null && ativas.length == 1) {
      _contaId = ativas.single.id;
    }

    for (var parcela = 1; parcela <= 12; parcela++) {
      final taxa = grupo?.taxaNula(parcela);
      _taxas[parcela] = TextEditingController(
        text: taxa == null ? '' : _campoPercentual(taxa),
      );
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    for (final controller in _taxas.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final contaId = _contaId;
    if (contaId == null) {
      return;
    }

    final limite = _credito ? 12 : 1;
    final taxas = <int, double>{};

    for (var parcela = 1; parcela <= limite; parcela++) {
      taxas[parcela] = _lerPercentual(_taxas[parcela]!.text)!;
    }

    setState(() => _salvando = true);

    try {
      await widget.salvar(
        grupoAnterior: widget.grupo,
        nome: _nomeController.text.trim(),
        formaPagamento: _formaPagamento,
        contaId: contaId,
        ativo: _ativo,
        repassarCliente: _repassarCliente,
        taxas: taxas,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar a regra.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final limite = _credito ? 12 : 1;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, teclado + 20),
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
              Center(
                child: Container(
                  width: 45,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                widget.grupo == null ? 'Nova regra' : 'Editar regra',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cadastre todas as taxas uma única vez. No pagamento você só escolhe a quantidade de parcelas.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nomeController,
                enabled: !_salvando,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome da regra',
                  hintText: 'Ex.: Stone Visa/Mastercard',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (valor) {
                  if ((valor ?? '').trim().length < 2) {
                    return 'Informe o nome da regra.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _formaPagamento,
                decoration: const InputDecoration(
                  labelText: 'Forma',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Cartão de crédito',
                    child: Text('Crédito'),
                  ),
                  DropdownMenuItem(
                    value: 'Cartão de débito',
                    child: Text('Débito'),
                  ),
                ],
                onChanged: _salvando
                    ? null
                    : (valor) {
                        if (valor == null) {
                          return;
                        }
                        setState(() => _formaPagamento = valor);
                      },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _contaId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta da maquininha',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  helperText:
                      'O recebimento e a taxa serão lançados automaticamente nesta conta.',
                ),
                items: widget.contas
                    .map(
                      (conta) => DropdownMenuItem<int>(
                        value: conta.id,
                        child: Text(
                          conta.ativo ? conta.nome : '${conta.nome} (inativa)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _contaId = valor),
                validator: (valor) {
                  if (valor == null) {
                    return 'Selecione a conta da maquininha.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              Text(
                _credito ? 'Taxas por parcela' : 'Taxa do débito',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _credito
                    ? 'Preencha de 1x até 12x.'
                    : 'No débito será usada somente a taxa de 1x.',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final colunas = constraints.maxWidth >= 520 ? 3 : 2;
                  final largura =
                      (constraints.maxWidth - ((colunas - 1) * 10)) / colunas;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var parcela = 1; parcela <= limite; parcela++)
                        SizedBox(
                          width: largura,
                          child: TextFormField(
                            controller: _taxas[parcela],
                            enabled: !_salvando,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            decoration: InputDecoration(
                              labelText: '${parcela}x',
                              suffixText: '%',
                            ),
                            validator: (valor) {
                              final taxa = _lerPercentual(valor ?? '');
                              if (taxa == null || taxa < 0 || taxa > 100) {
                                return '0 a 100';
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _repassarCliente,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _repassarCliente = valor),
                title: const Text('Repassar taxa ao cliente'),
                subtitle: const Text(
                  'Desligado: a empresa absorve a taxa. Ligado: o sistema calcula o acréscimo necessário.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                onChanged: _salvando
                    ? null
                    : (valor) => setState(() => _ativo = valor),
                title: const Text('Regra ativa'),
                subtitle: const Text(
                  'Somente regras ativas são usadas automaticamente.',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_salvando ? 'Salvando...' : 'Salvar regra'),
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

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onCriar});

  final VoidCallback onCriar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.credit_card_off_outlined,
              size: 72,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma regra cadastrada',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cadastre a maquininha, a conta e as taxas de 1x a 12x.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCriar,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar primeira regra'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrupoRegraTaxa {
  const _GrupoRegraTaxa({required this.itens});

  final List<_LinhaRegraTaxa> itens;

  _LinhaRegraTaxa get principal => itens.first;
  String get nome => principal.nome;
  String get formaPagamento => principal.formaPagamento;
  int? get contaId => principal.contaId;
  String get contaNome => principal.contaNome.isEmpty
      ? 'Sem conta vinculada'
      : principal.contaNome;
  bool get ativo => itens.any((item) => item.ativo);
  bool get repassarCliente => itens.any((item) => item.repassarCliente);
  bool get credito => formaPagamento == 'Cartão de crédito';

  double taxa(int parcelas) => taxaNula(parcelas) ?? 0;

  double? taxaNula(int parcelas) {
    for (final item in itens.reversed) {
      if (item.parcelas == parcelas) {
        return item.taxaPercentual;
      }
    }
    return null;
  }
}

class _LinhaRegraTaxa {
  const _LinhaRegraTaxa({
    required this.id,
    required this.nome,
    required this.formaPagamento,
    required this.parcelas,
    required this.contaId,
    required this.contaNome,
    required this.taxaPercentual,
    required this.taxaFixa,
    required this.prazoRecebimentoDias,
    required this.prioridade,
    required this.repassarCliente,
    required this.observacoes,
    required this.ativo,
  });

  final int? id;
  final String nome;
  final String formaPagamento;
  final int parcelas;
  final int? contaId;
  final String contaNome;
  final double taxaPercentual;
  final double taxaFixa;
  final int prazoRecebimentoDias;
  final int prioridade;
  final bool repassarCliente;
  final String observacoes;
  final bool ativo;

  factory _LinhaRegraTaxa.fromMap(Map<String, Object?> map) {
    return _LinhaRegraTaxa(
      id: _int(map['id']),
      nome: _texto(map['nome']),
      formaPagamento: _texto(map['forma_pagamento']),
      parcelas: _int(map['parcelas']) ?? 1,
      contaId: _int(map['conta_id']),
      contaNome: _texto(map['conta_nome']),
      taxaPercentual: _double(map['taxa_percentual']),
      taxaFixa: _double(map['taxa_fixa']),
      prazoRecebimentoDias: _int(map['prazo_recebimento_dias']) ?? 0,
      prioridade: _int(map['prioridade']) ?? 0,
      repassarCliente: _int(map['repassar_cliente']) == 1,
      observacoes: _texto(map['observacoes']),
      ativo: _int(map['ativo']) == 1,
    );
  }
}

int? _int(dynamic valor) {
  if (valor is int) {
    return valor;
  }
  if (valor is num) {
    return valor.toInt();
  }
  return int.tryParse(valor?.toString().trim() ?? '');
}

double _double(dynamic valor) {
  if (valor is num) {
    return valor.toDouble();
  }
  return double.tryParse(
        valor?.toString().trim().replaceAll(',', '.') ?? '',
      ) ??
      0;
}

String _texto(dynamic valor) => valor?.toString().trim() ?? '';

double? _lerPercentual(String texto) {
  final limpo = texto
      .trim()
      .replaceAll('%', '')
      .replaceAll(' ', '');

  if (limpo.isEmpty) {
    return null;
  }

  if (limpo.contains(',') && limpo.contains('.')) {
    return double.tryParse(
      limpo.replaceAll('.', '').replaceAll(',', '.'),
    );
  }

  return double.tryParse(limpo.replaceAll(',', '.'));
}

String _campoPercentual(double valor) {
  return valor
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

String _formatarPercentual(double valor) => '${_campoPercentual(valor)}%';
