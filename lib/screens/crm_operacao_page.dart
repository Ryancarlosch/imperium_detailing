import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/crm_acao_relacionamento.dart';
import '../repositories/crm_operacao_repository.dart';
import '../services/notification_service.dart';
import '../services/whatsapp_service.dart';
import 'crm_desempenho_page.dart';
import 'orcamento_detalhes_page.dart';

class CrmOperacaoPage extends StatefulWidget {
  const CrmOperacaoPage({super.key});

  @override
  State<CrmOperacaoPage> createState() => _CrmOperacaoPageState();
}

class _CrmOperacaoPageState extends State<CrmOperacaoPage> {
  final CrmOperacaoRepository _repository = CrmOperacaoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _sincronizando = false;
  bool _lembreteAtivo = false;
  String _filtro = 'Atrasadas';
  List<CrmAcaoRelacionamento> _acoes = const [];
  CrmOperacaoResumo? _resumo;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool sincronizar = true}) async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      if (sincronizar) _sincronizando = true;
    });

    try {
      if (sincronizar) {
        await _repository.sincronizarAcoes();
      }
      final resultados = await Future.wait<Object>([
        _repository.listarAcoes(status: 'Todos'),
        _repository.carregarResumo(),
        NotificationService.instance.lembreteDiarioCrmAtivo(),
      ]);
      if (!mounted) return;
      setState(() {
        _acoes = resultados[0] as List<CrmAcaoRelacionamento>;
        _resumo = resultados[1] as CrmOperacaoResumo;
        _lembreteAtivo = resultados[2] as bool;
        _carregando = false;
        _sincronizando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _sincronizando = false;
      });
      _mensagem(
        'Não foi possível carregar as ações do CRM.\n$erro',
        erro: true,
      );
    }
  }

  List<CrmAcaoRelacionamento> get _acoesFiltradas {
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final fimSete = dia.add(const Duration(days: 7));

    return _acoes.where((acao) {
      final vencimento = acao.vencimentoData;
      final dataAcao = vencimento == null
          ? null
          : DateTime(vencimento.year, vencimento.month, vencimento.day);
      return switch (_filtro) {
        'Atrasadas' =>
          acao.status == 'Pendente' &&
              dataAcao != null &&
              dataAcao.isBefore(dia),
        'Hoje' => acao.status == 'Pendente' && dataAcao == dia,
        'Próximas' =>
          acao.status == 'Pendente' &&
              dataAcao != null &&
              dataAcao.isAfter(dia) &&
              !dataAcao.isAfter(fimSete),
        'Pendentes' => acao.status == 'Pendente',
        'Concluídas' => acao.status == 'Concluida',
        'Ignoradas' => acao.status == 'Ignorada',
        _ => true,
      };
    }).toList();
  }

  void _mensagem(String texto, {bool erro = false}) {
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

  Future<void> _abrirWhatsApp(CrmAcaoRelacionamento acao) async {
    if (acao.telefone.trim().isEmpty) {
      _mensagem('Este contato não possui telefone cadastrado.', erro: true);
      return;
    }

    try {
      await WhatsAppService.enviarMensagemPersonalizada(
        telefone: acao.telefone,
        mensagem: acao.mensagemSugerida,
      );
      if (!mounted) return;
      final concluir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('WhatsApp aberto'),
          content: const Text(
            'Abrir o WhatsApp não confirma que a mensagem foi enviada. '
            'Marque como realizada somente depois de concluir o contato.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ainda não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Marcar realizada'),
            ),
          ],
        ),
      );
      if (concluir == true && mounted) {
        await _concluir(acao);
      }
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _concluir(CrmAcaoRelacionamento acao) async {
    DateTime? proximoContato;
    if (acao.tipo == 'Follow-up lead') {
      final escolha = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Concluir follow-up'),
          content: const Text(
            'Você pode encerrar este contato ou já agendar o próximo follow-up.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Sem próximo contato'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 1),
              child: const Text('Agendar próximo'),
            ),
          ],
        ),
      );
      if (escolha == null) return;
      if (escolha == 1 && mounted) {
        final hoje = DateTime.now();
        proximoContato = await showDatePicker(
          context: context,
          initialDate: hoje.add(const Duration(days: 2)),
          firstDate: hoje,
          lastDate: DateTime(hoje.year + 2, 12, 31),
          locale: const Locale('pt', 'BR'),
        );
        if (proximoContato == null) return;
      }
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Marcar como realizada?'),
          content: Text(acao.titulo),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    try {
      await _repository.concluirAcao(
        acao.id,
        proximoContato: proximoContato,
        observacoes: 'Contato concluído pela Central de Relacionamento.',
      );
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _adiar(CrmAcaoRelacionamento acao) async {
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: hoje.add(const Duration(days: 1)),
      firstDate: hoje,
      lastDate: DateTime(hoje.year + 2, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (escolhida == null) return;
    try {
      await _repository.adiarAcao(acao.id, escolhida);
      await _carregar(sincronizar: false);
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _ignorar(CrmAcaoRelacionamento acao) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ignorar esta ação?'),
        content: Text(
          '${acao.titulo}\n\nEla continuará no histórico, mas sairá das pendências.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ignorar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _repository.ignorarAcao(
      acao.id,
      motivo: 'Ignorada manualmente na Central de Relacionamento.',
    );
    await _carregar(sincronizar: false);
  }

  Future<void> _levarOrcamentoAoFunil(CrmAcaoRelacionamento acao) async {
    try {
      final leadId = await _repository.criarOuAtualizarLeadDoOrcamento(
        acao.entidadeId,
      );
      _mensagem('Orçamento vinculado ao funil no lead #$leadId.');
      await _carregar();
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _alternarLembrete() async {
    try {
      if (_lembreteAtivo) {
        await NotificationService.instance.desativarLembreteDiarioCrm();
        if (!mounted) return;
        setState(() => _lembreteAtivo = false);
        _mensagem('Lembrete diário do CRM desativado.');
        return;
      }
      final permitido = await NotificationService.instance.solicitarPermissao();
      if (!permitido) {
        _mensagem('Permissão de notificações não foi concedida.', erro: true);
        return;
      }
      await NotificationService.instance.ativarLembreteDiarioCrm();
      if (!mounted) return;
      setState(() => _lembreteAtivo = true);
      _mensagem('Lembrete diário do CRM ativado para 09:00.');
    } catch (erro) {
      _mensagem('Não foi possível configurar o lembrete.\n$erro', erro: true);
    }
  }

  Future<void> _abrirOrcamento(CrmAcaoRelacionamento acao) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OrcamentoDetalhesPage(orcamentoId: acao.entidadeId),
      ),
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    final acoes = _acoesFiltradas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Central de relacionamento'),
        actions: [
          IconButton(
            tooltip: _lembreteAtivo
                ? 'Desativar lembrete diário'
                : 'Ativar lembrete diário às 09:00',
            onPressed: _alternarLembrete,
            icon: Icon(
              _lembreteAtivo
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Desempenho do CRM',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const CrmDesempenhoPage()),
            ),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Sincronizar ações',
            onPressed: _sincronizando ? null : _carregar,
            icon: _sincronizando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando && resumo == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                children: [
                  if (resumo != null)
                    _ResumoOperacao(resumo: resumo, moeda: _moeda),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'O Imperium prepara a mensagem e abre o WhatsApp. '
                              'O envio continua sob sua confirmação no WhatsApp; '
                              'nenhuma mensagem é disparada automaticamente.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final filtro in const [
                          'Atrasadas',
                          'Hoje',
                          'Próximas',
                          'Pendentes',
                          'Concluídas',
                          'Ignoradas',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(filtro),
                              selected: _filtro == filtro,
                              onSelected: (_) =>
                                  setState(() => _filtro = filtro),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (acoes.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          children: [
                            Icon(Icons.task_alt_rounded, size: 44),
                            SizedBox(height: 8),
                            Text('Nenhuma ação neste filtro.'),
                          ],
                        ),
                      ),
                    )
                  else
                    ...acoes.map(_acaoCard),
                ],
              ),
      ),
    );
  }

  Widget _acaoCard(CrmAcaoRelacionamento acao) {
    final data = acao.vencimentoData;
    final atrasada = acao.atrasadaEm(DateTime.now());
    final icon = switch (acao.tipo) {
      'Follow-up lead' => Icons.person_search_outlined,
      'Follow-up orçamento' => Icons.request_quote_outlined,
      'Pós-venda' => Icons.volunteer_activism_outlined,
      'Benefício/cupom' => Icons.card_giftcard_outlined,
      _ => Icons.checklist_outlined,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acao.titulo,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        [
                          acao.nomeContato,
                          if (data != null) _data.format(data),
                          if (acao.prioridade == 'Alta') 'Prioridade alta',
                        ].where((item) => item.trim().isNotEmpty).join(' • '),
                        style: TextStyle(
                          color: atrasada
                              ? Colors.orangeAccent
                              : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                if (acao.status == 'Pendente')
                  PopupMenuButton<String>(
                    onSelected: (valor) {
                      if (valor == 'adiar') _adiar(acao);
                      if (valor == 'ignorar') _ignorar(acao);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'adiar', child: Text('Adiar')),
                      PopupMenuItem(value: 'ignorar', child: Text('Ignorar')),
                    ],
                  ),
              ],
            ),
            if (acao.mensagemSugerida.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                acao.mensagemSugerida,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (acao.status == 'Pendente') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: acao.telefone.trim().isEmpty
                        ? null
                        : () => _abrirWhatsApp(acao),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _concluir(acao),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Concluir'),
                  ),
                  if (acao.entidadeTipo == 'orcamento')
                    OutlinedButton.icon(
                      onPressed: () => _abrirOrcamento(acao),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Orçamento'),
                    ),
                  if (acao.entidadeTipo == 'orcamento')
                    OutlinedButton.icon(
                      onPressed: () => _levarOrcamentoAoFunil(acao),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Levar ao funil'),
                    ),
                ],
              ),
            ],
            if (acao.observacoes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                acao.observacoes,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResumoOperacao extends StatelessWidget {
  const _ResumoOperacao({required this.resumo, required this.moeda});

  final CrmOperacaoResumo resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Operação comercial',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ResumoChip(titulo: 'Atrasadas', valor: '${resumo.atrasadas}'),
                _ResumoChip(titulo: 'Hoje', valor: '${resumo.hoje}'),
                _ResumoChip(
                  titulo: 'Próx. 7 dias',
                  valor: '${resumo.proximosSeteDias}',
                ),
                _ResumoChip(
                  titulo: 'Concluídas no mês',
                  valor: '${resumo.concluidasMes}',
                ),
                _ResumoChip(
                  titulo: 'Orçamentos pendentes',
                  valor: '${resumo.orcamentosPendentes}',
                ),
                _ResumoChip(
                  titulo: 'Valor em orçamento',
                  valor: moeda.format(resumo.valorOrcamentosPendentes),
                ),
                _ResumoChip(
                  titulo: 'Cupons ativos',
                  valor: '${resumo.cuponsAtivos}',
                ),
                _ResumoChip(
                  titulo: 'Receita via cupom/mês',
                  valor: moeda.format(resumo.receitaCuponsUsados),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoChip extends StatelessWidget {
  const _ResumoChip({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Text('$titulo: $valor'),
    );
  }
}
