import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_financeiro_administracao_service.dart';

class WebFinanceiroAdministracaoPage extends StatefulWidget {
  const WebFinanceiroAdministracaoPage({super.key});

  @override
  State<WebFinanceiroAdministracaoPage> createState() =>
      _WebFinanceiroAdministracaoPageState();
}

class _WebFinanceiroAdministracaoPageState
    extends State<WebFinanceiroAdministracaoPage> {
  final _service = WebFinanceiroAdministracaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _fornecedores = const [];
  List<Map<String, dynamic>> _regras = const [];
  List<Map<String, dynamic>> _custos = const [];
  List<Map<String, dynamic>> _metas = const [];
  List<Map<String, dynamic>> _planos = const [];
  List<Map<String, dynamic>> _contas = const [];
  List<Map<String, dynamic>> _movimentos = const [];
  List<Map<String, dynamic>> _transferencias = const [];
  List<Map<String, dynamic>> _colaboradores = const [];

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
      final dados = await Future.wait<dynamic>([
        _service.listarFornecedores(),
        _service.listarRegrasTaxa(),
        _service.listarCustosFixos(),
        _service.listarMetas(),
        _service.listarPlanoContas(),
        _service.listarContas(),
        _service.listarMovimentos(),
        _service.listarTransferencias(),
        _service.listarColaboradoresCusto(),
      ]);
      if (!mounted) return;
      setState(() {
        _fornecedores = dados[0] as List<Map<String, dynamic>>;
        _regras = dados[1] as List<Map<String, dynamic>>;
        _custos = dados[2] as List<Map<String, dynamic>>;
        _metas = dados[3] as List<Map<String, dynamic>>;
        _planos = dados[4] as List<Map<String, dynamic>>;
        _contas = dados[5] as List<Map<String, dynamic>>;
        _movimentos = dados[6] as List<Map<String, dynamic>>;
        _transferencias = dados[7] as List<Map<String, dynamic>>;
        _colaboradores = dados[8] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _snack(String texto, {bool erro = false}) {
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

  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    try {
      await acao();
      await _carregar();
      _snack(sucesso);
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.insights_outlined), text: 'Visão geral'),
                Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Fornecedores'),
                Tab(icon: Icon(Icons.credit_card_outlined), text: 'Maquininha'),
                Tab(icon: Icon(Icons.home_work_outlined), text: 'Custos fixos'),
                Tab(icon: Icon(Icons.track_changes_outlined), text: 'Metas'),
                Tab(icon: Icon(Icons.account_tree_outlined), text: 'Plano de contas'),
                Tab(icon: Icon(Icons.engineering_outlined), text: 'Mão de obra'),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_erro != null)
                  _Erro(texto: _erro!, onRetry: _carregar)
                else
                  TabBarView(
                    children: [
                      _visaoGeral(),
                      _lista(
                        titulo: 'Fornecedores',
                        subtitulo: 'Cadastro usado nas despesas e integrações fiscais.',
                        onNovo: () => _editarFornecedor(),
                        itens: _fornecedores,
                        tituloItem: (e) => (e['nome'] ?? 'Fornecedor').toString(),
                        detalheItem: (e) => [
                          e['documento'],
                          e['telefone'],
                          e['email'],
                          e['categoria'],
                        ].map((v) => (v ?? '').toString()).where((v) => v.trim().isNotEmpty).join(' · '),
                        onEditar: _editarFornecedor,
                      ),
                      _lista(
                        titulo: 'Regras da maquininha',
                        subtitulo: 'Taxas por forma e parcelamento, conta de recebimento e repasse ao cliente.',
                        onNovo: () => _editarRegra(),
                        itens: _regras,
                        tituloItem: (e) => (e['nome'] ?? 'Regra').toString(),
                        detalheItem: (e) =>
                            '${e['forma_pagamento'] ?? ''} · ${e['parcelas'] ?? 1}x · '
                            '${_double(e['taxa_percentual']).toStringAsFixed(2).replaceAll('.', ',')}%'
                            ' + ${_moeda.format(_double(e['taxa_fixa']))}',
                        onEditar: _editarRegra,
                      ),
                      _lista(
                        titulo: 'Custos fixos',
                        subtitulo: 'Base mensal usada na gestão e na precificação.',
                        onNovo: () => _editarCusto(),
                        itens: _custos,
                        tituloItem: (e) => (e['nome'] ?? 'Custo fixo').toString(),
                        detalheItem: (e) =>
                            '${_moeda.format(_double(e['valor_mensal']))}/mês · ${e['categoria'] ?? 'Despesa fixa'}',
                        onEditar: _editarCusto,
                      ),
                      _lista(
                        titulo: 'Metas financeiras',
                        subtitulo: 'Metas mensais por tipo e plano de contas.',
                        onNovo: () => _editarMeta(),
                        itens: _metas,
                        tituloItem: (e) => (e['tipo'] ?? 'Meta').toString(),
                        detalheItem: (e) =>
                            '${_int(e['mes']).toString().padLeft(2, '0')}/${e['ano'] ?? ''} · ${_moeda.format(_double(e['valor_meta']))}',
                        onEditar: _editarMeta,
                      ),
                      _lista(
                        titulo: 'Plano de contas',
                        subtitulo: 'Classificação financeira compartilhada entre Web e mobile.',
                        onNovo: () => _editarPlano(),
                        itens: _planos,
                        tituloItem: (e) => '${e['codigo'] ?? ''} · ${e['nome'] ?? ''}',
                        detalheItem: (e) =>
                            '${e['tipo'] ?? ''} · ${e['natureza'] ?? ''} · ${e['grupo_dre'] ?? 'Não DRE'}',
                        onEditar: _editarPlano,
                      ),
                      _lista(
                        titulo: 'Custos de mão de obra',
                        subtitulo: 'Remuneração, encargos, outros custos e horas produtivas usados na precificação.',
                        onNovo: () => _editarColaborador(),
                        itens: _colaboradores,
                        tituloItem: (e) => (e['nome'] ?? 'Funcionário').toString(),
                        detalheItem: (e) {
                          final mensal = _double(e['remuneracao_mensal']) +
                              _double(e['encargos_mensais']) +
                              _double(e['outros_custos_mensais']);
                          final horas = _double(e['horas_produtivas_mes']);
                          final hora = horas <= 0 ? 0 : mensal / horas;
                          return '${e['funcao'] ?? ''} · ${_moeda.format(mensal)}/mês · '
                              '${horas.toStringAsFixed(1)}h · ${_moeda.format(hora)}/h';
                        },
                        onEditar: _editarColaborador,
                      ),
                    ],
                  ),
                if (_carregando)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _visaoGeral() {
    final agora = DateTime.now();
    var entradaRealizada = 0.0;
    var saidaRealizada = 0.0;
    var entradaPrevista = 0.0;
    var saidaPrevista = 0.0;

    for (final item in _movimentos) {
      if (item['transferencia_id'] != null || item['impacta_dre'] == false) {
        continue;
      }
      final data = DateTime.tryParse(
        (item['data_pagamento'] ?? item['data_vencimento'] ?? item['data'] ?? '')
            .toString(),
      );
      if (data == null || data.year != agora.year || data.month != agora.month) {
        continue;
      }
      final entrada = (item['tipo'] ?? '')
          .toString()
          .toLowerCase()
          .contains('entrada');
      final status = (item['status'] ?? '').toString().toLowerCase();
      final valor = _double(item['valor']);
      if (status == 'realizado') {
        if (entrada) {
          entradaRealizada += valor;
        } else {
          saidaRealizada += valor;
        }
      } else if (status == 'previsto') {
        if (entrada) {
          entradaPrevista += valor;
        } else {
          saidaPrevista += valor;
        }
      }
    }

    final custoFixo = _custos
        .where((e) => _bool(e['ativo']))
        .fold<double>(0, (t, e) => t + _double(e['valor_mensal']));
    final maoObra = _colaboradores
        .where((e) => _bool(e['ativo']))
        .fold<double>(
          0,
          (t, e) =>
              t +
              _double(e['remuneracao_mensal']) +
              _double(e['encargos_mensais']) +
              _double(e['outros_custos_mensais']),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            const SizedBox(
              width: 650,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gestão financeira', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text(
                    'Fornecedores, taxas, custos, metas, plano de contas, mão de obra e transferências.',
                    style: TextStyle(color: Color(0xFF89939E)),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Atualizar'),
                ),
                FilledButton.icon(
                  onPressed: _contas.where((e) => _bool(e['ativo'])).length >= 2
                      ? _abrirTransferencia
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Transferir'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final colunas = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            final largura =
                (constraints.maxWidth - (colunas - 1) * 12) / colunas;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Kpi(width: largura, titulo: 'Entradas realizadas', valor: _moeda.format(entradaRealizada), detalhe: 'Mês atual'),
                _Kpi(width: largura, titulo: 'Saídas realizadas', valor: _moeda.format(saidaRealizada), detalhe: 'Mês atual'),
                _Kpi(width: largura, titulo: 'Entradas previstas', valor: _moeda.format(entradaPrevista), detalhe: 'Mês atual'),
                _Kpi(width: largura, titulo: 'Saídas previstas', valor: _moeda.format(saidaPrevista), detalhe: 'Mês atual'),
                _Kpi(width: largura, titulo: 'Custos fixos ativos', valor: _moeda.format(custoFixo), detalhe: 'Base mensal'),
                _Kpi(width: largura, titulo: 'Mão de obra ativa', valor: _moeda.format(maoObra), detalhe: 'Remuneração + encargos'),
                _Kpi(width: largura, titulo: 'Fornecedores ativos', valor: '${_fornecedores.where((e) => _bool(e['ativo'])).length}', detalhe: 'Cadastros disponíveis'),
                _Kpi(width: largura, titulo: 'Transferências', valor: '${_transferencias.length}', detalhe: 'Histórico Cloud'),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Previsto x realizado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 30,
              runSpacing: 16,
              children: [
                _Comparacao(titulo: 'Entradas', previsto: entradaPrevista, realizado: entradaRealizada, moeda: _moeda),
                _Comparacao(titulo: 'Saídas', previsto: saidaPrevista, realizado: saidaRealizada, moeda: _moeda),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lista({
    required String titulo,
    required String subtitulo,
    required VoidCallback onNovo,
    required List<Map<String, dynamic>> itens,
    required String Function(Map<String, dynamic>) tituloItem,
    required String Function(Map<String, dynamic>) detalheItem,
    required Future<void> Function(Map<String, dynamic>) onEditar,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 680,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitulo, style: const TextStyle(color: Color(0xFF89939E))),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onNovo,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (itens.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhum registro encontrado.'),
            ),
          )
        else
          ...itens.map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(_bool(item['ativo']) ? Icons.check_circle_outline : Icons.archive_outlined),
                title: Text(tituloItem(item), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  detalheItem(item).trim().isEmpty
                      ? 'Sem detalhes adicionais'
                      : detalheItem(item),
                ),
                trailing: OutlinedButton.icon(
                  onPressed: () => onEditar(item),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<bool?> _dialogo(String titulo, List<Widget> Function(StateSetter) campos) {
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _espacar(campos(setLocal)),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarFornecedor([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final documento = TextEditingController(text: '${atual?['documento'] ?? ''}');
    final telefone = TextEditingController(text: '${atual?['telefone'] ?? ''}');
    final email = TextEditingController(text: '${atual?['email'] ?? ''}');
    final categoria = TextEditingController(text: '${atual?['categoria'] ?? ''}');
    final endereco = TextEditingController(text: '${atual?['endereco'] ?? ''}');
    final cidade = TextEditingController(text: '${atual?['cidade'] ?? ''}');
    final estado = TextEditingController(text: '${atual?['estado'] ?? ''}');
    final observacoes = TextEditingController(text: '${atual?['observacoes'] ?? ''}');
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Novo fornecedor' : 'Editar fornecedor',
      (setLocal) => [
        _campo(nome, 'Nome *'),
        _linha([_campo(documento, 'CNPJ/CPF'), _campo(categoria, 'Categoria')]),
        _linha([_campo(telefone, 'Telefone'), _campo(email, 'E-mail')]),
        _campo(endereco, 'Endereço'),
        _linha([_campo(cidade, 'Cidade'), _campo(estado, 'UF')]),
        _campo(observacoes, 'Observações', linhas: 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fornecedor ativo'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarFornecedor(
        id: atual?['id']?.toString(),
        nome: nome.text,
        documento: documento.text,
        telefone: telefone.text,
        email: email.text,
        categoria: categoria.text,
        endereco: endereco.text,
        cidade: cidade.text,
        estado: estado.text,
        observacoes: observacoes.text,
        ativo: ativo,
      ),
      'Fornecedor salvo e sincronizado.',
    );
  }

  Future<void> _editarRegra([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final forma = TextEditingController(text: '${atual?['forma_pagamento'] ?? 'Cartão de crédito'}');
    final parcelas = TextEditingController(text: '${atual?['parcelas'] ?? 1}');
    final percentual = TextEditingController(text: _double(atual?['taxa_percentual']).toStringAsFixed(2));
    final fixa = TextEditingController(text: _double(atual?['taxa_fixa']).toStringAsFixed(2));
    final prazo = TextEditingController(text: '${atual?['prazo_recebimento_dias'] ?? 0}');
    final prioridade = TextEditingController(text: '${atual?['prioridade'] ?? 0}');
    final observacoes = TextEditingController(text: '${atual?['observacoes'] ?? ''}');
    String? contaId = atual?['conta_id']?.toString();
    var repassar = _bool(atual?['repassar_cliente']);
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Nova regra de taxa' : 'Editar regra de taxa',
      (setLocal) => [
        _campo(nome, 'Nome da regra *'),
        _linha([_campo(forma, 'Forma de pagamento *'), _campo(parcelas, 'Parcelas')]),
        _linha([_campo(percentual, 'Taxa %'), _campo(fixa, 'Taxa fixa')]),
        _linha([_campo(prazo, 'Prazo (dias)'), _campo(prioridade, 'Prioridade')]),
        DropdownButtonFormField<String?>(
          initialValue: _contas.any((e) => e['id']?.toString() == contaId) ? contaId : null,
          decoration: const InputDecoration(labelText: 'Conta da maquininha'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Sem conta específica')),
            ..._contas.where((e) => _bool(e['ativo'])).map(
              (e) => DropdownMenuItem<String?>(
                value: e['id']?.toString(),
                child: Text((e['nome'] ?? 'Conta').toString()),
              ),
            ),
          ],
          onChanged: (v) => contaId = v,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repassar taxa ao cliente'),
          value: repassar,
          onChanged: (v) => setLocal(() => repassar = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Regra ativa'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
        _campo(observacoes, 'Observações', linhas: 2),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarRegraTaxa(
        id: atual?['id']?.toString(),
        nome: nome.text,
        formaPagamento: forma.text,
        parcelas: _int(parcelas.text),
        contaId: contaId,
        taxaPercentual: _numero(percentual.text),
        taxaFixa: _numero(fixa.text),
        prazoRecebimentoDias: _int(prazo.text),
        prioridade: _int(prioridade.text),
        repassarCliente: repassar,
        observacoes: observacoes.text,
        ativo: ativo,
      ),
      'Regra de taxa salva e sincronizada.',
    );
  }

  Future<void> _editarCusto([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final valor = TextEditingController(text: _double(atual?['valor_mensal']).toStringAsFixed(2));
    final categoria = TextEditingController(text: '${atual?['categoria'] ?? 'Despesa fixa'}');
    final dia = TextEditingController(text: atual?['dia_vencimento']?.toString() ?? '');
    final observacoes = TextEditingController(text: '${atual?['observacoes'] ?? ''}');
    String? planoId = atual?['plano_conta_id']?.toString();
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Novo custo fixo' : 'Editar custo fixo',
      (setLocal) => [
        _campo(nome, 'Nome *'),
        _linha([_campo(valor, 'Valor mensal'), _campo(dia, 'Dia do vencimento')]),
        _campo(categoria, 'Categoria'),
        _planoDropdown(planoId, (v) => planoId = v),
        _campo(observacoes, 'Observações', linhas: 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Custo ativo'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarCustoFixo(
        id: atual?['id']?.toString(),
        nome: nome.text,
        valorMensal: _numero(valor.text),
        categoria: categoria.text,
        diaVencimento: dia.text.trim().isEmpty ? null : _int(dia.text),
        planoContaId: planoId,
        observacoes: observacoes.text,
        ativo: ativo,
      ),
      'Custo fixo salvo e sincronizado.',
    );
  }

  Future<void> _editarMeta([Map<String, dynamic>? atual]) async {
    final agora = DateTime.now();
    final ano = TextEditingController(text: '${atual?['ano'] ?? agora.year}');
    final mes = TextEditingController(text: '${atual?['mes'] ?? agora.month}');
    final tipo = TextEditingController(text: '${atual?['tipo'] ?? 'Faturamento'}');
    final valor = TextEditingController(text: _double(atual?['valor_meta']).toStringAsFixed(2));
    final observacoes = TextEditingController(text: '${atual?['observacoes'] ?? ''}');
    String? planoId = atual?['plano_conta_id']?.toString();
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Nova meta financeira' : 'Editar meta financeira',
      (setLocal) => [
        _linha([_campo(ano, 'Ano'), _campo(mes, 'Mês')]),
        _linha([_campo(tipo, 'Tipo'), _campo(valor, 'Valor da meta')]),
        _planoDropdown(planoId, (v) => planoId = v),
        _campo(observacoes, 'Observações', linhas: 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Meta ativa'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarMeta(
        id: atual?['id']?.toString(),
        ano: _int(ano.text),
        mes: _int(mes.text),
        tipo: tipo.text,
        planoContaId: planoId,
        valorMeta: _numero(valor.text),
        observacoes: observacoes.text,
        ativo: ativo,
      ),
      'Meta financeira salva e sincronizada.',
    );
  }

  Future<void> _editarPlano([Map<String, dynamic>? atual]) async {
    final codigo = TextEditingController(text: '${atual?['codigo'] ?? ''}');
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final tipo = TextEditingController(text: '${atual?['tipo'] ?? 'Saída'}');
    final natureza = TextEditingController(text: '${atual?['natureza'] ?? 'Não classificado'}');
    final grupo = TextEditingController(text: '${atual?['grupo_dre'] ?? 'Não DRE'}');
    final parent = TextEditingController(text: '${atual?['parent_codigo'] ?? ''}');
    final ordem = TextEditingController(text: '${atual?['ordem'] ?? 0}');
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Novo plano de contas' : 'Editar plano de contas',
      (setLocal) => [
        _linha([_campo(codigo, 'Código *'), _campo(ordem, 'Ordem')]),
        _campo(nome, 'Nome *'),
        _linha([_campo(tipo, 'Tipo'), _campo(natureza, 'Natureza')]),
        _linha([_campo(grupo, 'Grupo DRE'), _campo(parent, 'Código pai')]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Plano ativo'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarPlanoConta(
        id: atual?['id']?.toString(),
        codigo: codigo.text,
        nome: nome.text,
        tipo: tipo.text,
        natureza: natureza.text,
        grupoDre: grupo.text,
        parentCodigo: parent.text,
        ordem: _int(ordem.text),
        ativo: ativo,
      ),
      'Plano de contas salvo e sincronizado.',
    );
  }

  Future<void> _editarColaborador([Map<String, dynamic>? atual]) async {
    final nome = TextEditingController(text: '${atual?['nome'] ?? ''}');
    final funcao = TextEditingController(text: '${atual?['funcao'] ?? ''}');
    final remuneracao = TextEditingController(text: _double(atual?['remuneracao_mensal']).toStringAsFixed(2));
    final encargos = TextEditingController(text: _double(atual?['encargos_mensais']).toStringAsFixed(2));
    final outros = TextEditingController(text: _double(atual?['outros_custos_mensais']).toStringAsFixed(2));
    final horas = TextEditingController(text: _double(atual?['horas_produtivas_mes']).toStringAsFixed(1));
    final observacoes = TextEditingController(text: '${atual?['observacoes'] ?? ''}');
    var ativo = atual == null || _bool(atual['ativo']);

    final ok = await _dialogo(
      atual == null ? 'Novo custo de mão de obra' : 'Editar mão de obra',
      (setLocal) => [
        _linha([_campo(nome, 'Nome *'), _campo(funcao, 'Função')]),
        _linha([_campo(remuneracao, 'Remuneração mensal'), _campo(encargos, 'Encargos mensais')]),
        _linha([_campo(outros, 'Outros custos mensais'), _campo(horas, 'Horas produtivas/mês')]),
        _campo(observacoes, 'Observações', linhas: 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Funcionário ativo nos custos'),
          value: ativo,
          onChanged: (v) => setLocal(() => ativo = v),
        ),
      ],
    );
    if (ok != true) return;
    await _executar(
      () => _service.salvarColaboradorCusto(
        id: atual?['id']?.toString(),
        nome: nome.text,
        funcao: funcao.text,
        remuneracaoMensal: _numero(remuneracao.text),
        encargosMensais: _numero(encargos.text),
        outrosCustosMensais: _numero(outros.text),
        horasProdutivasMes: _numero(horas.text),
        observacoes: observacoes.text,
        ativo: ativo,
      ),
      'Custo de mão de obra salvo e sincronizado.',
    );
  }

  Future<void> _abrirTransferencia() async {
    final ativas = _contas.where((e) => _bool(e['ativo'])).toList();
    if (ativas.length < 2) return;

    String origemId = ativas.first['id'].toString();
    String destinoId = ativas[1]['id'].toString();
    DateTime data = DateTime.now();
    final valor = TextEditingController();
    final descricao = TextEditingController(text: 'Transferência entre contas');
    final observacoes = TextEditingController();

    final ok = await _dialogo(
      'Transferir entre contas',
      (setLocal) => [
        DropdownButtonFormField<String>(
          initialValue: origemId,
          decoration: const InputDecoration(labelText: 'Conta de origem'),
          items: ativas.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text((e['nome'] ?? 'Conta').toString()))).toList(),
          onChanged: (v) { if (v != null) setLocal(() => origemId = v); },
        ),
        DropdownButtonFormField<String>(
          initialValue: destinoId,
          decoration: const InputDecoration(labelText: 'Conta de destino'),
          items: ativas.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text((e['nome'] ?? 'Conta').toString()))).toList(),
          onChanged: (v) { if (v != null) setLocal(() => destinoId = v); },
        ),
        _campo(valor, 'Valor *'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Data'),
          subtitle: Text(DateFormat('dd/MM/yyyy').format(data)),
          trailing: OutlinedButton(
            onPressed: () async {
              final escolhida = await showDatePicker(
                context: context,
                initialDate: data,
                firstDate: DateTime(DateTime.now().year - 2),
                lastDate: DateTime(DateTime.now().year + 1),
              );
              if (escolhida != null) setLocal(() => data = escolhida);
            },
            child: const Text('Alterar'),
          ),
        ),
        _campo(descricao, 'Descrição'),
        _campo(observacoes, 'Observações', linhas: 2),
      ],
    );
    if (ok != true) return;

    await _executar(
      () async {
        await _service.transferir(
          contaOrigemId: origemId,
          contaDestinoId: destinoId,
          valor: _numero(valor.text),
          data: data,
          descricao: descricao.text,
          observacoes: observacoes.text,
        );
      },
      'Transferência realizada e sincronizada.',
    );
  }

  Widget _planoDropdown(String? valor, ValueChanged<String?> onChanged) {
    final atual = _planos.any((e) => e['id']?.toString() == valor) ? valor : null;
    return DropdownButtonFormField<String?>(
      initialValue: atual,
      decoration: const InputDecoration(labelText: 'Plano de contas'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Sem classificação específica')),
        ..._planos.where((e) => _bool(e['ativo'])).map(
          (e) => DropdownMenuItem<String?>(
            value: e['id']?.toString(),
            child: Text('${e['codigo'] ?? ''} · ${e['nome'] ?? ''}'),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _campo(TextEditingController controller, String label, {int linhas = 1}) {
    return TextField(
      controller: controller,
      minLines: linhas,
      maxLines: linhas,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _linha(List<Widget> itens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: _espacar(itens));
        }
        return Row(
          children: [
            for (var i = 0; i < itens.length; i++) ...[
              Expanded(child: itens[i]),
              if (i < itens.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _espacar(List<Widget> itens) {
    final result = <Widget>[];
    for (var i = 0; i < itens.length; i++) {
      result.add(itens[i]);
      if (i < itens.length - 1) result.add(const SizedBox(height: 10));
    }
    return result;
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.width, required this.titulo, required this.valor, required this.detalhe});
  final double width;
  final String titulo;
  final String valor;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(detalhe, style: const TextStyle(color: Color(0xFF89939E), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Comparacao extends StatelessWidget {
  const _Comparacao({required this.titulo, required this.previsto, required this.realizado, required this.moeda});
  final String titulo;
  final double previsto;
  final double realizado;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Previsto: ${moeda.format(previsto)}'),
          Text('Realizado: ${moeda.format(realizado)}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: previsto <= 0 ? 0 : (realizado / previsto).clamp(0.0, 1.0).toDouble(),
          ),
        ],
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.texto, required this.onRetry});
  final String texto;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 36),
              const SizedBox(height: 10),
              Text(texto, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final texto = value?.toString().toLowerCase() ?? '';
  return texto == 'true' || texto == '1';
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return _numero(value?.toString() ?? '');
}

double _numero(String value) {
  var texto = value.trim().replaceAll(r'R$', '').replaceAll(' ', '');
  if (texto.contains(',')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(texto) ?? 0;
}

String _textoErro(Object erro) {
  return erro
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
