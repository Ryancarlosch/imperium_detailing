import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/custos_repository.dart';
import 'custo_servicos_page.dart';
import 'custos_fixos_page.dart';
import 'mao_obra_custos_page.dart';
import 'pagamentos_funcionarios_page.dart';
import 'resultado_ordens_page.dart';

class CustosPage extends StatefulWidget {
  const CustosPage({super.key});

  @override
  State<CustosPage> createState() => _CustosPageState();
}

class _CustosPageState extends State<CustosPage> {
  final CustosRepository _repository = CustosRepository();
  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  bool _carregando = true;
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
      final resumo = await _repository.obterResumoEstruturaCustos();
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
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar os custos.\n$erro'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrir(Widget pagina) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => pagina));
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custos e precificação'),
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
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _ResumoCustos(
                    custoFixo: _resumo['custo_fixo_mensal'] ?? 0,
                    custoMaoObra: _resumo['custo_mao_obra_mensal'] ?? 0,
                    horasProdutivas: _resumo['horas_produtivas'] ?? 0,
                    custoEstruturaHora: _resumo['custo_estrutura_hora'] ?? 0,
                    moeda: _moeda,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Ferramentas de custo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Use estes dados para entender seu custo por hora e ajustar os preços.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  _Menu(
                    titulo: 'Custos fixos',
                    subtitulo:
                        'Aluguel, energia, internet, contador e demais custos mensais',
                    icone: Icons.home_work_outlined,
                    onTap: () => _abrir(const CustosFixosPage()),
                  ),
                  _Menu(
                    titulo: 'Mão de obra',
                    subtitulo:
                        'Remuneração, encargos, horas produtivas e custo/hora',
                    icone: Icons.engineering_outlined,
                    onTap: () => _abrir(const MaoObraCustosPage()),
                  ),
                  _Menu(
                    titulo: 'Pagamentos de funcionários',
                    subtitulo:
                        'Pagamentos semanais ou avulsos, com valor livre em cada lançamento',
                    icone: Icons.payments_outlined,
                    onTap: () => _abrir(const PagamentosFuncionariosPage()),
                  ),
                  _Menu(
                    titulo: 'Precificação dos serviços',
                    subtitulo:
                        'Custo estimado, margem atual e preço sugerido por serviço',
                    icone: Icons.design_services_outlined,
                    onTap: () => _abrir(const CustoServicosPage()),
                  ),
                  _Menu(
                    titulo: 'Análise gerencial por OS',
                    subtitulo:
                        'Compare resultado comercial com custo gerencial estimado',
                    icone: Icons.receipt_long_outlined,
                    onTap: () => _abrir(const ResultadoOrdensPage()),
                  ),
                  const SizedBox(height: 14),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Esta área é gerencial: salário de referência, custo/hora e custos fixos servem para precificação e análise das OS. Eles não criam despesas na DRE nem movimentam o saldo. Quando você pagar salário, aluguel, energia ou outra despesa, faça o lançamento financeiro normal; aí o valor aparece na DRE detalhada e no Caixa conforme a data do lançamento/pagamento.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResumoCustos extends StatelessWidget {
  const _ResumoCustos({
    required this.custoFixo,
    required this.custoMaoObra,
    required this.horasProdutivas,
    required this.custoEstruturaHora,
    required this.moeda,
  });

  final double custoFixo;
  final double custoMaoObra;
  final double horasProdutivas;
  final double custoEstruturaHora;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estrutura para precificação',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _linha('Custos fixos', moeda.format(custoFixo)),
            _linha(
              'Mão de obra mensal de referência',
              moeda.format(custoMaoObra),
            ),
            _linha(
              'Horas produtivas',
              '${horasProdutivas.toStringAsFixed(1)} h',
            ),
            const Divider(),
            _linha(
              'Custo médio da operação por hora',
              moeda.format(custoEstruturaHora),
              destaque: true,
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
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              fontSize: destaque ? 17 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Icon(icone, color: const Color(0xFFD6A84B)),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
