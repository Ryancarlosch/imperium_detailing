import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/dashboard_repository.dart';
import 'package:imperium_detailing/repositories/dre_repository.dart';
import 'package:imperium_detailing/repositories/financeiro_dashboard_repository.dart';
import 'package:imperium_detailing/repositories/pagamento_repository.dart';
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
      'imperium_fluxo_financeiro_e2e_',
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
    'OS com desconto e pagamento parcial permanece coerente em toda a cadeia',
    () async {
      final database = await AppDatabase.instance.database;
      final pagamentoRepository = PagamentoRepository();
      final hoje = DateTime.now();
      final data = DateTime(hoje.year, hoje.month, hoje.day, 12);
      final dataIso = data.toIso8601String();

      final contaId = await _prepararContaPadrao(database, saldoInicial: 5000);

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente Fluxo Completo',
        'telefone': '11999999999',
      });

      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-E2E-DESCONTO',
        'status': 'Finalizada',
        'data_abertura': dataIso,
        'data_inicio': dataIso,
        'data_finalizacao': dataIso,
        'valor_total': 600.0,
        'desconto': 250.0,
        'status_pagamento': 'Pendente',
        'valor_recebido': 0.0,
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

      await pagamentoRepository.registrarPagamento(
        ordemServicoId: ordemId,
        valor: 200.0,
        formaPagamento: 'Pix',
        dataPagamento: data,
        contaFinanceiraId: contaId,
      );

      final resumoOrdem = await pagamentoRepository.buscarResumoOrdem(ordemId);
      expect(resumoOrdem, isNotNull);
      expect(_double(resumoOrdem!['valor_final']), closeTo(350, 0.001));
      expect(_double(resumoOrdem['valor_recebido']), closeTo(200, 0.001));
      expect(_double(resumoOrdem['valor_pendente']), closeTo(150, 0.001));
      expect(resumoOrdem['status_pagamento'], 'Parcialmente pago');

      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );

      expect(movimentos, hasLength(1));
      expect(
        (movimentos.single['tipo'] ?? '').toString().toLowerCase(),
        'entrada',
      );
      expect(_double(movimentos.single['valor']), closeTo(200, 0.001));
      expect(movimentos.single['conta_id'], contaId);
      expect(movimentos.single['origem'], 'Pagamento de OS');

      final dashboard = await DashboardRepository().carregarDashboard(
        periodo: DashboardPeriodo.personalizado,
        inicioPersonalizado: data,
        fimPersonalizado: data,
      );

      expect(dashboard.faturamentoCompetencia, closeTo(350, 0.001));
      expect(dashboard.faturamento, closeTo(200, 0.001));
      expect(dashboard.saidas, closeTo(0, 0.001));
      expect(dashboard.saldo, closeTo(200, 0.001));

      final contaDashboard = dashboard.saldosContas.singleWhere(
        (conta) => conta.nome == 'Caixa / Dinheiro',
      );
      expect(contaDashboard.saldoAtual, closeTo(5200, 0.001));

      final servico = dashboard.topServicos.singleWhere(
        (item) => item.nome == 'Polimento técnico',
      );
      expect(servico.total, closeTo(350, 0.001));

      final dre = await DreRepository().calcular(
        inicio: data,
        fim: data,
        regime: DreRegime.competencia,
      );

      expect(dre.receitaBruta, closeTo(600, 0.001));
      expect(dre.deducoes, closeTo(250, 0.001));
      expect(dre.receitaLiquida, closeTo(350, 0.001));

      final financeiro = await FinanceiroDashboardRepository().carregar(
        mes: data,
      );

      expect(financeiro.vendasFinalizadas, closeTo(350, 0.001));
      expect(financeiro.recebido, closeTo(200, 0.001));
      expect(financeiro.taxas, closeTo(0, 0.001));
      expect(financeiro.aReceber, closeTo(150, 0.001));

      final resumoGeral = await pagamentoRepository.obterResumoGeral();
      expect(resumoGeral['recebido'], closeTo(200, 0.001));
      expect(resumoGeral['a_receber'], closeTo(150, 0.001));
      expect(resumoGeral['liquido'], closeTo(200, 0.001));
    },
  );

  test(
    'parcela no cartao, taxa e estorno atualizam conta e DRE caixa',
    () async {
      final database = await AppDatabase.instance.database;
      final pagamentoRepository = PagamentoRepository();
      final hoje = DateTime.now();
      final data = DateTime(hoje.year, hoje.month, hoje.day, 13);
      final agoraIso = DateTime.now().toIso8601String();

      final stoneId = await database.insert('financeiro_contas', {
        'nome': 'Stone E2E',
        'tipo': 'Maquininha',
        'instituicao': 'Stone',
        'saldo_inicial': 1000.0,
        'data_saldo_inicial': null,
        'observacoes': 'Conta do teste financeiro ponta a ponta.',
        'ativo': 1,
        'criado_em': agoraIso,
        'atualizado_em': agoraIso,
      });

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente Parcelado E2E',
        'telefone': '11988888888',
      });

      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-E2E-CARTAO',
        'status': 'Finalizada',
        'data_abertura': data.toIso8601String(),
        'data_inicio': data.toIso8601String(),
        'data_finalizacao': data.toIso8601String(),
        'valor_total': 1000.0,
        'desconto': 0.0,
        'status_pagamento': 'Pendente',
        'valor_recebido': 0.0,
        'lancado_financeiro': 0,
      });

      await pagamentoRepository.criarParcelamento(
        ordemServicoId: ordemId,
        totalParcelas: 2,
        primeiroVencimento: hoje.add(const Duration(days: 10)),
      );

      final parcelas = await pagamentoRepository.listarPagamentosDaOrdem(
        ordemId,
      );
      expect(parcelas, hasLength(2));

      final primeira = parcelas.singleWhere((item) => item.parcelaNumero == 1);

      await pagamentoRepository.receberParcela(
        pagamentoId: primeira.id!,
        formaPagamento: 'Cartão de crédito',
        dataPagamento: data,
        taxaOperacao: 20.0,
        taxaPercentual: 4.0,
        contaFinanceiraId: stoneId,
        aplicarRegraTaxaAutomatica: false,
      );

      var resumo = await pagamentoRepository.buscarResumoOrdem(ordemId);
      expect(_double(resumo!['valor_final']), closeTo(1000, 0.001));
      expect(_double(resumo['valor_recebido']), closeTo(500, 0.001));
      expect(_double(resumo['valor_pendente']), closeTo(500, 0.001));
      expect(resumo['status_pagamento'], 'Parcialmente pago');

      final movimentosAntesEstorno = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );

      expect(movimentosAntesEstorno, hasLength(2));
      expect(
        movimentosAntesEstorno
            .where(
              (item) =>
                  (item['tipo'] ?? '').toString().toLowerCase() == 'entrada',
            )
            .fold<double>(0, (soma, item) => soma + _double(item['valor'])),
        closeTo(500, 0.001),
      );
      expect(
        movimentosAntesEstorno
            .where((item) {
              final tipo = (item['tipo'] ?? '').toString().toLowerCase();
              return tipo == 'saída' || tipo == 'saida';
            })
            .fold<double>(0, (soma, item) => soma + _double(item['valor'])),
        closeTo(20, 0.001),
      );

      var saldos = await FinanceiroDashboardRepository().saldosContas();
      expect(saldos['Stone E2E'], closeTo(1480, 0.001));

      var financeiro = await FinanceiroDashboardRepository().carregar(
        mes: data,
      );

      expect(financeiro.vendasFinalizadas, closeTo(1000, 0.001));
      expect(financeiro.recebido, closeTo(500, 0.001));
      expect(financeiro.taxas, closeTo(20, 0.001));
      expect(financeiro.recebidoLiquido, closeTo(480, 0.001));
      expect(financeiro.aReceber, closeTo(500, 0.001));
      expect(financeiro.dreCaixa.receitaLiquida, closeTo(500, 0.001));
      expect(financeiro.dreCaixa.custosVariaveis, closeTo(20, 0.001));

      await pagamentoRepository.estornarPagamento(
        pagamentoId: primeira.id!,
        motivo: 'Estorno de validacao ponta a ponta.',
      );

      resumo = await pagamentoRepository.buscarResumoOrdem(ordemId);
      expect(_double(resumo!['valor_recebido']), closeTo(0, 0.001));
      expect(_double(resumo['valor_pendente']), closeTo(1000, 0.001));

      final movimentosDepoisEstorno = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );

      expect(movimentosDepoisEstorno, hasLength(3));

      saldos = await FinanceiroDashboardRepository().saldosContas();
      expect(saldos['Stone E2E'], closeTo(980, 0.001));

      financeiro = await FinanceiroDashboardRepository().carregar(mes: data);
      expect(financeiro.aReceber, closeTo(1000, 0.001));
      expect(financeiro.dreCaixa.receitaLiquida, closeTo(0, 0.001));
      expect(financeiro.dreCaixa.custosVariaveis, closeTo(20, 0.001));
    },
  );
}

Future<int> _prepararContaPadrao(
  Database database, {
  required double saldoInicial,
}) async {
  final conta = await database.query(
    'financeiro_contas',
    columns: ['id'],
    where: 'nome = ?',
    whereArgs: ['Caixa / Dinheiro'],
    limit: 1,
  );

  expect(conta, isNotEmpty);

  final id = (conta.single['id'] as num).toInt();

  await database.update(
    'financeiro_contas',
    {
      'saldo_inicial': saldoInicial,
      'atualizado_em': DateTime.now().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  return id;
}

double _double(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
