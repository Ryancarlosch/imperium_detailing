import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/veiculo.dart';
import '../repositories/veiculo_repository.dart';
import '../services/consulta_placa_service.dart';
import 'veiculo_detalhes_page.dart';

class VeiculosClientePage extends StatefulWidget {
  final Cliente cliente;

  const VeiculosClientePage({super.key, required this.cliente});

  @override
  State<VeiculosClientePage> createState() => _VeiculosClientePageState();
}

class _VeiculosClientePageState extends State<VeiculosClientePage> {
  final VeiculoRepository _repository = VeiculoRepository();
  final ConsultaPlacaService _consultaPlacaService = ConsultaPlacaService();

  List<Veiculo> veiculos = [];
  bool carregando = true;
  bool _salvandoCadastro = false; // veiculo-cadastro-salvando-v1

  @override
  void initState() {
    super.initState();
    carregarVeiculos();
  }

  Future<void> carregarVeiculos() async {
    final clienteId = widget.cliente.id;

    if (clienteId == null) {
      setState(() {
        carregando = false;
      });
      return;
    }

    try {
      final lista = await _repository.listarVeiculosDoCliente(clienteId);

      if (!mounted) return;

      setState(() {
        veiculos = lista;
        carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar veículos: $erro')),
      );
    }
  }

  Future<void> abrirCadastro() async {
    final clienteId = widget.cliente.id;

    if (clienteId == null) return;

    final marcaController = TextEditingController();
    final modeloController = TextEditingController();
    final placaController = TextEditingController();
    final corController = TextEditingController();
    final anoController = TextEditingController();
    final observacoesController = TextEditingController();
    var ultimaPlacaConsultada = '';

    // consulta-placa-ui-helper-v1
    Future<void> consultarPlaca(BuildContext dialogContext) async {
      final placa = ConsultaPlacaService.normalizarPlaca(placaController.text);

      if (!ConsultaPlacaService.placaValida(placa)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Digite os 7 caracteres da placa para consultar.'),
            ),
          );
        return;
      }

      try {
        final resultado = await _consultaPlacaService.consultar(placa);

        if (!mounted || !dialogContext.mounted) return;

        placaController.text = resultado.placa;
        marcaController.text = resultado.marca;
        modeloController.text = resultado.modelo;
        corController.text = resultado.cor;

        if (resultado.anoPreferencial.isNotEmpty) {
          anoController.text = resultado.anoPreferencial;
        }

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Dados do veículo preenchidos pela placa.'),
            ),
          );
      } on ConsultaPlacaNaoEncontradaException catch (erro) {
        if (!mounted || !dialogContext.mounted) return;

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(erro.mensagem),
              behavior: SnackBarBehavior.floating,
            ),
          );
      } catch (erro) {
        if (!mounted || !dialogContext.mounted) return;

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Não foi possível consultar a placa. '
                'Você pode preencher os dados manualmente.\n'
                '$erro',
              ),
            ),
          );
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Novo veículo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: marcaController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Marca',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modeloController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: placaController,
                  textCapitalization: TextCapitalization.characters,
                  // consulta-placa-auto-onchanged-v1
                  onChanged: (valor) {
                    final placa = ConsultaPlacaService.normalizarPlaca(valor);

                    if (placa.length == 7 && placa != ultimaPlacaConsultada) {
                      ultimaPlacaConsultada = placa;
                      consultarPlaca(dialogContext);
                    }
                  },
                  onSubmitted: (_) => consultarPlaca(dialogContext),
                  decoration: InputDecoration(
                    labelText: 'Placa',
                    helperText:
                        'Ao completar a placa, marca, modelo, ano e cor serão buscados.',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Consultar placa',
                      onPressed: () => consultarPlaca(dialogContext),
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: corController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Cor',
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: anoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ano',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacoesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final marca = marcaController.text.trim();
                final modelo = modeloController.text.trim();

                if (marca.isEmpty || modelo.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe a marca e o modelo.'),
                    ),
                  );
                  return;
                }

                if (_salvandoCadastro) return;
                setState(() => _salvandoCadastro = true);

                try {
                  final veiculo = Veiculo(
                    clienteId: clienteId,
                    marca: marca,
                    modelo: modelo,
                    placa: placaController.text.trim().toUpperCase(),
                    cor: corController.text.trim(),
                    ano: anoController.text.trim(),
                    observacoes: observacoesController.text.trim(),
                  );

                  await _repository.inserirVeiculo(veiculo);

                  if (!dialogContext.mounted) return;

                  Navigator.pop(dialogContext);
                  await carregarVeiculos();
                } catch (erro) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Não foi possível salvar o veículo: $erro',
                        ),
                      ),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _salvandoCadastro = false);
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> abrirDetalhes(Veiculo veiculo) async {
    if (veiculo.id == null) {
      return;
    }

    final alterou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return VeiculoDetalhesPage(veiculoId: veiculo.id!);
        },
      ),
    );

    if (alterou == true) {
      await carregarVeiculos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Veículos de ${widget.cliente.nome}')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : veiculos.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.directions_car_outlined,
                    size: 72,
                    color: Colors.white38,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum veículo cadastrado',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Toque no botão + para cadastrar',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: carregarVeiculos,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: veiculos.length,
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (context, index) {
                  final veiculo = veiculos[index];

                  return Card(
                    child: ListTile(
                      onTap: () {
                        abrirDetalhes(veiculo);
                      },
                      leading: const CircleAvatar(
                        child: Icon(Icons.directions_car),
                      ),
                      title: Text('${veiculo.marca} ${veiculo.modelo}'),
                      subtitle: Text(
                        veiculo.placa.isNotEmpty
                            ? veiculo.placa
                            : 'Placa não informada',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: abrirCadastro,
        child: const Icon(Icons.add),
      ),
    );
  }
}
