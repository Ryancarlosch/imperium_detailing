import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/services/nota_fiscal_correcao_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late NotaFiscalCorrecaoService service;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp('imperium_nf_correcao_test_');
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    service = NotaFiscalCorrecaoService();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) await pasta.delete(recursive: true);
  });

  test(
    'excluir nota desfaz estoque e estorna caixa preservando auditoria',
    () async {
      final database = await AppDatabase.instance.database;
      final fixture = await _criarFixture(database, financeiroRealizado: true);

      final impacto = await service.analisar(fixture.notaId);
      expect(impacto.entradasEstoque, 1);
      expect(impacto.financeirosRealizados, 1);
      expect(impacto.podeDesfazerAutomaticamente, isTrue);

      await service.excluirNotaComDesfazimento(
        notaFiscalId: fixture.notaId,
        motivo: 'Nota lançada incorretamente',
      );

      expect(
        await database.query(
          'notas_fiscais_entrada',
          where: 'id = ?',
          whereArgs: [fixture.notaId],
        ),
        isEmpty,
      );

      final item = (await database.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [fixture.itemEstoqueId],
      )).single;
      expect((item['quantidade'] as num).toDouble(), 0);

      final lote = (await database.query(
        'estoque_lotes',
        where: 'id = ?',
        whereArgs: [fixture.loteId],
      )).single;
      expect((lote['quantidade_disponivel'] as num).toDouble(), 0);
      expect(lote['ativo'], 0);

      final financeiros = await database.query(
        'movimentos_financeiros',
        where: 'numero_documento LIKE ?',
        whereArgs: ['%NF-TESTE%'],
        orderBy: 'id ASC',
      );
      expect(financeiros, hasLength(2));
      expect(financeiros.first['status'], 'Realizado');
      expect(financeiros.first['origem'], 'Nota fiscal de entrada estornada');
      expect(financeiros.first['impacta_dre'], 0);
      expect(financeiros.last['tipo'], 'Entrada');
      expect(financeiros.last['status'], 'Realizado');
      expect(financeiros.last['origem'], 'Estorno de nota fiscal de entrada');
      expect(financeiros.last['impacta_dre'], 0);

      final efeitoCaixa = await database.rawQuery('''
      SELECT COALESCE(SUM(
        CASE WHEN LOWER(tipo) = 'entrada' THEN valor ELSE -valor END
      ), 0) AS total
      FROM movimentos_financeiros
      WHERE status = 'Realizado'
        AND numero_documento LIKE '%NF-TESTE%'
    ''');
      expect((efeitoCaixa.first['total'] as num).toDouble(), 0);

      final auditoria = await service.listarAuditoria(
        chaveAcesso: fixture.chave,
      );
      expect(auditoria, isNotEmpty);
      expect(auditoria.any((row) => row['tipo'] == 'Excluir nota'), isTrue);
      expect(auditoria.any((row) => row['tipo'] == 'Estorno estoque'), isTrue);
      expect(
        auditoria.any((row) => row['tipo'] == 'Estorno financeiro'),
        isTrue,
      );
      // A auditoria permanece após a exclusão e perde apenas o FK da nota.
      expect(auditoria.every((row) => row['nota_fiscal_id'] == null), isTrue);

      // A chave volta a ficar disponível para uma futura reimportação correta.
      final reimportada = await database.insert('notas_fiscais_entrada', {
        'chave_acesso': fixture.chave,
        'modelo': 65,
        'numero': 777,
        'serie': 1,
        'data_emissao': '2026-09-09T12:00:00.000',
        'emitente_nome': 'Fornecedor reimportado',
        'valor_total': 50.0,
        'situacao_fiscal': 'autorizada',
        'status_importacao': 'processada',
        'origem_importacao': 'qrCode',
        'importada_em': '2026-09-09T12:01:00.000',
      });
      expect(reimportada, greaterThan(0));
    },
  );

  test(
    'desfazer integração cancela previsto sem criar estorno de caixa',
    () async {
      final database = await AppDatabase.instance.database;
      final fixture = await _criarFixture(database, financeiroRealizado: false);

      await service.desfazerIntegracoes(
        notaFiscalId: fixture.notaId,
        motivo: 'Corrigir vínculo da compra',
      );

      final financeiros = await database.query(
        'movimentos_financeiros',
        where: 'nota_fiscal_id = ?',
        whereArgs: [fixture.notaId],
      );
      expect(financeiros, hasLength(1));
      expect(financeiros.single['status'], 'Cancelado');

      final nota = await database.query(
        'notas_fiscais_entrada',
        where: 'id = ?',
        whereArgs: [fixture.notaId],
      );
      expect(nota, hasLength(1));

      final entradasAtivas = await database.query(
        'movimentacoes_estoque',
        where:
            "nota_fiscal_id = ? AND tipo = 'ENTRADA' AND origem = 'Nota fiscal de entrada'",
        whereArgs: [fixture.notaId],
      );
      expect(entradasAtivas, isEmpty);
    },
  );

  test('bloqueia exclusão automática quando o lote já foi consumido', () async {
    final database = await AppDatabase.instance.database;
    final fixture = await _criarFixture(database, financeiroRealizado: false);
    await database.update(
      'estoque_lotes',
      {'quantidade_disponivel': 1.0},
      where: 'id = ?',
      whereArgs: [fixture.loteId],
    );

    final impacto = await service.analisar(fixture.notaId);
    expect(impacto.podeDesfazerAutomaticamente, isFalse);
    expect(impacto.lotesConsumidos, 1);

    await expectLater(
      service.excluirNotaComDesfazimento(
        notaFiscalId: fixture.notaId,
        motivo: 'Nota incorreta no sistema',
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      await database.query(
        'notas_fiscais_entrada',
        where: 'id = ?',
        whereArgs: [fixture.notaId],
      ),
      hasLength(1),
    );
  });
}

class _Fixture {
  const _Fixture({
    required this.notaId,
    required this.itemEstoqueId,
    required this.loteId,
    required this.chave,
  });

  final int notaId;
  final int itemEstoqueId;
  final int loteId;
  final String chave;
}

Future<_Fixture> _criarFixture(
  Database database, {
  required bool financeiroRealizado,
}) async {
  const chave = '42260983305235009841650150001422351111111116';
  final agora = DateTime(2026, 9, 9, 10).toIso8601String();
  final notaId = await database.insert('notas_fiscais_entrada', {
    'chave_acesso': chave,
    'modelo': 65,
    'numero': 142235,
    'serie': 15,
    'data_emissao': agora,
    'emitente_cnpj_cpf': '83305235009841',
    'emitente_nome': 'COOPERATIVA AGROINDUSTRIAL ALFA',
    'valor_produtos': 50.0,
    'valor_total': 50.0,
    'situacao_fiscal': 'autorizada',
    'status_importacao': 'processada',
    'origem_importacao': 'qrCode',
    'importada_em': agora,
  });

  final itemEstoqueId = await database.insert('itens_estoque', {
    'nome': 'Produto fiscal teste',
    'categoria': 'Teste',
    'quantidade': 2.0,
    'quantidade_minima': 0.0,
    'unidade': 'un',
    'valor_total_pago': 50.0,
    'quantidade_total': 2.0,
    'ean': '',
    'custo_unitario': 25.0,
    'custo_unitario_calculado': 25.0,
    'fornecedor': 'Fornecedor',
    'observacoes': '',
    'ativo': 1,
    'atualizado_em': agora,
  });
  final itemFiscalId = await database.insert('notas_fiscais_entrada_itens', {
    'nota_fiscal_id': notaId,
    'numero_item': 1,
    'descricao': 'Produto fiscal teste',
    'unidade': 'UN',
    'quantidade': 2.0,
    'valor_unitario': 25.0,
    'valor_total': 50.0,
    'valor_desconto': 0.0,
    'estoque_item_id': itemEstoqueId,
    'observacoes': '',
  });
  final loteId = await database.insert('estoque_lotes', {
    'item_estoque_id': itemEstoqueId,
    'data_compra': agora,
    'quantidade_original': 2.0,
    'quantidade_normalizada': 2.0,
    'quantidade_disponivel': 2.0,
    'unidade_original': 'UN',
    'unidade_base': 'un',
    'valor_total_pago': 50.0,
    'custo_unitario': 25.0,
    'fornecedor': 'Fornecedor',
    'observacao': 'NF teste',
    'ativo': 1,
    'criado_em': agora,
  });
  await database.insert('movimentacoes_estoque', {
    'item_estoque_id': itemEstoqueId,
    'tipo': 'ENTRADA',
    'quantidade': 2.0,
    'quantidade_anterior': 0.0,
    'quantidade_posterior': 2.0,
    'custo_unitario': 25.0,
    'observacoes': '',
    'motivo': 'Compra fiscal',
    'origem': 'Nota fiscal de entrada',
    'ordem_servico_id': null,
    'lote_id': loteId,
    'nota_fiscal_id': notaId,
    'nota_fiscal_item_id': itemFiscalId,
    'data': agora,
  });

  final contaRows = await database.query(
    'financeiro_contas',
    columns: ['id'],
    where: 'ativo = 1',
    orderBy: 'id ASC',
    limit: 1,
  );
  final contaId = (contaRows.first['id'] as num).toInt();
  await database.insert('movimentos_financeiros', {
    'tipo': 'Saída',
    'descricao': 'Compra NF-TESTE',
    'valor': 50.0,
    'forma_pagamento': financeiroRealizado ? 'Pix' : 'Boleto',
    'data': agora,
    'conta_id': financeiroRealizado ? contaId : null,
    'nota_fiscal_id': notaId,
    'parcela_numero': 1,
    'total_parcelas': 1,
    'natureza': 'Compra para estoque',
    'origem': 'Nota fiscal de entrada',
    'status': financeiroRealizado ? 'Realizado' : 'Previsto',
    'data_competencia': agora,
    'data_vencimento': financeiroRealizado ? null : agora,
    'data_pagamento': financeiroRealizado ? agora : null,
    'numero_documento': 'NF-TESTE',
    'observacoes': '',
    'impacta_dre': 0,
  });

  return _Fixture(
    notaId: notaId,
    itemEstoqueId: itemEstoqueId,
    loteId: loteId,
    chave: chave,
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
