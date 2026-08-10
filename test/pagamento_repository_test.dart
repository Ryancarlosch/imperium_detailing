import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:imperium_detailing/repositories/pagamento_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late OrdemServicoRepository ordemRepository;
  late PagamentoRepository pagamentoRepository;
  var sequencia = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_pagamentos_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
    ordemRepository = OrdemServicoRepository();
    pagamentoRepository = PagamentoRepository();
    sequencia = 0;
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('PagamentoRepository', () {
    test('registra pagamento parcial e quita com múltiplas formas', () async {
      final ordemId = await _criarOrdemFinalizadaPendente(
        repository: ordemRepository,
        numero: _numero(++sequencia),
        valor: 1000,
      );

      final primeiroId = await pagamentoRepository.registrarPagamento(
        ordemServicoId: ordemId,
        valor: 400,
        formaPagamento: 'Pix',
        comprovanteCaminho: '/teste/comprovante_pix.pdf',
      );

      var ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
      expect(ordem, isNotNull);
      expect(ordem!.statusPagamento, 'Parcialmente pago');
      expect(ordem.valorRecebido, 400);
      expect(ordem.valorPendente, 600);
      expect(ordem.formaPagamento, 'Pix');
      expect(ordem.lancadoFinanceiro, isTrue);

      final database = await AppDatabase.instance.database;
      var movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(movimentos, hasLength(1));
      expect(movimentos.single['pagamento_id'], primeiroId);
      expect((movimentos.single['valor'] as num).toDouble(), 400);

      await pagamentoRepository.registrarPagamento(
        ordemServicoId: ordemId,
        valor: 600,
        formaPagamento: 'Dinheiro',
      );

      ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
      expect(ordem, isNotNull);
      expect(ordem!.statusPagamento, 'Pago');
      expect(ordem.valorRecebido, 1000);
      expect(ordem.valorPendente, 0);
      expect(ordem.formaPagamento, 'Múltiplas formas');

      movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );
      expect(movimentos, hasLength(2));
    });

    test('recusa pagamento maior que o saldo sem gravar nada', () async {
      final ordemId = await _criarOrdemFinalizadaPendente(
        repository: ordemRepository,
        numero: _numero(++sequencia),
        valor: 500,
      );

      await expectLater(
        pagamentoRepository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 501,
          formaPagamento: 'Pix',
        ),
        throwsA(isA<StateError>()),
      );

      final database = await AppDatabase.instance.database;
      final pagamentos = await database.query(
        'ordem_servico_pagamentos',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );
      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );
      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(pagamentos, isEmpty);
      expect(movimentos, isEmpty);
      expect(ordem!.statusPagamento, 'Pendente');
      expect(ordem.valorRecebido, 0);
    });

    test(
      'marca conta como vencida e volta a parcial após recebimento',
      () async {
        final ordemId = await _criarOrdemFinalizadaPendente(
          repository: ordemRepository,
          numero: _numero(++sequencia),
          valor: 800,
        );

        final ontem = DateTime.now().subtract(const Duration(days: 1));
        await pagamentoRepository.definirVencimento(
          ordemServicoId: ordemId,
          vencimento: ontem,
        );

        var resumo = await pagamentoRepository.buscarResumoOrdem(ordemId);
        expect(resumo, isNotNull);
        expect(resumo!['status_pagamento'], 'Vencido');

        await pagamentoRepository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 300,
          formaPagamento: 'Pix',
        );

        resumo = await pagamentoRepository.buscarResumoOrdem(ordemId);
        expect(resumo, isNotNull);
        expect(resumo!['status_pagamento'], 'Vencido');
        expect((resumo['valor_recebido'] as num).toDouble(), 300);
        expect((resumo['valor_pendente'] as num).toDouble(), 500);

        final amanha = DateTime.now().add(const Duration(days: 1));
        await pagamentoRepository.definirVencimento(
          ordemServicoId: ordemId,
          vencimento: amanha,
        );

        resumo = await pagamentoRepository.buscarResumoOrdem(ordemId);
        expect(resumo!['status_pagamento'], 'Parcialmente pago');
      },
    );

    test('cria parcelamento em centavos e recebe a primeira parcela', () async {
      final ordemId = await _criarOrdemFinalizadaPendente(
        repository: ordemRepository,
        numero: _numero(++sequencia),
        valor: 1000,
      );

      final primeiroVencimento = DateTime.now().add(const Duration(days: 10));
      await pagamentoRepository.criarParcelamento(
        ordemServicoId: ordemId,
        totalParcelas: 3,
        primeiroVencimento: primeiroVencimento,
      );

      var parcelas = await pagamentoRepository.listarPagamentosDaOrdem(ordemId);

      expect(parcelas, hasLength(3));
      expect(parcelas.every((item) => item.estaPendente), isTrue);
      expect(parcelas[0].parcelaNumero, 1);
      expect(parcelas[0].totalParcelas, 3);

      final totalParcelado = parcelas.fold<double>(
        0,
        (total, item) => total + item.valor,
      );
      expect(totalParcelado, closeTo(1000, 0.000001));

      final primeira = parcelas.firstWhere((item) => item.parcelaNumero == 1);
      await pagamentoRepository.receberParcela(
        pagamentoId: primeira.id!,
        formaPagamento: 'Cartão de crédito',
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
      expect(ordem, isNotNull);
      expect(ordem!.statusPagamento, 'Parcialmente pago');
      expect(ordem.valorRecebido, closeTo(primeira.valor, 0.000001));

      parcelas = await pagamentoRepository.listarPagamentosDaOrdem(ordemId);
      expect(parcelas.where((item) => item.estaPago), hasLength(1));
      expect(parcelas.where((item) => item.estaPendente), hasLength(2));
    });

    test(
      'bloqueia pagamento avulso enquanto existem parcelas pendentes',
      () async {
        final ordemId = await _criarOrdemFinalizadaPendente(
          repository: ordemRepository,
          numero: _numero(++sequencia),
          valor: 600,
        );

        await pagamentoRepository.criarParcelamento(
          ordemServicoId: ordemId,
          totalParcelas: 2,
          primeiroVencimento: DateTime.now().add(const Duration(days: 10)),
        );

        await expectLater(
          pagamentoRepository.registrarPagamento(
            ordemServicoId: ordemId,
            valor: 100,
            formaPagamento: 'Pix',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'estorna pagamento e cria saída financeira sem apagar histórico',
      () async {
        final ordemId = await _criarOrdemFinalizadaPendente(
          repository: ordemRepository,
          numero: _numero(++sequencia),
          valor: 450,
        );

        final pagamentoId = await pagamentoRepository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 450,
          formaPagamento: 'Pix',
        );

        await pagamentoRepository.estornarPagamento(
          pagamentoId: pagamentoId,
          motivo: 'Pagamento lançado por engano.',
        );

        final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
        expect(ordem, isNotNull);
        expect(ordem!.statusPagamento, 'Pendente');
        expect(ordem.valorRecebido, 0);
        expect(ordem.lancadoFinanceiro, isFalse);

        final pagamentos = await pagamentoRepository.listarPagamentosDaOrdem(
          ordemId,
        );
        expect(pagamentos, hasLength(1));
        expect(pagamentos.single.status, 'Estornado');
        expect(pagamentos.single.motivoEstorno, contains('engano'));

        final database = await AppDatabase.instance.database;
        final movimentos = await database.query(
          'movimentos_financeiros',
          where: 'ordem_servico_id = ?',
          whereArgs: [ordemId],
          orderBy: 'id ASC',
        );

        expect(movimentos, hasLength(2));
        expect(movimentos[0]['tipo'], 'entrada');
        expect(movimentos[1]['tipo'], 'saída');
        expect(movimentos[1]['pagamento_id'], pagamentoId);
      },
    );

    test('estorno de parcela reabre a parcela pendente', () async {
      final ordemId = await _criarOrdemFinalizadaPendente(
        repository: ordemRepository,
        numero: _numero(++sequencia),
        valor: 400,
      );

      await pagamentoRepository.criarParcelamento(
        ordemServicoId: ordemId,
        totalParcelas: 2,
        primeiroVencimento: DateTime.now().add(const Duration(days: 5)),
      );

      var parcelas = await pagamentoRepository.listarPagamentosDaOrdem(ordemId);
      final primeira = parcelas.firstWhere((item) => item.parcelaNumero == 1);

      await pagamentoRepository.receberParcela(
        pagamentoId: primeira.id!,
        formaPagamento: 'Dinheiro',
      );

      await pagamentoRepository.estornarPagamento(
        pagamentoId: primeira.id!,
        motivo: 'Cliente solicitou correção do recebimento.',
      );

      parcelas = await pagamentoRepository.listarPagamentosDaOrdem(ordemId);

      expect(
        parcelas.where(
          (item) => item.parcelaNumero == 1 && item.status == 'Estornado',
        ),
        hasLength(1),
      );
      expect(
        parcelas.where(
          (item) => item.parcelaNumero == 1 && item.status == 'Pendente',
        ),
        hasLength(1),
      );
    });

    test('recusa pagamento em OS não finalizada', () async {
      final database = await AppDatabase.instance.database;
      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente não finalizado',
      });

      final ordemId = await ordemRepository.inserirOrdemServico(
        OrdemServico(
          clienteId: clienteId,
          numero: _numero(++sequencia),
          status: 'Em andamento',
          dataAbertura: '2026-08-07',
          dataInicio: '2026-08-07',
          valorTotal: 300,
        ),
      );

      await expectLater(
        pagamentoRepository.registrarPagamento(
          ordemServicoId: ordemId,
          valor: 100,
          formaPagamento: 'Pix',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

String _numero(int sequencia) {
  return 'OS-PAG-${sequencia.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdemFinalizadaPendente({
  required OrdemServicoRepository repository,
  required String numero,
  required double valor,
}) async {
  final database = await AppDatabase.instance.database;
  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente $numero',
    'telefone': '11999999999',
  });

  final ordemId = await repository.inserirOrdemServico(
    OrdemServico(
      clienteId: clienteId,
      numero: numero,
      status: 'Em andamento',
      dataAbertura: '2026-08-07',
      dataInicio: '2026-08-07',
      valorTotal: valor,
    ),
  );

  await repository.finalizarOrdemServico(ordemServicoId: ordemId);
  return ordemId;
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
