import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/pendencias_operacionais_repository.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'ordens_servico_page.dart';
import 'ponto_funcionarios_page.dart';

class PendenciasOperacionaisPage extends StatefulWidget {
  const PendenciasOperacionaisPage({super.key});

  @override
  State<PendenciasOperacionaisPage> createState() =>
      _PendenciasOperacionaisPageState();
}

class _PendenciasOperacionaisPageState
    extends State<PendenciasOperacionaisPage> {
  final PendenciasOperacionaisRepository _repository =
      PendenciasOperacionaisRepository();

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  String? _erro;
  PendenciasOperacionaisResumo? _resumo;

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
      final resumo = await _repository.carregar();

      if (!mounted) return;

      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _carregando = false;
        _erro = _textoErro(erro);
      });
    }
  }

  Future<void> _abrirModulo(String modulo) async {
    Widget? pagina;

    switch (modulo) {
      case 'financeiro':
        pagina = const FinanceiroPage();
        break;
      case 'ordens_servico':
        pagina = const OrdensServicoPage(statusInicial: 'Todos');
        break;
      case 'estoque':
        pagina = const EstoquePage();
        break;
      case 'ponto':
        pagina = const PontoFuncionariosPage();
        break;
      case 'configuracoes':
        pagina = const ConfiguracoesPage();
        break;
    }

    if (pagina == null) return;

    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina!));

    await _carregar();
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto;
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendências operacionais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _erro != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 80),
                  _ErroCard(mensagem: _erro!, onTentarNovamente: _carregar),
                ],
              )
            : _conteudo(resumo!),
      ),
    );
  }

  Widget _conteudo(PendenciasOperacionaisResumo resumo) {
    final recebimentos = resumo.porTipo(
      PendenciaOperacionalTipo.recebimentoVencido,
    );
    final pagarVencidas = resumo.porTipo(
      PendenciaOperacionalTipo.contaPagarVencida,
    );
    final pagarProximas = resumo.porTipo(
      PendenciaOperacionalTipo.contaPagarProxima,
    );
    final ordens = resumo.porTipo(PendenciaOperacionalTipo.ordemServico);
    final estoque = resumo.porTipo(PendenciaOperacionalTipo.estoque);
    final ponto = resumo.porTipo(PendenciaOperacionalTipo.ponto);
    final backup = resumo.porTipo(PendenciaOperacionalTipo.backup);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      children: [
        _StatusGeralCard(resumo: resumo),
        const SizedBox(height: 12),
        _gradeResumo(resumo),
        if (!resumo.possuiPendencias) ...[
          const SizedBox(height: 14),
          const _TudoEmDiaCard(),
        ],
        if (recebimentos.isNotEmpty ||
            pagarVencidas.isNotEmpty ||
            pagarProximas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SecaoPendencias(
            titulo: 'Financeiro',
            subtitulo: 'Valores vencidos e compromissos dos próximos 7 dias.',
            icone: Icons.account_balance_wallet_outlined,
            actionLabel: 'Abrir Financeiro',
            onAction: () => _abrirModulo('financeiro'),
            itens: [...recebimentos, ...pagarVencidas, ...pagarProximas],
            moeda: _moeda,
          ),
        ],
        if (ordens.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SecaoPendencias(
            titulo: 'Ordens de Serviço',
            subtitulo: 'OS abertas ou em andamento há mais de 7 dias.',
            icone: Icons.car_repair_outlined,
            actionLabel: 'Abrir OS',
            onAction: () => _abrirModulo('ordens_servico'),
            itens: ordens,
            moeda: _moeda,
          ),
        ],
        if (ponto.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SecaoPendencias(
            titulo: 'Ponto dos funcionários',
            subtitulo: 'Dias passados sem registro e batidas incompletas.',
            icone: Icons.fingerprint_rounded,
            actionLabel: 'Abrir Ponto',
            onAction: () => _abrirModulo('ponto'),
            itens: ponto,
            moeda: _moeda,
          ),
        ],
        if (estoque.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SecaoPendencias(
            titulo: 'Estoque',
            subtitulo: 'Produtos no mínimo ou sem saldo disponível.',
            icone: Icons.inventory_2_outlined,
            actionLabel: 'Abrir Estoque',
            onAction: () => _abrirModulo('estoque'),
            itens: estoque,
            moeda: _moeda,
          ),
        ],
        if (backup.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SecaoPendencias(
            titulo: 'Segurança dos dados',
            subtitulo: 'Situação da cópia de segurança local.',
            icone: Icons.backup_outlined,
            actionLabel: 'Configurações',
            onAction: () => _abrirModulo('configuracoes'),
            itens: backup,
            moeda: _moeda,
          ),
        ],
        const SizedBox(height: 20),
        const _RegraRecebimentosCard(),
      ],
    );
  }

  Widget _gradeResumo(PendenciasOperacionaisResumo resumo) {
    final recebimentosQtd = resumo.quantidadePorTipo(
      PendenciaOperacionalTipo.recebimentoVencido,
    );
    final pagarVencidasQtd = resumo.quantidadePorTipo(
      PendenciaOperacionalTipo.contaPagarVencida,
    );
    final pagarProximasQtd = resumo.quantidadePorTipo(
      PendenciaOperacionalTipo.contaPagarProxima,
    );
    final ordensQtd = resumo.quantidadePorTipo(
      PendenciaOperacionalTipo.ordemServico,
    );
    final estoqueQtd = resumo.quantidadePorTipo(
      PendenciaOperacionalTipo.estoque,
    );
    final pontoQtd = resumo.quantidadePorTipo(PendenciaOperacionalTipo.ponto);

    return LayoutBuilder(
      builder: (context, constraints) {
        const espacamento = 8.0;
        final colunas = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 460
            ? 3
            : 2;
        final largura =
            (constraints.maxWidth - espacamento * (colunas - 1)) / colunas;

        final itens = <_IndicadorResumoDados>[
          _IndicadorResumoDados(
            titulo: 'Receber vencido',
            valor: _moeda.format(
              resumo.valorPorTipo(PendenciaOperacionalTipo.recebimentoVencido),
            ),
            detalhe: '$recebimentosQtd item(ns)',
            icone: Icons.money_off_csred_outlined,
            alerta: recebimentosQtd > 0,
          ),
          _IndicadorResumoDados(
            titulo: 'Pagar vencido',
            valor: _moeda.format(
              resumo.valorPorTipo(PendenciaOperacionalTipo.contaPagarVencida),
            ),
            detalhe: '$pagarVencidasQtd item(ns)',
            icone: Icons.event_busy_outlined,
            alerta: pagarVencidasQtd > 0,
          ),
          _IndicadorResumoDados(
            titulo: 'Próximos 7 dias',
            valor: _moeda.format(
              resumo.valorPorTipo(PendenciaOperacionalTipo.contaPagarProxima),
            ),
            detalhe: '$pagarProximasQtd conta(s)',
            icone: Icons.event_outlined,
          ),
          _IndicadorResumoDados(
            titulo: 'OS paradas',
            valor: '$ordensQtd',
            detalhe: 'há mais de 7 dias',
            icone: Icons.car_crash_outlined,
            alerta: ordensQtd > 0,
          ),
          _IndicadorResumoDados(
            titulo: 'Estoque',
            valor: '$estoqueQtd',
            detalhe: 'item(ns) em atenção',
            icone: Icons.inventory_outlined,
            alerta: estoqueQtd > 0,
          ),
          _IndicadorResumoDados(
            titulo: 'Ponto',
            valor: '$pontoQtd',
            detalhe: 'funcionário(s)',
            icone: Icons.pending_actions_outlined,
            alerta: pontoQtd > 0,
          ),
        ];

        return Wrap(
          spacing: espacamento,
          runSpacing: espacamento,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: _IndicadorResumoCard(dados: item),
              ),
          ],
        );
      },
    );
  }
}

class _StatusGeralCard extends StatelessWidget {
  const _StatusGeralCard({required this.resumo});

  final PendenciasOperacionaisResumo resumo;

  @override
  Widget build(BuildContext context) {
    final semPendencias = !resumo.possuiPendencias;
    final cor = semPendencias
        ? Colors.greenAccent
        : resumo.totalCriticas > 0
        ? Theme.of(context).colorScheme.error
        : Colors.orangeAccent;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              semPendencias
                  ? Icons.task_alt_rounded
                  : Icons.notification_important_outlined,
              color: cor,
              size: 28,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    semPendencias ? 'Operação em dia' : 'Atenção necessária',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    semPendencias
                        ? 'Nenhuma pendência operacional foi encontrada agora.'
                        : '${resumo.totalCriticas} crítica(s) • '
                              '${resumo.totalAtencao} item(ns) de atenção',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicadorResumoDados {
  const _IndicadorResumoDados({
    required this.titulo,
    required this.valor,
    required this.detalhe,
    required this.icone,
    this.alerta = false,
  });

  final String titulo;
  final String valor;
  final String detalhe;
  final IconData icone;
  final bool alerta;
}

class _IndicadorResumoCard extends StatelessWidget {
  const _IndicadorResumoCard({required this.dados});

  final _IndicadorResumoDados dados;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              dados.icone,
              size: 20,
              color: dados.alerta ? Colors.orangeAccent : null,
            ),
            const SizedBox(height: 9),
            Text(
              dados.valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Text(
              dados.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              dados.detalhe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecaoPendencias extends StatelessWidget {
  const _SecaoPendencias({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.actionLabel,
    required this.onAction,
    required this.itens,
    required this.moeda,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final String actionLabel;
  final VoidCallback onAction;
  final List<PendenciaOperacional> itens;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
        const SizedBox(height: 7),
        ...itens.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              onTap: onAction,
              leading: Icon(
                item.nivel == PendenciaOperacionalNivel.critica
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                color: item.nivel == PendenciaOperacionalNivel.critica
                    ? Theme.of(context).colorScheme.error
                    : Colors.orangeAccent,
              ),
              title: Text(
                item.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.descricao.trim().isEmpty
                  ? null
                  : Text(
                      item.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: item.valor == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          moeda.format(item.valor),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TudoEmDiaCard extends StatelessWidget {
  const _TudoEmDiaCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: Colors.greenAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhuma cobrança vencida, conta atrasada, OS parada, '
                'estoque baixo, pendência de ponto ou problema de backup.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegraRecebimentosCard extends StatelessWidget {
  const _RegraRecebimentosCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Em vendas parceladas, “Receber vencido” considera somente '
                'as parcelas cuja data já passou. Parcelas futuras continuam '
                'em Contas a Receber, mas não aparecem como atraso.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroCard extends StatelessWidget {
  const _ErroCard({required this.mensagem, required this.onTentarNovamente});

  final String mensagem;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar as pendências',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 7),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
