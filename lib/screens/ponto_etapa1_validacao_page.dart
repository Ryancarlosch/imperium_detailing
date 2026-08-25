import 'package:flutter/material.dart';

import '../services/ponto_etapa1_validacao_service.dart';

class PontoEtapa1ValidacaoPage extends StatefulWidget {
  const PontoEtapa1ValidacaoPage({super.key, required this.empresaId});

  final String empresaId;

  @override
  State<PontoEtapa1ValidacaoPage> createState() =>
      _PontoEtapa1ValidacaoPageState();
}

class _PontoEtapa1ValidacaoPageState extends State<PontoEtapa1ValidacaoPage> {
  final PontoEtapa1ValidacaoService _service =
      PontoEtapa1ValidacaoService.instance;
  final TextEditingController _observacoes = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  bool _doisAparelhos = false;
  bool _offlineOnline = false;
  bool _revogacao = false;
  bool _permissoes = false;
  bool _isolamento = false;

  Map<String, dynamic> _resultado = const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final resultado = await _service.executar(empresaId: widget.empresaId);

      if (!mounted) return;

      final manual = Map<String, dynamic>.from(
        (resultado['manual'] as Map?) ?? const {},
      );

      setState(() {
        _resultado = resultado;
        _doisAparelhos = manual['dois_aparelhos'] == true;
        _offlineOnline = manual['offline_online'] == true;
        _revogacao = manual['revogacao'] == true;
        _permissoes = manual['permissoes'] == true;
        _isolamento = manual['isolamento_multiempresa'] == true;
        _observacoes.text = (manual['observacoes'] ?? '').toString();
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mensagem('Falha ao validar Etapa 1: $erro', erro: true);
    }
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    setState(() => _salvando = true);

    try {
      await _service.salvarManual(
        empresaId: widget.empresaId,
        doisAparelhos: _doisAparelhos,
        offlineOnline: _offlineOnline,
        revogacao: _revogacao,
        permissoes: _permissoes,
        isolamentoMultiempresa: _isolamento,
        observacoes: _observacoes.text,
      );

      await _carregar();

      if (!mounted) return;

      _mensagem(
        _resultado['concluida'] == true
            ? 'Etapa 1 homologada neste aparelho.'
            : 'Checklist salvo. Ainda existem itens pendentes.',
        erro: false,
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem('Não foi possível salvar: $erro', erro: true);
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  void _mensagem(String texto, {required bool erro}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro
              ? const Color(0xFFB00020)
              : const Color(0xFF1B5E20),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final concluida = _resultado['concluida'] == true;
    final automaticoOk = _resultado['automatico_ok'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homologação da Etapa 1'),
        actions: [
          IconButton(
            tooltip: 'Atualizar diagnóstico',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          concluida
                              ? Icons.verified_rounded
                              : Icons.fact_check_outlined,
                          color: concluida
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            concluida
                                ? 'Etapa 1 — Ponto/Funcionários homologada.'
                                : 'A implementação da Etapa 1 está preparada. '
                                      'A conclusão exige diagnóstico técnico '
                                      'e testes reais abaixo.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Verificações automáticas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _CheckLinha(
                  titulo: 'Backend do Ponto atualizado',
                  ok: _resultado['backend_ok'] == true,
                ),
                _CheckLinha(
                  titulo: 'Migração inicial concluída',
                  ok: _resultado['migracao_ok'] == true,
                ),
                _CheckLinha(
                  titulo: 'Realtime disponível',
                  ok: _resultado['realtime_ok'] == true,
                ),
                _CheckLinha(
                  titulo: 'Batida offline idempotente',
                  ok: _resultado['idempotencia_ok'] == true,
                ),
                _CheckLinha(
                  titulo: 'Fila offline zerada',
                  ok: _resultado['fila_ok'] == true,
                  detalhe: '${_resultado['fila_pendente'] ?? 0} pendência(s)',
                ),
                _CheckLinha(
                  titulo: 'Tenant local corresponde à empresa',
                  ok: _resultado['tenant_local_ok'] == true,
                ),
                _CheckLinha(
                  titulo: 'Sem mapeamento de outra empresa',
                  ok: _resultado['mapeamentos_ok'] == true,
                  detalhe:
                      '${_resultado['mapeamentos_outra_empresa'] ?? 0} encontrado(s)',
                ),
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: Icon(
                      automaticoOk
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color: automaticoOk
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    title: Text(
                      automaticoOk
                          ? 'Diagnóstico automático aprovado'
                          : 'Diagnóstico automático ainda possui pendências',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Testes reais obrigatórios',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Marque somente depois de executar o teste no aparelho.',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _doisAparelhos,
                  onChanged: (valor) {
                    setState(() => _doisAparelhos = valor ?? false);
                  },
                  title: const Text('Dois aparelhos'),
                  subtitle: const Text(
                    'Uma batida feita em um aparelho apareceu no outro '
                    'sem criar nova batida.',
                  ),
                ),
                CheckboxListTile(
                  value: _offlineOnline,
                  onChanged: (valor) {
                    setState(() => _offlineOnline = valor ?? false);
                  },
                  title: const Text('Offline → online'),
                  subtitle: const Text(
                    'Batida salva offline sincronizou depois sem duplicar.',
                  ),
                ),
                CheckboxListTile(
                  value: _revogacao,
                  onChanged: (valor) {
                    setState(() => _revogacao = valor ?? false);
                  },
                  title: const Text('Revogação de aparelho'),
                  subtitle: const Text(
                    'Administrador revogou o aparelho e o acesso foi '
                    'bloqueado ao reabrir o app.',
                  ),
                ),
                CheckboxListTile(
                  value: _permissoes,
                  onChanged: (valor) {
                    setState(() => _permissoes = valor ?? false);
                  },
                  title: const Text('Permissões remotas'),
                  subtitle: const Text(
                    'Alteração feita pelo administrador refletiu no '
                    'funcionário.',
                  ),
                ),
                CheckboxListTile(
                  value: _isolamento,
                  onChanged: (valor) {
                    setState(() => _isolamento = valor ?? false);
                  },
                  title: const Text('Isolamento multiempresa'),
                  subtitle: const Text(
                    'Empresa A não acessou dados, funcionários ou ponto '
                    'da Empresa B.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _observacoes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Observações da homologação',
                    hintText: 'Aparelhos usados, comportamento observado...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _salvando ? 'Salvando...' : 'Salvar homologação da Etapa 1',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _CheckLinha extends StatelessWidget {
  const _CheckLinha({required this.titulo, required this.ok, this.detalhe});

  final String titulo;
  final bool ok;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.cancel_outlined,
        color: ok ? Colors.greenAccent : Colors.orangeAccent,
      ),
      title: Text(titulo),
      subtitle: detalhe == null ? null : Text(detalhe!),
    );
  }
}
