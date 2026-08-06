import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late OrdemServicoRepository repository;
  var sequenciaNumero = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_finalizacao_os_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);

    repository = OrdemServicoRepository();
    sequenciaNumero = 0;
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('OrdemServicoRepository - finalização', () {
    test('recusa finalizar uma OS ainda aberta', () async {
      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Aberta',
        valorTotal: 500,
      );

      await expectLater(
        repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Pix',
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await repository.buscarOrdemServicoPorId(ordemId);
      final database = await AppDatabase.instance.database;
      final movimentos = await database.query('movimentos_financeiros');

      expect(ordem, isNotNull);
      expect(ordem!.status, 'Aberta');
      expect(ordem.lancadoFinanceiro, isFalse);
      expect(movimentos, isEmpty);
    });

    test('recusa finalizar uma OS cancelada', () async {
      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Cancelada',
        valorTotal: 500,
      );

      await expectLater(
        repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Pix',
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await repository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.status, 'Cancelada');
      expect(ordem.lancadoFinanceiro, isFalse);
    });

    test(
      'finaliza OS em andamento e cria somente um lançamento financeiro',
      () async {
        final ordemId = await _criarOrdem(
          repository: repository,
          numero: _proximoNumero(() => ++sequenciaNumero),
          status: 'Em andamento',
          valorTotal: 1000,
          desconto: 100,
        );

        await repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Pix',
        );

        final ordem = await repository.buscarOrdemServicoPorId(ordemId);
        final database = await AppDatabase.instance.database;

        expect(ordem, isNotNull);
        final ordemFinalizada = ordem!;

        final movimentos = await database.query(
          'movimentos_financeiros',
          where: 'cliente_id = ?',
          whereArgs: [ordemFinalizada.clienteId],
        );

        expect(ordemFinalizada.status, 'Finalizada');
        expect(ordemFinalizada.dataFinalizacao, isNotNull);
        expect(ordemFinalizada.horaSaida, isNotNull);
        expect(ordemFinalizada.formaPagamento, 'Pix');
        expect(ordemFinalizada.lancadoFinanceiro, isTrue);

        expect(movimentos, hasLength(1));
        expect(movimentos.single['tipo'], 'entrada');
        expect((movimentos.single['valor'] as num).toDouble(), 900.0);
        expect(movimentos.single['forma_pagamento'], 'Pix');
        expect(
          movimentos.single['descricao'].toString(),
          contains(ordemFinalizada.numero),
        );

        await repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Dinheiro',
        );

        final movimentosDepois = await database.query(
          'movimentos_financeiros',
          where: 'cliente_id = ?',
          whereArgs: [ordemFinalizada.clienteId],
        );

        expect(movimentosDepois, hasLength(1));
      },
    );

    test('consome lotes pelo FIFO e registra os custos da OS', () async {
      final database = await AppDatabase.instance.database;
      final agora = DateTime.now();

      final itemEstoqueId = await database.insert('itens_estoque', {
        'nome': 'Shampoo automotivo',
        'categoria': 'Lavagem',
        'quantidade': 10,
        'quantidade_minima': 1,
        'unidade': 'ml',
        'valor_total_pago': 160,
        'quantidade_total': 10,
        'custo_unitario': 16,
        'custo_unitario_calculado': 16,
        'fornecedor': 'Fornecedor teste',
        'observacoes': '',
        'ativo': 1,
        'atualizado_em': agora.toIso8601String(),
      });

      final loteAntigoId = await database.insert('estoque_lotes', {
        'item_estoque_id': itemEstoqueId,
        'data_compra': '2026-01-01T10:00:00.000',
        'quantidade_original': 4,
        'quantidade_normalizada': 4,
        'quantidade_disponivel': 4,
        'unidade_original': 'ml',
        'unidade_base': 'ml',
        'valor_total_pago': 40,
        'custo_unitario': 10,
        'fornecedor': 'Fornecedor antigo',
        'observacao': 'Primeiro lote',
        'ativo': 1,
        'criado_em': '2026-01-01T10:00:00.000',
      });

      final loteNovoId = await database.insert('estoque_lotes', {
        'item_estoque_id': itemEstoqueId,
        'data_compra': '2026-02-01T10:00:00.000',
        'quantidade_original': 6,
        'quantidade_normalizada': 6,
        'quantidade_disponivel': 6,
        'unidade_original': 'ml',
        'unidade_base': 'ml',
        'valor_total_pago': 120,
        'custo_unitario': 20,
        'fornecedor': 'Fornecedor novo',
        'observacao': 'Segundo lote',
        'ativo': 1,
        'criado_em': '2026-02-01T10:00:00.000',
      });

      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Em andamento',
        valorTotal: 700,
      );

      final produtoOsId = await database.insert('ordem_servico_produtos', {
        'ordem_servico_id': ordemId,
        'produto_id': itemEstoqueId,
        'produto_nome': 'Shampoo automotivo',
        'quantidade': 7,
        'unidade': 'ml',
        'custo_unitario': 16,
        'custo_unitario_no_momento': 0,
        'custo_total_no_momento': 0,
        'composicao_lotes_json': '',
        'baixado_estoque': 0,
      });

      await repository.finalizarOrdemServico(
        ordemServicoId: ordemId,
        formaPagamento: 'Pix',
      );

      final itemEstoque = await database.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [itemEstoqueId],
        limit: 1,
      );

      final loteAntigo = await database.query(
        'estoque_lotes',
        where: 'id = ?',
        whereArgs: [loteAntigoId],
        limit: 1,
      );

      final loteNovo = await database.query(
        'estoque_lotes',
        where: 'id = ?',
        whereArgs: [loteNovoId],
        limit: 1,
      );

      final produtoOs = await database.query(
        'ordem_servico_produtos',
        where: 'id = ?',
        whereArgs: [produtoOsId],
        limit: 1,
      );

      final composicoes = await database.query(
        'ordem_servico_produto_lotes',
        where: 'ordem_servico_produto_id = ?',
        whereArgs: [produtoOsId],
        orderBy: 'id ASC',
      );

      final movimentacoes = await database.query(
        'movimentacoes_estoque',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'id ASC',
      );

      expect((itemEstoque.single['quantidade'] as num).toDouble(), 3.0);
      expect(
        (loteAntigo.single['quantidade_disponivel'] as num).toDouble(),
        0.0,
      );
      expect((loteNovo.single['quantidade_disponivel'] as num).toDouble(), 3.0);

      expect(produtoOs.single['baixado_estoque'], 1);
      expect(
        (produtoOs.single['custo_total_no_momento'] as num).toDouble(),
        100.0,
      );
      expect(
        (produtoOs.single['custo_unitario_no_momento'] as num).toDouble(),
        closeTo(100 / 7, 0.000001),
      );

      final composicaoJson =
          jsonDecode(produtoOs.single['composicao_lotes_json'].toString())
              as List<dynamic>;

      expect(composicaoJson, hasLength(2));
      expect(composicoes, hasLength(2));
      expect(movimentacoes, hasLength(2));

      expect(composicoes[0]['lote_id'], loteAntigoId);
      expect((composicoes[0]['quantidade'] as num).toDouble(), 4.0);
      expect((composicoes[0]['custo_unitario'] as num).toDouble(), 10.0);

      expect(composicoes[1]['lote_id'], loteNovoId);
      expect((composicoes[1]['quantidade'] as num).toDouble(), 3.0);
      expect((composicoes[1]['custo_unitario'] as num).toDouble(), 20.0);

      expect((movimentacoes[0]['quantidade_anterior'] as num).toDouble(), 10.0);
      expect((movimentacoes[0]['quantidade_posterior'] as num).toDouble(), 6.0);
      expect((movimentacoes[1]['quantidade_anterior'] as num).toDouble(), 6.0);
      expect((movimentacoes[1]['quantidade_posterior'] as num).toDouble(), 3.0);
    });

    test('estoque insuficiente desfaz toda a finalização', () async {
      final database = await AppDatabase.instance.database;
      final agora = DateTime.now();

      final itemEstoqueId = await database.insert('itens_estoque', {
        'nome': 'Cera automotiva',
        'categoria': 'Proteção',
        'quantidade': 2,
        'quantidade_minima': 1,
        'unidade': 'g',
        'valor_total_pago': 30,
        'quantidade_total': 2,
        'custo_unitario': 15,
        'custo_unitario_calculado': 15,
        'fornecedor': 'Fornecedor teste',
        'observacoes': '',
        'ativo': 1,
        'atualizado_em': agora.toIso8601String(),
      });

      final loteId = await database.insert('estoque_lotes', {
        'item_estoque_id': itemEstoqueId,
        'data_compra': '2026-03-01T10:00:00.000',
        'quantidade_original': 2,
        'quantidade_normalizada': 2,
        'quantidade_disponivel': 2,
        'unidade_original': 'g',
        'unidade_base': 'g',
        'valor_total_pago': 30,
        'custo_unitario': 15,
        'fornecedor': 'Fornecedor teste',
        'observacao': '',
        'ativo': 1,
        'criado_em': '2026-03-01T10:00:00.000',
      });

      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Em andamento',
        valorTotal: 500,
      );

      final produtoOsId = await database.insert('ordem_servico_produtos', {
        'ordem_servico_id': ordemId,
        'produto_id': itemEstoqueId,
        'produto_nome': 'Cera automotiva',
        'quantidade': 3,
        'unidade': 'g',
        'custo_unitario': 15,
        'custo_unitario_no_momento': 0,
        'custo_total_no_momento': 0,
        'composicao_lotes_json': '',
        'baixado_estoque': 0,
      });

      await expectLater(
        repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Pix',
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await repository.buscarOrdemServicoPorId(ordemId);

      final itemEstoque = await database.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [itemEstoqueId],
        limit: 1,
      );

      final lote = await database.query(
        'estoque_lotes',
        where: 'id = ?',
        whereArgs: [loteId],
        limit: 1,
      );

      final produtoOs = await database.query(
        'ordem_servico_produtos',
        where: 'id = ?',
        whereArgs: [produtoOsId],
        limit: 1,
      );

      final movimentosFinanceiros = await database.query(
        'movimentos_financeiros',
      );

      final movimentacoesEstoque = await database.query(
        'movimentacoes_estoque',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      final composicoes = await database.query(
        'ordem_servico_produto_lotes',
        where: 'ordem_servico_produto_id = ?',
        whereArgs: [produtoOsId],
      );

      expect(ordem, isNotNull);
      expect(ordem!.status, 'Em andamento');
      expect(ordem.lancadoFinanceiro, isFalse);
      expect(ordem.dataFinalizacao, isNull);

      expect((itemEstoque.single['quantidade'] as num).toDouble(), 2.0);
      expect((lote.single['quantidade_disponivel'] as num).toDouble(), 2.0);
      expect(produtoOs.single['baixado_estoque'], 0);
      expect(
        (produtoOs.single['custo_total_no_momento'] as num).toDouble(),
        0.0,
      );

      expect(movimentosFinanceiros, isEmpty);
      expect(movimentacoesEstoque, isEmpty);
      expect(composicoes, isEmpty);
    });
  });
}

String _proximoNumero(int Function() incrementar) {
  final numero = incrementar();
  return 'OS-FINALIZACAO-${numero.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdem({
  required OrdemServicoRepository repository,
  required String numero,
  required String status,
  required double valorTotal,
  double desconto = 0,
}) async {
  final database = await AppDatabase.instance.database;

  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente da $numero',
    'telefone': '11999999999',
    'email': 'cliente@teste.com',
    'endereco': 'Rua dos Testes, 100',
    'observacoes': 'Cliente criado para teste de finalização.',
  });

  return repository.inserirOrdemServico(
    OrdemServico(
      clienteId: clienteId,
      numero: numero,
      status: status,
      dataAbertura: '2026-08-06',
      dataInicio: status == 'Aberta' ? null : '2026-08-06',
      funcionarioResponsavel: 'Ryan',
      observacoes: 'OS criada por teste automatizado.',
      valorTotal: valorTotal,
      desconto: desconto,
      quilometragemEntrada: '50000',
      combustivelEntrada: 'Meio tanque',
    ),
  );
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
