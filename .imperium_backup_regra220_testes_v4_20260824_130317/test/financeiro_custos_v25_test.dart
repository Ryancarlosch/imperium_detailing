import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/colaborador_custo.dart';
import 'package:imperium_detailing/models/custo_fixo.dart';
import 'package:imperium_detailing/repositories/custos_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late CustosRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_financeiro_custos_v25_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    repository = CustosRepository();
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
    'calcula custo fixo, mão de obra e custo da estrutura por hora',
    () async {
      final agora = DateTime.now().toIso8601String();

      await repository.salvarCustoFixo(
        CustoFixo(
          nome: 'Aluguel',
          valorMensal: 2000,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
      await repository.salvarCustoFixo(
        CustoFixo(
          nome: 'Energia',
          valorMensal: 500,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      await repository.salvarColaborador(
        ColaboradorCusto(
          nome: 'Profissional 1',
          remuneracaoMensal: 4000,
          encargosMensais: 1000,
          horasProdutivasMes: 100,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final resumo = await repository.obterResumoEstruturaCustos();

      expect(resumo['custo_fixo_mensal'], closeTo(2500, 0.001));
      expect(resumo['custo_mao_obra_mensal'], closeTo(5000, 0.001));
      expect(resumo['horas_produtivas'], closeTo(100, 0.001));
      expect(resumo['custo_mao_obra_hora'], closeTo(50, 0.001));
      expect(resumo['custo_fixo_hora'], closeTo(25, 0.001));
      expect(resumo['custo_estrutura_hora'], closeTo(75, 0.001));
    },
  );

  test(
    'preserva custo/hora como snapshot ao lançar mão de obra na OS',
    () async {
      final agora = DateTime.now().toIso8601String();
      final database = await AppDatabase.instance.database;

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente teste',
      });
      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-CUSTO-001',
        'status': 'Finalizada',
        'data_abertura': agora,
        'data_finalizacao': agora,
        'valor_total': 1000,
      });

      final colaboradorId = await repository.salvarColaborador(
        ColaboradorCusto(
          nome: 'Profissional',
          remuneracaoMensal: 3000,
          encargosMensais: 1000,
          horasProdutivasMes: 100,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      await repository.registrarMaoObraOrdem(
        ordemServicoId: ordemId,
        colaboradorId: colaboradorId,
        horas: 5,
      );

      final lancamentos = await repository.listarMaoObraOrdem(ordemId);
      expect(lancamentos, hasLength(1));
      expect(
        (lancamentos.single['custo_hora_snapshot'] as num).toDouble(),
        closeTo(40, 0.001),
      );
      expect(
        (lancamentos.single['custo_total'] as num).toDouble(),
        closeTo(200, 0.001),
      );

      final colaborador = (await repository.listarColaboradores()).single;
      await repository.salvarColaborador(
        ColaboradorCusto(
          id: colaborador.id,
          nome: colaborador.nome,
          remuneracaoMensal: 6000,
          encargosMensais: 1000,
          horasProdutivasMes: 100,
          criadoEm: colaborador.criadoEm,
          atualizadoEm: agora,
        ),
      );

      final historico = await repository.listarMaoObraOrdem(ordemId);
      expect(
        (historico.single['custo_hora_snapshot'] as num).toDouble(),
        closeTo(40, 0.001),
      );
      expect(
        (historico.single['custo_total'] as num).toDouble(),
        closeTo(200, 0.001),
      );
    },
  );

  test(
    'calcula resultado da OS com produtos, taxas, mão de obra e rateio fixo',
    () async {
      final agora = DateTime.now().toIso8601String();
      final database = await AppDatabase.instance.database;

      await repository.salvarCustoFixo(
        CustoFixo(
          nome: 'Estrutura',
          valorMensal: 1000,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
      final colaboradorId = await repository.salvarColaborador(
        ColaboradorCusto(
          nome: 'Profissional',
          remuneracaoMensal: 2000,
          horasProdutivasMes: 100,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente resultado',
      });
      final ordemId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': 'OS-RESULTADO-001',
        'status': 'Finalizada',
        'data_abertura': agora,
        'data_finalizacao': agora,
        'valor_total': 1200,
        'desconto': 100,
        'desconto_negociacao': 50,
        'acrescimo_negociacao': 100,
        'juros_parcelamento': 50,
        'valor_recebido': 1200,
        'status_pagamento': 'Pago',
      });

      await database.insert('ordem_servico_produtos', {
        'ordem_servico_id': ordemId,
        'produto_nome': 'Produto A',
        'quantidade': 1,
        'unidade': 'un',
        'custo_unitario': 150,
        'custo_unitario_no_momento': 150,
        'custo_total_no_momento': 150,
        'composicao_lotes_json': '',
        'baixado_estoque': 1,
      });

      await database.insert('ordem_servico_pagamentos', {
        'ordem_servico_id': ordemId,
        'status': 'Pago',
        'valor': 1200,
        'forma_pagamento': 'Cartão de crédito',
        'data_pagamento': agora,
        'observacoes': '',
        'taxa_operacao': 40,
        'valor_liquido': 1160,
        'criado_em': agora,
        'atualizado_em': agora,
      });

      await repository.registrarMaoObraOrdem(
        ordemServicoId: ordemId,
        colaboradorId: colaboradorId,
        horas: 5,
      );

      final resultado = await repository.obterResultadoOrdem(ordemId);
      expect(resultado, isNotNull);
      expect(
        (resultado!['valor_negociado'] as num).toDouble(),
        closeTo(1200, 0.001),
      );
      expect(
        (resultado['custo_produtos'] as num).toDouble(),
        closeTo(150, 0.001),
      );
      expect(
        (resultado['taxas_pagamento'] as num).toDouble(),
        closeTo(40, 0.001),
      );
      expect(
        (resultado['custo_mao_obra'] as num).toDouble(),
        closeTo(100, 0.001),
      );
      expect(
        (resultado['rateio_custo_fixo'] as num).toDouble(),
        closeTo(50, 0.001),
      );
      expect((resultado['custo_total'] as num).toDouble(), closeTo(340, 0.001));
      expect(
        (resultado['resultado_os'] as num).toDouble(),
        closeTo(860, 0.001),
      );
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
