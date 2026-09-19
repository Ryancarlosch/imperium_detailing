import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/web_cloud_gestao_service.dart';
import 'imperium_web_theme.dart';
import '../widgets/web_financeiro_pagamentos_card.dart';

class WebFinanceiroLancamentosPage extends StatefulWidget {
  const WebFinanceiroLancamentosPage({super.key});

  @override
  State<WebFinanceiroLancamentosPage> createState() =>
      _WebFinanceiroLancamentosPageState();
}

class _WebFinanceiroLancamentosPageState
    extends State<WebFinanceiroLancamentosPage> {
  final _service = WebCloudGestaoService.instance;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

  late Future<_FinanceiroDados> _future;
  final _busca = TextEditingController();
  String _filtroTipo = 'Todos';
  String _filtroStatus = 'Todos';
  String _periodo = 'Este mês';

  @override
  void initState() {
    super.initState();
    _future = _buscarDados();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<_FinanceiroDados> _buscarDados() async {
    final resultados = await Future.wait<dynamic>([
      _service.resumoFinanceiro(),
      _service.listarContasFinanceiras(),
      _service.listarPlanoContasFinanceiro(),
      _service.listarMovimentosFinanceiros(),
    ]);

    return _FinanceiroDados(
      resumo: resultados[0] as Map<String, Object?>,
      contas: (resultados[1] as List<Map<String, dynamic>>)
          .where((item) => item['ativo'] != false)
          .toList(),
      planos: (resultados[2] as List<Map<String, dynamic>>)
          .where((item) => item['ativo'] != false)
          .toList(),
      movimentos: resultados[3] as List<Map<String, dynamic>>,
    );
  }

  void _recarregar() {
    setState(() => _future = _buscarDados());
  }

  Future<void> _abrirNovoLancamento(_FinanceiroDados dados) async {
    final descricao = TextEditingController();
    final valor = TextEditingController();
    final formaPagamento = TextEditingController(text: 'Pix');
    final numeroDocumento = TextEditingController();
    final observacoes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var tipo = 'Saída';
    var status = 'Realizado';
    var contaId = dados.contas.isEmpty
        ? ''
        : dados.contas.first['id'].toString();
    var planoId = '';
    var competencia = DateTime.now();
    DateTime? vencimento;
    var salvando = false;
    String? erro;

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: !salvando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> escolherCompetencia() async {
              final selecionada = await showDatePicker(
                context: context,
                initialDate: competencia,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('pt', 'BR'),
              );
              if (selecionada != null) {
                setModalState(() => competencia = selecionada);
              }
            }

            Future<void> escolherVencimento() async {
              final selecionada = await showDatePicker(
                context: context,
                initialDate: vencimento ?? competencia,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                locale: const Locale('pt', 'BR'),
              );
              if (selecionada != null) {
                setModalState(() => vencimento = selecionada);
              }
            }

            Future<void> salvar() async {
              if (salvando || !(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final valorNumero = _double(valor.text);
              if (status == 'Realizado' && contaId.isEmpty) {
                setModalState(() {
                  erro =
                      'Cadastre ou selecione uma conta/caixa para receber o lançamento.';
                });
                return;
              }

              setModalState(() {
                salvando = true;
                erro = null;
              });

              try {
                await _service.criarMovimentoFinanceiro(
                  tipo: tipo,
                  descricao: descricao.text,
                  valor: valorNumero,
                  status: status,
                  competencia: competencia,
                  vencimento: status == 'Previsto'
                      ? vencimento ?? competencia
                      : null,
                  contaId: status == 'Realizado' ? contaId : null,
                  planoContaId: planoId.isEmpty ? null : planoId,
                  formaPagamento: formaPagamento.text,
                  numeroDocumento: numeroDocumento.text,
                  observacoes: observacoes.text,
                );

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  salvando = false;
                  erro = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Text('Novo lançamento financeiro'),
              content: SizedBox(
                width: 640,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'O lançamento é salvo diretamente na nuvem e entra no mesmo fluxo de sincronização do aplicativo.',
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                initialValue: tipo,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Entrada',
                                    child: Text('Entrada'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Saída',
                                    child: Text('Saída'),
                                  ),
                                ],
                                onChanged: salvando
                                    ? null
                                    : (valor) {
                                        if (valor != null) {
                                          setModalState(() => tipo = valor);
                                        }
                                      },
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                initialValue: status,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Realizado',
                                    child: Text('Realizado'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Previsto',
                                    child: Text('Previsto'),
                                  ),
                                ],
                                onChanged: salvando
                                    ? null
                                    : (valor) {
                                        if (valor != null) {
                                          setModalState(() {
                                            status = valor;
                                            if (status == 'Previsto') {
                                              vencimento ??= competencia;
                                            }
                                          });
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descricao,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Descrição *',
                          ),
                          validator: (texto) {
                            if ((texto ?? '').trim().length < 3) {
                              return 'Informe uma descrição com pelo menos 3 caracteres.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: valor,
                          enabled: !salvando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor *',
                            prefixText: 'R\$ ',
                          ),
                          validator: (texto) {
                            if (_double(texto) <= 0) {
                              return 'Informe um valor maior que zero.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: planoId,
                          decoration: const InputDecoration(
                            labelText: 'Categoria financeira',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Categoria padrão automática'),
                            ),
                            ...dados.planos.map(
                              (plano) => DropdownMenuItem<String>(
                                value: plano['id'].toString(),
                                child: Text(
                                  '${plano['codigo'] ?? ''} · ${plano['nome'] ?? 'Categoria'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: salvando
                              ? null
                              : (valor) {
                                  setModalState(() => planoId = valor ?? '');
                                },
                        ),
                        if (status == 'Realizado') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: contaId.isEmpty ? null : contaId,
                            decoration: const InputDecoration(
                              labelText: 'Conta / caixa *',
                            ),
                            items: dados.contas
                                .map(
                                  (conta) => DropdownMenuItem<String>(
                                    value: conta['id'].toString(),
                                    child: Text(
                                      (conta['nome'] ?? 'Conta').toString(),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: salvando
                                ? null
                                : (valor) {
                                    setModalState(() => contaId = valor ?? '');
                                  },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: formaPagamento,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Forma de pagamento',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: salvando ? null : escolherCompetencia,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                'Competência: ${_data.format(competencia)}',
                              ),
                            ),
                            if (status == 'Previsto')
                              OutlinedButton.icon(
                                onPressed: salvando ? null : escolherVencimento,
                                icon: const Icon(Icons.schedule_outlined),
                                label: Text(
                                  'Vencimento: ${_data.format(vencimento ?? competencia)}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: numeroDocumento,
                          enabled: !salvando,
                          decoration: const InputDecoration(
                            labelText: 'Número do documento',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: observacoes,
                          enabled: !salvando,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                          ),
                        ),
                        if (erro != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            erro!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: salvando ? null : salvar,
                  icon: salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(salvando ? 'Salvando...' : 'Salvar lançamento'),
                ),
              ],
            );
          },
        );
      },
    );

    descricao.dispose();
    valor.dispose();
    formaPagamento.dispose();
    numeroDocumento.dispose();
    observacoes.dispose();

    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lançamento salvo na nuvem e disponível para sincronização.',
          ),
        ),
      );
      _recarregar();
    }
  }

  List<Map<String, dynamic>> _filtrarMovimentos(
    List<Map<String, dynamic>> movimentos,
  ) {
    final termo = _busca.text.trim().toLowerCase();
    final agora = DateTime.now();

    final filtrados = movimentos.where((movimento) {
      final entrada = _entrada(movimento['tipo']);
      final status = (movimento['status'] ?? '').toString();

      if (_filtroTipo == 'Entradas' && !entrada) return false;
      if (_filtroTipo == 'Saídas' && entrada) return false;
      if (_filtroStatus != 'Todos' && status != _filtroStatus) return false;

      final data = DateTime.tryParse((movimento['data'] ?? '').toString());
      if (_periodo == 'Este mês' &&
          (data == null ||
              data.year != agora.year ||
              data.month != agora.month)) {
        return false;
      }
      if (_periodo == '30 dias' &&
          (data == null ||
              data.isBefore(agora.subtract(const Duration(days: 30))))) {
        return false;
      }

      if (termo.isEmpty) return true;
      return [
        movimento['descricao'],
        movimento['forma_pagamento'],
        movimento['numero_documento'],
        movimento['observacoes'],
        status,
      ].any((v) => (v ?? '').toString().toLowerCase().contains(termo));
    }).toList();

    filtrados.sort((a, b) {
      final da = DateTime.tryParse((a['data'] ?? '').toString()) ?? DateTime(2000);
      final db = DateTime.tryParse((b['data'] ?? '').toString()) ?? DateTime(2000);
      return db.compareTo(da);
    });

    return filtrados;
  }

  Widget _resumoFinanceiro({
    required double width,
    required String titulo,
    required String valor,
    required String detalhe,
    required IconData icone,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valor,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalhe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF89939E),
                        fontSize: 11,
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

  Widget _contaCard(
    Map<String, dynamic> conta,
    Map<String, double> saldos,
    double width,
  ) {
    final saldo =
        saldos[conta['id'].toString()] ?? _double(conta['saldo_inicial']);

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                child: Icon(Icons.account_balance_wallet_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (conta['nome'] ?? 'Conta').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        (conta['tipo'] ?? '').toString(),
                        (conta['instituicao'] ?? '').toString(),
                      ].where((e) => e.trim().isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAAB3BD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _moeda.format(saldo),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: saldo < 0 ? Colors.orangeAccent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    return Chip(
      avatar: Icon(
        status.toLowerCase().contains('realiz')
            ? Icons.check_circle_outline
            : Icons.schedule_outlined,
        size: 16,
      ),
      label: Text(status.trim().isEmpty ? 'Não informado' : status),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FinanceiroDados>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final dados = snapshot.data!;
        final saldos =
            dados.resumo['saldos'] as Map<String, double>? ?? const {};
        final movimentos = _filtrarMovimentos(dados.movimentos);
        final statuses = dados.movimentos
            .map((e) => (e['status'] ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        return RefreshIndicator(
          onRefresh: () async {
            _recarregar();
            await _future;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 760;
              final tabela = constraints.maxWidth >= 1050;
              final larguraDisponivel =
                  constraints.maxWidth - (compacto ? 32 : 48);
              final colunasResumo = constraints.maxWidth >= 1180
                  ? 5
                  : constraints.maxWidth >= 760
                  ? 2
                  : 1;
              final larguraResumo =
                  (larguraDisponivel - (12 * (colunasResumo - 1))) /
                  colunasResumo;
              final colunasConta = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              final larguraConta =
                  (larguraDisponivel - (12 * (colunasConta - 1))) /
                  colunasConta;

              return ListView(
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
                              'Fluxo de caixa',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Saldos, recebimentos, despesas e lançamentos em uma visão operacional.',
                              style: TextStyle(color: Color(0xFFAAB3BD)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        tooltip: 'Atualizar',
                        onPressed: _recarregar,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: () => _abrirNovoLancamento(dados),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(compacto ? 'Novo' : 'Novo lançamento'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _resumoFinanceiro(
                        width: larguraResumo,
                        titulo: 'Saldo total',
                        valor: _moeda.format(
                          _double(dados.resumo['saldo_total']),
                        ),
                        detalhe: 'Saldo consolidado das contas',
                        icone: Icons.account_balance_wallet_outlined,
                      ),
                      _resumoFinanceiro(
                        width: larguraResumo,
                        titulo: 'Entradas do mês',
                        valor: _moeda.format(
                          _double(dados.resumo['entradas_mes']),
                        ),
                        detalhe: 'Recebimentos realizados no mês',
                        icone: Icons.south_west_rounded,
                      ),
                      _resumoFinanceiro(
                        width: larguraResumo,
                        titulo: 'Saídas do mês',
                        valor: _moeda.format(
                          _double(dados.resumo['saidas_mes']),
                        ),
                        detalhe: 'Despesas realizadas no mês',
                        icone: Icons.north_east_rounded,
                      ),
                      _resumoFinanceiro(
                        width: larguraResumo,
                        titulo: 'Resultado de caixa',
                        valor: _moeda.format(
                          _double(dados.resumo['resultado_caixa_mes']),
                        ),
                        detalhe: 'Entradas menos saídas realizadas',
                        icone: Icons.trending_up_rounded,
                      ),
                      _resumoFinanceiro(
                        width: larguraResumo,
                        titulo: 'A receber',
                        valor: _moeda.format(
                          _double(dados.resumo['a_receber']),
                        ),
                        detalhe: 'Valores ainda pendentes',
                        icone: Icons.schedule_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Contas e caixas',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${dados.contas.length} conta(s)',
                        style: const TextStyle(
                          color: Color(0xFF89939E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (dados.contas.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhuma conta financeira ativa cadastrada.',
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: dados.contas
                          .map(
                            (conta) =>
                                _contaCard(conta, saldos, larguraConta),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 22),
                  WebFinanceiroPagamentosCard(onChanged: _recarregar),
                  const SizedBox(height: 22),
                  const Text(
                    'Movimentos financeiros',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compacto ? larguraDisponivel - 28 : 390,
                            child: TextField(
                              controller: _busca,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText:
                                    'Buscar descrição, forma, documento ou observação',
                                suffixIcon: _busca.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar busca',
                                        onPressed: () {
                                          _busca.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 165,
                            child: DropdownButtonFormField<String>(
                              initialValue: _filtroTipo,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'Entradas',
                                  child: Text('Entradas'),
                                ),
                                DropdownMenuItem(
                                  value: 'Saídas',
                                  child: Text('Saídas'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filtroTipo = v ?? 'Todos'),
                            ),
                          ),
                          SizedBox(
                            width: 175,
                            child: DropdownButtonFormField<String>(
                              initialValue: _filtroStatus,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos'),
                                ),
                                ...statuses.map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(item),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => _filtroStatus = v ?? 'Todos',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 175,
                            child: DropdownButtonFormField<String>(
                              initialValue: _periodo,
                              decoration: const InputDecoration(
                                labelText: 'Período',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'Este mês',
                                  child: Text('Este mês'),
                                ),
                                DropdownMenuItem(
                                  value: '30 dias',
                                  child: Text('Últimos 30 dias'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _periodo = v ?? 'Este mês'),
                            ),
                          ),
                          Text(
                            '${movimentos.length} resultado(s)',
                            style: const TextStyle(
                              color: Color(0xFF89939E),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (movimentos.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 36,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 40,
                              color: Color(0xFF89939E),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Nenhum movimento encontrado',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (tabela)
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 62,
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('DATA')),
                            DataColumn(label: Text('DESCRIÇÃO')),
                            DataColumn(label: Text('TIPO')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('CONTA')),
                            DataColumn(label: Text('FORMA')),
                            DataColumn(label: Text('VALOR')),
                          ],
                          rows: movimentos.map((movimento) {
                            final entrada = _entrada(movimento['tipo']);
                            final status =
                                (movimento['status'] ?? '').toString();
                            final contaNome = _nomeConta(
                              dados.contas,
                              movimento['conta_id']?.toString(),
                            );

                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 105,
                                    child: Text(
                                      _formatarData(
                                        movimento['data']?.toString(),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 310,
                                    child: Text(
                                      (movimento['descricao'] ?? 'Movimento')
                                          .toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        entrada
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(entrada ? 'Entrada' : 'Saída'),
                                    ],
                                  ),
                                ),
                                DataCell(_statusChip(status)),
                                DataCell(
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      contaNome.isEmpty ? '—' : contaNome,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      (movimento['forma_pagamento'] ?? '—')
                                          .toString(),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${entrada ? '+' : '-'} '
                                    '${_moeda.format(_double(movimento['valor']))}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: entrada
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  else
                    ...movimentos.map((movimento) {
                      final entrada = _entrada(movimento['tipo']);
                      final status =
                          (movimento['status'] ?? '').toString();
                      final contaNome = _nomeConta(
                        dados.contas,
                        movimento['conta_id']?.toString(),
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                entrada
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                              ),
                            ),
                            title: Text(
                              (movimento['descricao'] ?? 'Movimento')
                                  .toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              [
                                _formatarData(
                                  movimento['data']?.toString(),
                                ),
                                status,
                                contaNome,
                                (movimento['forma_pagamento'] ?? '').toString(),
                              ].where((e) => e.trim().isNotEmpty).join(' · '),
                            ),
                            trailing: Text(
                              '${entrada ? '+' : '-'} '
                              '${_moeda.format(_double(movimento['valor']))}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: entrada
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _formatarData(String? valor) {
    final data = DateTime.tryParse(valor ?? '');
    return data == null ? (valor ?? '') : _data.format(data);
  }
}

class _FinanceiroDados {
  const _FinanceiroDados({
    required this.resumo,
    required this.contas,
    required this.planos,
    required this.movimentos,
  });

  final Map<String, Object?> resumo;
  final List<Map<String, dynamic>> contas;
  final List<Map<String, dynamic>> planos;
  final List<Map<String, dynamic>> movimentos;
}

class _ResumoFinanceiroCard extends StatelessWidget {
  const _ResumoFinanceiroCard({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo),
              const SizedBox(height: 6),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _nomeConta(List<Map<String, dynamic>> contas, String? contaId) {
  if (contaId == null || contaId.isEmpty) return '';
  for (final conta in contas) {
    if (conta['id']?.toString() == contaId) {
      return (conta['nome'] ?? '').toString();
    }
  }
  return '';
}

bool _entrada(dynamic tipo) {
  final texto = tipo?.toString().toLowerCase() ?? '';
  return texto.contains('entrada') || texto.contains('receita');
}

double _double(dynamic valor) {
  if (valor is num) return valor.toDouble();
  return double.tryParse(
        valor?.toString().trim().replaceAll('.', '').replaceAll(',', '.') ?? '',
      ) ??
      0;
}
