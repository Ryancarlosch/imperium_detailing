import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';
import 'package:imperium_detailing/repositories/dashboard_repository.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_dashboard_ranking_liquido_test_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  test(
    'ranking de serviços rateia o valor líquido da OS e respeita desconto',
    () async {
      final database = await AppDatabase.instance.database;
      final repository = OrdemServicoRepository();
      final hoje = DateTime.now();
      final data = _dataIso(hoje);
      final dataFinalizacao = DateTime(
        hoje.year,
        hoje.month,
        hoje.day,
        12,
      ).toIso8601String();

      final cliente1 = await _criarCliente(database, 'Cliente Polimento');
      final os1 = await repository.inserirOrdemServico(
        OrdemServico(
          clienteId: cliente1,
          numero: 'OS-RANKING-LIQUIDO-001',
          status: 'Finalizada',
          dataAbertura: data,
          dataInicio: data,
          dataFinalizacao: dataFinalizacao,
          valorTotal: 600,
          desconto: 250,
        ),
      );

      await _inserirItem(
        database,
        ordemServicoId: os1,
        servico: 'Polimento técnico',
        quantidade: 1,
        valorUnitario: 600,
        ordem: 0,
      );

      final cliente2 = await _criarCliente(database, 'Cliente Combo');
      final os2 = await repository.inserirOrdemServico(
        OrdemServico(
          clienteId: cliente2,
          numero: 'OS-RANKING-LIQUIDO-002',
          status: 'Finalizada',
          dataAbertura: data,
          dataInicio: data,
          dataFinalizacao: dataFinalizacao,
          valorTotal: 1000,
          desconto: 250,
        ),
      );

      await _inserirItem(
        database,
        ordemServicoId: os2,
        servico: 'Higienização interna',
        quantidade: 1,
        valorUnitario: 600,
        ordem: 0,
      );
      await _inserirItem(
        database,
        ordemServicoId: os2,
        servico: 'Vitrificação',
        quantidade: 1,
        valorUnitario: 400,
        ordem: 1,
      );

      final dados = await DashboardRepository().carregarDashboard(
        periodo: DashboardPeriodo.personalizado,
        inicioPersonalizado: hoje,
        fimPersonalizado: hoje,
      );

      final polimento = dados.topServicos.singleWhere(
        (item) => item.nome == 'Polimento técnico',
      );
      final higienizacao = dados.topServicos.singleWhere(
        (item) => item.nome == 'Higienização interna',
      );
      final vitrificacao = dados.topServicos.singleWhere(
        (item) => item.nome == 'Vitrificação',
      );

      // Caso real relatado: R$ 600 - R$ 250 = R$ 350 vendidos.
      expect(polimento.total, closeTo(350, 0.001));

      // OS de R$ 1.000 com R$ 250 de desconto:
      // item de R$ 600 recebe 60% dos R$ 750 líquidos = R$ 450;
      // item de R$ 400 recebe 40% dos R$ 750 líquidos = R$ 300.
      expect(higienizacao.total, closeTo(450, 0.001));
      expect(vitrificacao.total, closeTo(300, 0.001));

      final somaRanking = dados.topServicos.fold<double>(
        0,
        (total, item) => total + item.total,
      );
      expect(somaRanking, closeTo(1100, 0.001));
      expect(dados.faturamentoCompetencia, closeTo(1100, 0.001));
    },
  );
}

Future<int> _criarCliente(Database database, String nome) {
  return database.insert('clientes', {
    'nome': nome,
    'telefone': '11999999999',
    'email': 'ranking@teste.com',
    'endereco': 'Rua Teste, 100',
    'observacoes': 'Teste do ranking líquido de serviços.',
  });
}

Future<void> _inserirItem(
  Database database, {
  required int ordemServicoId,
  required String servico,
  required double quantidade,
  required double valorUnitario,
  required int ordem,
}) {
  return database.insert('ordem_servico_itens', {
    'ordem_servico_id': ordemServicoId,
    'servico': servico,
    'descricao': '',
    'quantidade': quantidade,
    'valor_unitario': valorUnitario,
    'concluido': 1,
    'ordem': ordem,
  });
}

String _dataIso(DateTime data) {
  final ano = data.year.toString().padLeft(4, '0');
  final mes = data.month.toString().padLeft(2, '0');
  final dia = data.day.toString().padLeft(2, '0');
  return '$ano-$mes-$dia';
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
