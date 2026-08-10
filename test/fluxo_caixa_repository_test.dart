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

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late FinanceiroRepository financeiro;
  late FluxoCaixaRepository fluxo;
  late ContaFinanceiraRepository contas;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_fluxo_caixa_test_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    financeiro = FinanceiroRepository();
    fluxo = FluxoCaixaRepository();
    contas = ContaFinanceiraRepository();
  });

  tearDown(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('Financeiro 2.3B - fluxo de caixa', () {
    test('calcula realizado, previsto e saldo projetado', () async {
      final agora = DateTime.now().toIso8601String();
      final contaId = await contas.inserir(
        ContaFinanceira(
          nome: 'Conta de teste',
          saldoInicial: 1000,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Entrada realizada',
          valor: 500,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 1).toIso8601String(),
          contaId: contaId,
          status: 'Realizado',
          dataCompetencia: DateTime(2026, 8, 1).toIso8601String(),
          dataPagamento: DateTime(2026, 8, 1).toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Saída',
          descricao: 'Saída realizada',
          valor: 200,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 2).toIso8601String(),
          contaId: contaId,
          status: 'Realizado',
          dataCompetencia: DateTime(2026, 8, 2).toIso8601String(),
          dataPagamento: DateTime(2026, 8, 2).toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Entrada prevista',
          valor: 400,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 4).toIso8601String(),
          contaId: contaId,
          status: 'Previsto',
          dataCompetencia: DateTime(2026, 8, 4).toIso8601String(),
          dataVencimento: DateTime(2026, 8, 4).toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Saída',
          descricao: 'Saída prevista',
          valor: 300,
          formaPagamento: 'Pix',
          data: DateTime(2026, 8, 3).toIso8601String(),
          contaId: contaId,
          status: 'Previsto',
          dataCompetencia: DateTime(2026, 8, 3).toIso8601String(),
          dataVencimento: DateTime(2026, 8, 3).toIso8601String(),
        ),
      );

      final resumo = await fluxo.obterResumo(
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
      );

      expect(resumo['saldo_inicial'], 1000);
      expect(resumo['entradas_realizadas'], 500);
      expect(resumo['saidas_realizadas'], 200);
      expect(resumo['saldo_final'], 1300);
      expect(resumo['entradas_previstas'], 400);
      expect(resumo['saidas_previstas'], 300);
      expect(resumo['saldo_projetado'], 1400);

      final diario = await fluxo.listarFluxoDiario(
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
      );
      expect(diario, hasLength(4));
      expect(diario.last['saldo_projetado_acumulado'], 1400);
    });

    test('agrupa fluxo mensal preenchendo meses sem movimento', () async {
      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Receita janeiro',
          valor: 100,
          formaPagamento: 'Pix',
          data: DateTime(2026, 1, 10).toIso8601String(),
          status: 'Realizado',
          dataCompetencia: DateTime(2026, 1, 10).toIso8601String(),
          dataPagamento: DateTime(2026, 1, 10).toIso8601String(),
        ),
      );

      final mensal = await fluxo.listarFluxoMensal(
        inicio: DateTime(2026, 1, 1),
        fim: DateTime(2026, 12, 31),
      );

      expect(mensal, hasLength(12));
      expect(mensal.first['mes_ref'], '2026-01');
      expect(mensal.first['entradas_realizadas'], 100);
      expect(mensal[1]['mes_ref'], '2026-02');
      expect(mensal[1]['entradas_realizadas'], 0);
    });

    test(
      'previsto x realizado ignora categorias que não impactam DRE',
      () async {
        final database = await AppDatabase.instance.database;
        final planoNaoDre = await database.query(
          'financeiro_plano_contas',
          columns: ['id'],
          where: 'codigo = ?',
          whereArgs: ['9.01'],
          limit: 1,
        );

        await financeiro.inserirMovimento(
          MovimentoFinanceiro(
            tipo: 'Entrada',
            descricao: 'Receita prevista teste',
            valor: 300,
            formaPagamento: 'Pix',
            data: DateTime(2026, 8, 10).toIso8601String(),
            status: 'Previsto',
            dataCompetencia: DateTime(2026, 8, 10).toIso8601String(),
            dataVencimento: DateTime(2026, 8, 10).toIso8601String(),
          ),
        );

        await financeiro.inserirMovimento(
          MovimentoFinanceiro(
            tipo: 'Entrada',
            descricao: 'Transferência simulada',
            valor: 999,
            formaPagamento: 'Transferência',
            data: DateTime(2026, 8, 10).toIso8601String(),
            planoContaId: (planoNaoDre.first['id'] as num).toInt(),
            status: 'Realizado',
            dataCompetencia: DateTime(2026, 8, 10).toIso8601String(),
            dataPagamento: DateTime(2026, 8, 10).toIso8601String(),
          ),
        );

        final resumo = await fluxo.obterPrevistoRealizado(
          inicio: DateTime(2026, 8, 1),
          fim: DateTime(2026, 8, 31),
        );

        expect(resumo['entrada_prevista'], 300);
        expect(resumo['entrada_realizada'], 0);
      },
    );
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
