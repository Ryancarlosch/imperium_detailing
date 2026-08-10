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
      'imperium_dashboard_saldos_test_',
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

  test('dashboard mostra saldo atual separado por conta ativa', () async {
    final database = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();

    final caixaPadrao = await database.query(
      'financeiro_contas',
      columns: ['id'],
      where: 'nome = ?',
      whereArgs: ['Caixa / Dinheiro'],
      limit: 1,
    );
    expect(caixaPadrao, isNotEmpty);

    await database.update(
      'financeiro_contas',
      {'saldo_inicial': 300.0, 'atualizado_em': agora},
      where: 'id = ?',
      whereArgs: [caixaPadrao.single['id']],
    );

    final nubankId = await database.insert('financeiro_contas', {
      'nome': 'Nubank Empresa',
      'tipo': 'Conta bancária',
      'instituicao': 'Nubank',
      'saldo_inicial': 5000.0,
      'data_saldo_inicial': null,
      'observacoes': '',
      'ativo': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    });

    final stoneId = await database.insert('financeiro_contas', {
      'nome': 'Stone',
      'tipo': 'Maquininha',
      'instituicao': 'Stone',
      'saldo_inicial': 1000.0,
      'data_saldo_inicial': null,
      'observacoes': '',
      'ativo': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    });

    await database.insert('financeiro_contas', {
      'nome': 'Conta antiga',
      'tipo': 'Outro',
      'instituicao': '',
      'saldo_inicial': 10000.0,
      'data_saldo_inicial': null,
      'observacoes': '',
      'ativo': 0,
      'criado_em': agora,
      'atualizado_em': agora,
    });

    Future<void> movimento({
      required int contaId,
      required String tipo,
      required double valor,
      String status = 'Realizado',
    }) async {
      await database.insert('movimentos_financeiros', {
        'tipo': tipo,
        'descricao': 'Movimento de teste do dashboard',
        'valor': valor,
        'forma_pagamento': 'Pix',
        'data': agora,
        'conta_id': contaId,
        'status': status,
        'data_competencia': agora,
        'data_pagamento': status == 'Realizado' ? agora : null,
      });
    }

    await movimento(contaId: nubankId, tipo: 'Entrada', valor: 500.0);
    await movimento(contaId: nubankId, tipo: 'Saída', valor: 200.0);
    await movimento(
      contaId: nubankId,
      tipo: 'Entrada',
      valor: 999.0,
      status: 'Previsto',
    );
    await movimento(contaId: stoneId, tipo: 'Entrada', valor: 400.0);
    await movimento(contaId: stoneId, tipo: 'Saída', valor: 40.0);

    final dados = await DashboardRepository().carregarDashboard();

    final nubank = dados.saldosContas.singleWhere(
      (conta) => conta.nome == 'Nubank Empresa',
    );
    final stone = dados.saldosContas.singleWhere(
      (conta) => conta.nome == 'Stone',
    );
    final caixa = dados.saldosContas.singleWhere(
      (conta) => conta.nome == 'Caixa / Dinheiro',
    );

    expect(nubank.saldoAtual, closeTo(5300.0, 0.001));
    expect(stone.saldoAtual, closeTo(1360.0, 0.001));
    expect(caixa.saldoAtual, closeTo(300.0, 0.001));
    expect(dados.saldoTotalContas, closeTo(6960.0, 0.001));
    expect(
      dados.saldosContas.where((conta) => conta.nome == 'Conta antiga'),
      isEmpty,
    );
  });
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
