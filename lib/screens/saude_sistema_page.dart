import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../repositories/saude_sistema_repository.dart';

class SaudeSistemaPage extends StatefulWidget {
  const SaudeSistemaPage({super.key});

  @override
  State<SaudeSistemaPage> createState() => _SaudeSistemaPageState();
}

class _SaudeSistemaPageState extends State<SaudeSistemaPage> {
  final SaudeSistemaRepository _repository = SaudeSistemaRepository();
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _testandoNuvem = false;
  bool _sincronizando = false;
  bool _sincronizandoPonto = false;
  String? _erro;
  SaudeSistemaResumo? _resumo;
  Map<String, dynamic>? _nuvem;

  @override
  void initState() {
    super.initState();
    _carregarLocal();
  }

  Future<void> _carregarLocal() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resumo = await _repository.diagnosticarLocal();
      if (!mounted) {
        return;
      }
      setState(() {
        _resumo = resumo;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() {
        _carregando = false;
        _erro = _textoErro(erro);
      });
    }
  }

  Future<void> _testarNuvem() async {
    if (_testandoNuvem || _sincronizando) {
      return;
    }

    setState(() {
      _testandoNuvem = true;
      _nuvem = null;
    });

    try {
      final resultado = await _repository.diagnosticarNuvem();
      if (!mounted) {
        return;
      }
      setState(() {
        _nuvem = resultado;
        _testandoNuvem = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nuvem = {'saudavel': false, 'mensagem': _textoErro(erro)};
        _testandoNuvem = false;
      });
    }
  }

  Future<void> _sincronizarTudo() async {
    if (_sincronizando || _testandoNuvem) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar agora?'),
        content: const Text(
          'Esta ação executa o motor de sincronização que já existe no '
          'Imperium para clientes, veículos, agenda, OS e Ponto. Ela não '
          'migra Financeiro nem Estoque para a nuvem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _sincronizando = true;
    });

    try {
      final executou = await _repository.sincronizarAgora();
      if (!mounted) {
        return;
      }
      if (!executou) {
        _mensagem(
          'A sincronização não iniciou porque não há conta/empresa Supabase ativa.',
          erro: true,
        );
        return;
      }
      _mensagem('Sincronização concluída pelo motor atual.');
      await _carregarLocal();
      await _testarNuvem();
    } catch (erro) {
      if (!mounted) {
        return;
      }
      _mensagem('Falha na sincronização: ${_textoErro(erro)}', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
        });
      }
    }
  }

  Future<void> _sincronizarFilaPonto() async {
    if (_sincronizandoPonto) {
      return;
    }

    setState(() {
      _sincronizandoPonto = true;
    });

    try {
      final enviados = await _repository.sincronizarPontoPendente();
      if (!mounted) {
        return;
      }
      _mensagem('$enviados batida(s) pendente(s) processada(s).');
      await _carregarLocal();
    } catch (erro) {
      if (!mounted) {
        return;
      }
      _mensagem(
        'Falha ao sincronizar a fila do Ponto: ${_textoErro(erro)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _sincronizandoPonto = false;
        });
      }
    }
  }

  Future<void> _copiarRelatorio() async {
    final resumo = _resumo;
    if (resumo == null) {
      return;
    }

    final buffer = StringBuffer(resumo.gerarRelatorio());
    final nuvem = _nuvem;
    if (nuvem != null) {
      buffer
        ..writeln('')
        ..writeln('')
        ..writeln('NUVEM')
        ..writeln('- saudável: ${nuvem['saudavel'] == true ? 'sim' : 'não'}')
        ..writeln('- empresa: ${_mascararId(nuvem['empresa_id']?.toString())}')
        ..writeln('- mensagem: ${(nuvem['mensagem'] ?? '').toString()}');

      final ponto = nuvem['ponto'];
      if (ponto is Map) {
        buffer
          ..writeln('- backend Ponto: ${(ponto['backend_version'] ?? 0)}')
          ..writeln(
            '- empresa confere: ${ponto['empresa_confere'] == true ? 'sim' : 'não'}',
          )
          ..writeln(
            '- idempotência: ${ponto['tabela_idempotencia'] == true ? 'sim' : 'não'}',
          )
          ..writeln(
            '- realtime: ${ponto['realtime_ponto_registros'] == true ? 'sim' : 'não'}',
          );
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) {
      return;
    }
    _mensagem('Relatório de saúde copiado.');
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

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'Exception: ',
      'DatabaseException(',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto.length > 600 ? texto.substring(0, 600) : texto;
  }

  String _mascararId(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return 'não identificada';
    }
    if (texto.length <= 10) {
      return texto;
    }
    return '${texto.substring(0, 6)}…${texto.substring(texto.length - 4)}';
  }

  String _formatarData(String? iso) {
    final texto = iso?.trim() ?? '';
    if (texto.isEmpty) {
      return 'Nunca registrado';
    }
    final data = DateTime.tryParse(texto);
    return data == null ? texto : _dataHora.format(data.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saúde e homologação'),
        actions: [
          IconButton(
            tooltip: 'Copiar relatório',
            onPressed: _resumo == null ? null : _copiarRelatorio,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregarLocal,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarLocal,
        child: _carregando
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _erro != null
            ? _ErroSaude(mensagem: _erro!, onRetry: _carregarLocal)
            : _conteudo(_resumo!),
      ),
    );
  }

  Widget _conteudo(SaudeSistemaResumo resumo) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
      children: [
        _StatusGeral(resumo: resumo),
        const SizedBox(height: 14),
        _secaoBanco(resumo),
        const SizedBox(height: 14),
        _secaoSincronizacao(resumo),
        const SizedBox(height: 14),
        _secaoAcessos(resumo.acessos),
        const SizedBox(height: 14),
        _secaoAlertas(resumo),
        const SizedBox(height: 14),
        _cardRegraSeguranca(),
      ],
    );
  }

  Widget _secaoBanco(SaudeSistemaResumo resumo) {
    return _SecaoSaude(
      titulo: 'Banco local',
      subtitulo: 'Integridade, schema e volume atual do SQLite.',
      icone: Icons.storage_outlined,
      children: [
        _LinhaInfo(
          titulo: 'Schema',
          valor: '${resumo.versaoSchema}',
          detalhe: 'Versão esperada pelo aplicativo',
          ok: resumo.versaoSchema > 0,
        ),
        _LinhaInfo(
          titulo: 'SQLite quick_check',
          valor: resumo.sqliteIntegro ? 'OK' : 'Falha',
          detalhe: resumo.sqliteMensagem,
          ok: resumo.sqliteIntegro,
        ),
        _LinhaInfo(
          titulo: 'Foreign keys',
          valor: '${resumo.violacoesForeignKey}',
          detalhe: 'Vínculos quebrados encontrados',
          ok: resumo.violacoesForeignKey == 0,
        ),
        const Divider(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: resumo.contagens.entries
              .map(
                (entry) => _ContagemChip(titulo: entry.key, valor: entry.value),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _secaoSincronizacao(SaudeSistemaResumo resumo) {
    final nuvem = _nuvem;
    final ponto = nuvem?['ponto'];

    return _SecaoSaude(
      titulo: 'Nuvem e sincronização',
      subtitulo:
          'Mostra o que já está mapeado e permite testar o backend sem alterar regras protegidas.',
      icone: Icons.cloud_sync_outlined,
      children: [
        _LinhaInfo(
          titulo: 'Empresa deste aparelho',
          valor: _mascararId(resumo.empresaCache),
          detalhe: resumo.tenantsMapeados <= 1
              ? 'Mapeamento local compatível com um único tenant.'
              : '${resumo.tenantsMapeados} tenants aparecem nos mapas locais.',
          ok: resumo.tenantsMapeados <= 1,
        ),
        _LinhaInfo(
          titulo: 'Última sincronização',
          valor: _formatarData(resumo.ultimoSyncEm),
          detalhe: 'Registrada pelo motor OperacionalSyncService.',
        ),
        _LinhaInfo(
          titulo: 'Exclusões pendentes',
          valor: '${resumo.exclusoesSyncPendentes}',
          detalhe: 'Tombstones aguardando envio para a nuvem.',
          ok: resumo.exclusoesSyncPendentes == 0,
        ),
        _LinhaInfo(
          titulo: 'Fila offline do Ponto',
          valor: '${resumo.pontoPendentes}',
          detalhe: 'Batidas aguardando retry idempotente.',
          ok: resumo.pontoPendentes == 0,
        ),
        const SizedBox(height: 8),
        ...resumo.coberturaSync.map(
          (item) => _CoberturaSyncBar(cobertura: item),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _testandoNuvem || _sincronizando ? null : _testarNuvem,
              icon: _testandoNuvem
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(_testandoNuvem ? 'Testando...' : 'Testar nuvem'),
            ),
            OutlinedButton.icon(
              onPressed: _sincronizando || _testandoNuvem
                  ? null
                  : _sincronizarTudo,
              icon: _sincronizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(
                _sincronizando ? 'Sincronizando...' : 'Sincronizar agora',
              ),
            ),
            if (resumo.pontoPendentes > 0)
              OutlinedButton.icon(
                onPressed: _sincronizandoPonto ? null : _sincronizarFilaPonto,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(
                  _sincronizandoPonto
                      ? 'Processando...'
                      : 'Enviar fila do Ponto',
                ),
              ),
          ],
        ),
        if (nuvem != null) ...[
          const SizedBox(height: 14),
          _ResultadoNuvemCard(
            saudavel: nuvem['saudavel'] == true,
            mensagem: (nuvem['mensagem'] ?? '').toString(),
            empresa: _mascararId(nuvem['empresa_id']?.toString()),
            backendPonto: ponto is Map
                ? (ponto['backend_version'] ?? 0).toString()
                : '-',
            realtime: ponto is Map && ponto['realtime_ponto_registros'] == true,
            idempotencia: ponto is Map && ponto['tabela_idempotencia'] == true,
          ),
        ],
      ],
    );
  }

  Widget _secaoAcessos(SaudeAcessosResumo acessos) {
    return _SecaoSaude(
      titulo: 'Usuários e segurança',
      subtitulo: 'Auditoria local de login e configuração dos usuários.',
      icone: Icons.admin_panel_settings_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ContagemChip(titulo: 'Ativos', valor: acessos.usuariosAtivos),
            _ContagemChip(titulo: 'Inativos', valor: acessos.usuariosInativos),
            _ContagemChip(titulo: 'Sem PIN', valor: acessos.usuariosSemPin),
            _ContagemChip(titulo: 'Logins 24h', valor: acessos.sucessos24h),
            _ContagemChip(titulo: 'Falhas 24h', valor: acessos.falhas24h),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Acessos recentes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (acessos.acessosRecentes.isEmpty)
          const Text(
            'Nenhum acesso registrado.',
            style: TextStyle(color: Colors.white60),
          )
        else
          ...acessos.acessosRecentes.take(15).map(_acessoTile),
      ],
    );
  }

  Widget _acessoTile(Map<String, dynamic> acesso) {
    final sucesso = _int(acesso['sucesso']) == 1;
    final nome = (acesso['usuario_nome'] ?? '').toString().trim();
    final login = (acesso['login'] ?? '').toString().trim();
    final motivo = (acesso['motivo'] ?? '').toString().trim();
    final data = DateTime.tryParse((acesso['criado_em'] ?? '').toString());

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        sucesso ? Icons.check_circle_outline : Icons.error_outline,
        color: sucesso ? Colors.greenAccent : Colors.orangeAccent,
      ),
      title: Text(nome.isEmpty ? login : '$nome ($login)'),
      subtitle: Text(
        [
          if (motivo.isNotEmpty) motivo,
          if (data != null) _dataHora.format(data.toLocal()),
        ].join(' • '),
      ),
    );
  }

  Widget _secaoAlertas(SaudeSistemaResumo resumo) {
    return _SecaoSaude(
      titulo: 'Integridade e pendências',
      subtitulo: 'Nenhum item desta lista é corrigido automaticamente.',
      icone: Icons.fact_check_outlined,
      children: [
        if (resumo.itens.isEmpty)
          const _SemAlertasCard()
        else
          ...resumo.itens.map((item) => _AlertaSaudeTile(item: item)),
      ],
    );
  }

  Widget _cardRegraSeguranca() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFFD6A84B)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Esta central é principalmente diagnóstica. Ela não apaga dados, '
              'não troca empresa, não altera RLS e não migra Financeiro nem Estoque '
              'para a nuvem. A sincronização só é executada quando você toca '
              'explicitamente no botão correspondente.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  int _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}

class _StatusGeral extends StatelessWidget {
  const _StatusGeral({required this.resumo});

  final SaudeSistemaResumo resumo;

  @override
  Widget build(BuildContext context) {
    final cor = resumo.criticos > 0
        ? Colors.redAccent
        : resumo.atencoes > 0
        ? Colors.orangeAccent
        : Colors.greenAccent;
    final titulo = resumo.criticos > 0
        ? 'Atenção: inconsistência crítica'
        : resumo.atencoes > 0
        ? 'Sistema íntegro, com pendências'
        : 'Integridade local aprovada';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withValues(alpha: 0.38)),
      ),
      child: Row(
        children: [
          Icon(
            resumo.criticos > 0
                ? Icons.warning_amber_rounded
                : Icons.verified_outlined,
            color: cor,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${resumo.criticos} crítico(s) • ${resumo.atencoes} atenção(ões) • schema ${resumo.versaoSchema}',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecaoSaude extends StatelessWidget {
  const _SecaoSaude({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.children,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icone, color: const Color(0xFFD6A84B)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({
    required this.titulo,
    required this.valor,
    required this.detalhe,
    this.ok,
  });

  final String titulo;
  final String valor;
  final String detalhe;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ok != null) ...[
            Icon(
              ok! ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              size: 19,
              color: ok! ? Colors.greenAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  detalhe,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContagemChip extends StatelessWidget {
  const _ContagemChip({required this.titulo, required this.valor});

  final String titulo;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Text('$titulo: $valor'),
    );
  }
}

class _CoberturaSyncBar extends StatelessWidget {
  const _CoberturaSyncBar({required this.cobertura});

  final SaudeCoberturaSync cobertura;

  @override
  Widget build(BuildContext context) {
    final percentual = cobertura.percentual;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(cobertura.entidade)),
              Text('${cobertura.mapeados}/${cobertura.locais}'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percentual / 100,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class _ResultadoNuvemCard extends StatelessWidget {
  const _ResultadoNuvemCard({
    required this.saudavel,
    required this.mensagem,
    required this.empresa,
    required this.backendPonto,
    required this.realtime,
    required this.idempotencia,
  });

  final bool saudavel;
  final String mensagem;
  final String empresa;
  final String backendPonto;
  final bool realtime;
  final bool idempotencia;

  @override
  Widget build(BuildContext context) {
    final cor = saudavel ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                saudavel ? Icons.cloud_done : Icons.cloud_off_outlined,
                color: cor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  saudavel
                      ? 'Diagnóstico da nuvem aprovado'
                      : 'Nuvem com pendências',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(mensagem, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            'Empresa $empresa • Ponto backend $backendPonto • '
            'Realtime ${realtime ? 'OK' : 'pendente'} • '
            'Idempotência ${idempotencia ? 'OK' : 'pendente'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AlertaSaudeTile extends StatelessWidget {
  const _AlertaSaudeTile({required this.item});

  final SaudeItem item;

  @override
  Widget build(BuildContext context) {
    final (icone, cor) = switch (item.nivel) {
      SaudeNivel.critico => (Icons.error_outline, Colors.redAccent),
      SaudeNivel.atencao => (Icons.warning_amber_rounded, Colors.orangeAccent),
      SaudeNivel.ok => (Icons.check_circle_outline, Colors.greenAccent),
      SaudeNivel.informacao => (Icons.info_outline, Colors.lightBlueAccent),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone, color: cor),
      title: Text(item.titulo),
      subtitle: Text(item.detalhe),
    );
  }
}

class _SemAlertasCard extends StatelessWidget {
  const _SemAlertasCard();

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.verified_outlined, color: Colors.greenAccent),
      title: Text('Nenhuma inconsistência local detectada'),
      subtitle: Text(
        'Os checks de integridade executados nesta tela passaram.',
      ),
    );
  }
}

class _ErroSaude extends StatelessWidget {
  const _ErroSaude({required this.mensagem, required this.onRetry});

  final String mensagem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 90),
        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
        const SizedBox(height: 12),
        const Text(
          'Não foi possível gerar o diagnóstico',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(mensagem, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }
}
