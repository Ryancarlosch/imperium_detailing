import 'package:flutter/material.dart';

import '../services/web_estoque_config_service.dart';

class WebEstoqueConfigPage extends StatefulWidget {
  const WebEstoqueConfigPage({super.key});

  @override
  State<WebEstoqueConfigPage> createState() => _WebEstoqueConfigPageState();
}

class _WebEstoqueConfigPageState extends State<WebEstoqueConfigPage> {
  final _service = WebEstoqueConfigService.instance;
  final _minimo = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  String? _atualizadoEmBase;

  bool _controlarEstoque = true;
  bool _produtosOs = false;
  bool _baixaAutomatica = false;
  bool _exigirQuantidade = false;
  bool _alertarBaixo = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final config = await _service.carregar();
      if (!mounted) return;
      setState(() {
        _controlarEstoque = _bool(config['controlar_estoque'], padrao: true);
        _produtosOs = _bool(config['controlar_produtos_ordem_servico']);
        _baixaAutomatica = _bool(config['baixa_automatica']);
        _exigirQuantidade = _bool(config['exigir_quantidade']);
        _alertarBaixo = _bool(config['alertar_estoque_baixo'], padrao: true);
        _minimo.text = _double(
          config['estoque_minimo_padrao'],
          padrao: 1,
        ).toStringAsFixed(2);
        _atualizadoEmBase = config['atualizado_em']?.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _erro = _textoErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final minimo = _numero(_minimo.text);
    if (minimo < 0) {
      _snack('Informe um estoque mínimo padrão válido.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      final salvo = await _service.salvar(
        controlarEstoque: _controlarEstoque,
        controlarProdutosOrdemServico: _produtosOs,
        baixaAutomatica: _baixaAutomatica,
        exigirQuantidade: _exigirQuantidade,
        alertarEstoqueBaixo: _alertarBaixo,
        estoqueMinimoPadrao: minimo,
        atualizadoEmBase: _atualizadoEmBase,
      );
      if (!mounted) return;
      setState(() {
        _atualizadoEmBase = salvo['atualizado_em']?.toString();
      });
      _snack('Configuração do estoque salva e sincronizada com o aplicativo.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
      await _carregar();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _alterarControle(bool valor) {
    setState(() {
      _controlarEstoque = valor;
      if (!valor) {
        _produtosOs = false;
        _baixaAutomatica = false;
        _exigirQuantidade = false;
      }
    });
  }

  void _alterarProdutosOs(bool valor) {
    setState(() {
      _produtosOs = valor;
      if (!valor) {
        _baixaAutomatica = false;
        _exigirQuantidade = false;
      }
    });
  }

  void _snack(String texto, {bool erro = false}) {
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

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _carregar,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(_erro!),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            const SizedBox(
              width: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configurações do estoque',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'As mesmas regras usadas no Android e nas Ordens de Serviço.',
                    style: TextStyle(color: Color(0xFF89939E)),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(_salvando ? 'Salvando...' : 'Salvar alterações'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.inventory_2_outlined),
                title: const Text('Controlar estoque'),
                subtitle: const Text('Ativa o módulo de controle de produtos.'),
                value: _controlarEstoque,
                onChanged: _salvando ? null : _alterarControle,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.assignment_turned_in_outlined),
                title: const Text('Produtos nas Ordens de Serviço'),
                subtitle: const Text(
                  'Mostra e controla os produtos utilizados dentro das OS.',
                ),
                value: _produtosOs,
                onChanged: !_controlarEstoque || _salvando
                    ? null
                    : _alterarProdutosOs,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.auto_fix_high_outlined),
                title: const Text('Baixa automática'),
                subtitle: const Text(
                  'Desconta os produtos quando a Ordem de Serviço for finalizada.',
                ),
                value: _baixaAutomatica,
                onChanged: !_controlarEstoque || !_produtosOs || _salvando
                    ? null
                    : (valor) => setState(() => _baixaAutomatica = valor),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.numbers_rounded),
                title: const Text('Exigir quantidade utilizada'),
                subtitle: const Text(
                  'Não permite produto na OS sem informar a quantidade.',
                ),
                value: _exigirQuantidade,
                onChanged: !_controlarEstoque || !_produtosOs || _salvando
                    ? null
                    : (valor) => setState(() => _exigirQuantidade = valor),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.warning_amber_rounded),
                title: const Text('Alertar estoque baixo'),
                subtitle: const Text(
                  'Destaca produtos que atingiram a quantidade mínima.',
                ),
                value: _alertarBaixo,
                onChanged: !_controlarEstoque || _salvando
                    ? null
                    : (valor) => setState(() => _alertarBaixo = valor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 360,
          child: TextField(
            controller: _minimo,
            enabled: !_salvando,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Estoque mínimo padrão',
              helperText:
                  'Valor sugerido para novos produtos; cada produto pode ter seu próprio mínimo.',
              prefixIcon: Icon(Icons.low_priority_rounded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.sync_rounded),
            title: Text(
              'Configuração compartilhada',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Alterações feitas aqui chegam ao Android no próximo ciclo de sincronização, e alterações do aplicativo voltam para o Web.',
            ),
          ),
        ),
      ],
    );
  }
}

bool _bool(dynamic value, {bool padrao = false}) {
  if (value == null) return padrao;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final texto = value.toString().toLowerCase();
  if (texto == 'true' || texto == '1') return true;
  if (texto == 'false' || texto == '0') return false;
  return padrao;
}

double _double(dynamic value, {double padrao = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ??
      padrao;
}

double _numero(String value) {
  var texto = value.trim().replaceAll(' ', '');
  if (texto.contains(',')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(texto) ?? -1;
}

String _textoErro(Object erro) {
  return erro
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
