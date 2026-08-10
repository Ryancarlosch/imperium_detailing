import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/pagamento_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late PagamentoRepository repository;
  var sequencia = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_pagamentos_v23_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
    repository = PagamentoRepository();
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('Pagamentos v23 - ajustes comerciais e taxas', () {
    test(
      'aplica desconto, acréscimo e juros sem alterar o valor original',
      () async {
        final ordemId = await _criarOrdemFinalizada(
          numero: _numero(++sequencia),
          valorTotal: 1000,
          descontoOs: 100,
        );

        await repository.registrarAjusteComercial(
          ordemServicoId: ordemId,
          tipo: 'Acréscimo',
          valor: 80,
          motivo: 'Acréscimo negociado com o cliente.',
        );

        await repository.registrarAjusteComercial(
          ordemServicoId: ordemId,
          tipo: 'Juros',
          valor: 40,
          motivo: 'Juros para parcelamento em seis vezes.',
        );

        final descontoId = await repository.registrarAjusteComercial(
          ordemServicoId: ordemId,
          tipo: 'Desconto',
          valor: 20,
          motivo: 'Desconto comercial de fechamento.',
        );

        var resumo = await repository.buscarResumoOrdem(ordemId);

        expect(resumo, isNotNull);
        expect((resumo!['valor_total'] as num).toDouble(), 1000);
        expect((resumo['desconto'] as num).toDouble(), 100);
        expect((resumo['valor_base'] as num).toDouble(), 900);
        expect((resumo['acrescimo_negociacao'] as num).toDouble(), 80);
        expect((resumo['juros_parcelamento'] as num).toDouble(), 40);
        expect((resumo['desconto_negociacao'] as num).toDouble(), 20);
        expect((resumo['valor_final'] as num).toDouble(), 1000);
        expect((resumo['valor_pendente'] as num).toDouble(), 1000);

        var ajustes = await repository.listarAjustesDaOrdem(ordemId);
        expect(ajustes, hasLength(3));
        expect(ajustes.where((item) => item.estaAtivo), hasLength(3));

        await repository.estornarAjusteComercial(
          ajusteId: descontoId,
          motivo: 'Desconto removido após nova negociação.',
        );

        resumo = await repository.buscarResumoOrdem(ordemId);
        expect((resumo!['desconto_negociacao'] as num).toDouble(), 0);
        expect((resumo['valor_final'] as num).toDouble(), 1020);

        ajustes = await repository.listarAjustesDaOrdem(ordemId);
        final desconto = ajustes.firstWhere((item) => item.id == descontoId);
        expect(desconto.estaCancelado, isTrue);
        expect(desconto.motivoCancelamento, contains('nova negociação'));
      },
    );

    test(
      'impede desconto que deixaria o total abaixo do que já foi recebido',
      () async {
        final ordemId = await _criarOrdemFinalizada(
          numero: _numero(++sequencia),
          valorTotal: 1000,
        );

        await repository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 700,
          formaPagamento: 'Pix',
        );

        await expectLater(
          repository.registrarAjusteComercial(
            ordemServicoId: ordemId,
            tipo: 'Desconto',
            valor: 400,
            motivo: 'Desconto incompatível com o valor já recebido.',
          ),
          throwsA(isA<StateError>()),
        );

        final resumo = await repository.buscarResumoOrdem(ordemId);
        expect((resumo!['valor_final'] as num).toDouble(), 1000);
        expect((resumo['valor_recebido'] as num).toDouble(), 700);
        expect((resumo['valor_pendente'] as num).toDouble(), 300);

        final ajustes = await repository.listarAjustesDaOrdem(ordemId);
        expect(ajustes, isEmpty);
      },
    );

    test(
      'bloqueia ajuste comercial enquanto existem parcelas pendentes',
      () async {
        final ordemId = await _criarOrdemFinalizada(
          numero: _numero(++sequencia),
          valorTotal: 900,
        );

        await repository.criarParcelamento(
          ordemServicoId: ordemId,
          totalParcelas: 3,
          primeiroVencimento: DateTime.now().add(const Duration(days: 10)),
        );

        await expectLater(
          repository.registrarAjusteComercial(
            ordemServicoId: ordemId,
            tipo: 'Acréscimo',
            valor: 90,
            motivo: 'Tentativa de alterar parcelamento existente.',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('taxa da maquininha gera saída financeira e valor líquido', () async {
      final ordemId = await _criarOrdemFinalizada(
        numero: _numero(++sequencia),
        valorTotal: 1000,
      );

      final pagamentoId = await repository.registrarPagamento(
        ordemServicoId: ordemId,
        valor: 1000,
        formaPagamento: 'Cartão de crédito',
        taxaOperacao: 39.90,
        taxaPercentual: 3.99,
      );

      final pagamentos = await repository.listarPagamentosDaOrdem(ordemId);
      expect(pagamentos, hasLength(1));
      expect(pagamentos.single.id, pagamentoId);
      expect(pagamentos.single.taxaPercentual, closeTo(3.99, 0.000001));
      expect(pagamentos.single.taxaOperacao, closeTo(39.90, 0.000001));
      expect(pagamentos.single.valorLiquido, closeTo(960.10, 0.000001));

      final database = await AppDatabase.instance.database;
      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );

      expect(movimentos, hasLength(2));
      expect(movimentos[0]['tipo'], 'entrada');
      expect((movimentos[0]['valor'] as num).toDouble(), 1000);
      expect(movimentos[1]['tipo'], 'saída');
      expect(
        (movimentos[1]['valor'] as num).toDouble(),
        closeTo(39.90, 0.000001),
      );
      expect(movimentos[1]['descricao'], contains('Taxa da maquininha'));
      expect(movimentos[1]['pagamento_id'], pagamentoId);

      final resumo = await repository.buscarResumoOrdem(ordemId);
      expect(resumo!['status_pagamento'], 'Pago');
      expect((resumo['valor_recebido'] as num).toDouble(), 1000);
      expect(
        (resumo['taxas_operacao'] as num).toDouble(),
        closeTo(39.90, 0.000001),
      );
      expect(
        (resumo['valor_liquido_recebido'] as num).toDouble(),
        closeTo(960.10, 0.000001),
      );
    });

    test(
      'estorno preserva a taxa da maquininha como custo histórico',
      () async {
        final ordemId = await _criarOrdemFinalizada(
          numero: _numero(++sequencia),
          valorTotal: 500,
        );

        final pagamentoId = await repository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 500,
          formaPagamento: 'Cartão de crédito',
          taxaOperacao: 20,
          taxaPercentual: 4,
        );

        await repository.estornarPagamento(
          pagamentoId: pagamentoId,
          motivo: 'Pagamento cancelado pelo cliente.',
        );

        final resumo = await repository.buscarResumoOrdem(ordemId);
        expect((resumo!['valor_recebido'] as num).toDouble(), 0);
        expect((resumo['taxas_operacao'] as num).toDouble(), 20);
        expect((resumo['valor_liquido_recebido'] as num).toDouble(), -20);
        expect(resumo['status_pagamento'], 'Pendente');
      },
    );

    test(
      'taxa também pode ser aplicada ao recebimento de uma parcela',
      () async {
        final ordemId = await _criarOrdemFinalizada(
          numero: _numero(++sequencia),
          valorTotal: 1000,
        );

        await repository.criarParcelamento(
          ordemServicoId: ordemId,
          totalParcelas: 2,
          primeiroVencimento: DateTime.now().add(const Duration(days: 5)),
        );

        final parcelas = await repository.listarPagamentosDaOrdem(ordemId);
        final primeira = parcelas.firstWhere((item) => item.parcelaNumero == 1);

        await repository.receberParcela(
          pagamentoId: primeira.id!,
          formaPagamento: 'Cartão de débito',
          taxaOperacao: 10,
        );

        final atualizadas = await repository.listarPagamentosDaOrdem(ordemId);
        final paga = atualizadas.firstWhere((item) => item.id == primeira.id);

        expect(paga.estaPago, isTrue);
        expect(paga.taxaOperacao, 10);
        expect(paga.valorLiquido, closeTo(paga.valor - 10, 0.000001));
      },
    );
  });
}

String _numero(int sequencia) {
  return 'OS-V23-${sequencia.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdemFinalizada({
  required String numero,
  required double valorTotal,
  double descontoOs = 0,
}) async {
  final database = await AppDatabase.instance.database;

  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente $numero',
    'telefone': '11999999999',
  });

  return database.insert('ordens_servico', {
    'cliente_id': clienteId,
    'numero': numero,
    'status': 'Finalizada',
    'data_abertura': '2026-08-07',
    'data_finalizacao': '2026-08-07',
    'valor_total': valorTotal,
    'desconto': descontoOs,
    'status_pagamento': 'Pendente',
    'valor_recebido': 0,
    'lancado_financeiro': 0,
  });
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
