import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../repositories/precificacao_repository.dart';
import '../services/operacional_realtime_service.dart';
import '../services/operacional_sync_service.dart';
import '../services/precificacao_cloud_v2_service.dart';

class PrecificacaoCloudCentralPage extends StatefulWidget {
  const PrecificacaoCloudCentralPage({super.key});

  @override
  State<PrecificacaoCloudCentralPage> createState() =>
      _PrecificacaoCloudCentralPageState();
}

class _PrecificacaoCloudCentralPageState
    extends State<PrecificacaoCloudCentralPage> {
  final PrecificacaoRepository _repository = PrecificacaoRepository();
  final PrecificacaoCloudV2Service _cloud = PrecificacaoCloudV2Service.instance;
  StreamSubscription<void>? _operacionalRealtimeSubscription;
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _sincronizando = false;
  bool _recarregandoPorRealtime = false;
  String? _empresaId;
  PrecificacaoPainel? _painel;
  List<Map<String, Object?>> _conflitos = const [];
  List<Map<String, Object?>> _simulacoes = const [];

  @override
  void initState() {
    super.initState();
    _operacionalRealtimeSubscription = OperacionalRealtimeService
        .instance
        .atualizacoes
        .listen((_) {
          unawaited(_recarregarPorRealtime());
        });
    _carregar();
  }

  @override
  void dispose() {
    _operacionalRealtimeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _recarregarPorRealtime() async {
    if (!mounted ||
        _recarregandoPorRealtime ||
        _carregando ||
        _sincronizando) {
      return;
    }

    _recarregandoPorRealtime = true;
    try {
      final empresaId = await OperacionalSyncService.instance.empresaAtualId();
      final painel = await _repository.carregar();

      List<Map<String, Object?>> conflitos = const [];
      List<Map<String, Object?>> simulacoes = const [];

      if (empresaId != null && empresaId.isNotEmpty) {
        conflitos = await _cloud.listarConflitosPendentes(empresaId: empresaId);
        simulacoes = await _cloud.listarSimulacoes(empresaId);
      }

      if (!mounted) return;

      setState(() {
        _empresaId = empresaId;
        _painel = painel;
        _conflitos = conflitos;
        _simulacoes = simulacoes;
      });
    } catch (_) {
      // Realtime é um acelerador; a central mantém o último snapshot local.
    } finally {
      _recarregandoPorRealtime = false;
    }
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final empresaId = await OperacionalSyncService.instance.empresaAtualId();
      final painel = await _repository.carregar();

      List<Map<String, Object?>> conflitos = const [];
      List<Map<String, Object?>> simulacoes = const [];

      if (empresaId != null && empresaId.isNotEmpty) {
        conflitos = await _cloud.listarConflitosPendentes(empresaId: empresaId);
        simulacoes = await _cloud.listarSimulacoes(empresaId);
      }

      if (!mounted) return;

      setState(() {
        _empresaId = empresaId;
        _painel = painel;
        _conflitos = conflitos;
        _simulacoes = simulacoes;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem(
        'Não foi possível abrir a Central de Precificação.\n$erro',
        erro: true,
      );
    }
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    try {
      await OperacionalSyncService.instance.tentarSincronizarTudo();
      await _carregar();

      if (mounted) {
        _mensagem('Sincronização da precificação concluída.');
      }
    } finally {
      if (mounted) {
        setState(() => _sincronizando = false);
      }
    }
  }

  Future<void> _aplicarPreco(PrecificacaoServico servico) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Aplicar preço sugerido?'),
          content: Text(
            '${servico.nome}\n\n'
            'Preço atual: ${_moeda.format(servico.precoAtual)}\n'
            'Preço sugerido: ${_moeda.format(servico.precoSugerido)}\n\n'
            'O catálogo será alterado somente para este serviço.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await _repository.aplicarPrecoPadrao(
        servicoId: servico.id,
        preco: servico.precoSugerido,
      );

      await OperacionalSyncService.instance.tentarSincronizarTudo();
      await _carregar();

      if (mounted) {
        _mensagem('Preço de ${servico.nome} atualizado.');
      }
    } catch (erro) {
      if (mounted) {
        _mensagem('$erro', erro: true);
      }
    }
  }

  Future<void> _novaSimulacao() async {
    final empresaId = _empresaId;
    final painel = _painel;

    if (empresaId == null || empresaId.isEmpty || painel == null) {
      _mensagem(
        'A empresa precisa estar conectada à nuvem para salvar cenários.',
        erro: true,
      );
      return;
    }

    final nomeController = TextEditingController(
      text: 'Cenário ${DateFormat('dd/MM HH:mm').format(DateTime.now())}',
    );
    final margemClienteController = TextEditingController(
      text: _numero(painel.config.margemCliente),
    );
    final margem1a4Controller = TextEditingController(
      text: _numero(painel.config.margemRevenda1a4),
    );
    final margem5a9Controller = TextEditingController(
      text: _numero(painel.config.margemRevenda5a9),
    );
    final margem10Controller = TextEditingController(
      text: _numero(painel.config.margemRevenda10Mais),
    );
    final margemMinimaController = TextEditingController(
      text: _numero(painel.config.margemMinima),
    );
    final taxaController = TextEditingController(
      text: _numero(painel.resumo.taxaCartaoMediaPercentual),
    );
    final custoHoraController = TextEditingController(
      text: _numero(painel.resumo.custoHora),
    );
    final metaController = TextEditingController(text: '0');
    final observacoesController = TextEditingController();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Novo cenário de precificação'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do cenário',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CampoNumero(
                    controller: margemClienteController,
                    label: 'Margem cliente',
                    suffix: '%',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CampoNumero(
                          controller: margem1a4Controller,
                          label: 'Revenda 1–4',
                          suffix: '%',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CampoNumero(
                          controller: margem5a9Controller,
                          label: 'Revenda 5–9',
                          suffix: '%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CampoNumero(
                          controller: margem10Controller,
                          label: 'Revenda 10+',
                          suffix: '%',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CampoNumero(
                          controller: margemMinimaController,
                          label: 'Margem mínima',
                          suffix: '%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CampoNumero(
                          controller: taxaController,
                          label: 'Taxa média cartão',
                          suffix: '%',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CampoNumero(
                          controller: custoHoraController,
                          label: 'Custo-hora',
                          prefix: r'R$ ',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _CampoNumero(
                    controller: metaController,
                    label: 'Meta de faturamento do cenário',
                    prefix: r'R$ ',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: observacoesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O cenário é apenas uma simulação. Ele não altera os '
                    'preços do catálogo.',
                    style: TextStyle(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Simular e salvar'),
            ),
          ],
        );
      },
    );

    if (salvar == true) {
      try {
        await _cloud.simularESalvar(
          empresaId: empresaId,
          nome: nomeController.text,
          margemCliente: _valor(margemClienteController.text),
          margemRevenda1a4: _valor(margem1a4Controller.text),
          margemRevenda5a9: _valor(margem5a9Controller.text),
          margemRevenda10Mais: _valor(margem10Controller.text),
          margemMinima: _valor(margemMinimaController.text),
          taxaCartaoPercentual: _valor(taxaController.text),
          custoHora: _valor(custoHoraController.text),
          metaFaturamento: _valor(metaController.text),
          observacoes: observacoesController.text,
        );

        await _carregar();

        if (mounted) {
          _mensagem('Cenário calculado e salvo.');
        }
      } catch (erro) {
        if (mounted) {
          _mensagem('$erro', erro: true);
        }
      }
    }

    nomeController.dispose();
    margemClienteController.dispose();
    margem1a4Controller.dispose();
    margem5a9Controller.dispose();
    margem10Controller.dispose();
    margemMinimaController.dispose();
    taxaController.dispose();
    custoHoraController.dispose();
    metaController.dispose();
    observacoesController.dispose();
  }

  Future<void> _resolverConflito(
    Map<String, Object?> conflito, {
    required bool usarLocal,
  }) async {
    final id = _int(conflito['id']);
    if (id <= 0) return;

    final entidade = _rotuloEntidade(_texto(conflito['entidade']));
    final escolha = usarLocal ? 'versão deste aparelho' : 'versão da nuvem';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Resolver conflito?'),
          content: Text(
            '$entidade\n\n'
            'Será mantida a $escolha.\n\n'
            'A outra versão será substituída.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      if (usarLocal) {
        await _cloud.resolverUsandoLocal(id);
      } else {
        await _cloud.resolverUsandoNuvem(id);
      }

      await OperacionalSyncService.instance.tentarSincronizarTudo();
      await _carregar();

      if (mounted) {
        _mensagem('Conflito resolvido.');
      }
    } catch (erro) {
      if (mounted) {
        _mensagem('$erro', erro: true);
      }
    }
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
    final painel = _painel;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Central de Precificação'),
          actions: [
            IconButton(
              tooltip: 'Sincronizar agora',
              onPressed: _sincronizando ? null : _sincronizar,
              icon: _sincronizando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_rounded),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.monitor_heart_outlined),
                text: 'Visão geral',
              ),
              Tab(icon: Icon(Icons.science_outlined), text: 'Simulações'),
              Tab(icon: Icon(Icons.sync_problem_rounded), text: 'Conflitos'),
            ],
          ),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : painel == null
            ? const Center(
                child: Text('Não foi possível carregar a precificação.'),
              )
            : TabBarView(
                children: [
                  _visaoGeral(painel),
                  _simulacoesTab(),
                  _conflitosTab(),
                ],
              ),
      ),
    );
  }

  Widget _visaoGeral(PrecificacaoPainel painel) {
    final criticos = painel.servicos
        .where((item) => item.margemAtual < painel.config.margemMinima)
        .toList();
    final prejuizo = painel.servicos
        .where((item) => item.precoAtual < item.precoEquilibrio)
        .toList();

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
        children: [
          if (_empresaId == null || _empresaId!.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_rounded),
                title: const Text('Nuvem indisponível'),
                subtitle: const Text(
                  'Os cálculos locais continuam funcionando. Faça login na '
                  'empresa para usar conflitos e simulações compartilhadas.',
                ),
                trailing: const Icon(Icons.info_outline_rounded),
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ResumoCard(
                titulo: 'Serviços',
                valor: '${painel.servicos.length}',
                icone: Icons.build_circle_outlined,
              ),
              _ResumoCard(
                titulo: 'Margem crítica',
                valor: '${criticos.length}',
                icone: Icons.warning_amber_rounded,
              ),
              _ResumoCard(
                titulo: 'Abaixo do equilíbrio',
                valor: '${prejuizo.length}',
                icone: Icons.trending_down_rounded,
              ),
              _ResumoCard(
                titulo: 'Conflitos',
                valor: '${_conflitos.length}',
                icone: Icons.sync_problem_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Base de cálculo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _linha('Custo-hora', _moeda.format(painel.resumo.custoHora)),
                  _linha(
                    'Base mensal usada',
                    _moeda.format(painel.resumo.baseMensalUsada),
                  ),
                  _linha(
                    'Taxa média de cartão',
                    '${painel.resumo.taxaCartaoMediaPercentual.toStringAsFixed(2)}%',
                  ),
                  _linha(
                    'Margem mínima',
                    '${painel.config.margemMinima.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Serviços que precisam de atenção',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (criticos.isEmpty && prejuizo.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nenhum serviço está abaixo da margem mínima ou do '
                        'ponto de equilíbrio.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...painel.servicos
                .where(
                  (item) =>
                      item.margemAtual < painel.config.margemMinima ||
                      item.precoAtual < item.precoEquilibrio,
                )
                .map(
                  (servico) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _servicoCriticoCard(painel, servico),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _servicoCriticoCard(
    PrecificacaoPainel painel,
    PrecificacaoServico servico,
  ) {
    final abaixoEquilibrio = servico.precoAtual < servico.precoEquilibrio;
    final margemCritica = servico.margemAtual < painel.config.margemMinima;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    servico.nome,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (abaixoEquilibrio)
                  const _Badge(texto: 'Prejuízo')
                else if (margemCritica)
                  const _Badge(texto: 'Margem baixa'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Text('Atual: ${_moeda.format(servico.precoAtual)}'),
                Text('Custo: ${_moeda.format(servico.custoBase)}'),
                Text('Equilíbrio: ${_moeda.format(servico.precoEquilibrio)}'),
                Text(
                  'Sugerido: ${_moeda.format(servico.precoSugerido)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Margem: ${servico.margemAtual.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: servico.precoSugerido <= 0
                    ? null
                    : () => _aplicarPreco(servico),
                icon: const Icon(Icons.price_change_outlined),
                label: const Text('Aplicar sugerido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simulacoesTab() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
        children: [
          FilledButton.icon(
            onPressed: _empresaId == null ? null : _novaSimulacao,
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Criar novo cenário'),
          ),
          const SizedBox(height: 12),
          Text(
            'Os cenários não alteram o catálogo. Eles ficam salvos para '
            'comparar margens, taxa de cartão, custo-hora e metas.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_simulacoes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Nenhuma simulação salva ainda.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._simulacoes.map(
              (simulacao) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _simulacaoCard(simulacao),
              ),
            ),
        ],
      ),
    );
  }

  Widget _simulacaoCard(Map<String, Object?> simulacao) {
    final resultado = _resultadoSimulacao(simulacao);
    final quantidade = _int(resultado['quantidade_servicos']);
    final criado = DateTime.tryParse(_texto(simulacao['criado_em']));
    final remoto = _texto(simulacao['remoto_id']).isNotEmpty;

    return Card(
      child: ExpansionTile(
        leading: Icon(
          remoto ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        ),
        title: Text(
          _texto(simulacao['nome']).isEmpty
              ? 'Cenário'
              : _texto(simulacao['nome']),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${criado == null ? '' : _dataHora.format(criado)}'
          '${criado == null ? '' : ' • '}'
          '$quantidade serviços',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _linha(
            'Margem cliente',
            '${_double(simulacao['margem_cliente']).toStringAsFixed(1)}%',
          ),
          _linha(
            'Taxa cartão',
            '${_double(simulacao['taxa_cartao_percentual']).toStringAsFixed(2)}%',
          ),
          _linha('Custo-hora', _moeda.format(_double(simulacao['custo_hora']))),
          _linha(
            'Meta faturamento',
            _moeda.format(_double(simulacao['meta_faturamento'])),
          ),
          const Divider(),
          if (resultado['servicos'] is List)
            ...((resultado['servicos'] as List).take(5)).map((raw) {
              final item = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : <String, dynamic>{};

              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_texto(item['nome'])),
                subtitle: Text(
                  'Atual ${_moeda.format(_double(item['preco_atual']))} → '
                  'Sugerido ${_moeda.format(_double(item['preco_sugerido']))}',
                ),
              );
            }),
          if (quantidade > 5)
            Text(
              '+ ${quantidade - 5} serviços no cenário',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _conflitosTab() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
        children: [
          if (_conflitos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.cloud_done_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Nenhum conflito de precificação pendente.'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Quando o mesmo dado foi alterado em dois aparelhos, escolha '
              'qual versão deve prevalecer.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            ..._conflitos.map(
              (conflito) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _conflitoCard(conflito),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _conflitoCard(Map<String, Object?> conflito) {
    final entidade = _rotuloEntidade(_texto(conflito['entidade']));
    final motivo = _rotuloMotivo(_texto(conflito['motivo']));
    final detectado = DateTime.tryParse(_texto(conflito['detectado_em']));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_problem_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entidade,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(motivo),
            if (detectado != null) ...[
              const SizedBox(height: 4),
              Text(
                'Detectado em ${_dataHora.format(detectado)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _resolverConflito(conflito, usarLocal: false),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Usar nuvem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _resolverConflito(conflito, usarLocal: true),
                    icon: const Icon(Icons.phone_android_rounded),
                    label: const Text('Usar local'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          const SizedBox(width: 12),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Map<String, dynamic> _resultadoSimulacao(Map<String, Object?> simulacao) {
    final raw = _texto(simulacao['resultado_json']);
    if (raw.isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _rotuloEntidade(String valor) {
    switch (valor) {
      case 'config':
        return 'Configuração de margens';
      case 'servico':
        return 'Serviço do catálogo';
      case 'colaborador':
        return 'Custo de mão de obra';
      case 'preferencia':
        return 'Preferência do serviço';
      case 'receita':
        return 'Receita de produtos';
      default:
        return valor.isEmpty ? 'Precificação' : valor;
    }
  }

  String _rotuloMotivo(String valor) {
    switch (valor) {
      case 'alteracao_concorrente':
        return 'O mesmo registro foi alterado localmente e na nuvem.';
      case 'cas_falhou':
        return 'A nuvem mudou entre a conferência e a tentativa de salvar.';
      case 'cas_falhou_na_exclusao':
        return 'O registro remoto mudou antes da exclusão ser confirmada.';
      case 'exclusao_local_e_alteracao_remota':
        return 'Foi excluído localmente, mas alterado em outro aparelho.';
      case 'alteracao_local_e_exclusao_remota':
        return 'Foi alterado localmente, mas excluído em outro aparelho.';
      case 'remoto_ausente':
        return 'O registro remoto não existe mais.';
      default:
        return valor.replaceAll('_', ' ');
    }
  }

  String _numero(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toStringAsFixed(0);
    }
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _valor(String texto) {
    return double.tryParse(texto.trim().replaceAll(',', '.')) ?? 0;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone),
              const SizedBox(height: 8),
              Text(
                valor,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(titulo),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CampoNumero extends StatelessWidget {
  const _CampoNumero({
    required this.controller,
    required this.label,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
