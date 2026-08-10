import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/regra_taxa_cartao.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:imperium_detailing/repositories/pagamento_repository.dart';
import 'package:imperium_detailing/repositories/regra_taxa_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late RegraTaxaRepository regras;
  late OrdemServicoRepository ordens;
  late PagamentoRepository pagamentos;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_taxa_repasse_v27_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    regras = RegraTaxaRepository();
    ordens = OrdemServicoRepository();
    pagamentos = PagamentoRepository();
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
    'finalização em cartão repassa taxa, registra acréscimo e preserva líquido',
    () async {
      final agora = DateTime.now().toIso8601String();
      final regraId = await regras.salvar(
        RegraTaxaCartao(
          nome: 'Crédito 3x repassado',
          formaPagamento: 'Cartão de crédito',
          parcelas: 3,
          taxaPercentual: 4,
          repassarCliente: true,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final database = await AppDatabase.instance.database;
      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente repasse',
      });
      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-REPASSE-001',
        'status': 'Em andamento',
        'data_abertura': '2026-08-09',
        'data_inicio': '2026-08-09',
        'valor_total': 1000,
        'desconto': 0,
      });

      await ordens.finalizarOrdemServico(
        ordemServicoId: ordemId,
        formaPagamento: 'Cartão de crédito',
        valorPagamento: 1000,
        parcelasTaxa: 3,
      );

      final ordem = (await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
      )).single;
      expect(ordem['status'], 'Finalizada');
      expect(ordem['status_pagamento'], 'Pago');
      expect(
        (ordem['acrescimo_negociacao'] as num).toDouble(),
        closeTo(41.67, 0.001),
      );
      expect(
        (ordem['valor_recebido'] as num).toDouble(),
        closeTo(1041.67, 0.001),
      );

      final pagamento = (await database.query(
        'ordem_servico_pagamentos',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      )).single;
      expect(pagamento['regra_taxa_id'], regraId);
      expect((pagamento['parcelas_taxa'] as num).toInt(), 3);
      expect((pagamento['valor'] as num).toDouble(), closeTo(1041.67, 0.001));
      expect(
        (pagamento['taxa_operacao'] as num).toDouble(),
        closeTo(41.67, 0.001),
      );
      expect(
        (pagamento['valor_liquido'] as num).toDouble(),
        closeTo(1000, 0.001),
      );

      final ajuste = (await database.query(
        'ordem_servico_ajustes_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      )).single;
      expect(ajuste['tipo'], 'Acréscimo');
      expect(ajuste['origem'], 'Taxa de maquininha');
      expect(ajuste['regra_taxa_id'], regraId);
      expect(ajuste['pagamento_id'], pagamento['id']);
      expect((ajuste['valor'] as num).toDouble(), closeTo(41.67, 0.001));

      await pagamentos.estornarPagamento(
        pagamentoId: (pagamento['id'] as num).toInt(),
        motivo: 'Teste de estorno do repasse automático.',
      );

      final ordemEstornada = (await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
      )).single;
      expect(
        (ordemEstornada['acrescimo_negociacao'] as num).toDouble(),
        closeTo(0, 0.001),
      );
      expect(
        (ordemEstornada['valor_recebido'] as num).toDouble(),
        closeTo(0, 0.001),
      );
      expect(ordemEstornada['status_pagamento'], 'Pendente');

      final ajusteEstornado = (await database.query(
        'ordem_servico_ajustes_financeiros',
        where: 'id = ?',
        whereArgs: [ajuste['id']],
      )).single;
      expect(ajusteEstornado['status'], 'Cancelado');
    },
  );

  test(
    'regra absorvida mantém total da OS e registra somente o custo',
    () async {
      final agora = DateTime.now().toIso8601String();
      await regras.salvar(
        RegraTaxaCartao(
          nome: 'Débito absorvido',
          formaPagamento: 'Cartão de débito',
          taxaPercentual: 2,
          repassarCliente: false,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final database = await AppDatabase.instance.database;
      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente absorvido',
      });
      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-REPASSE-002',
        'status': 'Finalizada',
        'data_abertura': '2026-08-09',
        'data_finalizacao': '2026-08-09',
        'valor_total': 500,
        'status_pagamento': 'Pendente',
        'valor_recebido': 0,
      });

      await pagamentos.registrarPagamento(
        ordemServicoId: ordemId,
        valor: 500,
        formaPagamento: 'Cartão de débito',
      );

      final pagamento = (await database.query(
        'ordem_servico_pagamentos',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      )).single;
      expect((pagamento['valor'] as num).toDouble(), closeTo(500, 0.001));
      expect(
        (pagamento['taxa_operacao'] as num).toDouble(),
        closeTo(10, 0.001),
      );
      expect(
        (pagamento['valor_liquido'] as num).toDouble(),
        closeTo(490, 0.001),
      );

      final ajustes = await database.query(
        'ordem_servico_ajustes_financeiros',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );
      expect(ajustes, isEmpty);
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
