import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_bootstrap.dart';

class ImperiumEmpresasPage extends StatefulWidget {
  const ImperiumEmpresasPage({super.key});

  @override
  State<ImperiumEmpresasPage> createState() => _ImperiumEmpresasPageState();
}

class _ImperiumEmpresasPageState extends State<ImperiumEmpresasPage> {
  static const String _empresaImperium = 'dbbf4114-06fa-46b8-a2f6-50b3f3ead436';

  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  bool _carregando = true;
  bool _processando = false;
  String? _erro;
  List<Map<String, dynamic>> _empresas = const [];

  SupabaseClient? get _client => SupabaseBootstrap.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final client = _client;

    if (client == null) {
      setState(() {
        _carregando = false;
        _erro = 'Supabase não está disponível.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resposta = await client.rpc('imperium_admin_listar_clientes');

      final lista = resposta is List
          ? resposta
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      setState(() {
        _empresas = lista;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  Future<void> _novaEmpresa() async {
    final dados = await showDialog<_NovaEmpresaResultado>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NovaEmpresaDialog(),
    );

    if (dados == null) return;

    await _executar(
      () async {
        final client = _client;
        if (client == null) {
          throw StateError('Supabase indisponível.');
        }

        await client.rpc(
          'imperium_admin_criar_empresa_beta',
          params: {
            'p_nome': dados.nome,
            'p_proprietario_nome': dados.proprietario,
            'p_email': dados.email,
            'p_telefone': dados.telefone,
            'p_modalidade': dados.modalidade,
            'p_dias': dados.dias,
            'p_valor': dados.valor,
            'p_tolerancia': dados.tolerancia,
          },
        );
      },
      sucesso:
          'Empresa criada. O proprietário já pode fazer o primeiro acesso.',
    );
  }

  Future<void> _alterarLicenca(
    Map<String, dynamic> empresa,
    String acao, {
    int? dias,
    double? valor,
    String sucesso = 'Licença atualizada.',
  }) async {
    final id = (empresa['empresa_id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    await _executar(() async {
      final client = _client;
      if (client == null) {
        throw StateError('Supabase indisponível.');
      }

      await client.rpc(
        'imperium_admin_alterar_licenca',
        params: {
          'p_empresa_id': id,
          'p_acao': acao,
          'p_dias': dias,
          'p_valor': valor,
        },
      );
    }, sucesso: sucesso);
  }

  Future<void> _editarEmail(Map<String, dynamic> empresa) async {
    final controller = TextEditingController(
      text: (empresa['proprietario_email'] ?? '').toString(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atualizar acesso do proprietário'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = controller.text.trim();
              if (!valor.contains('@')) return;
              Navigator.pop(context, valor);
            },
            child: const Text('Liberar/Atualizar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (email == null) return;

    final id = (empresa['empresa_id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    await _executar(() async {
      final client = _client;
      if (client == null) {
        throw StateError('Supabase indisponível.');
      }

      await client.rpc(
        'imperium_admin_vincular_proprietario',
        params: {'p_empresa_id': id, 'p_email': email},
      );
    }, sucesso: 'Acesso do proprietário atualizado.');
  }

  Future<void> _historico(Map<String, dynamic> empresa) async {
    final id = (empresa['empresa_id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    final client = _client;
    if (client == null) return;

    try {
      final resposta = await client.rpc(
        'imperium_admin_historico_licenca',
        params: {'p_empresa_id': id},
      );

      final itens = resposta is List
          ? resposta
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Histórico da licença'),
          content: SizedBox(
            width: 520,
            child: itens.isEmpty
                ? const Text('Nenhuma alteração registrada.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: itens.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, index) {
                      final item = itens[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((item['acao'] ?? '').toString()),
                        subtitle: Text(
                          [
                            _formatarDataHora(item['criado_em']),
                            (item['detalhes'] ?? '').toString(),
                          ].where((e) => e.trim().isNotEmpty).join(' • '),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    }
  }

  Future<int?> _pedirDias({required String titulo, int sugestao = 30}) async {
    final controller = TextEditingController(text: sugestao.toString());

    final dias = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantidade de dias',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = int.tryParse(controller.text.trim());
              if (valor == null || valor < 1 || valor > 3650) {
                return;
              }
              Navigator.pop(context, valor);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    controller.dispose();
    return dias;
  }

  Future<void> _executar(
    Future<void> Function() acao, {
    required String sucesso,
  }) async {
    if (_processando) return;

    setState(() => _processando = true);

    try {
      await acao();
      await _carregar();

      if (!mounted) return;
      _mensagem(sucesso);
    } catch (erro) {
      if (!mounted) return;
      _mensagem(_textoErro(erro), erro: true);
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida.' : texto;
  }

  String _formatarData(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    return data == null ? '' : _data.format(data);
  }

  String _formatarDataHora(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '');
    if (data == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(data.toLocal());
  }

  Color _corStatus(String status) {
    final s = status.toLowerCase();
    if (s == 'vitalicia' || s == 'ativa' || s == 'teste' || s == 'cortesia') {
      return Colors.greenAccent;
    }
    if (s == 'tolerancia') return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _badge(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto.toUpperCase(),
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _linha(String titulo, String valor) {
    if (valor.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }

  Widget _empresaCard(Map<String, dynamic> empresa) {
    final id = (empresa['empresa_id'] ?? '').toString();
    final interna = id == _empresaImperium;
    final status = (empresa['status_efetivo'] ?? 'sem_licenca').toString();
    final cor = _corStatus(status);
    final email = (empresa['proprietario_email'] ?? '').toString();
    final proprietario = (empresa['proprietario_nome'] ?? '').toString();
    final telefone = (empresa['telefone'] ?? '').toString();
    final onboarding = (empresa['onboarding_status'] ?? '').toString();
    final convite = empresa['convite_pendente'] == true;
    final validade = _formatarData(empresa['valido_ate']);
    final dias = empresa['dias_restantes'];
    final valor = empresa['valor_mensal'] is num
        ? (empresa['valor_mensal'] as num).toDouble()
        : double.tryParse(empresa['valor_mensal']?.toString() ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            interna
                ? Icons.workspace_premium_outlined
                : Icons.business_outlined,
          ),
        ),
        title: Text(
          (empresa['empresa_nome'] ?? 'Empresa').toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              _badge(status, cor),
              _badge(
                (empresa['plano'] ?? 'Sem plano').toString(),
                Colors.blueAccent,
              ),
              if (convite)
                _badge('Aguardando primeiro acesso', Colors.orangeAccent),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          _linha('Proprietário', proprietario),
          _linha('E-mail', email),
          _linha('Telefone', telefone),
          _linha('Onboarding', onboarding),
          if (validade.isNotEmpty) _linha('Válido até', validade),
          if (dias != null) _linha('Dias restantes', '$dias'),
          if (valor != null) _linha('Valor', _moeda.format(valor)),
          const SizedBox(height: 12),
          if (!interna)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'teste',
                          dias: 7,
                          sucesso: 'Teste de 7 dias liberado.',
                        ),
                  child: const Text('Teste 7d'),
                ),
                OutlinedButton(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'teste',
                          dias: 15,
                          sucesso: 'Teste de 15 dias liberado.',
                        ),
                  child: const Text('Teste 15d'),
                ),
                OutlinedButton(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'teste',
                          dias: 30,
                          sucesso: 'Teste de 30 dias liberado.',
                        ),
                  child: const Text('Teste 30d'),
                ),
                FilledButton.tonal(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'renovar_30',
                          sucesso: 'Licença renovada por 30 dias.',
                        ),
                  child: const Text('+30 dias'),
                ),
                FilledButton.tonal(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'renovar_365',
                          sucesso: 'Licença renovada por 365 dias.',
                        ),
                  child: const Text('+365 dias'),
                ),
                OutlinedButton(
                  onPressed: _processando
                      ? null
                      : () async {
                          final dias = await _pedirDias(
                            titulo: 'Liberar dias personalizados',
                          );
                          if (dias == null) return;
                          await _alterarLicenca(
                            empresa,
                            'liberar_dias',
                            dias: dias,
                            sucesso: '$dias dia(s) adicionados.',
                          );
                        },
                  child: const Text('Dias personalizados'),
                ),
                OutlinedButton.icon(
                  onPressed: _processando ? null : () => _editarEmail(empresa),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Acesso'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _historico(empresa),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Histórico'),
                ),
                if (status.toLowerCase() == 'suspensa')
                  FilledButton.tonalIcon(
                    onPressed: _processando
                        ? null
                        : () => _alterarLicenca(
                            empresa,
                            'reativar',
                            sucesso: 'Empresa reativada.',
                          ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Reativar'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _processando
                        ? null
                        : () => _alterarLicenca(
                            empresa,
                            'suspender',
                            sucesso: 'Empresa suspensa.',
                          ),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Suspender'),
                  ),
                OutlinedButton.icon(
                  onPressed: _processando
                      ? null
                      : () => _alterarLicenca(
                          empresa,
                          'vitalicia',
                          sucesso: 'Licença vitalícia liberada.',
                        ),
                  icon: const Icon(Icons.all_inclusive_rounded),
                  label: const Text('Vitalícia'),
                ),
              ],
            ),
          if (interna)
            const Text(
              'Empresa proprietária do Imperium • licença vitalícia.',
              style: TextStyle(color: Colors.greenAccent),
            ),
        ],
      ),
    );
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Empresas • Imperium'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _processando ? null : _novaEmpresa,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nova empresa'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Cadastre empresas beta, libere o e-mail '
                        'do proprietário e controle a licença. '
                        'Cada empresa usa seu próprio tenant na nuvem.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_erro != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _erro!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    )
                  else if (_empresas.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Nenhuma empresa encontrada.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._empresas.map(_empresaCard),
                ],
              ),
      ),
    );
  }
}

class _NovaEmpresaResultado {
  const _NovaEmpresaResultado({
    required this.nome,
    required this.proprietario,
    required this.email,
    required this.telefone,
    required this.modalidade,
    required this.dias,
    required this.valor,
    required this.tolerancia,
  });

  final String nome;
  final String proprietario;
  final String email;
  final String telefone;
  final String modalidade;
  final int dias;
  final double? valor;
  final int tolerancia;
}

class _NovaEmpresaDialog extends StatefulWidget {
  const _NovaEmpresaDialog();

  @override
  State<_NovaEmpresaDialog> createState() => _NovaEmpresaDialogState();
}

class _NovaEmpresaDialogState extends State<_NovaEmpresaDialog> {
  final _nome = TextEditingController();
  final _proprietario = TextEditingController();
  final _email = TextEditingController();
  final _telefone = TextEditingController();
  final _dias = TextEditingController(text: '15');
  final _valor = TextEditingController();
  final _tolerancia = TextEditingController(text: '3');

  String _modalidade = 'teste';

  @override
  void dispose() {
    _nome.dispose();
    _proprietario.dispose();
    _email.dispose();
    _telefone.dispose();
    _dias.dispose();
    _valor.dispose();
    _tolerancia.dispose();
    super.dispose();
  }

  bool get _usaDias => _modalidade == 'teste' || _modalidade == 'personalizada';

  void _salvar() {
    final nome = _nome.text.trim();
    final email = _email.text.trim().toLowerCase();
    final dias = int.tryParse(_dias.text.trim()) ?? 15;
    final tolerancia = int.tryParse(_tolerancia.text.trim()) ?? 3;
    final valor = double.tryParse(_valor.text.trim().replaceAll(',', '.'));

    if (nome.length < 2 || !email.contains('@')) return;
    if (_usaDias && (dias < 1 || dias > 3650)) return;
    if (tolerancia < 0 || tolerancia > 30) return;

    Navigator.pop(
      context,
      _NovaEmpresaResultado(
        nome: nome,
        proprietario: _proprietario.text.trim(),
        email: email,
        telefone: _telefone.text.trim(),
        modalidade: _modalidade,
        dias: dias,
        valor: valor,
        tolerancia: tolerancia,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova empresa'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome da empresa *',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _proprietario,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do proprietário',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail do proprietário *',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _telefone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _modalidade,
                decoration: const InputDecoration(labelText: 'Licença'),
                items: const [
                  DropdownMenuItem(value: 'teste', child: Text('Teste')),
                  DropdownMenuItem(
                    value: 'mensal',
                    child: Text('Mensal • 30 dias'),
                  ),
                  DropdownMenuItem(
                    value: 'anual',
                    child: Text('Anual • 365 dias'),
                  ),
                  DropdownMenuItem(
                    value: 'personalizada',
                    child: Text('Personalizada'),
                  ),
                  DropdownMenuItem(
                    value: 'vitalicia',
                    child: Text('Vitalícia'),
                  ),
                ],
                onChanged: (valor) {
                  if (valor == null) return;
                  setState(() => _modalidade = valor);
                },
              ),
              if (_usaDias) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _dias,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dias'),
                ),
              ],
              if (_modalidade == 'mensal' || _modalidade == 'anual') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _tolerancia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tolerância após vencimento',
                    suffixText: 'dias',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor opcional',
                  prefixText: r'R$ ',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _salvar,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Criar empresa'),
        ),
      ],
    );
  }
}
