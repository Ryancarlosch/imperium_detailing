import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/conta_financeira.dart';
import 'package:imperium_detailing/models/fornecedor.dart';
import 'package:imperium_detailing/models/movimento_financeiro.dart';
import 'package:imperium_detailing/repositories/conta_financeira_repository.dart';
import 'package:imperium_detailing/repositories/dashboard_repository.dart';
import 'package:imperium_detailing/repositories/financeiro_repository.dart';
import 'package:imperium_detailing/repositories/fornecedor_repository.dart';
import 'package:imperium_detailing/repositories/plano_contas_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late FinanceiroRepository financeiro;
  late PlanoContasRepository plano;
  late ContaFinanceiraRepository contas;
  late FornecedorRepository fornecedores;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_financeiro_v24_test_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    financeiro = FinanceiroRepository();
    plano = PlanoContasRepository();
    contas = ContaFinanceiraRepository();
    fornecedores = FornecedorRepository();
  });

  tearDown(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('Financeiro v24 - motor financeiro', () {
    test('registra despesa prevista e baixa como realizada', () async {
      final categorias = await plano.listarFolhasParaTipo('Saída');
      final aluguel = categorias.firstWhere((item) => item.nome == 'Aluguel');
      final agora = DateTime.now().toIso8601String();

      final fornecedorId = await fornecedores.inserir(
        Fornecedor(
          nome: 'Imobiliária Teste',
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final contaId = await contas.inserir(
        ContaFinanceira(
          nome: 'Banco de teste',
          saldoInicial: 1000,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final competencia = DateTime(2026, 8, 1);
      final vencimento = DateTime(2026, 8, 10);
      final id = await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Saída',
          descricao: 'Aluguel da oficina',
          valor: 500,
          formaPagamento: 'Pix',
          data: vencimento.toIso8601String(),
          planoContaId: aluguel.id,
          contaId: contaId,
          fornecedorId: fornecedorId,
          status: 'Previsto',
          dataCompetencia: competencia.toIso8601String(),
          dataVencimento: vencimento.toIso8601String(),
        ),
      );

      var movimento = await financeiro.buscarMovimentoPorId(id);
      expect(movimento, isNotNull);
      expect(movimento!.status, 'Previsto');
      expect(movimento.natureza, 'Despesa fixa');
      expect(movimento.impactaDre, isTrue);

      await financeiro.marcarComoRealizado(
        id: id,
        dataPagamento: DateTime(2026, 8, 8),
      );

      movimento = await financeiro.buscarMovimentoPorId(id);
      expect(movimento!.status, 'Realizado');
      expect(movimento.dataPagamento, isNotNull);

      final resumo = await financeiro.obterResumoFinanceiro(
        dataInicial: '2026-08-01',
        dataFinal: '2026-08-31',
      );
      expect(resumo['saidas'], 500);
    });

    test('transferência gera dois movimentos e não impacta DRE', () async {
      final agora = DateTime.now().toIso8601String();
      final origemId = await contas.inserir(
        ContaFinanceira(
          nome: 'Conta origem',
          saldoInicial: 1000,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
      final destinoId = await contas.inserir(
        ContaFinanceira(
          nome: 'Conta destino',
          saldoInicial: 100,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final transferenciaId = await financeiro.registrarTransferencia(
        contaOrigemId: origemId,
        contaDestinoId: destinoId,
        valor: 250,
        data: DateTime(2026, 8, 8),
      );

      final database = await AppDatabase.instance.database;
      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
        orderBy: 'id ASC',
      );

      expect(movimentos, hasLength(2));
      expect(movimentos.every((item) => item['impacta_dre'] == 0), isTrue);
      expect(
        movimentos.map((item) => item['tipo']).toSet(),
        containsAll(<String>{'Saída', 'Entrada'}),
      );

      final contasAtualizadas = await contas.listar();
      final origem = contasAtualizadas.firstWhere(
        (item) => item.id == origemId,
      );
      final destino = contasAtualizadas.firstWhere(
        (item) => item.id == destinoId,
      );
      expect(origem.saldoAtual, 750);
      expect(destino.saldoAtual, 350);
    });

    test('dashboard considera somente movimentações realizadas', () async {
      final hoje = DateTime.now();
      final data = DateTime(hoje.year, hoje.month, hoje.day, 10);

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Receita realizada',
          valor: 100,
          formaPagamento: 'Pix',
          data: data.toIso8601String(),
          status: 'Realizado',
          dataCompetencia: data.toIso8601String(),
          dataPagamento: data.toIso8601String(),
        ),
      );

      await financeiro.inserirMovimento(
        MovimentoFinanceiro(
          tipo: 'Entrada',
          descricao: 'Receita prevista',
          valor: 900,
          formaPagamento: 'Pix',
          data: data.toIso8601String(),
          status: 'Previsto',
          dataCompetencia: data.toIso8601String(),
          dataVencimento: data.toIso8601String(),
        ),
      );

      final dashboard = await DashboardRepository().carregarDashboard(
        periodo: DashboardPeriodo.hoje,
      );

      expect(dashboard.faturamento, 100);
    });

    test('protege movimentação automática contra edição manual', () async {
      final database = await AppDatabase.instance.database;
      final data = DateTime(2026, 8, 8).toIso8601String();
      final id = await database.insert('movimentos_financeiros', {
        'tipo': 'Entrada',
        'descricao': 'Movimento automático de teste',
        'valor': 100,
        'forma_pagamento': 'Pix',
        'data': data,
        'origem': 'Pagamento de OS',
        'status': 'Realizado',
        'data_competencia': data,
        'data_pagamento': data,
        'impacta_dre': 1,
      });

      final movimento = await financeiro.buscarMovimentoPorId(id);
      expect(movimento, isNotNull);

      await expectLater(
        financeiro.atualizarMovimento(
          movimento!.copyWith(descricao: 'Tentativa de alteração'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
