import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/precificacao_repository.dart';

class MaoObraCustosPage extends StatefulWidget {
  const MaoObraCustosPage({super.key});

  @override
  State<MaoObraCustosPage> createState() => _MaoObraCustosPageState();
}

class _MaoObraCustosPageState extends State<MaoObraCustosPage> {
  final CustosRepository _repository = CustosRepository();
  final PrecificacaoRepository _precificacaoRepository =
      PrecificacaoRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
  List<ColaboradorCusto> _colaboradores = [];
  Map<String, double> _resumo = const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }
    try {
      final resultados = await Future.wait<dynamic>([
        _repository.listarColaboradores(),
        _repository.obterResumoEstruturaCustos(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _colaboradores = List<ColaboradorCusto>.from(
          resultados[0] as List<dynamic>,
        );
        _resumo = Map<String, double>.from(
          resultados[1] as Map<String, double>,
        );
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _carregando = false);
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _editarCargaHorariaEquipe() async {
    try {
      final config = await _precificacaoRepository.carregarConfig();

      if (!mounted) return;

      final controller = TextEditingController(
        text: config.horasProdutivasMes.toStringAsFixed(1).replaceAll('.', ','),
      );

      final valor = await showDialog<double>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Carga horária mensal da equipe'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Horas mensais',
              suffixText: 'h',
              helperText:
                  'Informe uma única vez. Todos os funcionários usam a mesma carga horária.',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                var texto = controller.text.trim();

                if (texto.contains(',') && texto.contains('.')) {
                  texto = texto.replaceAll('.', '').replaceAll(',', '.');
                } else {
                  texto = texto.replaceAll(',', '.');
                }

                final numero = double.tryParse(texto);

                if (numero != null && numero > 0) {
                  Navigator.of(dialogContext).pop(numero);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      );

      controller.dispose();

      if (valor == null) return;

      await _precificacaoRepository.salvarConfig(
        PrecificacaoConfig(
          horasProdutivasMes: valor,
          mesesMedia: config.mesesMedia,
          margemCliente: config.margemCliente,
          margemRevenda: config.margemRevenda5a9,
          margemMinima: config.margemMinima,
          margemRevenda1a4: config.margemRevenda1a4,
          margemRevenda5a9: config.margemRevenda5a9,
          margemRevenda10Mais: config.margemRevenda10Mais,
        ),
      );

      await _repository.sincronizarHorasProdutivasEquipe(valor);

      await _carregar();

      _mensagem(
        'Carga horária da equipe atualizada para '
        '${valor.toStringAsFixed(1)} h/mês.',
      );
    } catch (erro) {
      _mensagem('$erro', erro: true);
    }
  }

  Future<void> _abrirFormulario([ColaboradorCusto? colaborador]) async {
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColaboradorForm(
        repository: _repository,
        colaborador: colaborador,
        horasEquipe: _resumo['horas_produtivas'] ?? 160,
      ),
    );
    if (resultado == true) {
      await _carregar();
    }
  }

  Future<void> _arquivar(ColaboradorCusto colaborador) async {
    if (colaborador.id == null) {
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arquivar colaborador de custo'),
        content: Text(
          'Arquivar "${colaborador.nome}"? Lançamentos históricos nas OS continuam preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
    if (confirmar != true) {
      return;
    }
    await _repository.arquivarColaborador(colaborador.id!);
    await _carregar();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Mão de obra')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Adicionar'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _linha(
                            'Custo mensal de mão de obra',
                            _moeda.format(
                              _resumo['custo_mao_obra_mensal'] ?? 0,
                            ),
                          ),
                          _linha(
                            'Carga horária mensal da equipe',
                            '${(_resumo['horas_produtivas'] ?? 0).toStringAsFixed(1)} h',
                          ),
                          const Divider(),
                          _linha(
                            'Custo médio da hora produtiva',
                            _moeda.format(_resumo['custo_mao_obra_hora'] ?? 0),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _editarCargaHorariaEquipe,
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('Alterar carga horária da equipe'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cadastre também seu próprio pró-labore quando sua mão de obra participa dos serviços. Isso evita considerar seu tempo como custo zero. Os custos de todos são somados, mas a carga horária da equipe entra apenas uma vez no cálculo.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  if (_colaboradores.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 60,
                        horizontal: 24,
                      ),
                      child: Text(
                        'Nenhum custo de mão de obra cadastrado. Adicione proprietário, funcionários ou terceiros recorrentes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                  else
                    ..._colaboradores.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          leading: const Icon(
                            Icons.engineering_outlined,
                            color: Color(0xFFD6A84B),
                          ),
                          title: Text(
                            item.nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              if (item.funcao.isNotEmpty) item.funcao,
                              '${_moeda.format(item.custoHoraProdutiva)}/h de custo individual',
                            ].join(' • '),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (valor) {
                              if (valor == 'editar') {
                                _abrirFormulario(item);
                              }
                              if (valor == 'arquivar') {
                                _arquivar(item);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'editar',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'arquivar',
                                child: Text('Arquivar'),
                              ),
                            ],
                          ),
                          onTap: () => _abrirFormulario(item),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _linha(String titulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(titulo)),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: destaque ? 17 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColaboradorForm extends StatefulWidget {
  const _ColaboradorForm({
    required this.repository,
    required this.horasEquipe,
    this.colaborador,
  });

  final CustosRepository repository;
  final double horasEquipe;
  final ColaboradorCusto? colaborador;

  @override
  State<_ColaboradorForm> createState() => _ColaboradorFormState();
}

class _ColaboradorFormState extends State<_ColaboradorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _funcao;
  late final TextEditingController _remuneracao;
  late final TextEditingController _encargos;
  late final TextEditingController _outros;
  late final TextEditingController _horas;
  late final TextEditingController _observacoes;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final item = widget.colaborador;
    _nome = TextEditingController(text: item?.nome ?? '');
    _funcao = TextEditingController(text: item?.funcao ?? '');
    _remuneracao = TextEditingController(
      text: item == null ? '' : _fmt(item.remuneracaoMensal),
    );
    _encargos = TextEditingController(
      text: item == null ? '' : _fmt(item.encargosMensais),
    );
    _outros = TextEditingController(
      text: item == null ? '' : _fmt(item.outrosCustosMensais),
    );
    _horas = TextEditingController(
      text: widget.horasEquipe.toStringAsFixed(1).replaceAll('.', ','),
    );
    _observacoes = TextEditingController(text: item?.observacoes ?? '');
  }

  String _fmt(double valor) => valor.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _nome.dispose();
    _funcao.dispose();
    _remuneracao.dispose();
    _encargos.dispose();
    _outros.dispose();
    _horas.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  double _valor(TextEditingController controller) {
    var texto = controller.text
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(texto.replaceAll(',', '.')) ?? 0;
  }

  Future<void> _salvar() async {
    if (_salvando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toIso8601String();
      final anterior = widget.colaborador;
      await widget.repository.salvarColaborador(
        ColaboradorCusto(
          id: anterior?.id,
          nome: _nome.text.trim(),
          funcao: _funcao.text.trim(),
          remuneracaoMensal: _valor(_remuneracao),
          encargosMensais: _valor(_encargos),
          outrosCustosMensais: _valor(_outros),
          horasProdutivasMes: _valor(_horas),
          observacoes: _observacoes.text.trim(),
          ativo: anterior?.ativo ?? true,
          criadoEm: anterior?.criadoEm ?? agora,
          atualizadoEm: agora,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$erro'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, teclado + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.colaborador == null
                    ? 'Novo custo de mão de obra'
                    : 'Editar mão de obra',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _funcao,
                decoration: const InputDecoration(
                  labelText: 'Função',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _campoValor(_remuneracao, 'Remuneração / pró-labore mensal'),
              const SizedBox(height: 12),
              _campoValor(_encargos, 'Encargos e benefícios mensais'),
              const SizedBox(height: 12),
              _campoValor(_outros, 'Outros custos mensais'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _horas,
                readOnly: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Carga horária mensal da equipe',
                  suffixText: 'h',
                  prefixIcon: Icon(Icons.schedule_outlined),
                ),
                validator: (_) => _valor(_horas) <= 0
                    ? 'Informe as horas realmente produtivas do mês.'
                    : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'A carga horária é única para toda a equipe. Para alterá-la, use o botão na tela Mão de obra.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacoes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _salvando
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoValor(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'R\$ ',
        prefixIcon: const Icon(Icons.attach_money_rounded),
      ),
      validator: (_) =>
          _valor(controller) < 0 ? 'Informe um valor válido.' : null,
    );
  }
}
