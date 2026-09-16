import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/dashboard_repository.dart';
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
      'imperium_dashboard_ranking_desconto_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDown(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  test(
    'ranking de serviços usa valor líquido vendido após desconto da OS',
    () async {
      final database = await AppDatabase.instance.database;

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente Ranking Desconto',
        'telefone': '11999999999',
      });

      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-RANK-DESC-001',
        'status': 'Finalizada',
        'data_abertura': '2026-09-10T09:00:00.000',
        'data_finalizacao': '2026-09-10T12:00:00.000',
        'valor_total': 600.0,
        'desconto': 250.0,
        'desconto_negociacao': 0.0,
        'acrescimo_negociacao': 0.0,
        'juros_parcelamento': 0.0,
        'lancado_financeiro': 0,
      });

      await database.insert('ordem_servico_itens', {
        'ordem_servico_id': ordemId,
        'servico': 'Polimento técnico',
        'descricao': '',
        'quantidade': 1.0,
        'valor_unitario': 600.0,
        'concluido': 1,
        'ordem': 0,
      });

      final dados = await DashboardRepository().carregarDashboard(
        periodo: DashboardPeriodo.personalizado,
        inicioPersonalizado: DateTime(2026, 9, 1),
        fimPersonalizado: DateTime(2026, 9, 30),
      );

      final servico = dados.topServicos.singleWhere(
        (item) => item.nome == 'Polimento técnico',
      );
      final cliente = dados.topClientes.singleWhere(
        (item) => item.nome == 'Cliente Ranking Desconto',
      );

      expect(servico.quantidade, 1);
      expect(servico.total, closeTo(350.0, 0.001));
      expect(cliente.total, closeTo(350.0, 0.001));
    },
  );

  test(
    'desconto de OS com vários serviços é rateado proporcionalmente',
    () async {
      final database = await AppDatabase.instance.database;

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente Ranking Rateio',
        'telefone': '11988888888',
      });

      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-RANK-DESC-002',
        'status': 'Finalizada',
        'data_abertura': '2026-09-11T09:00:00.000',
        'data_finalizacao': '2026-09-11T12:00:00.000',
        'valor_total': 1000.0,
        'desconto': 200.0,
        'desconto_negociacao': 0.0,
        'acrescimo_negociacao': 0.0,
        'juros_parcelamento': 0.0,
        'lancado_financeiro': 0,
      });

      await database.insert('ordem_servico_itens', {
        'ordem_servico_id': ordemId,
        'servico': 'Serviço A',
        'descricao': '',
        'quantidade': 1.0,
        'valor_unitario': 600.0,
        'concluido': 1,
        'ordem': 0,
      });

      await database.insert('ordem_servico_itens', {
        'ordem_servico_id': ordemId,
        'servico': 'Serviço B',
        'descricao': '',
        'quantidade': 1.0,
        'valor_unitario': 400.0,
        'concluido': 1,
        'ordem': 1,
      });

      final dados = await DashboardRepository().carregarDashboard(
        periodo: DashboardPeriodo.personalizado,
        inicioPersonalizado: DateTime(2026, 9, 1),
        fimPersonalizado: DateTime(2026, 9, 30),
      );

      final servicoA = dados.topServicos.singleWhere(
        (item) => item.nome == 'Serviço A',
      );
      final servicoB = dados.topServicos.singleWhere(
        (item) => item.nome == 'Serviço B',
      );

      expect(servicoA.total, closeTo(480.0, 0.001));
      expect(servicoB.total, closeTo(320.0, 0.001));
      expect(servicoA.total + servicoB.total, closeTo(800.0, 0.001));
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
