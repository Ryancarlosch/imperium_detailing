import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_bootstrap.dart';

class ImperiumClientesPage extends StatefulWidget {
  const ImperiumClientesPage({super.key});

  @override
  State<ImperiumClientesPage> createState() => _ImperiumClientesPageState();
}

class _ImperiumClientesPageState extends State<ImperiumClientesPage> {
  final DateFormat _data = DateFormat('dd/MM/yyyy');
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  bool _carregando = true;
  bool _processando = false;
  String? _erro;
  List<Map<String, dynamic>> _clientes = const [];

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
        _clientes = lista;
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

  DateTime? _parseData(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString().trim());
  }

  String _statusTexto(Map<String, dynamic> cliente) {
    final status = (cliente['status_base'] ?? '').toString().toLowerCase();
    final testeAte = _parseData(cliente['teste_ate']);
    final vencimento = _parseData(cliente['vencimento']);
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);

    if (status == 'vitalicia') return 'VITALÍCIA';
    if (status == 'suspensa') return 'SUSPENSA';
    if (status == 'cancelada') return 'CANCELADA';

    if (status == 'teste') {
      if (testeAte == null) return 'TESTE';
      final limite = DateTime(testeAte.year, testeAte.month, testeAte.day);
      return hojeDia.isAfter(limite) ? 'TESTE VENCIDO' : 'TESTE';
    }

    if (status == 'ativa') {
      if (vencimento == null) return 'ATIVA';
      final limite = DateTime(
        vencimento.year,
        vencimento.month,
        vencimento.day,
      );
      return hojeDia.isAfter(limite) ? 'VENCIDA' : 'ATIVA';
    }

    return status.isEmpty ? 'SEM LICENÇA' : status.toUpperCase();
  }

  Color _statusCor(String status) {
    if (status.contains('VITAL')) return Colors.purpleAccent;
    if (status == 'ATIVA' || status == 'TESTE') return Colors.greenAccent;
    if (status.contains('VENCID') ||
        status == 'SUSPENSA' ||
        status == 'CANCELADA') {
      return Colors.redAccent;
    }
    return Colors.orangeAccent;
  }

  Future<void> _novoCliente() async {
    final resultado = await showDialog<_NovoClienteResultado>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NovoClienteDialog(),
    );

    if (resultado == null || _processando) return;

    await _executar(
      () async {
        final client = _client;
        if (client == null) throw StateError('Supabase indisponível.');

        await client.rpc(
          'imperium_admin_criar_cliente',
          params: {
            'p_nome': resultado.nome,
            'p_email': resultado.email,
            'p_modalidade': resultado.modalidade,
            'p_dias': resultado.dias,
            'p_valor': resultado.valor,
          },
        );
      },
      sucesso:
          'Empresa criada. O proprietário já pode usar o e-mail informado no primeiro acesso.',
    );
  }

  Future<void> _acao(
    Map<String, dynamic> cliente,
    String acao, {
    int? dias,
    double? valor,
    String? sucesso,
  }) async {
    final empresaId = cliente['empresa_id']?.toString() ?? '';
    if (empresaId.isEmpty) return;

    await _executar(() async {
      final client = _client;
      if (client == null) throw StateError('Supabase indisponível.');

      await client.rpc(
        'imperium_admin_alterar_licenca',
        params: {
          'p_empresa_id': empresaId,
          'p_acao': acao,
          'p_dias': dias,
          'p_valor': valor,
        },
      );
    }, sucesso: sucesso ?? 'Licença atualizada.');
  }

  Future<void> _testePersonalizado(Map<String, dynamic> cliente) async {
    final dias = await _pedirDias(
      titulo: 'Liberar período de teste',
      sugestao: 15,
    );

    if (dias == null) return;

    await _acao(
      cliente,
      'teste',
      dias: dias,
      sucesso: 'Teste liberado por $dias dia(s).',
    );
  }

  Future<void> _liberacaoPersonalizada(Map<String, dynamic> cliente) async {
    final dias = await _pedirDias(
      titulo: 'Liberar acesso por dias',
      sugestao: 30,
    );

    if (dias == null) return;

    await _acao(
      cliente,
      'liberar_dias',
      dias: dias,
      sucesso: 'Acesso liberado por mais $dias dia(s).',
    );
  }

  Future<int?> _pedirDias({
    required String titulo,
    required int sugestao,
  }) async {
    final controller = TextEditingController(text: sugestao.toString());

    final resultado = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantidade de dias',
              helperText: 'Ex.: 7, 15, 30, 45, 90...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final dias = int.tryParse(controller.text.trim());
                if (dias == null || dias < 1 || dias > 3650) return;
                Navigator.pop(context, dias);
              },
              child: const Text('Liberar'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return resultado;
  }

  Future<void> _vincularProprietario(Map<String, dynamic> cliente) async {
    final controller = TextEditingController(
      text: cliente['proprietario_email']?.toString() ?? '',
    );

    final email = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Proprietário / acesso'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail do proprietário',
              helperText:
                  'Se a conta ainda não existir, ficará como convite pendente.',
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
              child: const Text('Salvar acesso'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (email == null) return;

    final empresaId = cliente['empresa_id']?.toString() ?? '';
    if (empresaId.isEmpty) return;

    await _executar(() async {
      final client = _client;
      if (client == null) throw StateError('Supabase indisponível.');

      await client.rpc(
        'imperium_admin_vincular_proprietario',
        params: {'p_empresa_id': empresaId, 'p_email': email},
      );
    }, sucesso: 'Acesso do proprietário atualizado.');
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

  Widget _clienteCard(Map<String, dynamic> cliente) {
    final status = _statusTexto(cliente);
    final statusCor = _statusCor(status);
    final plano = (cliente['plano'] ?? 'Sem plano').toString();
    final email = (cliente['proprietario_email'] ?? '').toString().trim();
    final testeAte = _parseData(cliente['teste_ate']);
    final vencimento = _parseData(cliente['vencimento']);
    final valor = cliente['valor_mensal'] is num
        ? (cliente['valor_mensal'] as num).toDouble()
        : double.tryParse(cliente['valor_mensal']?.toString() ?? '');
    final convitePendente = cliente['convite_pendente'] == true;

    final dataLimite = status.startsWith('TESTE') ? testeAte : vencimento;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusCor.withValues(alpha: 0.12),
          child: Icon(Icons.business_outlined, color: statusCor),
        ),
        title: Text(
          (cliente['empresa_nome'] ?? 'Empresa').toString(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              _Badge(texto: status, cor: statusCor),
              _Badge(texto: plano.toUpperCase(), cor: Colors.blueAccent),
              if (convitePendente)
                const _Badge(
                  texto: 'CONVITE PENDENTE',
                  cor: Colors.orangeAccent,
                ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          _linha('Proprietário', email.isEmpty ? 'Ainda não vinculado' : email),
          _linha(
            'Validade',
            dataLimite == null ? 'Sem vencimento' : _data.format(dataLimite),
          ),
          if (valor != null) _linha('Valor', _moeda.format(valor)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'teste',
                        dias: 7,
                        sucesso: 'Teste de 7 dias liberado.',
                      ),
                child: const Text('Teste 7d'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'teste',
                        dias: 15,
                        sucesso: 'Teste de 15 dias liberado.',
                      ),
                child: const Text('Teste 15d'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'teste',
                        dias: 30,
                        sucesso: 'Teste de 30 dias liberado.',
                      ),
                child: const Text('Teste 30d'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _testePersonalizado(cliente),
                child: const Text('Teste personalizado'),
              ),
              FilledButton.tonal(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'renovar_30',
                        sucesso: 'Plano mensal renovado por 30 dias.',
                      ),
                child: const Text('+30 dias'),
              ),
              FilledButton.tonal(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'renovar_365',
                        sucesso: 'Plano anual renovado por 365 dias.',
                      ),
                child: const Text('+1 ano'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _liberacaoPersonalizada(cliente),
                child: const Text('+ dias'),
              ),
              OutlinedButton.icon(
                onPressed: _processando
                    ? null
                    : () => _vincularProprietario(cliente),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Acesso'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'reativar',
                        sucesso: 'Licença reativada.',
                      ),
                child: const Text('Reativar'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _acao(
                        cliente,
                        'suspender',
                        sucesso: 'Licença suspensa.',
                      ),
                child: const Text('Suspender'),
              ),
              OutlinedButton(
                onPressed: _processando
                    ? null
                    : () => _confirmarVitalicia(cliente),
                child: const Text('Vitalícia'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarVitalicia(Map<String, dynamic> cliente) async {
    final nome = (cliente['empresa_nome'] ?? 'Empresa').toString();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Liberar licença vitalícia?'),
          content: Text(
            '$nome ficará sem vencimento e sem necessidade de renovação.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Liberar vitalícia'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _acao(cliente, 'vitalicia', sucesso: 'Licença vitalícia liberada.');
  }

  Widget _linha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(titulo, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: SelectableText(
              valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imperium • Clientes'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _processando ? null : _novoCliente,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nova empresa'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(_erro!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: _carregar,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.admin_panel_settings_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${_clientes.length} empresa(s). '
                              'Controle teste, mensal, anual, personalizado, '
                              'suspensão e licença vitalícia.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final cliente in _clientes) _clienteCard(cliente),
                  if (_clientes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Nenhuma empresa cadastrada.')),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.30)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NovoClienteResultado {
  const _NovoClienteResultado({
    required this.nome,
    required this.email,
    required this.modalidade,
    required this.dias,
    required this.valor,
  });

  final String nome;
  final String email;
  final String modalidade;
  final int dias;
  final double? valor;
}

class _NovoClienteDialog extends StatefulWidget {
  const _NovoClienteDialog();

  @override
  State<_NovoClienteDialog> createState() => _NovoClienteDialogState();
}

class _NovoClienteDialogState extends State<_NovoClienteDialog> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _dias = TextEditingController(text: '15');
  final _valor = TextEditingController();

  String _modalidade = 'teste';

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _dias.dispose();
    _valor.dispose();
    super.dispose();
  }

  bool get _usaDias => _modalidade == 'teste' || _modalidade == 'personalizada';

  void _selecionarModalidade(String? valor) {
    if (valor == null) return;

    setState(() {
      _modalidade = valor;

      switch (valor) {
        case 'teste':
          if ((int.tryParse(_dias.text) ?? 0) < 1) {
            _dias.text = '15';
          }
          break;
        case 'mensal':
          _dias.text = '30';
          break;
        case 'anual':
          _dias.text = '365';
          break;
        case 'personalizada':
          _dias.text = '30';
          break;
        case 'vitalicia':
          _dias.text = '0';
          break;
      }
    });
  }

  void _salvar() {
    final nome = _nome.text.trim();
    final email = _email.text.trim();
    final dias = int.tryParse(_dias.text.trim()) ?? 0;
    final valorTexto = _valor.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final valor = valorTexto.isEmpty ? null : double.tryParse(valorTexto);

    if (nome.isEmpty || !email.contains('@')) return;
    if (_usaDias && (dias < 1 || dias > 3650)) return;

    Navigator.pop(
      context,
      _NovoClienteResultado(
        nome: nome,
        email: email,
        modalidade: _modalidade,
        dias: dias,
        valor: valor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova empresa'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nome,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome da empresa',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'E-mail do proprietário',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _modalidade,
                decoration: const InputDecoration(
                  labelText: 'Licença inicial',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'teste',
                    child: Text('Período de teste'),
                  ),
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
                    child: Text('Período personalizado'),
                  ),
                  DropdownMenuItem(
                    value: 'vitalicia',
                    child: Text('Vitalícia'),
                  ),
                ],
                onChanged: _selecionarModalidade,
              ),
              if (_usaDias) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _dias,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dias',
                    helperText: '7, 15, 30 ou qualquer período até 3650 dias',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                ),
              ],
              if (_modalidade != 'vitalicia') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _valor,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor vendido (opcional)',
                    prefixText: r'R$ ',
                  ),
                ),
              ],
              if (_modalidade == 'mensal') ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mensal: libera 30 dias.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
              if (_modalidade == 'anual') ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Anual: libera 365 dias.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
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
          icon: const Icon(Icons.add_business),
          label: const Text('Criar empresa'),
        ),
      ],
    );
  }
}
