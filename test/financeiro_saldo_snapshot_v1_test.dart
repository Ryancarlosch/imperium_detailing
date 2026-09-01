import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/conta_financeira.dart';
import 'package:imperium_detailing/models/movimento_financeiro.dart';
import 'package:imperium_detailing/repositories/conta_financeira_repository.dart';
import 'package:imperium_detailing/repositories/financeiro_repository.dart';
import 'package:imperium_detailing/repositories/fluxo_caixa_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String bancoPath;
  late ContaFinanceiraRepository contas;
  late FinanceiroRepository financeiro;
  late FluxoCaixaRepository fluxo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp(
      'imperium_financeiro_snapshot_v1_',
    );
    await databaseFactory.setDatabasesPath(pasta.path);
    bancoPath = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(bancoPath);
    contas = ContaFinanceiraRepository();
    financeiro = FinanceiroRepository();
    fluxo = FluxoCaixaRepository();
  });

  tearDown(() async {
    await _removerBanco(bancoPath);
  });

  tearDownAll(() async {
    if (await pasta.exists()) {
      await pasta.delete(recursive: true);
    }
  });

  test('schema atual cria tabela formal de conciliacao', () async {
    final database = await AppDatabase.instance.database;
    final tabelas = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['financeiro_conciliacoes_conta'],
    );
    expect(tabelas, hasLength(1));
  });

  test(
    'snapshot ignora movimento antigo e entra no fluxo na data correta',
    () async {
      final snapshot = DateTime(2026, 8, 10);
      final contaId = await contas.inserir(
        ContaFinanceira(
          nome: 'Conta snapshot',
          saldoInicial: 1000,
          dataSaldoInicial: snapshot.toIso8601String(),
          criadoEm: snapshot.toIso8601String(),
          atualizadoEm: snapshot.toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Movimento anterior',
          valor: 100,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 5).toIso8601String(),
          contaId: contaId,
          status: 'Realizado',
          dataCompetencia: DateTime(2026, 8, 5).toIso8601String(),
          dataPagamento: DateTime(2026, 8, 5).toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Saída',
          descricao: 'Movimento posterior',
          valor: 200,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 11).toIso8601String(),
          contaId: contaId,
          status: 'Realizado',
          dataCompetencia: DateTime(2026, 8, 11).toIso8601String(),
          dataPagamento: DateTime(2026, 8, 11).toIso8601String(),
        ),
      );

      final lista = await contas.listar();
      final conta = lista.firstWhere((item) => item.id == contaId);
      expect(conta.saldoAtual, closeTo(800, 0.001));

      final mesCompleto = await fluxo.obterResumo(
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
      );
      expect(mesCompleto['saldo_final'], closeTo(800, 0.001));

      final aPartirSnapshot = await fluxo.obterResumo(
        inicio: snapshot,
        fim: DateTime(2026, 8, 31),
      );
      expect(aPartirSnapshot['saldo_final'], closeTo(800, 0.001));

      final diario = await fluxo.listarFluxoDiario(
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
      );
      final diaSnapshot = diario.firstWhere(
        (item) => item['data_ref'] == '2026-08-10',
      );
      expect(
        (diaSnapshot['saldo_inicial_adicionado'] as num).toDouble(),
        closeTo(1000, 0.001),
      );

      await contas.alterarAtivo(contaId, false);

      final depoisDeDesativar = await fluxo.obterResumo(
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
      );
      expect(depoisDeDesativar['saldo_final'], closeTo(800, 0.001));
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
