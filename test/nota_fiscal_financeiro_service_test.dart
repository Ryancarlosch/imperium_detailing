import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/conta_financeira_repository.dart';
import 'package:imperium_detailing/repositories/dre_repository.dart';
import 'package:imperium_detailing/services/nota_fiscal_financeiro_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late NotaFiscalFinanceiroService service;
  late ContaFinanceiraRepository contas;
  late DreRepository dre;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_nota_fiscal_financeiro_test_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    service = NotaFiscalFinanceiroService();
    contas = ContaFinanceiraRepository();
    dre = DreRepository();
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
    'compra já paga reduz saldo e compra de estoque não impacta DRE',
    () async {
      final database = await AppDatabase.instance.database;
      final notaId = await _criarNota(database, valor: 500);

      final contaId = await _contaPadrao(database);
      await database.update(
        'financeiro_contas',
        {'saldo_inicial': 1000.0},
        where: 'id = ?',
        whereArgs: [contaId],
      );
      final planoEstoque = await _plano(database, '9.06');

      await service.criarLancamento(
        notaFiscalId: notaId,
        jaPago: true,
        planoContaId: planoEstoque,
        contaId: contaId,
        formaPagamento: 'Pix',
        dataPagamento: DateTime(2026, 9, 8),
      );

      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'nota_fiscal_id = ?',
        whereArgs: [notaId],
      );
      expect(movimentos, hasLength(1));
      expect(movimentos.single['status'], 'Realizado');
      expect(movimentos.single['impacta_dre'], 0);
      expect(movimentos.single['data_vencimento'], isNull);
      expect(
        (movimentos.single['numero_documento'] ?? '').toString(),
        isNotEmpty,
      );

      final conta = (await contas.listar()).firstWhere(
        (item) => item.id == contaId,
      );
      expect(conta.saldoAtual, closeTo(500, 0.000001));

      final resultado = await dre.calcular(
        inicio: DateTime(2026, 9, 1),
        fim: DateTime(2026, 9, 30),
        regime: DreRegime.competencia,
      );
      expect(resultado.outrasDespesas, closeTo(0, 0.000001));
      expect(resultado.custosVariaveis, closeTo(0, 0.000001));
    },
  );

  test(
    'compra parcelada prevista não altera saldo e baixa só a parcela paga',
    () async {
      final database = await AppDatabase.instance.database;
      final notaId = await _criarNota(database, valor: 1000);

      final contaId = await _contaPadrao(database);
      await database.update(
        'financeiro_contas',
        {'saldo_inicial': 1000.0},
        where: 'id = ?',
        whereArgs: [contaId],
      );
      final planoEstoque = await _plano(database, '9.06');

      await service.criarLancamento(
        notaFiscalId: notaId,
        jaPago: false,
        planoContaId: planoEstoque,
        contaId: null,
        formaPagamento: 'Boleto',
        totalParcelas: 3,
        primeiroVencimento: DateTime(2026, 10, 10),
      );

      var resumo = await service.obterResumo(notaId);
      expect(resumo.status, 'Previsto');
      expect(resumo.movimentos, hasLength(3));
      expect(resumo.valorPrevisto, closeTo(1000, 0.000001));
      expect(resumo.valorPago, 0);

      var conta = (await contas.listar()).firstWhere(
        (item) => item.id == contaId,
      );
      expect(conta.saldoAtual, closeTo(1000, 0.000001));

      final primeira = resumo.movimentos.first;
      await service.marcarParcelaComoPaga(
        movimentoId: primeira.id!,
        contaId: contaId,
        dataPagamento: DateTime(2026, 10, 9),
        formaPagamento: 'Pix',
      );

      resumo = await service.obterResumo(notaId);
      expect(resumo.status, 'Parcialmente pago');
      expect(resumo.valorPago, closeTo(333.34, 0.000001));
      expect(resumo.valorPrevisto, closeTo(666.66, 0.000001));

      conta = (await contas.listar()).firstWhere((item) => item.id == contaId);
      expect(conta.saldoAtual, closeTo(666.66, 0.000001));
    },
  );

  test(
    'despesa a prazo entra no DRE por competência e no caixa só ao pagar',
    () async {
      final database = await AppDatabase.instance.database;
      final notaId = await _criarNota(database, valor: 600);
      final contaId = await _contaPadrao(database);
      final planoDespesa = await _plano(database, '2.99.01');

      await service.criarLancamento(
        notaFiscalId: notaId,
        jaPago: false,
        planoContaId: planoDespesa,
        formaPagamento: 'Boleto',
        primeiroVencimento: DateTime(2026, 10, 10),
      );

      var competencia = await dre.calcular(
        inicio: DateTime(2026, 9, 1),
        fim: DateTime(2026, 9, 30),
        regime: DreRegime.competencia,
      );
      var caixa = await dre.calcular(
        inicio: DateTime(2026, 9, 1),
        fim: DateTime(2026, 9, 30),
        regime: DreRegime.caixa,
      );

      expect(competencia.outrasDespesas, closeTo(600, 0.000001));
      expect(caixa.outrasDespesas, closeTo(0, 0.000001));

      final resumo = await service.obterResumo(notaId);
      await service.marcarParcelaComoPaga(
        movimentoId: resumo.movimentos.single.id!,
        contaId: contaId,
        dataPagamento: DateTime(2026, 10, 10),
        formaPagamento: 'Pix',
      );

      competencia = await dre.calcular(
        inicio: DateTime(2026, 9, 1),
        fim: DateTime(2026, 9, 30),
        regime: DreRegime.competencia,
      );
      caixa = await dre.calcular(
        inicio: DateTime(2026, 10, 1),
        fim: DateTime(2026, 10, 31),
        regime: DreRegime.caixa,
      );

      expect(competencia.outrasDespesas, closeTo(600, 0.000001));
      expect(caixa.outrasDespesas, closeTo(600, 0.000001));
    },
  );

  test('documento não autorizado não gera financeiro', () async {
    final database = await AppDatabase.instance.database;
    final notaId = await _criarNota(
      database,
      valor: 100,
      situacaoFiscal: 'cancelada',
    );
    final plano = await _plano(database, '9.06');

    await expectLater(
      service.criarLancamento(
        notaFiscalId: notaId,
        jaPago: false,
        planoContaId: plano,
        formaPagamento: 'Boleto',
        primeiroVencimento: DateTime(2026, 10, 10),
      ),
      throwsA(isA<StateError>()),
    );

    final movimentos = await database.query(
      'movimentos_financeiros',
      where: 'nota_fiscal_id = ?',
      whereArgs: [notaId],
    );
    expect(movimentos, isEmpty);
  });

  test(
    'idempotência bloqueia duplicação e cancelamento permite refazer previsão',
    () async {
      final database = await AppDatabase.instance.database;
      final notaId = await _criarNota(database, valor: 300);
      final planoEstoque = await _plano(database, '9.06');

      Future<void> criar() => service
          .criarLancamento(
            notaFiscalId: notaId,
            jaPago: false,
            planoContaId: planoEstoque,
            formaPagamento: 'Boleto',
            primeiroVencimento: DateTime(2026, 10, 15),
          )
          .then((_) {});

      await criar();
      await expectLater(criar(), throwsA(isA<StateError>()));

      await service.cancelarPlanejamento(notaId);
      var resumo = await service.obterResumo(notaId);
      expect(resumo.status, 'Cancelado');

      await criar();
      resumo = await service.obterResumo(notaId);
      expect(resumo.status, 'Previsto');

      final ativos = await database.query(
        'movimentos_financeiros',
        where: "nota_fiscal_id = ? AND status != 'Cancelado'",
        whereArgs: [notaId],
      );
      expect(ativos, hasLength(1));
    },
  );
}

Future<int> _criarNota(
  Database database, {
  required double valor,
  String situacaoFiscal = 'autorizada',
}) {
  return database.insert('notas_fiscais_entrada', {
    'chave_acesso': '35191111111111111111550010000000011000000012',
    'modelo': 55,
    'numero': 123,
    'serie': 1,
    'data_emissao': '2026-09-05T10:00:00.000',
    'emitente_cnpj_cpf': '11111111111111',
    'emitente_nome': 'Fornecedor Fiscal Teste',
    'valor_produtos': valor,
    'valor_total': valor,
    'situacao_fiscal': situacaoFiscal,
    'status_importacao': 'processada',
    'origem_importacao': 'xml',
    'importada_em': '2026-09-08T10:00:00.000',
  });
}

Future<int> _contaPadrao(Database database) async {
  final rows = await database.query(
    'financeiro_contas',
    columns: ['id'],
    where: 'ativo = 1',
    orderBy: 'id ASC',
    limit: 1,
  );
  return (rows.first['id'] as num).toInt();
}

Future<int> _plano(Database database, String codigo) async {
  final rows = await database.query(
    'financeiro_plano_contas',
    columns: ['id'],
    where: 'codigo = ? AND ativo = 1',
    whereArgs: [codigo],
    limit: 1,
  );
  return (rows.first['id'] as num).toInt();
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
