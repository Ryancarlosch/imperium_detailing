import 'package:flutter/material.dart';

import '../services/nota_fiscal_dfe_backend_service.dart';
import '../services/nota_fiscal_integridade_service.dart';

class NotaFiscalIntegridadePage extends StatefulWidget {
  const NotaFiscalIntegridadePage({super.key});

  @override
  State<NotaFiscalIntegridadePage> createState() =>
      _NotaFiscalIntegridadePageState();
}

class _NotaFiscalIntegridadePageState extends State<NotaFiscalIntegridadePage> {
  final NotaFiscalIntegridadeService _service = NotaFiscalIntegridadeService();
  FiscalIntegridadeResumo? _resumo;
  DfeBackendStatus? _dfe;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resumo = await _service.diagnosticarLocal();
      final dfe = await _service.diagnosticarDfe();
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _dfe = dfe;
        _carregando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _erro = error.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saúde Fiscal'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
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
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(_erro!, textAlign: TextAlign.center),
                ],
              )
            : _conteudo(_resumo!),
      ),
    );
  }

  Widget _conteudo(FiscalIntegridadeResumo resumo) {
    final dfe = _dfe;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resumo.criticos > 0
                      ? 'Há inconsistências fiscais críticas'
                      : resumo.atencoes > 0
                      ? 'Fiscal íntegro, com pendências'
                      : 'Integridade fiscal aprovada',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Notas', resumo.totalNotas),
                    _chip('Processadas', resumo.processadas),
                    _chip('Pendentes', resumo.pendentes),
                    _chip('Erros', resumo.erros),
                    _chip('Autorizadas', resumo.autorizadas),
                    _chip('Com estoque', resumo.comEstoque),
                    _chip('Com financeiro', resumo.comFinanceiro),
                    _chip('Itens sem vínculo', resumo.itensSemVinculo),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              dfe?.provedorConfigurado == true
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
            title: const Text('Backend NF-e 55 / DF-e'),
            subtitle: Text(
              dfe == null
                  ? 'Diagnóstico não disponível.'
                  : '${dfe.mensagem}\n'
                        'Provedor: ${dfe.provedor.isEmpty ? '-' : dfe.provedor} · '
                        'token: ${dfe.provedorConfigurado ? 'configurado' : 'pendente'} · '
                        'CNPJ servidor: ${dfe.cnpjConfigurado ? 'configurado' : 'não informado'} · '
                        'manifestação automática: ${dfe.manifestacaoAutomatica ? 'ATIVA' : 'não'}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (resumo.itens.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_outlined),
              title: Text('Nenhuma inconsistência detectada'),
              subtitle: Text(
                'Os testes de reconciliação local de notas, itens, estoque e financeiro passaram.',
              ),
            ),
          )
        else
          ...resumo.itens.map(_alerta),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Regra de segurança: somente documento fiscal processado e autorizado pode gerar entrada de estoque ou lançamento financeiro. A Saúde Fiscal é diagnóstica e não corrige dados automaticamente.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String titulo, int valor) =>
      Chip(label: Text('$titulo: $valor'));

  Widget _alerta(FiscalIntegridadeItem item) {
    final (icone, cor) = switch (item.nivel) {
      FiscalIntegridadeNivel.critico => (Icons.error_outline, Colors.redAccent),
      FiscalIntegridadeNivel.atencao => (
        Icons.warning_amber_rounded,
        Colors.orangeAccent,
      ),
      FiscalIntegridadeNivel.informacao => (
        Icons.info_outline,
        Colors.lightBlueAccent,
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icone, color: cor),
        title: Text(item.titulo),
        subtitle: Text(item.detalhe),
      ),
    );
  }
}
